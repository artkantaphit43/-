# frozen_string_literal: true

require_relative 'steel'
require_relative 'hardware'
require_relative 'beam'
require_relative 'pipes'

module ArtK
  module SteelSupport
    # The four support details of the user's drawings, in support
    # coordinates: x along the pipes, y across, z up, origin on the
    # clicked pipe's axis. Wall details have the wall face at y = −wall.
    #
    #   wf – box frame of channel on a wall / column, 3 expansion anchors,
    #        pipes U-bolted inside, a higher (hot) line on angles on top
    #   wb – triangular wall bracket: arm, post and 45° brace, 2 anchors
    #   th – trapeze hung from a round truss chord: U-bolt + channel cleat,
    #        threaded rods, channel with the pipes U-bolted on it
    #   tt – channel laid across round truss chords below, U-bolted to them,
    #        pipes U-bolted on top
    #
    # Each returns a Result: the geometry, BOM rows, checks (stress,
    # deflection, rod / anchor load) and notes. Sections, rods and anchors
    # are chosen as the lightest that pass unless the options fix them.
    module Details
      TYPES = {
        'wf' => { th: 'โครงกล่องยึดผนัง/เสา', en: 'Wall box frame', min: 'C100', anchor: '1/2', anchors: 3 },
        'wb' => { th: 'ขาค้ำสามเหลี่ยมยึดผนัง', en: 'Wall triangle bracket', min: 'C75', anchor: '3/8', anchors: 2 },
        'th' => { th: 'แขวนใต้โครง Truss', en: 'Trapeze under truss', min: 'C75', rod: '3/8' },
        'tt' => { th: 'วางบนโครง Truss', en: 'Channel on truss', min: 'C75' }
      }.freeze

      RISE = 300.0        # pipes whose undersides differ by ≤ this share a member (packers)
      REACH = 1500.0      # farthest pipe face from the wall
      FRAME_RISE = 1200.0 # a hot line up to this above the box rides on top
      DEFL = 240.0        # deflection limit span / 240
      SHOE_LEN = 200.0    # angle shoe length along the pipe
      PAD = 'แผ่นรอง (packer) เหล็กแผ่น'

      Result = Struct.new(:part, :bom, :checks, :notes, :carried, :lines, :info, keyword_init: true) do
        def ok?
          checks.all? { |c| c[:ok] }
        end

        # The steel itself passes (anchors / rods are sized on their own).
        def members_ok?
          checks.all? { |c| c[:ok] || c[:kind] != :member }
        end
      end

      module_function

      # ---------- shared ----------

      def opt(opts, key, default)
        v = opts[key] || opts[key.to_s]
        v.nil? || v == 'auto' || v == '' ? default : v
      end

      def fixed?(opts, key)
        v = opts[key] || opts[key.to_s]
        !(v.nil? || v == 'auto' || v == '')
      end

      def sections(opts, type)
        return [opt(opts, :section, nil)] if fixed?(opts, :section)

        min = Steel::AUTO.index(TYPES[type][:min])
        Steel::AUTO.drop(min)
      end

      def spacing(p, opts)
        s = opts[:spacing_m] || opts['spacing_m']
        s.to_f.positive? ? s.to_f : p[:span_m].to_f
      end

      def loads(pipes, opts)
        pipes.map { |p| [p[:y], Pipes.load_n(p, spacing(p, opts))] }
      end

      def u_size(p)
        Hardware.u_bolt_size(p[:od])
      end

      # Room a U-bolt with its washer needs beyond the pipe's outer face.
      def u_room(p)
        s = Hardware.get(u_size(p))
        s[:d] + s[:wod] / 2.0 + 15.0
      end

      def check(list, item, value, limit, unit, kind: :member)
        list << { item: item, value: value.round(2), limit: limit.round(2), unit: unit, ok: value <= limit + 1e-9,
                  kind: kind }
      end

      # Bending + deflection of a member on two supports.
      def beam_checks(list, name, key, x0, x1, s1, s2, lds)
        pr = Steel.props(key)
        r = Beam.two_support(x0, x1, s1, s2, lds, Steel::E * pr[:i_flat])
        check(list, "#{name}: หน่วยแรงดัด (bending)", r[:m_max] / pr[:z_flat], Steel::FB, 'MPa')
        check(list, "#{name}: การแอ่นตัว (deflection)", r[:defl], (x1 - x0) / DEFL, 'mm')
        r
      end

      def bom_steel(bom, key, len, what)
        bom << { cat: 'steel', key: key, desc: Steel.get(key)[:name], what: what, qty: 1, length: len.round,
                 kg: (len / 1000.0 * Steel.kg_m(key)).round(2) }
      end

      def bom_item(bom, cat, desc, qty, key: nil)
        bom << { cat: cat, key: key || desc, desc: desc, qty: qty }
      end

      def bom_pad(bom, kg)
        bom << { cat: 'plate', key: 'pad', desc: PAD, qty: 1, kg: kg.round(2) }
      end

      # Packer plate under a pipe whose underside is above the member top.
      def packer(part, bom, p, z_top, depth)
        gap = Pipes.bottom(p) - z_top
        return if gap < 2.0

        w = 2.0 * (p[:r] + Hardware.get(u_size(p))[:d]) + 10.0
        part.add(:steel, Mesh.box([-depth / 2.0 + 5.0, p[:y] - w / 2.0, z_top], [depth / 2.0 - 5.0, p[:y] + w / 2.0, z_top + gap]))
        bom_pad(bom, (depth - 10.0) * w * gap * Steel::RHO)
      end

      # U-bolt round pipe p (over its insulation), legs through a web whose
      # top face is at z_web (thickness t), washer + nut underneath.
      def pipe_u_bolt(part, bom, p, z_web, t, x: 0.0)
        size = u_size(p)
        s = Hardware.get(size)
        rc = p[:r] + 1.0 + s[:d] / 2.0
        under = z_web - t
        leg = p[:z] - (under - Hardware.stack_height(size) - 0.6 * s[:d])
        Hardware.u_bolt(part, [x, p[:y], p[:z]], [0, 1.0, 0], [0, 0, 1.0], p[:r] + 1.0, size, leg)
        [-1, 1].each { |k| Hardware.fastening(part, [x, p[:y] + k * rc, under], [0, 0, -1.0], size) }
        bom_item(bom, 'ubolt', "U-bolt #{Hardware.label(size)} รัดท่อ #{p[:label]}", 1, key: "ub #{size} #{p[:od].round}")
        nuts(bom, size, 2)
      end

      def nuts(bom, size, n)
        bom_item(bom, 'nut', "น็อตตัวเมีย + แหวน #{Hardware.label(size)}", n, key: "nut #{size}")
      end

      def box_lines(lines, min, max)
        x0, y0, z0 = min
        x1, y1, z1 = max
        c = [[x0, y0, z0], [x1, y0, z0], [x1, y1, z0], [x0, y1, z0], [x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1]]
        [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]].each do |i, j|
          lines << [c[i], c[j]]
        end
      end

      # Pipes that fit beside a wall at y = −wall.
      def by_wall(pipes, wall, notes)
        pipes.select do |p|
          near = p[:y] - p[:r] - u_room(p)
          ok = near > -wall + 55.0 && wall + p[:y] + p[:r] <= REACH
          notes << "ท่อ #{p[:label]} #{near <= -wall + 55.0 ? 'ชิดผนังเกิน' : 'ห่างผนังเกิน 1.5 m'} – ไม่ได้รับ" unless ok
          ok
        end
      end

      def tiers(pipes)
        z_b = pipes.map { |p| Pipes.bottom(p) }.min
        lower = pipes.select { |p| Pipes.bottom(p) - z_b <= RISE }
        [z_b, lower, pipes - lower]
      end

      # Anchor size: the option, or the smallest from +min+ carrying t and v.
      def anchor_size(opts, min, t_kn, v_kn)
        return opt(opts, :anchor, min) if fixed?(opts, :anchor)

        Hardware::ORDER.drop(Hardware::ORDER.index(min)).find do |s|
          a = Hardware.get(s)
          t_kn / a[:anc_t] + v_kn / a[:anc_v] <= 1.0
        end || Hardware::ORDER.last
      end

      def anchor_checks(list, notes, size, t_kn, v_kn)
        a = Hardware.get(size)
        c = check(list, "พุก #{Hardware.label(size)}: แรงดึง+แรงเฉือน (T/Ta + V/Va)",
                  t_kn / a[:anc_t] + v_kn / a[:anc_v], 1.0, '', kind: :anchor).last
        notes << 'พุกรับแรงไม่พอ – เพิ่มจำนวนพุก/แผ่นเพลท หรือลดระยะห่างซัพพอร์ต' unless c[:ok]
      end

      # Run +body+ for each candidate section until all its checks pass;
      # the last one (with failing checks) when none does.
      def choose(opts, type)
        res = nil
        sections(opts, type).each do |key|
          res = yield key
          return res if res.members_ok? || fixed?(opts, :section)
        end
        res.notes << 'เหล็กใหญ่สุดยังไม่ผ่านการตรวจ – ลดระยะห่างซัพพอร์ตหรือเลือกเหล็กเอง' unless res.members_ok?
        res
      end

      def result(part, bom, checks, notes, carried, lines, info)
        Result.new(part: part, bom: bom, checks: checks, notes: notes, carried: carried, lines: lines, info: info)
      end

      # ---------- wf: wall box frame ----------

      def wall_frame(pipes, wall, opts = {})
        notes = []
        pipes = by_wall(pipes, wall, notes)
        raise 'ไม่มีท่อที่วางในโครงได้' if pipes.empty?

        choose(opts, 'wf') { |key| wall_frame_with(key, pipes, wall, opts, notes.dup) }
      end

      def shoe_angle(p)
        need = [p[:ins].to_f + 25.0, 50.0].max
        Steel::ANGLES.find { |k| Steel.get(k)[:a] >= need } || Steel::ANGLES.last
      end

      def wall_frame_with(key, pipes, wall, opts, notes)
        sec = Steel.get(key)
        b = sec[:b]
        h = sec[:h]
        t = Steel.web(key)
        z_b, lower, rest = tiers(pipes)
        reach_up = lower.map { |p| Pipes.top(p) + Hardware.get(u_size(p))[:d] }.max
        base = ->(p) { Pipes.bare_bottom(p) - Steel.get(shoe_angle(p))[:a] }
        upper = rest.select { |p| base.call(p) - b >= reach_up + 30.0 && Pipes.bottom(p) - z_b <= FRAME_RISE }
        lo = upper.map(&base).min
        upper = upper.select { |p| base.call(p) - lo <= RISE } if lo
        (rest - upper).each { |p| notes << "ท่อ #{p[:label]} อยู่ระดับที่โครงรับไม่ได้ – ไม่ได้รับ" }
        z_t = lo || reach_up + 50.0 + b
        z_bot = z_b - b
        y_w = -wall
        y_in = y_w + b
        y_out = (lower.map { |p| p[:y] + p[:r] + [u_room(p), 50.0].max } +
                 upper.map { |p| p[:y] + Steel.get(shoe_angle(p))[:a] + 20.0 }).max + b
        part = Mesh::Part.new
        bom = []
        lines = []
        x = [1.0, 0, 0]
        part.add(:steel, Steel.member(key, [0, y_w, z_bot], [0, y_w, z_t], x, [0, 1.0, 0]))
        part.add(:steel, Steel.member(key, [0, y_out, z_bot], [0, y_out, z_t], x, [0, -1.0, 0]))
        part.add(:steel, Steel.member(key, [0, y_in, z_b], [0, y_out - b, z_b], x, [0, 0, -1.0]))
        part.add(:steel, Steel.member(key, [0, y_in, z_t], [0, y_out - b, z_t], x, [0, 0, -1.0]))
        box_lines(lines, [-h / 2, y_w, z_bot], [h / 2, y_out, z_t])
        bom_steel(bom, key, 2 * (z_t - z_bot), 'เสาโครง 2 ตัว')
        bom_steel(bom, key, 2 * (y_out - b - y_in), 'คานบน + คานล่าง')
        lower.each do |p|
          packer(part, bom, p, z_b, h)
          pipe_u_bolt(part, bom, p, z_b, t)
        end
        upper.each { |p| angle_shoe(part, bom, p, z_t, base.call(p)) }
        checks = []
        beam_checks(checks, "คานล่าง #{sec[:inch]}", key, y_in, y_out - b, y_in, y_out - b, loads(lower, opts))
        beam_checks(checks, "คานบน #{sec[:inch]}", key, y_in, y_out - b, y_in, y_out - b, loads(upper, opts)) if upper.any?
        all = lower + upper
        n = (opts[:anchors] || opts['anchors'] || TYPES['wf'][:anchors]).to_i.clamp(2, 4)
        fr = n == 2 ? [0.2, 0.8] : (0...n).map { |i| 0.15 + 0.7 * i / (n - 1) }
        zs = fr.map { |f| z_bot + f * (z_t - z_bot) }
        p_all = loads(all, opts)
        m = p_all.sum { |y, pn| pn * (y - y_w) }
        t_kn = Beam.anchor_tension(m, zs.map { |z| z - z_bot }) / 1000.0
        v_kn = p_all.sum { |_, pn| pn } / n / 1000.0
        asz = anchor_size(opts, TYPES['wf'][:anchor], t_kn, v_kn)
        anchor_checks(checks, notes, asz, t_kn, v_kn)
        zs.each do |z|
          Hardware.anchor(part, [0, y_w, z], [0, 1.0, 0], t, asz)
          lines << [[0, y_w - 60, z], [0, y_w + 20, z]]
        end
        bom_item(bom, 'anchor', "พุก Expansion bolt #{Hardware.label(asz)}", n, key: "anc #{asz}")
        result(part, bom, checks, notes, all, lines,
               section: key, anchor: asz, anchors: n, size: [y_out - y_w, z_t - z_bot], wall: wall,
               load_kn: (p_all.sum { |_, pn| pn } / 1000.0).round(2), t_kn: t_kn.round(2), v_kn: v_kn.round(2))
      end

      # Two angles back to back under a hot pipe, flat legs on the top
      # member (z_t, on a packer up to +seat+), upright legs welded to the
      # bare pipe – it slides on the frame.
      def angle_shoe(part, bom, p, z_t, seat)
        key = shoe_angle(p)
        a = Steel.get(key)[:a]
        if seat - z_t > 2.0
          part.add(:steel, Mesh.box([-SHOE_LEN / 2, p[:y] - a, z_t], [SHOE_LEN / 2, p[:y] + a, seat]))
          bom_pad(bom, SHOE_LEN * 2 * a * (seat - z_t) * Steel::RHO)
        end
        x0 = [-SHOE_LEN / 2, p[:y], seat]
        x1 = [SHOE_LEN / 2, p[:y], seat]
        part.add(:steel, Steel.angle(key, x0, x1, [0, -1.0, 0], [0, 0, 1.0]))
        part.add(:steel, Steel.angle(key, x0, x1, [0, 1.0, 0], [0, 0, 1.0]))
        bom_steel(bom, key, 2 * SHOE_LEN, "shoe รับท่อ #{p[:label]}")
      end

      # ---------- wb: triangular wall bracket ----------

      def wall_bracket(pipes, wall, opts = {})
        notes = []
        pipes = by_wall(pipes, wall, notes)
        raise 'ไม่มีท่อที่วางบนขาค้ำได้' if pipes.empty?

        _z_b, lower, rest = tiers(pipes)
        rest.each { |p| notes << "ท่อ #{p[:label]} สูงกว่าท่ออื่นเกิน #{RISE.round} mm – ไม่ได้รับ" }
        choose(opts, 'wb') { |key| wall_bracket_with(key, lower, wall, opts, notes.dup) }
      end

      def wall_bracket_with(key, pipes, wall, opts, notes)
        sec = Steel.get(key)
        b = sec[:b]
        h = sec[:h]
        t = Steel.web(key)
        z_a = pipes.map { |p| Pipes.bottom(p) }.min
        y_w = -wall
        y_in = y_w + b
        y_tip = pipes.map { |p| p[:y] + p[:r] + [u_room(p), 50.0].max }.max
        y_j = y_in + 0.75 * (y_tip - y_in)
        z_toe = z_a - b
        z_f = z_toe - (y_j - y_in) # 45°
        z_low = z_f - 70.0
        part = Mesh::Part.new
        bom = []
        lines = []
        x = [1.0, 0, 0]
        part.add(:steel, Steel.member(key, [0, y_in, z_a], [0, y_tip, z_a], x, [0, 0, -1.0]))
        part.add(:steel, Steel.member(key, [0, y_w, z_low], [0, y_w, z_a], x, [0, 1.0, 0]))
        f = [0, y_in, z_f]
        j = [0, y_j, z_toe]
        dir = Vec.unit(Vec.sub(j, f))
        toes = [0, -dir[2], dir[1]] # toward the corner
        part.add(:steel, Steel.member(key, f, j, x, toes, cut0: [f, [0, 1.0, 0]], cut1: [j, [0, 0, 1.0]]))
        brace = Vec.dist(f, j)
        box_lines(lines, [-h / 2, y_in, z_toe], [h / 2, y_tip, z_a])
        box_lines(lines, [-h / 2, y_w, z_low], [h / 2, y_in, z_a])
        lines << [f, j]
        bom_steel(bom, key, (y_tip - y_in) + (z_a - z_low) + brace, 'แขน + เสา + ค้ำยัน')
        pipes.each do |p|
          packer(part, bom, p, z_a, h)
          pipe_u_bolt(part, bom, p, z_a, t)
        end
        checks = []
        lds = loads(pipes, opts)
        sin = Math.sin(Math.atan2(z_toe - z_f, y_j - y_in))
        pr = Steel.props(key)
        bw = b / sin # brace foot print on the arm
        r = beam_checks(checks, "แขน #{sec[:inch]}", key, y_in, y_tip, y_in, y_j - bw / 2.0, lds)
        c = r[:r2] / sin
        kl_r = brace / pr[:r_min]
        check(checks, "ค้ำยัน #{sec[:inch]}: แรงอัด (compression)", c / pr[:area], Beam.fa(kl_r), 'MPa')
        zs = [z_toe - 40.0, z_f - 30.0]
        m = lds.sum { |y, pn| pn * (y - y_w) }
        t_kn = Beam.anchor_tension(m, zs.map { |z| z - z_low }) / 1000.0
        v_kn = lds.sum { |_, pn| pn } / 2.0 / 1000.0
        asz = anchor_size(opts, TYPES['wb'][:anchor], t_kn, v_kn)
        anchor_checks(checks, notes, asz, t_kn, v_kn)
        zs.each do |z|
          Hardware.anchor(part, [0, y_w, z], [0, 1.0, 0], t, asz)
          lines << [[0, y_w - 60, z], [0, y_w + 20, z]]
        end
        bom_item(bom, 'anchor', "พุก Expansion bolt #{Hardware.label(asz)}", 2, key: "anc #{asz}")
        result(part, bom, checks, notes, pipes, lines,
               section: key, anchor: asz, anchors: 2, size: [y_tip - y_w, z_a - z_low], wall: wall,
               load_kn: (lds.sum { |_, pn| pn } / 1000.0).round(2), t_kn: t_kn.round(2), v_kn: v_kn.round(2))
      end

      # ---------- th: trapeze hung from a truss chord ----------

      # chord: { kind: :round, z:, r: } (axis along y through x = 0) or
      # { kind: :flat, z: } (soffit – drop-in anchors).
      def truss_hang(pipes, chord, opts = {})
        notes = []
        _z_b, lower, rest = tiers(pipes)
        rest.each { |p| notes << "ท่อ #{p[:label]} สูงกว่าท่ออื่นเกิน #{RISE.round} mm – ไม่ได้รับ" }
        top = lower.map { |p| Pipes.top(p) }.max
        raise 'โครงด้านบนต่ำกว่าท่อ' if chord[:z] - chord[:r].to_f <= top + 20.0

        choose(opts, 'th') { |key| truss_hang_with(key, lower, chord, opts, notes.dup) }
      end

      def truss_hang_with(key, pipes, chord, opts, notes)
        sec = Steel.get(key)
        b = sec[:b]
        h = sec[:h]
        t = Steel.web(key)
        z_b = pipes.map { |p| Pipes.bottom(p) }.min
        first = pipes.first
        last = pipes.last
        lds = loads(pipes, opts)
        rsz = opt(opts, :rod, TYPES['th'][:rod])
        unless fixed?(opts, :rod) # the rod size moves the rods a little: size on the first spacing
          y1, y2 = rod_lines(first, last, rsz)
          rr = Beam.two_support(y1, y2, y1, y2, lds, 1.0)
          rsz = Hardware.size_for([rr[:r1], rr[:r2]].max / 1000.0, :rod_kn, min: TYPES['th'][:rod])
        end
        y1, y2 = rod_lines(first, last, rsz)
        rs = Hardware.get(rsz)
        part = Mesh::Part.new
        bom = []
        lines = []
        x = [1.0, 0, 0]
        e = 75.0
        part.add(:steel, Steel.member(key, [0, y1 - e, z_b], [0, y2 + e, z_b], x, [0, 0, -1.0]))
        box_lines(lines, [-h / 2, y1 - e, z_b - b], [h / 2, y2 + e, z_b])
        bom_steel(bom, key, y2 - y1 + 2 * e, 'คานรับท่อ')
        pipes.each do |p|
          packer(part, bom, p, z_b, h)
          pipe_u_bolt(part, bom, p, z_b, t)
        end
        checks = []
        r = beam_checks(checks, "คานรับท่อ #{sec[:inch]}", key, y1 - e, y2 + e, y1, y2, lds)
        rod_kn = [r[:r1], r[:r2]].max / 1000.0
        check(checks, "เหล็กเส้นเกลียว #{Hardware.label(rsz)}: แรงดึง (MSS SP-58)", rod_kn, rs[:rod_kn], 'kN', kind: :rod)
        under = z_b - t
        rod_low = under - Hardware.stack_height(rsz) - 0.6 * rs[:d]
        len = 0.0
        [y1, y2].each do |y|
          top = hanger_top(part, bom, chord, key, y, rsz, lines)
          Hardware.rod(part, [0, y, rod_low], [0, y, top], rsz)
          Hardware.fastening(part, [0, y, z_b], [0, 0, 1.0], rsz)
          Hardware.fastening(part, [0, y, under], [0, 0, -1.0], rsz)
          lines << [[0, y, rod_low], [0, y, top]]
          len += top - rod_low
        end
        bom_item(bom, 'rod', "เหล็กเส้นเกลียว #{Hardware.label(rsz)} ยาว #{(len / 2.0).round} มม.", 2, key: "rod #{rsz} #{(len / 2.0).round}")
        nuts(bom, rsz, 4)
        notes << 'โครงด้านบนไม่ใช่ท่อกลม – ใส่พุก drop-in ใต้พื้น (ถ้าเป็นเหล็กรูปพรรณให้เปลี่ยนเป็น beam clamp)' if chord[:kind] != :round
        result(part, bom, checks, notes, pipes, lines,
               section: key, rod: rsz, rods: [y1, y2], chord: chord,
               load_kn: (lds.sum { |_, pn| pn } / 1000.0).round(2), rod_kn: rod_kn.round(2))
      end

      # Rods just clear of the end pipes' U-bolt washers.
      def rod_lines(first, last, rsz)
        rw = Hardware.get(rsz)[:wod] / 2.0
        off = lambda do |p|
          u = Hardware.get(u_size(p))
          [p[:r] + u[:d] / 2.0 + u[:wod] / 2.0 + rw + 10.0, p[:r] + 40.0].max
        end
        [first[:y] - off.call(first), last[:y] + off.call(last)]
      end

      # Top of one hanger: a channel cleat under the chord (toes up – the
      # chord sits on them) held by a U-bolt over the chord; the rod goes
      # through the cleat web with a nut each side. Flat soffit: drop-in
      # anchor. Returns the rod's top end.
      def hanger_top(part, bom, chord, key, y, rsz, lines)
        rs = Hardware.get(rsz)
        unless chord[:kind] == :round
          z = chord[:z]
          part.add(:galv, Mesh.cylinder([0, y, z + 30.0], [0, y, z], rs[:d] / 2.0 + 3.0))
          bom_item(bom, 'anchor', "พุก Drop-in #{Hardware.label(rsz)}", 1, key: "dropin #{rsz}")
          return z + 25.0
        end
        sec = Steel.get(key)
        cr = chord[:r]
        zc = chord[:z]
        t = Steel.web(key)
        lc = [150.0, 2 * cr + 2 * rs[:d] + 2 * rs[:wod] + 20.0].max
        z_w = zc - cr - sec[:b] # cleat web underside
        part.add(:steel, Steel.member(key, [-lc / 2, y, z_w], [lc / 2, y, z_w], [0, 1.0, 0], [0, 0, 1.0]))
        box_lines(lines, [-lc / 2, y - sec[:h] / 2, z_w], [lc / 2, y + sec[:h] / 2, zc - cr])
        bom_steel(bom, key, lc, 'ชิ้นรองใต้ truss')
        leg = zc - (z_w - Hardware.stack_height(rsz) - 0.6 * rs[:d])
        Hardware.u_bolt(part, [0, y, zc], [1.0, 0, 0], [0, 0, 1.0], cr + 0.5, rsz, leg)
        rc = cr + 0.5 + rs[:d] / 2.0
        [-1, 1].each { |k| Hardware.fastening(part, [k * rc, y, z_w], [0, 0, -1.0], rsz) }
        bom_item(bom, 'ubolt', "U-bolt #{Hardware.label(rsz)} รัด truss Ø#{(2 * cr).round}", 1, key: "ubt #{rsz} #{(2 * cr).round}")
        nuts(bom, rsz, 2)
        Hardware.fastening(part, [0, y, z_w], [0, 0, -1.0], rsz)
        top = Hardware.fastening(part, [0, y, z_w + t], [0, 0, 1.0], rsz)
        top[2] + 0.6 * rs[:d]
      end

      # ---------- tt: channel on truss chords ----------

      # chords: [{ y:, z:, r: }] round members along x below the pipes.
      def truss_top(pipes, chords, opts = {})
        notes = []
        _z_b, lower, rest = tiers(pipes)
        rest.each { |p| notes << "ท่อ #{p[:label]} สูงกว่าท่ออื่นเกิน #{RISE.round} mm – ไม่ได้รับ" }
        raise 'ไม่พบโครง truss ใต้ท่อ' if chords.empty?

        choose(opts, 'tt') { |key| truss_top_with(key, lower, chords.sort_by { |c| c[:y] }, opts, notes.dup) }
      end

      def truss_top_with(key, pipes, chords, opts, notes)
        sec = Steel.get(key)
        b = sec[:b]
        h = sec[:h]
        t = Steel.web(key)
        ya = pipes.first[:y]
        yb = pipes.last[:y]
        left = chords.select { |c| c[:y] <= ya }.max_by { |c| c[:y] } || chords.first
        right = chords.select { |c| c[:y] >= yb }.min_by { |c| c[:y] } || chords.last
        used = chords.select { |c| c[:y].between?(left[:y], right[:y]) }
        z_toe = used.map { |c| c[:z] + c[:r] }.max
        z_w = z_toe + b
        low = pipes.map { |p| Pipes.bottom(p) }.min
        if low < z_w - 1.0
          raise "ท่ออยู่ต่ำกว่าเหล็กที่วางบน truss #{(z_w - low).round} มม. – ยกท่อขึ้นหรือใช้แบบแขวน"
        end

        far = pipes.select { |p| Pipes.bottom(p) - z_w > RISE }
        far.each { |p| notes << "ท่อ #{p[:label]} สูงจากเหล็กเกิน #{RISE.round} mm – ไม่ได้รับ" }
        pipes -= far
        raise 'ท่อสูงจาก truss เกินไป' if pipes.empty?

        y0 = [left[:y] - left[:r] - 60.0, pipes.first[:y] - pipes.first[:r] - u_room(pipes.first)].min
        y1 = [right[:y] + right[:r] + 60.0, pipes.last[:y] + pipes.last[:r] + u_room(pipes.last)].max
        part = Mesh::Part.new
        bom = []
        lines = []
        part.add(:steel, Steel.member(key, [0, y0, z_w], [0, y1, z_w], [1.0, 0, 0], [0, 0, -1.0]))
        box_lines(lines, [-h / 2, y0, z_toe], [h / 2, y1, z_w])
        bom_steel(bom, key, y1 - y0, 'คานรับท่อบน truss')
        legs = pipes.flat_map { |p| [-1, 1].map { |k| p[:y] + k * (p[:r] + 1.0 + Hardware.get(u_size(p))[:d] / 2.0) } }
        pipes.each do |p|
          packer(part, bom, p, z_w, h)
          pipe_u_bolt(part, bom, p, z_w, t)
        end
        used.each do |c|
          gap = z_toe - (c[:z] + c[:r])
          if gap > 30.0
            notes << "truss ที่ y = #{c[:y].round} ต่ำกว่าเส้นอื่น #{gap.round} มม. – ไม่ได้รัด"
            next
          end
          chord_u_bolt(part, bom, c, z_w, t, h, legs, gap)
          lines << [[0, c[:y], c[:z]], [0, c[:y], z_toe]]
        end
        notes << 'มี truss เส้นเดียวใต้ท่อ – ควรวางคร่อม 2 เส้น' if left.equal?(right)
        checks = []
        lds = loads(pipes, opts)
        beam_checks(checks, "คานรับท่อ #{sec[:inch]}", key, y0, y1, left[:y], right[:y], lds) unless left.equal?(right)
        result(part, bom, checks, notes, pipes, lines,
               section: key, chords: used.size, load_kn: (lds.sum { |_, pn| pn } / 1000.0).round(2))
      end

      # U-bolt under a chord, legs up through the member web, nuts on top;
      # beside a pipe U-bolt it moves along x to clear it. Shim plate when
      # the chord is a little lower than the highest one.
      def chord_u_bolt(part, bom, c, z_w, t, h, legs, gap)
        size = c[:r] * 2 <= 61.0 ? '3/8' : '1/2'
        s = Hardware.get(size)
        rc = c[:r] + 0.5 + s[:d] / 2.0
        mine = [c[:y] - rc, c[:y] + rc]
        clash = mine.any? { |y| legs.any? { |l| (l - y).abs < s[:wod] + 2.0 } }
        x = clash ? h / 4.0 : 0.0
        top = z_w + Hardware.stack_height(size) + 0.6 * s[:d]
        Hardware.u_bolt(part, [x, c[:y], c[:z]], [0, 1.0, 0], [0, 0, -1.0], c[:r] + 0.5, size, top - c[:z])
        mine.each { |y| Hardware.fastening(part, [x, y, z_w], [0, 0, 1.0], size) }
        if gap > 1.0
          part.add(:steel, Mesh.box([-h / 2 + 5, c[:y] - c[:r], c[:z] + c[:r]], [h / 2 - 5, c[:y] + c[:r], c[:z] + c[:r] + gap]))
          bom_pad(bom, (h - 10) * 2 * c[:r] * gap * Steel::RHO)
        end
        bom_item(bom, 'ubolt', "U-bolt #{Hardware.label(size)} รัด truss Ø#{(2 * c[:r]).round}", 1, key: "ubt #{size} #{(2 * c[:r]).round}")
        nuts(bom, size, 2)
        z_w - t
      end
    end
  end
end
