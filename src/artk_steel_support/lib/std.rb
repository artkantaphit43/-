# frozen_string_literal: true

require_relative 'details'

module ArtK
  module SteelSupport
    # The user's standard column supports A B C D, steel exactly as drawn
    # (mm): only the U-bolts follow the pipes actually there.
    #
    # Support coordinates: x along the pipes (0 = the column's centre),
    # y out from the column face (0 = face), z up (0 = the top of the steel
    # the pipes sit on). Channels stand with their webs in the y–z plane
    # (what the elevations show: the depth, mitred corners), web back at
    # x = −B/2, toes toward +x; the back flange lies on the column face and
    # takes the expansion anchors.
    #
    #   A  bracket C 3":  arm 310 from the face, post 300 deep, 45° brace,
    #      2 anchors 3/8"; one 3"/4" water line
    #   B  bracket C 4":  arm 480, post 400, 45° brace, 2 anchors 3/8";
    #      lines at 200 and 430 from the face
    #   C  box frame C 4": 870 out × 520 high, 3 anchors 1/2"; 6" water at
    #      330 (230 inside the post), 2" air; 4" steam on a 4" angle shoe on
    #      a 2" angle seat on top
    #   D  box frame C 4": 870 × 520, 3 anchors 1/2"; lines at 330, 540, 690
    module Std
      D = Details
      TYPES = {
        'A' => { form: :bracket, sec: 'C75', arm: 310.0, post: 300.0, anchor: '3/8', bolts: [70.0, 240.0],
                 pipes: [{ y: 160.0, od: 114.3, label: '4" ประปา' }], th: 'ซัพพอร์ต A – ขาค้ำ C 3"' },
        'B' => { form: :bracket, sec: 'C100', arm: 480.0, post: 400.0, anchor: '3/8', bolts: [65.0, 315.0],
                 pipes: [{ y: 200.0, od: 60.3, label: '2"' }, { y: 430.0, od: 48.3, label: '1½"' }],
                 th: 'ซัพพอร์ต B – ขาค้ำ C 4"' },
        'C' => { form: :frame, sec: 'C100', width: 870.0, height: 520.0, anchor: '1/2', bolts: [80.0, 260.0, 440.0],
                 pipes: [{ y: 330.0, od: 168.3, label: '6" ประปา' }, { y: 600.0, od: 60.3, label: '2" ลม' }],
                 top: { y: 435.0, od: 114.3, label: '4" สตีม', seat: 'L50', seat_len: 250.0, shoe: 'L100', shoe_len: 200.0 },
                 th: 'ซัพพอร์ต C – โครงกล่อง C 4" + สตีมด้านบน' },
        'D' => { form: :frame, sec: 'C100', width: 870.0, height: 520.0, anchor: '1/2', bolts: [80.0, 260.0, 440.0],
                 pipes: [{ y: 330.0, od: 168.3, label: '6"' }, { y: 540.0, od: 73.0, label: '2½"' },
                         { y: 690.0, od: 48.3, label: '1½"' }],
                 th: 'ซัพพอร์ต D – โครงกล่อง C 4"' }
      }.freeze
      RISE = 300.0 # a pipe up to this above the steel rides on a packer
      SNAP = 120.0 # a pipe drawn onto a support this near one of the drawing's places goes there

      module_function

      def type(t)
        TYPES[t] or raise ArgumentError, "unknown support #{t}"
      end

      # How far out from the column face the support carries pipes.
      def reach(t)
        s = type(t)
        s[:form] == :bracket ? s[:arm] : s[:width] - Steel.depth(s[:sec])
      end

      def nominal(t)
        s = type(t)
        list = s[:pipes].map { |q| pipe(q[:y], q[:od] / 2.0, q[:od], q[:label]) }
        if (tp = s[:top])
          list << pipe(tp[:y], shoe_top(s) + tp[:od] / 2.0, tp[:od], tp[:label]).merge(top: true)
        end
        list
      end

      def pipe(y, z, od, label)
        { y: y, z: z, od: od, ins: 0.0, r: od / 2.0, kg_m: Pipes.generic_kg_m(od), span_m: Pipes.default_span_m(od),
          label: label }
      end

      # Top face of a frame's top member.
      def top_level(s)
        s[:height] - Steel.depth(s[:sec])
      end

      # Top of C's steam shoe as drawn (2" angle seat + 4" angle).
      def shoe_top(s)
        tp = s[:top]
        top_level(s) + Steel.get(tp[:seat])[:t] + Steel.get(tp[:shoe])[:a]
      end

      # Across the steel the pipes sit on (a bracket's arm / between a
      # frame's posts): [from, to] out from the column face.
      def bearing(s)
        h = Steel.depth(s[:sec])
        s[:form] == :bracket ? [0.0, s[:arm]] : [h, s[:width] - h]
      end

      # A point picked on support +t+ (y, z its support coordinates) to draw
      # a pipe from – Plant Piping's pipe tool: where that pipe goes,
      # { y:, z: (its underside), bare: (on the bare pipe – C's steam
      # shoe), half: (the steel there along the pipe, ±) } or nil.
      # On the steel the pipes sit on or its guide → on it; on C's top /
      # seat / shoe → on the shoe as drawn; on a guide point of 2.0.4 and
      # before (the drawn line's centre) → where that line rests. y: the
      # nearest of the drawing's places within SNAP that no pipe there
      # (+taken+) holds and – +pipe+ { od:, ins: } given – it fits, else
      # where picked.
      def rest(t, y, z, pipe = nil, taken = [])
        s = type(t)
        lo, hi = bearing(s)
        b = Steel.width(s[:sec]) / 2.0
        q = nominal(t).find { |p| (p[:y] - y).abs <= 3.0 && (p[:z] - z).abs <= 3.0 }
        r = if z.abs <= 3.0 && y.between?(lo - 3.0, hi + 3.0)
              { z: 0.0, bare: false, half: b }
            elsif s[:top] && y.between?(lo, hi) && z.between?(top_level(s) - 3.0, shoe_top(s) + 3.0)
              { z: shoe_top(s), bare: true, half: s[:top][:shoe_len] / 2.0 }
            elsif q
              { z: q[:z] - q[:r], bare: q[:top] == true, half: b }
            end
        r && r.merge(y: place(t, s, y, r, pipe, taken))
      end

      # Rest.y: the drawing's place for a pipe +drawn+ there (or y).
      def place(t, s, y, rest, drawn, taken)
        mine = taken.select { |p| on_top?(s, p) == rest[:bare] }
        near = nominal(t).select { |q| (q[:top] == true) == rest[:bare] && (q[:y] - y).abs <= SNAP }
        best = near.sort_by { |q| (q[:y] - y).abs }.find do |q|
          if drawn
            r = drawn[:od] / 2.0 + drawn[:ins].to_f
            lift = rest[:bare] ? drawn[:od] / 2.0 : r
            p = pipe(q[:y], rest[:z] + lift, drawn[:od], 'new').merge(ins: drawn[:ins].to_f, r: r)
            carried, top = fit(t, s, mine + [p], [])
            (carried.include?(p) || top.equal?(p)) && mine.none? { |o| (o[:y] - p[:y]).abs < side(o) + side(p) }
          else
            mine.none? { |o| (o[:y] - q[:y]).abs < o[:r] + q[:r] + 25.0 }
          end
        end
        best ? best[:y] : y
      end

      # A pipe on C's steam shoe (above the top member), not on the bottom.
      def on_top?(s, p)
        !s[:top].nil? && Pipes.bare_bottom(p) >= top_level(s) + 30.0
      end

      # From the pipe's centre out to its U-bolt's washer edge.
      def side(p)
        u = Hardware.get(D.u_size(p))
        p[:r] + 1.0 + u[:d] / 2.0 + u[:wod] / 2.0
      end

      # Support +t+ for the pipes there (support coordinates; nil / empty:
      # the drawing's own lines). The drawing's places no pipe takes get
      # guide points where those lines rest (info rests: [y, z] of their
      # underside; guides: their centres).
      def build(t, pipes = nil, opts = {})
        s = type(t)
        key = s[:sec]
        sec = Steel.get(key)
        h = sec[:h]
        b = sec[:b]
        tf = sec[:t2]
        xu = sec[:t1] / 2.0 # U-bolts / anchors mid the flange beside the web
        notes = []
        given = pipes && !pipes.empty?
        pipes = given ? pipes : nominal(t)
        carried, top_pipe = fit(t, s, pipes, notes)
        if carried.empty? && top_pipe.nil? && given
          notes << 'ไม่มีท่ออยู่ในตำแหน่งของซัพพอร์ต – ใส่ U-bolt ตามแบบ'
          # not where a pipe there (in the steel / off its places) is
          clear = nominal(t).reject do |q|
            pipes.any? { |p| (p[:y] - q[:y]).abs < p[:r] + q[:r] && (p[:z] - q[:z]).abs < p[:r] + q[:r] }
          end
          carried, top_pipe = fit(t, s, clear, [])
          given = false
        end
        part = Mesh::Part.new
        bom = []
        lines = []
        checks = []
        if s[:form] == :bracket
          bracket(part, bom, lines, checks, s, key, carried, opts)
        else
          frame(part, bom, lines, checks, s, key, carried, top_pipe, opts)
        end
        carried.each do |p|
          D.packer(part, bom, p, 0.0, b)
          D.pipe_u_bolt(part, bom, p, 0.0, tf, x: xu)
        end
        anchors(part, bom, checks, notes, s, key, carried + [top_pipe].compact, opts)
        checks.each do |c|
          next if c[:ok] || c[:kind] == :anchor # anchors note themselves

          notes << "#{c[:item]} เกินค่าที่ยอมให้ (#{c[:value]} > #{c[:limit]} #{c[:unit]}) – ลดระยะห่างซัพพอร์ต"
        end
        size = s[:form] == :bracket ? [s[:arm], s[:post]] : [s[:width], s[:height]]
        free = given ? free_places(t, carried, top_pipe) : carried + [top_pipe].compact
        D::Result.new(part: part, bom: bom, checks: checks, notes: notes, carried: carried + [top_pipe].compact,
                      lines: lines, info: { type: t, section: key, anchor: s[:anchor], anchors: s[:bolts].size,
                                            nominal: !given, guides: free.map { |p| [p[:y], p[:z]] },
                                            rests: free.map { |p| [p[:y], p[:top] ? shoe_top(s) : Pipes.bottom(p)] },
                                            size: size, h: h })
      end

      # The drawing's lines whose place no pipe there takes.
      def free_places(t, carried, top_pipe)
        nominal(t).reject do |q|
          next !top_pipe.nil? if q[:top]

          carried.any? { |p| (p[:y] - q[:y]).abs < p[:r] + q[:r] + 25.0 }
        end
      end

      # Pipes on the bearing steel (and the steam line on a frame's top);
      # the rest are noted. The washers under the flange stay clear of a
      # bracket's back flange on the column (the post's front flange stops
      # at the mitre, below the nuts) / of a frame's back post.
      def fit(t, s, pipes, notes)
        h = Steel.depth(s[:sec])
        lo = (s[:form] == :bracket ? Steel.get(s[:sec])[:t2] : h) + 2.0
        hi = s[:form] == :bracket ? s[:arm] : s[:width] - h - 2.0
        room = s[:form] == :frame ? top_level(s) - h - 10.0 : Float::INFINITY
        carried = []
        top = nil
        rest = []
        pipes.each do |p|
          u = Hardware.get(D.u_size(p))
          bottom = Pipes.bottom(p)
          if bottom.between?(-1.0, RISE) && p[:y] - side(p) >= lo && p[:y] + side(p) <= hi && p[:z] + p[:r] + u[:d] <= room
            carried << p
          elsif on_top?(s, p) && p[:y].between?(0.0, s[:width])
            top = p if top.nil? || (p[:y] - s[:top][:y]).abs < (top[:y] - s[:top][:y]).abs
          else
            rest << p
          end
        end
        b0, b1 = bearing(s)
        rest.each do |p|
          b = Pipes.bottom(p)
          if b < -1.0 && b + 2.0 * p[:r] > -h && p[:y] + p[:r] > b0 && p[:y] - p[:r] < b1
            notes << "ท่อ #{p[:label]} จมในเหล็ก #{(-b).round} มม. – ซัพพอร์ตอยู่ระดับที่วางไว้: " \
                     'ยกท่อขึ้น หรือวาดท่อใหม่ลงจุดไกด์/บนเหล็ก'
            next
          end
          near = p[:y] + p[:r] > 0 && p[:y] - p[:r] < hi + 150.0 && Pipes.bottom(p) < (s[:height] || s[:post]) + 300.0
          notes << "ท่อ #{p[:label]} ไม่อยู่ในตำแหน่งที่ซัพพอร์ต #{t} รับได้ – ไม่ได้รัด" if near
        end
        [carried.sort_by { |p| p[:y] }, top]
      end

      # Channel standing in the support plane along the centre line p → q
      # ([y, z]), depth centred on it; cut0 / cut1: [[y, z], [ny, nz]].
      def standing(part, key, p, q, cut0: nil, cut1: nil)
        b = Steel.width(key)
        d = Vec.unit([0.0, q[0] - p[0], q[1] - p[1]])
        n = [0.0, -d[2], d[1]]
        pl = ->(c) { c && [[0.0, c[0][0], c[0][1]], [0.0, c[1][0], c[1][1]]] }
        part.add(:steel, Steel.member(key, [-b / 2.0, p[0], p[1]], [-b / 2.0, q[0], q[1]], n, [1.0, 0, 0],
                                      cut0: pl.call(cut0), cut1: pl.call(cut1)))
      end

      def outline(lines, pts, b)
        pts.each_cons(2) do |(y0, z0), (y1, z1)|
          [-b / 2.0, b / 2.0].each { |x| lines << [[x, y0, z0], [x, y1, z1]] }
        end
      end

      # ---------- A / B ----------

      def bracket(part, bom, lines, checks, s, key, pipes, opts)
        h = Steel.depth(key)
        b = Steel.width(key)
        arm = s[:arm]
        post = s[:post]
        mitre = [[0.0, 0.0], [1.0, 1.0]]
        standing(part, key, [0.0, -h / 2.0], [arm, -h / 2.0], cut0: mitre)
        standing(part, key, [h / 2.0, -post], [h / 2.0, 0.0], cut1: mitre)
        # 45° brace: its lower edge from the post's inner foot to the arm
        c = h / (2.0 * Math.sqrt(2.0))
        standing(part, key, [h - c, -post + c], [post - c, -h + c], cut0: [[h, 0.0], [1.0, 0.0]],
                                                                    cut1: [[0.0, -h], [0.0, 1.0]])
        outline(lines, [[0.0, -post], [0.0, 0.0], [arm, 0.0], [arm, -h], [post, -h], [h, -post], [0.0, -post]], b)
        brace = Math.sqrt(2.0) * (post - h)
        D.bom_steel(bom, key, arm, 'แขน')
        D.bom_steel(bom, key, post, 'เสา')
        D.bom_steel(bom, key, brace, 'ค้ำยัน 45°')
        pr = Steel.props(key)
        lds = D.loads(pipes, opts)
        r = beam(checks, "แขน #{Steel.get(key)[:inch]}", key, 0.0, arm, h / 2.0, post - h / Math.sqrt(2.0), lds)
        D.check(checks, "ค้ำยัน #{Steel.get(key)[:inch]}: แรงอัด (compression)", r[:r2] * Math.sqrt(2.0) / pr[:area],
                Beam.fa(brace / pr[:r_min]), 'MPa')
      end

      # Strong-axis bending (the webs stand upright) + deflection.
      def beam(checks, name, key, x0, x1, s1, s2, lds)
        pr = Steel.props(key)
        r = Beam.two_support(x0, x1, s1, s2, lds, Steel::E * pr[:i_edge])
        D.check(checks, "#{name}: หน่วยแรงดัด (bending)", r[:m_max] / pr[:z_edge], Steel::FB, 'MPa')
        D.check(checks, "#{name}: การแอ่นตัว (deflection)", r[:defl], (x1 - x0) / D::DEFL, 'mm')
        r
      end

      # ---------- C / D ----------

      def frame(part, bom, lines, checks, s, key, pipes, top_pipe, opts)
        h = Steel.depth(key)
        b = Steel.width(key)
        w = s[:width]
        zt = top_level(s)
        z0 = -h
        bl = [[0.0, z0], [1.0, -1.0]]
        br = [[w, z0], [1.0, 1.0]]
        tl = [[0.0, zt], [1.0, 1.0]]
        tr = [[w, zt], [1.0, -1.0]]
        standing(part, key, [0.0, -h / 2.0], [w, -h / 2.0], cut0: bl, cut1: br)
        standing(part, key, [0.0, zt - h / 2.0], [w, zt - h / 2.0], cut0: tl, cut1: tr)
        standing(part, key, [h / 2.0, z0], [h / 2.0, zt], cut0: bl, cut1: tl)
        standing(part, key, [w - h / 2.0, z0], [w - h / 2.0, zt], cut0: br, cut1: tr)
        outline(lines, [[0.0, z0], [w, z0], [w, zt], [0.0, zt], [0.0, z0]], b)
        outline(lines, [[h, 0.0], [w - h, 0.0], [w - h, zt - h], [h, zt - h], [h, 0.0]], b)
        D.bom_steel(bom, key, 2 * w, 'คานบน + คานล่าง')
        D.bom_steel(bom, key, 2 * s[:height], 'เสาโครง 2 ตัว')
        inch = Steel.get(key)[:inch]
        beam(checks, "คานล่าง #{inch}", key, h / 2.0, w - h / 2.0, h / 2.0, w - h / 2.0, D.loads(pipes, opts))
        return unless s[:top]

        top_shoe(part, bom, lines, s, b, top_pipe)
        beam(checks, "คานบน #{inch}", key, h / 2.0, w - h / 2.0, h / 2.0, w - h / 2.0, D.loads([top_pipe].compact, opts))
      end

      # 2" angle seat lying on the top member (its other leg down the web
      # back), 4" angle shoe on it under the steam line, upright leg welded
      # to the bare pipe (cut / packed to its height).
      def top_shoe(part, bom, lines, s, b, pipe)
        tp = s[:top]
        zt = top_level(s)
        seat = Steel.get(tp[:seat])
        shoe = Steel.get(tp[:shoe])
        y = pipe ? pipe[:y] : tp[:y]
        z_seat = zt + seat[:t]
        x0 = -b / 2.0 - seat[:t]
        part.add(:steel, Steel.angle(tp[:seat], [x0, y - tp[:seat_len] / 2, z_seat], [x0, y + tp[:seat_len] / 2, z_seat],
                                     [1.0, 0, 0], [0, 0, -1.0]))
        D.bom_steel(bom, tp[:seat], tp[:seat_len], 'ที่รองสตีม')
        leg = shoe[:a]
        base = z_seat
        if pipe
          gap = Pipes.bare_bottom(pipe) - z_seat
          if gap > shoe[:a] + 1.0 # packed up under the shoe
            base = z_seat + gap - shoe[:a]
            part.add(:steel, Mesh.box([-tp[:shoe_len] / 2, y - shoe[:t], z_seat], [tp[:shoe_len] / 2, y + shoe[:a], base]))
            D.bom_pad(bom, tp[:shoe_len] * (shoe[:a] + shoe[:t]) * (base - z_seat) * Steel::RHO)
          else
            leg = [gap, shoe[:t] + shoe[:r1] + shoe[:r2] + 2.0].max
          end
        end
        heel = [-tp[:shoe_len] / 2, y - shoe[:t] / 2.0, base]
        part.add(:steel, Steel.angle(tp[:shoe], heel, Vec.add(heel, [tp[:shoe_len], 0, 0]), [0, 1.0, 0], [0, 0, 1.0],
                                     leg2_len: leg))
        D.bom_steel(bom, tp[:shoe], tp[:shoe_len], 'shoe ท่อสตีม')
        lines << [[0, y, z_seat], [0, y, base + leg]]
      end

      # ---------- anchors ----------

      def anchors(part, bom, checks, notes, s, key, pipes, opts)
        sec = Steel.get(key)
        xu = sec[:t1] / 2.0
        size = s[:anchor]
        top = s[:form] == :bracket ? 0.0 : top_level(s)
        foot = s[:form] == :bracket ? -s[:post] : -sec[:h]
        zs = s[:bolts].map { |d| top - d }
        zs.each { |z| Hardware.anchor(part, [xu, 0.0, z], [0, 1.0, 0], sec[:t2], size) }
        D.bom_item(bom, 'anchor', "พุก Expansion bolt #{Hardware.label(size)}", zs.size, key: "anc #{size}")
        lds = D.loads(pipes, opts)
        m = lds.sum { |y, pn| pn * y }
        t_kn = Beam.anchor_tension(m, zs.map { |z| z - foot }) / 1000.0
        v_kn = lds.sum { |_, pn| pn } / zs.size / 1000.0
        D.anchor_checks(checks, notes, size, t_kn, v_kn)
      end
    end
  end
end
