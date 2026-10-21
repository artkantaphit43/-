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
          a = Steel.get(tp[:shoe])[:a]
          list << pipe(tp[:y], top_level(s) + Steel.get(tp[:seat])[:t] + a + tp[:od] / 2.0, tp[:od], tp[:label])
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

      # Support +t+ for the pipes there (support coordinates; nil / empty:
      # the drawing's own lines, with guide points at their centres).
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
          carried, top_pipe = fit(t, s, nominal(t), [])
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
        guides = given ? [] : (carried + [top_pipe].compact).map { |p| [p[:y], p[:z]] }
        D::Result.new(part: part, bom: bom, checks: checks, notes: notes, carried: carried + [top_pipe].compact,
                      lines: lines, info: { type: t, section: key, anchor: s[:anchor], anchors: s[:bolts].size,
                                            nominal: !given, guides: guides, size: size, h: h })
      end

      # Pipes on the bearing steel (and the steam line on a frame's top);
      # the rest are noted.
      def fit(t, s, pipes, notes)
        h = Steel.depth(s[:sec])
        lo = h + 2.0 # clear of the post (washers under the flange)
        hi = s[:form] == :bracket ? s[:arm] : s[:width] - h - 2.0
        room = s[:form] == :frame ? top_level(s) - h - 10.0 : Float::INFINITY
        carried = []
        top = nil
        rest = []
        pipes.each do |p|
          u = Hardware.get(D.u_size(p))
          side = p[:r] + 1.0 + u[:d] / 2.0 + u[:wod] / 2.0
          bottom = Pipes.bottom(p)
          if bottom.between?(-1.0, RISE) && p[:y] - side >= lo && p[:y] + side <= hi && p[:z] + p[:r] + u[:d] <= room
            carried << p
          elsif s[:top] && Pipes.bare_bottom(p) >= top_level(s) + 30.0 && p[:y].between?(0.0, s[:width])
            top = p if top.nil? || (p[:y] - s[:top][:y]).abs < (top[:y] - s[:top][:y]).abs
          else
            rest << p
          end
        end
        rest.each do |p|
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
