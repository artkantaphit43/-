# frozen_string_literal: true

require_relative 'vec'
require_relative 'mesh'

module ArtK
  module PlantPipe
    # Pipe supports: spacing rules, placement and parametric models.
    #
    # Spacing (maximum span between supports, horizontal pipe, water-filled):
    # * steel      – MSS SP-69 / ASME B31.1 Table 121.5 (water service)
    # * copper     – MSS SP-69 (copper tube, water)
    # * PVC-U      – typical manufacturer values at ≤ 23 °C
    # * PP-R       – typical manufacturer values, cold water; hot services
    #                ×0.6 because PP-R creeps at temperature
    # * HDPE       – ≈ 12 × OD at 20 °C (flexible pipe)
    # Values are design guidance – the project specification or the pipe
    # manufacturer governs. Plastic hot-water spans are the usual trap, so
    # they are reduced automatically.
    #
    # Canonical frame for every support model: pipe axis along +X through
    # the origin, +Z up. Heights are measured from the pipe centreline.
    module Supports
      M = Mesh
      FT = 0.3048

      # NPS (in) => span (ft), MSS SP-69 Table 3 steel water service
      STEEL_SPAN_FT = [[0.5, 7], [0.75, 7], [1, 7], [1.25, 7], [1.5, 9], [2, 10], [2.5, 11], [3, 12],
                       [3.5, 13], [4, 14], [5, 16], [6, 17], [8, 19], [10, 22], [12, 23], [14, 25],
                       [16, 27], [18, 28], [20, 30], [24, 32]].freeze
      COPPER_SPAN_FT = [[0.5, 5], [0.75, 5], [1, 6], [1.25, 7], [1.5, 8], [2, 8], [2.5, 9], [3, 10],
                        [3.5, 11], [4, 12]].freeze
      # OD (mm) => span (m)
      PVC_SPAN = [[22, 1.2], [26, 1.2], [34, 1.4], [42, 1.5], [48, 1.6], [60, 1.8], [76, 2.0], [89, 2.1],
                  [114, 2.3], [165, 2.6], [216, 2.8], [267, 3.0], [318, 3.2]].freeze
      PPR_SPAN = [[20, 0.6], [25, 0.75], [32, 0.9], [40, 1.0], [50, 1.2], [63, 1.4], [75, 1.5], [90, 1.6],
                  [110, 1.8]].freeze

      # Hanger rod diameter by NPS (MSS SP-58), with metric equivalent.
      ROD = [[2.0, 9.5, '3/8" (M10)'], [3.5, 12.7, '1/2" (M12)'], [5.0, 15.9, '5/8" (M16)'],
             [6.0, 19.1, '3/4" (M20)'], [12.0, 22.2, '7/8" (M22)'], [18.0, 25.4, '1" (M24)'],
             [99.0, 31.8, '1-1/4" (M30)']].freeze

      TYPES = {
        'clevis'   => { name: 'Clevis hanger + threaded rod', th: 'แขวน Clevis + เหล็กเกลียว (เจาะพุกฝ้า/พื้น)', mount: :above },
        'beam'     => { name: 'Beam clamp + rod + clevis', th: 'แขวน Beam clamp ยึดคานเหล็ก', mount: :above },
        'trapeze'  => { name: 'Trapeze (strut channel 41×41)', th: 'แขวน Trapeze รางยูนิสตรัท', mount: :above, multi: true },
        'pipe'     => { name: 'Pipe-on-pipe hanger', th: 'แขวนจากท่อใหญ่ด้านบน', mount: :pipe_above },
        'stand'    => { name: 'Adjustable pipe stand', th: 'ขาตั้งท่อปรับระดับ (Pipe stand)', mount: :below },
        'hframe'   => { name: 'H-frame / goalpost', th: 'โครง H-frame / Goalpost', mount: :below, multi: true },
        'shoe'     => { name: 'Sleeper + pipe shoe', th: 'คานรองท่อ + Pipe shoe', mount: :below },
        'bracket'  => { name: 'Wall bracket', th: 'แขนค้ำยึดผนัง (Wall bracket)', mount: :side }
      }.freeze

      # Neighbouring pipes share one support when they run parallel (within
      # GROUP_ANGLE), the clear gap between neighbouring pipe surfaces is
      # at most the group gap (setting 'support_group_mm', chained pipe to
      # pipe) and their bottoms are within GROUP_RISE of the first pipe's –
      # higher pipes stand on packers, more than that is a separate support.
      GROUP_GAP = 600.0
      GROUP_RISE = 300.0
      GROUP_ANGLE = 5.0
      GROUP_WIDTH = 2500.0 # mm, widest frame / trapeze
      BRACKET_REACH = 1200.0 # mm, longest cantilever arm

      # What a single-pipe support becomes when it carries several pipes.
      MULTI_OF = {
        'clevis' => 'trapeze', 'beam' => 'trapeze', 'trapeze' => 'trapeze', 'stand' => 'hframe',
        'hframe' => 'hframe', 'shoe' => 'sleeper', 'bracket' => 'bracket'
      }.freeze

      module_function

      # Pipes to carry together. cands: [[y, r, z, id], …] across the
      # support (y sideways, z centre height, r radius incl. insulation);
      # the pipe clicked is the one nearest y = 0, z = 0.
      def group(cands, gap: GROUP_GAP, rise: GROUP_RISE, width: GROUP_WIDTH)
        return cands.first(1) if cands.size < 2 || gap <= 0

        list = cands.sort_by(&:first)
        i0 = list.index(list.min_by { |y, _r, z| y.abs + z.abs })
        bop0 = list[i0][2] - list[i0][1]
        ok = ->(c) { ((c[2] - c[1]) - bop0).abs <= rise }
        out = [list[i0]]
        [1, -1].each do |step|
          k = i0
          last = list[i0]
          loop do
            k += step
            break if k.negative? || k >= list.size

            c = list[k]
            next unless ok.call(c) # a pipe on another level is skipped, not a barrier
            break if (c[0] - last[0]).abs - c[1] - last[1] > gap

            ys = (out + [c]).map(&:first)
            rmax = (out + [c]).map { |o| o[1] }.max
            break if ys.max - ys.min + 2 * rmax > width

            out << c
            last = c
          end
        end
        out.sort_by(&:first)
      end

      # Support positions along a straight pipe of length len (from its
      # start), spans at most span_mm, the end supports e from each end,
      # keeping supports that already exist there (fixed, from a support
      # shared with a neighbouring pipe). Returns the new positions only.
      def fill(len, span_mm, e, fixed = [])
        fixed = fixed.select { |x| x >= -1.0 && x <= len + 1.0 }.sort
        pts = fixed.dup
        pts.unshift(e) unless pts.first && pts.first <= e + 0.25 * span_mm
        pts.push(len - e) unless pts.last && pts.last >= len - e - 0.25 * span_mm
        pts = pts.uniq.sort
        out = pts - fixed
        pts.each_cons(2) do |a, b|
          n = ((b - a) / span_mm).ceil
          (1...n).each { |k| out << a + (b - a) * k / n }
        end
        out.sort
      end

      def interp(table, x)
        return table.first[1] if x <= table.first[0]
        return table.last[1] if x >= table.last[0]

        table.each_cons(2) do |(x0, y0), (x1, y1)|
          return y0 + (y1 - y0) * (x - x0) / (x1 - x0) if x.between?(x0, x1)
        end
      end

      # Maximum span (m) for a pipe spec (+hot+ = hot service).
      def max_span_m(spec, hot: false)
        fam = spec.respond_to?(:family) ? spec.family : 'CS'
        nps = spec.nps_in || (spec.od / 25.4)
        case fam
        when 'CU' then interp(COPPER_SPAN_FT, nps) * FT
        when 'PVC' then interp(PVC_SPAN, spec.od)
        when 'PPR' then interp(PPR_SPAN, spec.od) * (hot ? 0.6 : 1.0)
        when 'HDPE' then [12.0 * spec.od / 1000.0, 0.5].max * (hot ? 0.7 : 1.0)
        else interp(STEEL_SPAN_FT, nps) * FT
        end.round(2)
      end

      def rod(spec)
        nps = spec.nps_in || (spec.od / 25.4)
        r = ROD.find { |max, _, _| nps <= max } || ROD.last
        { dia: r[1], label: r[2] }
      end

      # Support positions for one run.
      #   pipes  – [{ from:, to: }] straight pieces (mm)
      #   loads  – [[x,y,z], ...] concentrated loads (valves) needing a support nearby
      # Rules: horizontal pipes only (risers need riser clamps at floors),
      # first/last support within e = min(600 mm, span/4) of each fitting,
      # equal spacing ≤ span in between, and a support within 600 mm of every
      # concentrated load.
      # Returns { supports: [{ at:, dir:, pipe: index }], risers: n }
      # fixed: points (same coordinates as the pipes) of supports already
      # carrying these pipes (shared with a neighbour) – kept, gaps filled.
      def place(pipes, span_mm, loads: [], near: 600.0, fixed: [])
        out = []
        risers = 0
        pipes.each_with_index do |pp, idx|
          a = pp[:from]
          b = pp[:to]
          d = Vec.sub(b, a)
          len = Vec.length(d)
          next if len < 1.0

          h = Math.hypot(d[0], d[1])
          if d[2].abs > h
            risers += 1
            next
          end
          dir = Vec.scale(d, 1.0 / len)
          e = [near, span_mm / 4.0, len / 2.0].min
          free = len - 2 * e
          on = fixed.filter_map do |c|
            t = Vec.dot(Vec.sub(c, a), dir)
            t if t > -1.0 && t < len + 1.0 && Vec.dist(Vec.add(a, Vec.scale(dir, t)), c) <= 1.0
          end
          xs = if on.any?
                 fill(len, span_mm, e, on)
               elsif free <= 1.0
                 [len / 2.0]
               else
                 n = (free / span_mm).ceil
                 (0..n).map { |k| e + free * k / n }
               end
          xs.each { |x| out << { at: Vec.add(a, Vec.scale(dir, x)), dir: dir, pipe: idx } }
        end
        loads.each do |c|
          next if out.any? { |s| Vec.dist(s[:at], c) <= near } || fixed.any? { |f| Vec.dist(f, c) <= near }

          best = nil
          pipes.each_with_index do |pp, idx|
            a = pp[:from]
            ab = Vec.sub(pp[:to], a)
            len = Vec.length(ab)
            next if len < 1.0

            t = Vec.dot(Vec.sub(c, a), ab) / (len * len)
            next if t.negative? || t > 1.0

            proj = Vec.add(a, Vec.scale(ab, t))
            next if Vec.dist(proj, c) > 1.0

            dir = Vec.scale(ab, 1.0 / len)
            s = t * len
            x = s + near * 0.8 <= len ? s + near * 0.8 : [s - near * 0.8, 0.0].max
            best = { at: Vec.add(a, Vec.scale(dir, x)), dir: dir, pipe: idx }
          end
          out << best if best
        end
        { supports: out, risers: risers }
      end

      # ---------------------------------------------------------------
      # Models (canonical frame). r = pipe radius incl. insulation.
      # ---------------------------------------------------------------

      def u_bolt(part, cy, cz, r, rod_r, down_to, steps)
        # bent rod over the top of the pipe + two legs
        part.add(:galv, M.bend([0, cy, cz], [0, 1, 0], [1, 0, 0], r + rod_r, Math::PI, rod_r, nil,
                               steps: 8, arc_steps: [steps / 2, 6].max))
        [-1, 1].each do |s|
          y = cy + s * (r + rod_r)
          part.add(:galv, M.cylinder([0, y, down_to], [0, y, cz], rod_r, steps: 8))
        end
      end

      def nut(part, z, rod_r)
        part.add(:galv, M.ngon_prism([0, 0, z], [0, 0, z + rod_r * 1.6], rod_r * 1.9, 6))
      end

      def rod_part(part, z0, z1, rod_r)
        part.add(:galv, M.cylinder([0, 0, z0], [0, 0, z1], rod_r, steps: 8))
      end

      # Top attachment: :slab (drop-in anchor + washer) or :beam (clamp).
      def top_fixing(part, z, rod_r, kind)
        if kind == :beam
          f = M.frame([0, 0, z], [1, 0, 0], [0, 1, 0])
          part.add(:steel, M.box(f, [0, 0, -12], [70, 45, 24]))       # clamp body under flange
          part.add(:steel, M.box(f, [0, -30, 8], [70, 12, 40]))       # jaw
          part.add(:galv, M.cylinder([0, -26, 22], [0, 10, 22], rod_r * 0.9, steps: 8)) # set screw
        else
          part.add(:galv, M.cylinder([0, 0, z - 45], [0, 0, z], rod_r * 1.45, steps: 10)) # anchor sleeve
          part.add(:galv, M.cylinder([0, 0, z - 48], [0, 0, z - 45], rod_r * 2.6, steps: 12)) # washer
        end
      end

      # Clevis hanger with rod to a slab (kind :slab) or beam (kind :beam).
      def clevis(r, drop, rod_dia, kind: :slab, steps: 16, detailed: true)
        part = Mesh::Part.new
        rod_r = rod_dia / 2.0
        t = [0.04 * r * 2, 3.0].max
        w = [0.25 * r * 2, 25.0].max
        rr = r + 1.0
        # strap cradling the bottom half
        part.add(:galv, M.revolve([[[-w / 2, rr], [w / 2, rr], [w / 2, rr + t], [-w / 2, rr + t]]],
                                  axis_o: [0, 0, 0], axis: [1, 0, 0], ref: [0, -1, 0], angle: Math::PI, steps: steps / 2))
        top = rr + 0.6 * r + 20.0
        [-1, 1].each do |s|
          part.add(:galv, M.bar([0, s * (rr + t / 2), 0], [0, s * (rod_r * 1.5 + t / 2), top], t, w, [1, 0, 0]))
        end
        part.add(:galv, M.cylinder([0, -(rod_r * 2 + t), top], [0, rod_r * 2 + t, top], rod_r, steps: 8)) # cross bolt
        rod_part(part, top, drop, rod_r)
        if detailed
          nut(part, top + rod_r * 1.2, rod_r)
          nut(part, top + rod_r * 3.2, rod_r)
        end
        top_fixing(part, drop, rod_r, kind)
        part
      end

      # Small pipe hung from a larger pipe above: ring clamp – rod – ring clamp.
      def pipe_hanger(r, upper_r, dist, rod_dia, steps: 16)
        part = Mesh::Part.new
        rod_r = rod_dia / 2.0
        w = [0.3 * r * 2, 25.0].max
        [[0.0, r], [dist, upper_r]].each do |z, rad|
          ring = [[-w / 2, rad + 1], [w / 2, rad + 1], [w / 2, rad + 5], [-w / 2, rad + 5]]
          part.add(:galv, M.revolve([ring], axis_o: [0, 0, z], axis: [1, 0, 0], steps: steps))
          lug = z.zero? ? 1.0 : -1.0
          part.add(:galv, M.box(M.frame([0, 0, z + lug * (rad + 12)], [1, 0, 0], [0, 1, 0]), [0, 0, 0], [w, 10, 24]))
        end
        rod_part(part, r + 24, dist - upper_r - 24, rod_r)
        part
      end

      # Strut channel 41×41 (C-section as 5 plates) along Y at z (top face).
      def strut(part, y0, y1, z_top)
        len = y1 - y0
        f = M.frame([0, (y0 + y1) / 2.0, 0], [0, 1, 0], [-1, 0, 0])
        t = 2.5
        part.add(:galv, M.box(f, [0, 0, z_top - 41 + t / 2], [len, 41, t]))               # web (bottom)
        [-1, 1].each do |s|
          part.add(:galv, M.box(f, [0, s * (20.5 - t / 2), z_top - 20.5], [len, t, 41 - 2 * t])) # sides
          part.add(:galv, M.box(f, [0, s * (20.5 - 5), z_top - t / 2], [len, 10 - t, t]))  # lips
        end
      end

      # Trapeze: offsets = [[y, r, z], ...] pipes across the channel (z =
      # centre height relative to the origin, default 0). The channel sits
      # under the lowest pipe; higher pipes need packers (not modelled).
      def trapeze(offsets, drop, rod_dia, kind: :slab, steps: 16, detailed: true)
        part = Mesh::Part.new
        rod_r = rod_dia / 2.0
        ys = offsets.map(&:first)
        rmax = offsets.map { |o| o[1] }.max
        z_top = offsets.map { |_, r, z| z.to_f - r }.min
        y0 = ys.min - rmax - 100
        y1 = ys.max + rmax + 100
        strut(part, y0, y1, z_top)
        [y0 + 25, y1 - 25].each do |y|
          part.add(:galv, M.cylinder([0, y, z_top - 60], [0, y, drop], rod_r, steps: 8))
          nut_at = M.frame([0, y, 0], [1, 0, 0], [0, 1, 0])
          sub = Mesh::Part.new
          nut(sub, z_top - 41 - rod_r * 1.6, rod_r)
          top_fixing(sub, drop, rod_r, kind)
          part.merge(sub, nut_at)
        end
        packers(part, offsets, z_top)
        offsets.each { |y, r, z| u_bolt(part, y, z.to_f, r, [rod_r * 0.8, 4.0].max, z.to_f - r, steps) } if detailed
        part
      end

      # Steel packer (stool) under each pipe that sits higher than the
      # common bearing level z_top.
      def packers(part, offsets, z_top)
        offsets.each do |y, r, z|
          bop = z.to_f - r
          next if bop - z_top < 2.0

          w = [[r * 1.2, 50.0].max, 150.0].min
          f = M.frame([0, y, 0], [1, 0, 0], [0, 1, 0])
          part.add(:steel, M.box(f, [0, 0, (z_top + bop) / 2.0], [100, w, bop - z_top]))
        end
      end

      # Adjustable pipe stand: base plate, post, threaded adjuster, saddle, U-bolt.
      def stand(r, height, steps: 16, detailed: true)
        part = Mesh::Part.new
        post_r = r > 60 ? 44.45 : 30.15
        base = [6 * post_r, 150.0].max
        zf = -height
        f = M.frame([0, 0, zf], [1, 0, 0], [0, 1, 0])
        part.add(:steel, M.box(f, [0, 0, 6], [base, base, 12]))
        if detailed
          [[-1, -1], [1, -1], [1, 1], [-1, 1]].each do |sx, sy|
            c = [sx * (base / 2 - 20), sy * (base / 2 - 20), zf + 12]
            part.add(:galv, M.cylinder(c, Vec.add(c, [0, 0, 25]), 6.0, steps: 6))
          end
        end
        saddle_z = -r - 10.0
        adj = [0.25 * (height - r), 60.0].min
        post_top = saddle_z - 12 - adj
        part.add(:steel, M.cylinder([0, 0, zf + 12], [0, 0, post_top], post_r, ri: post_r - 4, steps: steps))
        part.add(:galv, M.cylinder([0, 0, post_top - 20], [0, 0, saddle_z - 12], post_r * 0.55, steps: 10))
        part.add(:galv, M.ngon_prism([0, 0, post_top], [0, 0, post_top + 14], post_r * 1.1, 6))
        part.add(:steel, M.box(M.frame([0, 0, saddle_z - 12], [1, 0, 0], [0, 1, 0]), [0, 0, 6],
                               [[2 * r, 80].max, 2 * r + 30, 12]))
        w = [0.8 * r, 50.0].max
        part.add(:steel, M.revolve([[[-w / 2, r + 1], [w / 2, r + 1], [w / 2, r + 7], [-w / 2, r + 7]]],
                                   axis_o: [0, 0, 0], axis: [1, 0, 0], ref: [0, -1, 0], angle: Math::PI,
                                   steps: steps / 2))
        u_bolt(part, 0.0, 0.0, r, [0.06 * r, 5.0].max, saddle_z - 12, steps) if detailed
        part
      end

      # H-frame / goalpost for several pipes: offsets = [[y, r, z], ...].
      def hframe(offsets, height, steps: 16, detailed: true)
        part = Mesh::Part.new
        ys = offsets.map(&:first)
        rmax = offsets.map { |o| o[1] }.max
        z_top = offsets.map { |_, r, z| z.to_f - r }.min
        y0 = ys.min - rmax - 150
        y1 = ys.max + rmax + 150
        zf = -height
        beam_h = 100.0
        part.add(:steel, M.box(M.frame([0, (y0 + y1) / 2.0, 0], [0, 1, 0], [-1, 0, 0]), [0, 0, z_top - beam_h / 2],
                               [y1 - y0 + 100, 100, beam_h]))
        [y0, y1].each do |y|
          part.add(:steel, M.box(M.frame([0, y, 0], [1, 0, 0], [0, 1, 0]), [0, 0, (zf + 12 + z_top - beam_h) / 2.0],
                                 [100, 100, z_top - beam_h - zf - 12]))
          part.add(:steel, M.box(M.frame([0, y, zf], [1, 0, 0], [0, 1, 0]), [0, 0, 6], [220, 220, 12]))
        end
        packers(part, offsets, z_top)
        offsets.each { |y, r, z| u_bolt(part, y, z.to_f, r, [0.06 * r, 5.0].max, z.to_f - r, steps) } if detailed
        part
      end

      # Concrete sleeper + T-shoe welded under the pipe (lets the pipe slide
      # and keeps insulation off the sleeper).
      # base: shoe height from the pipe centre (multi-pipe sleeper); the
      # sleeper itself is then left to the caller (height 0).
      def shoe(pipe_r, ins, height, steps: 16, base: nil)
        part = Mesh::Part.new
        shoe_h = base ? base - pipe_r : [ins + 50.0, 100.0].max
        z_sleeper = -pipe_r - shoe_h
        zf = -height
        len = 300.0
        width = [2 * pipe_r + 2 * ins + 200, 500.0].max
        if z_sleeper - zf > 5
          part.add(:concrete, M.box(M.frame([0, 0, zf], [1, 0, 0], [0, 1, 0]), [0, 0, (z_sleeper - zf) / 2.0],
                                    [400, width, z_sleeper - zf]))
        end
        f = M.frame([0, 0, 0], [1, 0, 0], [0, 1, 0])
        part.add(:steel, M.box(f, [0, 0, z_sleeper + 6], [len, [2 * pipe_r * 0.8, 100].max, 12]))       # base
        part.add(:steel, M.box(f, [0, 0, (z_sleeper + 12 - pipe_r * 0.9) / 2.0], [len, 10, -pipe_r * 0.9 - z_sleeper - 12])) # web
        part.add(:steel, M.revolve([[[-len / 2, pipe_r], [len / 2, pipe_r], [len / 2, pipe_r + 6], [-len / 2, pipe_r + 6]]],
                                   axis_o: [0, 0, 0], axis: [1, 0, 0], ref: [0, -1, 0], angle: Math::PI, steps: steps / 2))
        part
      end

      # One concrete sleeper under several pipes, a T-shoe on each:
      # offsets = [[y, pipe r, z, insulation], …]; floor at z = -height.
      def sleeper(offsets, height, steps: 16)
        part = Mesh::Part.new
        shoe_hs = offsets.map { |_y, _r, _z, ins| [ins.to_f + 50.0, 100.0].max }
        z_sleeper = offsets.each_with_index.map { |(_y, r, z, _), i| z.to_f - r - shoe_hs[i] }.min
        zf = -height
        ys = offsets.map(&:first)
        rmax = offsets.map { |o| o[1] + o[3].to_f }.max
        y0 = ys.min - rmax - 100
        y1 = ys.max + rmax + 100
        if z_sleeper - zf > 5
          part.add(:concrete, M.box(M.frame([0, (y0 + y1) / 2.0, zf], [1, 0, 0], [0, 1, 0]),
                                    [0, 0, (z_sleeper - zf) / 2.0], [400, y1 - y0, z_sleeper - zf]))
        end
        offsets.each do |y, r, z, _ins|
          sub = shoe(r, 0.0, 0.0, steps: steps, base: z.to_f - z_sleeper)
          part.merge(sub, M.frame([0, y, z.to_f], [1, 0, 0], [0, 1, 0]))
        end
        part
      end

      # Cantilever bracket on a wall / column face at y = -wall, arm under
      # the lowest pipe out to the farthest one, 45° knee brace. offsets =
      # [[y, r, z], …] measured from the pipe the bracket was placed on.
      def bracket(offsets, wall, steps: 16, detailed: true)
        offsets = [[0.0, offsets, 0.0]] if offsets.is_a?(Numeric) # single pipe: bracket(r, wall)
        part = Mesh::Part.new
        arm_top = offsets.map { |_y, r, z| z.to_f - r }.min - 2.0
        s = offsets.size > 1 ? 75.0 : 50.0
        reach = wall + offsets.map { |y, r, _z| y + r }.max + 60
        part.add(:steel, M.bar([0, -wall, arm_top - s / 2], [0, -wall + reach, arm_top - s / 2], s, s, [0, 0, 1]))
        brace = [0.7 * reach, 150.0].max
        part.add(:steel, M.bar([0, -wall + 5, arm_top - s - brace], [0, -wall + brace * 0.95, arm_top - s], 40, 40, [1, 0, 0]))
        part.add(:steel, M.box(M.frame([0, -wall, 0], [1, 0, 0], [0, 1, 0]), [0, 5, arm_top - (brace + s) / 2],
                               [120, 10, brace + s + 60]))
        packers(part, offsets, arm_top)
        offsets.each { |y, r, z| u_bolt(part, y, z.to_f, r, [0.06 * r, 5.0].max, z.to_f - r - 2.0, steps) } if detailed
        part
      end
    end
  end
end
