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
    #   E  trapeze C 4" 800 long hung on 2 threaded rods (700 apart) from a
    #      round member above (C-clip under it, U-bolt over it), centred on
    #      that member's axis; lines at 230 and 565. E2 (or pipes stacked
    #      there): a second member on the same rods, its top 420 over the
    #      lower one (as C's top member).
    #
    #      E's support coordinates: x along the pipes (0 = the round
    #      member's axis), y along the bottom member from its end, z up
    #      (0 = its top – the pipes' undersides).
    #   F  single rod hanger from the round member over the pipe (a pipe
    #      turned to run with the truss): U cradle on the member with a
    #      U-bolt over it, turnbuckle, rod, two-bolt pipe clamp (MSS SP-58
    #      type 4 / 13). Rod by load, at least MSS SP-69's for the pipe.
    #      Its coordinates: x along the pipe, y across (0 = under the
    #      member's axis), z up (0 = the pipe's underside as placed).
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
                 th: 'ซัพพอร์ต D – โครงกล่อง C 4"' },
        'E' => { form: :hanger, sec: 'C100', length: 800.0, rods: [50.0, 750.0], gap: 420.0, tiers: 1,
                 pipes: [{ y: 230.0, od: 168.3, label: '6"' }, { y: 565.0, od: 114.3, ins: 50.0, label: '4" หุ้มฉนวน 50' }],
                 th: 'ซัพพอร์ต E – แขวนท่อกลม C 4"' },
        'E2' => { form: :hanger, sec: 'C100', length: 800.0, rods: [50.0, 750.0], gap: 420.0, tiers: 2, series: 'E',
                  pipes: [{ y: 230.0, od: 168.3, label: '6"' }, { y: 565.0, od: 114.3, ins: 50.0, label: '4" หุ้มฉนวน 50' }],
                  th: 'ซัพพอร์ต E 2 ชั้น – แขวนท่อกลม C 4"' },
        'F' => { form: :rod, pipes: [{ y: 0.0, od: 114.3, label: '4"' }], swing: 4.0,
                 th: 'ซัพพอร์ต F – แขวนเดี่ยวจากท่อกลม (เหล็กเส้น + เกลียวเร่ง + แคลมป์)' }
      }.freeze
      # F's cradle on the round member: 6 mm plate bent to a U with lips, w long.
      CRADLE = { t: 6.0, w: 60.0 }.freeze
      TURNBUCKLE = 150.0 # body length (MSS SP-58 type 13, 6")
      # E's top: C-clip of 6 mm plate bent round (t), h high, w deep across
      # the round member, its web +web+ out from the rod.
      CLIP = { t: 6.0, h: 60.0, w: 65.0, web: 35.0 }.freeze
      DROP = 600.0 # E without a placement: round member this far over the top tier
      RISE = 300.0 # a pipe up to this above the steel rides on a packer
      SNAP = 120.0 # a pipe drawn onto a support this near one of the drawing's places goes there

      module_function

      def type(t)
        TYPES[t] or raise ArgumentError, "unknown support #{t}"
      end

      # How far out from the column face the support carries pipes.
      def reach(t)
        s = type(t)
        return s[:length] if s[:form] == :hanger

        s[:form] == :bracket ? s[:arm] : s[:width] - Steel.depth(s[:sec])
      end

      def hanger?(t)
        type(t)[:form] == :hanger
      end

      # Hung from a round member (E, F): placed from a pipe under it or by
      # clicking the member, then the level.
      def hung?(t)
        %i[hanger rod].include?(type(t)[:form])
      end

      # The drawing's lines (E: on each tier).
      def nominal(t, geo = nil)
        s = type(t)
        if s[:form] == :hanger
          return levels(t, geo).flat_map do |v|
            s[:pipes].map do |q|
              r = q[:od] / 2.0 + q[:ins].to_f
              pipe(q[:y], v + r, q[:od], v.positive? ? "#{q[:label]} ชั้นบน" : q[:label]).merge(ins: q[:ins].to_f, r: r)
            end
          end
        end
        list = s[:pipes].map { |q| pipe(q[:y], q[:od] / 2.0, q[:od], q[:label]) }
        if (tp = s[:top])
          list << pipe(tp[:y], shoe_top(s) + tp[:od] / 2.0, tp[:od], tp[:label]).merge(top: true)
        end
        list
      end

      # E's placement (a support's struct): chord { z:, r: } – the round
      # member's axis over the bottom member's top, its radius – and gap,
      # the upper member's top (nil: one tier; E2 always has it).
      def hanger_geo(t, geo)
        s = type(t)
        g = (geo || {}).transform_keys(&:to_sym)
        gap = g[:gap]&.to_f
        gap ||= s[:gap] if s[:tiers] == 2
        c = g[:chord]&.transform_keys(&:to_sym)
        chord = c ? { z: c[:z].to_f, r: c[:r].to_f } : { z: (gap || 0.0) + DROP, r: 50.0 }
        { gap: gap, chord: chord }
      end

      # Tops of the steel pipes sit on: [0] (A–D, E), [0, gap] (E 2 tiers).
      def levels(t, geo = nil)
        return [0.0] unless hanger?(t)

        gap = hanger_geo(t, geo)[:gap]
        gap ? [0.0, gap] : [0.0]
      end

      # Which steel a pipe +p+ is on: its top (C's steam shoe, E's upper tier).
      def level_of(t, p, geo = nil)
        s = type(t)
        return on_top?(s, p) ? shoe_top(s) : 0.0 unless s[:form] == :hanger

        levels(t, geo).reverse.find { |v| Pipes.bottom(p) >= v - 1.0 } || 0.0
      end

      # E: the round member's underside over the top tier at least this
      # (the clip + rod nuts).
      def min_drop
        CLIP[:h] + 50.0
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
      # frame's posts / between E's rods): [from, to] out from the column
      # face (E: from the member's end).
      def bearing(s)
        return [s[:rods][0] + 20.0, s[:rods][1] - 20.0] if s[:form] == :hanger
        return [-20.0, 20.0] if s[:form] == :rod

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
      def rest(t, y, z, pipe = nil, taken = [], geo: nil)
        s = type(t)
        lo, hi = bearing(s)
        b = s[:sec] ? Steel.width(s[:sec]) / 2.0 : CRADLE[:w] / 2.0
        q = nominal(t, geo).find { |p| (p[:y] - y).abs <= 3.0 && (p[:z] - z).abs <= 3.0 }
        lv = levels(t, geo).find { |v| (z - v).abs <= 3.0 }
        r = if lv && y.between?(lo - 3.0, hi + 3.0)
              { z: lv, bare: false, half: b }
            elsif s[:top] && y.between?(lo, hi) && z.between?(top_level(s) - 3.0, shoe_top(s) + 3.0)
              { z: shoe_top(s), bare: true, half: s[:top][:shoe_len] / 2.0 }
            elsif q
              { z: q[:z] - q[:r], bare: q[:top] == true, half: b }
            end
        r && r.merge(y: place(t, s, y, r, pipe, taken, geo))
      end

      # Rest.y: the drawing's place for a pipe +drawn+ there (or y).
      def place(t, s, y, rest, drawn, taken, geo = nil)
        mine = taken.select { |p| level_of(t, p, geo) == rest[:z] }
        near = nominal(t, geo).select { |q| (Pipes.bottom(q) - rest[:z]).abs < 1.0 && (q[:y] - y).abs <= SNAP }
        best = near.sort_by { |q| (q[:y] - y).abs }.find do |q|
          if drawn
            r = drawn[:od] / 2.0 + drawn[:ins].to_f
            lift = rest[:bare] ? drawn[:od] / 2.0 : r
            p = pipe(q[:y], rest[:z] + lift, drawn[:od], 'new').merge(ins: drawn[:ins].to_f, r: r)
            carried, top = fit(t, s, mine + [p], [], geo)
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
      def build(t, pipes = nil, opts = {}, geo = nil)
        s = type(t)
        return rod_hanger(t, pipes, opts, geo) if s[:form] == :rod

        key = s[:sec]
        sec = Steel.get(key)
        h = sec[:h]
        b = sec[:b]
        tf = sec[:t2]
        xu = sec[:t1] / 2.0 # U-bolts / anchors mid the flange beside the web
        notes = []
        given = pipes && !pipes.empty?
        pipes = given ? pipes : nominal(t, geo)
        carried, top_pipe = fit(t, s, pipes, notes, geo)
        if carried.empty? && top_pipe.nil? && given
          notes << 'ไม่มีท่ออยู่ในตำแหน่งของซัพพอร์ต – ใส่ U-bolt ตามแบบ'
          # not where a pipe there (in the steel / off its places) is
          clear = nominal(t, geo).reject do |q|
            pipes.any? { |p| (p[:y] - q[:y]).abs < p[:r] + q[:r] && (p[:z] - q[:z]).abs < p[:r] + q[:r] }
          end
          carried, top_pipe = fit(t, s, clear, [], geo)
          given = false
        end
        part = Mesh::Part.new
        bom = []
        lines = []
        checks = []
        rod = nil
        case s[:form]
        when :bracket then bracket(part, bom, lines, checks, s, key, carried, opts)
        when :frame then frame(part, bom, lines, checks, s, key, carried, top_pipe, opts)
        else rod = hanger(part, bom, lines, checks, t, s, key, carried, opts, geo)
        end
        carried.each do |p|
          v = level_of(t, p, geo)
          D.packer(part, bom, p, v, b)
          D.pipe_u_bolt(part, bom, p, v, tf, x: xu)
        end
        anchors(part, bom, checks, notes, s, key, carried + [top_pipe].compact, opts) if s[:anchor]
        checks.each do |c|
          next if c[:ok] || c[:kind] == :anchor # anchors note themselves

          notes << "#{c[:item]} เกินค่าที่ยอมให้ (#{c[:value]} > #{c[:limit]} #{c[:unit]}) – ลดระยะห่างซัพพอร์ต"
        end
        size = case s[:form]
               when :bracket then [s[:arm], s[:post]]
               when :frame then [s[:width], s[:height]]
               else [s[:length], levels(t, geo).last + h]
               end
        free = given ? free_places(t, carried, top_pipe, geo) : carried + [top_pipe].compact
        tiers = levels(t, geo).size
        title = s[:form] == :hanger && tiers == 2 ? TYPES['E2'][:th] : s[:th]
        D::Result.new(part: part, bom: bom, checks: checks, notes: notes, carried: carried + [top_pipe].compact,
                      lines: lines, info: { type: t, section: key, anchor: s[:anchor], anchors: s[:bolts].to_a.size,
                                            rod: rod, nominal: !given, guides: free.map { |p| [p[:y], p[:z]] },
                                            rests: free.map { |p| [p[:y], p[:top] ? shoe_top(s) : Pipes.bottom(p)] },
                                            size: size, h: h, tiers: tiers, title: title })
      end

      # The drawing's lines whose place no pipe there takes.
      def free_places(t, carried, top_pipe, geo = nil)
        nominal(t, geo).reject do |q|
          next !top_pipe.nil? if q[:top]

          carried.any? do |p|
            level_of(t, p, geo) == level_of(t, q, geo) && (p[:y] - q[:y]).abs < p[:r] + q[:r] + 25.0
          end
        end
      end

      # Pipes on the bearing steel (and the steam line on a frame's top);
      # the rest are noted. The washers under the flange stay clear of a
      # bracket's back flange on the column (the post's front flange stops
      # at the mitre, below the nuts) / of a frame's back post.
      def fit(t, s, pipes, notes, geo = nil)
        return fit_hanger(t, s, pipes, notes, geo) if s[:form] == :hanger
        return fit_rod(t, s, pipes, notes, geo) if s[:form] == :rod

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

      # ---------- E ----------

      # E: pipes on a tier – between the rods, under the upper member /
      # the round member; the rest are noted.
      def fit_hanger(t, s, pipes, notes, geo)
        hg = hanger_geo(t, geo)
        h = Steel.depth(s[:sec])
        lo, hi = bearing(s)
        lv = levels(t, geo)
        under = hg[:chord][:z] - hg[:chord][:r] - 10.0
        carried = []
        rest = []
        pipes.each do |p|
          b = Pipes.bottom(p)
          v = lv.reverse.find { |l| b >= l - 1.0 }
          roof = v && v < lv.last ? lv.last - h - 10.0 : under
          ok = v && b - v <= RISE && p[:y] - side(p) >= lo && p[:y] + side(p) <= hi &&
               p[:z] + p[:r] + Hardware.get(D.u_size(p))[:d] <= roof
          (ok ? carried : rest) << p
        end
        rest.each do |p|
          b = Pipes.bottom(p)
          deep = lv.find { |l| b < l - 1.0 && b + 2.0 * p[:r] > l - h }
          if deep && p[:y] + p[:r] > 0 && p[:y] - p[:r] < s[:length]
            notes << "ท่อ #{p[:label]} จมในเหล็ก #{(deep - b).round} มม. – ซัพพอร์ตอยู่ระดับที่วางไว้: " \
                     'ยกท่อขึ้น หรือวาดท่อใหม่ลงจุดไกด์/บนเหล็ก'
          elsif p[:y] + p[:r] > -150.0 && p[:y] - p[:r] < s[:length] + 150.0 && b < under
            notes << "ท่อ #{p[:label]} ไม่อยู่ในตำแหน่งที่ซัพพอร์ต #{t} รับได้ – ไม่ได้รัด"
          end
        end
        [carried.sort_by { |p| [level_of(t, p, geo), p[:y]] }, nil]
      end

      # E's steel: the member(s), the rods (sized by load, MSS SP-58) and
      # their clips under the round member. Returns the rod size.
      def hanger(part, bom, lines, checks, t, s, key, carried, opts, geo)
        hg = hanger_geo(t, geo)
        sec = Steel.get(key)
        h = sec[:h]
        b = sec[:b]
        l = s[:length]
        y1, y2 = s[:rods]
        lv = levels(t, geo)
        if hg[:chord][:z] - hg[:chord][:r] - lv.last < min_drop
          raise ArgumentError, "ท่อกลมด้านบนต่ำเกินไป – ใต้ท่อกลมต้องสูงกว่าคานบนสุดอย่างน้อย #{min_drop.round} มม."
        end

        reac = [0.0, 0.0]
        lv.each_with_index do |v, i|
          standing(part, key, [0.0, v - h / 2.0], [l, v - h / 2.0])
          outline(lines, [[0.0, v - h], [l, v - h], [l, v], [0.0, v], [0.0, v - h]], b)
          what = i.zero? ? 'คานรับท่อ' : 'คานรับท่อชั้นบน'
          D.bom_steel(bom, key, l, what)
          mine = carried.select { |p| level_of(t, p, geo) == v }
          r = beam(checks, "#{what} #{sec[:inch]}", key, 0.0, l, y1, y2, D.loads(mine, opts))
          reac[0] += r[:r1]
          reac[1] += r[:r2]
        end
        kn = reac.max / 1000.0
        rsz = Hardware.size_for(kn, :rod_kn)
        rs = Hardware.get(rsz)
        D.check(checks, "เหล็กเส้นเกลียว #{Hardware.label(rsz)}: แรงดึง (MSS SP-58)", kn, rs[:rod_kn], 'kN', kind: :rod)
        t2 = sec[:t2]
        low = -[50.0, t2 + Hardware.stack_height(rsz) + 0.6 * rs[:d]].max
        len = 0.0
        [[y1, -1.0], [y2, 1.0]].each do |y, out|
          top = clip(part, bom, lines, hg[:chord], y, out, rsz)
          Hardware.fastening(part, [0.0, y, -t2], [0, 0, -1.0], rsz) # carries the member
          Hardware.fastening(part, [0.0, y, 0.0], [0, 0, 1.0], rsz)  # lock nut
          if lv.size > 1 # through the upper member: under its bottom flange, lock nut on top
            Hardware.fastening(part, [0.0, y, lv.last - h], [0, 0, -1.0], rsz)
            Hardware.fastening(part, [0.0, y, lv.last], [0, 0, 1.0], rsz)
          end
          Hardware.rod(part, [0.0, y, low], [0.0, y, top], rsz)
          lines << [[0.0, y, low], [0.0, y, top]]
          len = top - low
        end
        D.bom_item(bom, 'rod', "เหล็กเส้นเกลียว #{Hardware.label(rsz)} ยาว #{len.round} มม.", 2, key: "rod #{rsz} #{len.round}")
        D.nuts(bom, rsz, 2 * (2 + 2 * lv.size))
        rsz
      end

      # C-clip under the round member at rod +y+ (web toward +out+): its
      # top flange under the member with a U-bolt over it (nuts under the
      # flange), the rod through the bottom flange – nut + washer on it,
      # lock nut under. Returns the rod's top end.
      def clip(part, bom, lines, chord, y, out, rsz)
        t = CLIP[:t]
        zc = chord[:z]
        r = chord[:r]
        usz = Hardware.u_bolt_size(2.0 * r)
        us = Hardware.get(usz)
        rc = r + 0.5 + us[:d] / 2.0
        lc = 2.0 * (rc + us[:wod] / 2.0) + 10.0
        z1 = zc - r
        z0 = z1 - CLIP[:h]
        yw = y + out * CLIP[:web]
        ya, yb = [yw, y - out * (CLIP[:w] - CLIP[:web])].minmax
        wa, wb = [yw, yw - out * t].minmax
        part.add(:steel, Mesh.box([-lc / 2.0, ya, z1 - t], [lc / 2.0, yb, z1]))
        part.add(:steel, Mesh.box([-lc / 2.0, ya, z0], [lc / 2.0, yb, z0 + t]))
        part.add(:steel, Mesh.box([-lc / 2.0, wa, z0 + t], [lc / 2.0, wb, z1 - t]))
        D.box_lines(lines, [-lc / 2.0, ya, z0], [lc / 2.0, yb, z1])
        bom << { cat: 'plate', key: 'clip', desc: "ตัวยึด C เพลทพับ #{t.round} มม. ใต้ท่อกลม", qty: 1,
                 kg: (lc * (2.0 * CLIP[:w] + CLIP[:h] - 2.0 * t) * t * Steel::RHO).round(2) }
        leg = zc - (z1 - t - Hardware.stack_height(usz) - 0.6 * us[:d])
        Hardware.u_bolt(part, [0.0, y, zc], [1.0, 0, 0], [0, 0, 1.0], r + 0.5, usz, leg)
        [-1, 1].each { |k| Hardware.fastening(part, [k * rc, y, z1 - t], [0, 0, -1.0], usz) }
        D.bom_item(bom, 'ubolt', "U-bolt #{Hardware.label(usz)} รัดท่อกลมบน Ø#{(2 * r).round}", 1,
                   key: "ubt #{usz} #{(2 * r).round}")
        D.nuts(bom, usz, 2)
        Hardware.fastening(part, [0.0, y, z0], [0, 0, -1.0], rsz)
        top = Hardware.fastening(part, [0.0, y, z0 + t], [0, 0, 1.0], rsz)
        top[2] + 0.6 * Hardware.get(rsz)[:d]
      end

      # ---------- F ----------

      # F's round member: { z:, r:, along: 'x' (over the pipe, along it) /
      # 'y' (across it) } – its axis over the support's origin.
      def rod_geo(geo)
        g = (geo || {}).transform_keys(&:to_sym)
        c = g[:chord]&.transform_keys(&:to_sym)
        return { z: 114.3 + DROP, r: 50.0, along: 'x' } unless c

        { z: c[:z].to_f, r: c[:r].to_f, along: (c[:along] || 'x').to_s }
      end

      # MSS SP-69 smallest rod for a single rod hanger, by pipe OD.
      def min_rod(od)
        if od <= 61.0 then '3/8'
        elsif od <= 102.0 then '1/2'
        elsif od <= 142.0 then '5/8'
        else '3/4'
        end
      end

      # Two-bolt pipe clamp (MSS SP-58 type 4): band t × w, bolt size.
      def clamp_size(od)
        if od <= 61.0 then { t: 5.0, w: 25.0, bolt: '3/8' }
        elsif od <= 115.0 then { t: 6.0, w: 32.0, bolt: '1/2' }
        else { t: 6.0, w: 38.0, bolt: '1/2' }
        end
      end

      # F carries one pipe: the one under its round member (nearest the
      # axis), with room for the cradle, turnbuckle and clamp above it.
      def fit_rod(t, _s, pipes, notes, geo)
        c = rod_geo(geo)
        roof = c[:z] - c[:r] - 60.0
        ok = pipes.select { |p| p[:y].abs <= 250.0 && p[:z] + p[:r] + clamp_ear(p) <= roof }
        me = ok.min_by { |p| p[:y].abs + 0.25 * Pipes.bottom(p).abs }
        pipes.each do |p|
          next if p.equal?(me) || p[:y].abs > 400.0 || p[:z] - p[:r] > c[:z]

          notes << "ท่อ #{p[:label]} ไม่อยู่ใต้ซัพพอร์ต #{t} (แขวนเดี่ยว 1 ท่อ) – ไม่ได้รัด"
        end
        [[me].compact, nil]
      end

      # How far the clamp's top ears reach over the pipe's top.
      def clamp_ear(p)
        cs = clamp_size(p[:od])
        2.0 * Hardware.get(cs[:bolt])[:wod] + 15.0
      end

      def rod_hanger(t, pipes, opts, geo)
        s = type(t)
        notes = []
        given = pipes && !pipes.empty?
        carried, = fit_rod(t, s, given ? pipes : nominal(t), notes, geo)
        if carried.empty? && given
          notes << 'ไม่มีท่อใต้ซัพพอร์ต – แคลมป์ตามแบบ'
          carried, = fit_rod(t, s, nominal(t), [], geo)
          given = false
        end
        raise ArgumentError, 'ท่อกลมด้านบนต่ำเกินไปสำหรับซัพพอร์ต F' if carried.empty?

        p = carried.first
        c = rod_geo(geo)
        part = Mesh::Part.new
        bom = []
        lines = []
        checks = []
        kn = Pipes.load_n(p, D.spacing(p, opts)) / 1000.0
        rsz = [Hardware.size_for(kn, :rod_kn), min_rod(p[:od])].max_by { |z| Hardware::ORDER.index(z) }
        rs = Hardware.get(rsz)
        D.check(checks, "เหล็กเส้นเกลียว #{Hardware.label(rsz)}: แรงดึง (MSS SP-58)", kn, rs[:rod_kn], 'kN', kind: :rod)
        top = cradle(part, bom, lines, c, rsz)
        low = pipe_clamp(part, bom, lines, p, rsz)
        dir = Vec.unit(Vec.sub(top, low))
        tilt = Math.acos(dir[2].clamp(-1.0, 1.0)) * 180.0 / Math::PI
        if tilt > s[:swing]
          notes << "เหล็กเส้นเอียง #{tilt.round(1)}° (เกิน #{s[:swing].round}° ตาม MSS SP-58) – " \
                   "ท่อเยื้องจากแนวท่อกลม #{Math.hypot(top[0] - low[0], top[1] - low[1]).round} มม."
        end
        Hardware.rod(part, low, top, rsz)
        lines << [low, top]
        len = Vec.dist(low, top)
        room = len - 2.0 * (Hardware.stack_height(rsz) + rs[:d]) - 80.0
        if room >= TURNBUCKLE
          turnbuckle(part, Vec.along(top, dir, -(3.0 * rs[:d] + 40.0 + TURNBUCKLE / 2.0)), dir, rsz)
          D.bom_item(bom, 'rod', "เกลียวเร่ง (Turnbuckle) #{Hardware.label(rsz)}", 1, key: "tb #{rsz}")
          D.nuts(bom, rsz, 2)
        else
          notes << 'ระยะแขวนสั้น – ไม่ใส่เกลียวเร่ง'
        end
        D.bom_item(bom, 'rod', "เหล็กเส้นเกลียว #{Hardware.label(rsz)} ยาว #{len.round} มม.", 1, key: "rod #{rsz} #{len.round}")
        checks.each do |ck|
          notes << "#{ck[:item]} เกินค่าที่ยอมให้ (#{ck[:value]} > #{ck[:limit]} #{ck[:unit]}) – ลดระยะห่างซัพพอร์ต" unless ck[:ok]
        end
        D::Result.new(part: part, bom: bom, checks: checks, notes: notes, carried: carried, lines: lines,
                      info: { type: t, section: nil, anchor: nil, anchors: 0, rod: rsz, rods: 1, nominal: !given,
                              guides: given ? [] : [[p[:y], p[:z]]], rests: given ? [] : [[p[:y], Pipes.bottom(p)]],
                              size: [CRADLE[:w], c[:z]], h: 0.0, tiers: 1, title: s[:th] })
      end

      # A flat bar w wide (along x), t thick, bent along +path+ ([y, z]
      # points of its centre line): one closed solid.
      def strap(path, w, t)
        n = path.size
        rings = path.each_with_index.map do |(y, z), i|
          a = path[[i - 1, 0].max]
          b = path[[i + 1, n - 1].min]
          l = Math.hypot(b[0] - a[0], b[1] - a[1])
          ny = -(b[1] - a[1]) / l * t / 2.0
          nz = (b[0] - a[0]) / l * t / 2.0
          [[-w / 2.0, y + ny, z + nz], [w / 2.0, y + ny, z + nz], [w / 2.0, y - ny, z - nz], [-w / 2.0, y - ny, z - nz]]
        end
        polys = []
        rings.each_cons(2) { |ra, rb| 4.times { |k| polys << [ra[k], ra[(k + 1) % 4], rb[(k + 1) % 4], rb[k]] } }
        polys << rings.first.reverse << rings.last
        solid = Mesh::Solid.new(polys)
        Mesh.volume(solid).negative? ? Mesh::Solid.new(polys.map(&:reverse)) : solid
      end

      # x ↔ y (a part drawn for a member along x, turned for one along y).
      def turned(solid)
        Mesh::Solid.new(solid.polys.map { |q| q.map { |a, b, c| [b, a, c] }.reverse })
      end

      # U cradle under the round member (lips out at the top, the member
      # resting on its edges), a U-bolt over the member through the lips,
      # the rod through its bottom – nut + washer inside, lock nut under.
      # Returns the rod's top end.
      def cradle(part, bom, lines, c, rsz)
        t = CRADLE[:t]
        zc = c[:z]
        r = c[:r]
        usz = Hardware.u_bolt_size(2.0 * r)
        us = Hardware.get(usz)
        rs = Hardware.get(rsz)
        rc = r + 0.5 + us[:d] / 2.0
        half = [[0.6 * r, r - 10.0].min, 15.0].max # opening
        zt = zc - Math.sqrt(r * r - half * half)  # the member rests on the edges
        sag = zt - (zc - r)
        h = [45.0, t + Hardware.stack_height(rsz) + 0.6 * rs[:d] + sag + 8.0].max
        lip = rc + us[:wod] / 2.0 + 5.0
        ys = half + t / 2.0
        path = [[-lip, zt - t / 2.0], [-ys, zt - t / 2.0], [-ys, zt - h + t / 2.0], [ys, zt - h + t / 2.0],
                [ys, zt - t / 2.0], [lip, zt - t / 2.0]]
        along = c[:along] == 'y'
        put = ->(solid) { part.add(:steel, along ? turned(solid) : solid) }
        pt = ->(q) { along ? [q[1], q[0], q[2]] : q }
        put.call(strap(path, CRADLE[:w], t))
        a = pt.call([-CRADLE[:w] / 2.0, -lip, zt - h])
        b = pt.call([CRADLE[:w] / 2.0, lip, zt])
        D.box_lines(lines, a.zip(b).map(&:min), a.zip(b).map(&:max))
        bom << { cat: 'plate', key: 'cradle', desc: "ตัวรับ U เพลทพับ #{t.round} มม. บนท่อกลม", qty: 1,
                 kg: (CRADLE[:w] * (2.0 * lip + 2.0 * h) * t * Steel::RHO).round(2) }
        lat = pt.call([0.0, 1.0, 0.0])
        leg = zc - (zt - t - Hardware.stack_height(usz) - 0.6 * us[:d])
        Hardware.u_bolt(part, [0.0, 0.0, zc], lat, [0, 0, 1.0], r + 0.5, usz, leg)
        [-1, 1].each { |k| Hardware.fastening(part, Vec.add(Vec.scale(lat, k * rc), [0, 0, zt - t]), [0, 0, -1.0], usz) }
        D.bom_item(bom, 'ubolt', "U-bolt #{Hardware.label(usz)} รัดท่อกลมบน Ø#{(2 * r).round}", 1,
                   key: "ubt #{usz} #{(2 * r).round}")
        D.nuts(bom, usz, 2)
        Hardware.fastening(part, [0.0, 0.0, zt - h], [0, 0, -1.0], rsz)
        top = Hardware.fastening(part, [0.0, 0.0, zt - h + t], [0, 0, 1.0], rsz)
        D.nuts(bom, rsz, 2)
        [0.0, 0.0, top[2] + 0.6 * rs[:d]]
      end

      # Two-bolt pipe clamp round pipe p (over its insulation): two halves,
      # their ears up (clamp bolt + load bolt, the rod's end block between)
      # and down (one bolt). Returns the rod's lower end.
      def pipe_clamp(part, bom, lines, p, rsz)
        cs = clamp_size(p[:od])
        t = cs[:t]
        bs = Hardware.get(cs[:bolt])
        rs = Hardware.get(rsz)
        g = rs[:d] + 6.0 # between the ears
        e = g / 2.0 + t / 2.0
        rr = p[:r] + t / 2.0
        yc = p[:y]
        zc = p[:z]
        join = Math.sqrt(rr * rr - e * e)
        z1 = join + 0.9 * bs[:wod]
        z2 = z1 + 1.1 * bs[:wod]
        top = z2 + 0.75 * bs[:wod]
        zb = -join - 0.9 * bs[:wod]
        bot = zb - 0.75 * bs[:wod]
        a0 = Math.asin(e / rr)
        arc = (0..24).map do |i|
          a = a0 + (Math::PI - 2.0 * a0) * i / 24.0
          [rr * Math.sin(a), rr * Math.cos(a)]
        end
        half = [[e, top]] + arc + [[e, bot]]
        [1, -1].each do |k|
          part.add(:steel, strap(half.map { |y, z| [yc + k * y, zc + z] }, cs[:w], t))
        end
        [zc + z1, zc + z2, zc + zb].each do |z|
          ends = [-1, 1].map { |k| [0.0, yc + k * (e + t / 2.0), z] }
          Hardware.rod(part, Vec.along(ends[0], [0, -1.0, 0], Hardware.stack_height(cs[:bolt]) + 0.6 * bs[:d]),
                       Vec.along(ends[1], [0, 1.0, 0], Hardware.stack_height(cs[:bolt]) + 0.6 * bs[:d]), cs[:bolt])
          Hardware.fastening(part, ends[0], [0, -1.0, 0], cs[:bolt])
          Hardware.fastening(part, ends[1], [0, 1.0, 0], cs[:bolt])
        end
        blk = 1.6 * rs[:d]
        part.add(:galv, Mesh.box([-cs[:w] * 0.4, yc - g / 2.0 + 0.5, zc + z2 - blk / 2.0],
                                 [cs[:w] * 0.4, yc + g / 2.0 - 0.5, zc + z2 + blk / 2.0]))
        D.box_lines(lines, [-cs[:w] / 2.0, yc - rr - t, zc + bot], [cs[:w] / 2.0, yc + rr + t, zc + top])
        D.bom_item(bom, 'clamp', "แคลมป์รัดท่อ 2 สลัก (MSS type 4) ท่อ #{p[:label]} – แถบ #{t.round}×#{cs[:w].round}", 1,
                   key: "clamp #{p[:od].round} #{p[:ins].to_f.round}")
        D.bom_item(bom, 'nut', "สลักเกลียว + น็อต + แหวน #{Hardware.label(cs[:bolt])} (แคลมป์)", 3, key: "bolt #{cs[:bolt]}")
        [0.0, yc, zc + z2 + blk / 2.0]
      end

      # Turnbuckle (MSS SP-58 type 13) on the rod: two threaded ends joined
      # by side bars, a lock nut at each end.
      def turnbuckle(part, mid, dir, rsz)
        s = Hardware.get(rsz)
        half = TURNBUCKLE / 2.0
        side = Vec.unit(Vec.cross(dir, dir[2].abs > 0.9 ? [1.0, 0, 0] : [0, 0, 1.0]))
        [-1, 1].each do |k|
          a = Vec.along(mid, dir, k * half)
          b = Vec.along(a, dir, -k * 1.4 * s[:d])
          part.add(:galv, Mesh.hex(k.positive? ? b : a, k.positive? ? a : b, 1.5 * s[:f]))
          Hardware.nut(part, a, Vec.scale(dir, k), rsz)
        end
        [-1, 1].each do |k|
          off = Vec.scale(side, k * 0.9 * s[:f])
          a = Vec.add(Vec.along(mid, dir, -half + 1.4 * s[:d]), off)
          b = Vec.add(Vec.along(mid, dir, half - 1.4 * s[:d]), off)
          part.add(:galv, Mesh.cylinder(a, b, 0.35 * s[:d]))
        end
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
