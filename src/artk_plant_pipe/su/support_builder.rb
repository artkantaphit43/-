# frozen_string_literal: true

module ArtK
  module PlantPipe
    # Places and renders pipe supports.
    #
    # Where does a hanger attach? The plugin ray-casts from the pipe
    # centreline in the model – up for hangers (slab soffit / beam), down
    # for stands and sleepers, sideways for wall brackets – skipping its own
    # pipes and supports. So supports adapt to the real building geometry
    # you have modelled; if nothing is found a documented fallback is used
    # and reported.
    #
    # Single-pipe supports are stored on the run ('supports' records in run
    # coordinates, with the attachment point) and regenerated on every
    # rebuild, so resizing a line resizes its hangers and rods.
    # Supports shared by neighbouring pipes (trapeze, H-frame, sleeper,
    # bracket) are standalone groups that remember where they stand
    # ('at', 'dir') and whom they carry, so they adapt when pipes are drawn
    # or resized next to them (adapt).
    module SupportBuilder
      H = ModelHelpers
      UP = [0.0, 0.0, 1.0].freeze
      FALLBACK_DROP = 600.0 # mm above the pipe top when no structure is found
      SIDE_SEARCH = 3000.0  # mm, wall search distance for brackets

      module_function

      def horizontal(dir)
        h = [dir[0], dir[1], 0.0]
        Vec.length(h) < 1e-6 ? [1.0, 0.0, 0.0] : Vec.unit(h)
      end

      # Support frame: x along the (horizontal) pipe, z up.
      def frame(at, dir)
        x = horizontal(dir)
        Mesh.frame(at, x, Vec.cross(UP, x))
      end

      # Ray-cast in world mm. Skips Plant Piping objects unless want: :pipe,
      # which returns the first of our pipes that belongs to another run.
      def cast(model, origin, dir, want: nil, exclude_run: nil, max_dist: 30_000.0)
        pt = origin
        30.times do
          hit = model.raytest([H.to_pt(pt), H.to_vec(dir)], true)
          return nil unless hit

          hp = H.from_pt(hit[0])
          return nil if Vec.dist(origin, hp) > max_dist

          ours = (hit[1] || []).select { |e| e.respond_to?(:get_attribute) && H.type_of(e) }
          if want == :pipe
            pipe = ours.find { |e| H.type_of(e) == 'pipe' }
            run = ours.find { |e| H.type_of(e) == 'run' }
            return { point: hp, pipe: pipe, run: run } if pipe && run != exclude_run
          elsif ours.empty?
            return { point: hp }
          end
          pt = Vec.add(hp, Vec.scale(dir, 1.0))
        end
        nil
      end

      # Build a support record for a point on a run (run-local at/dir).
      # tr = world transformation of the run. Returns [record or nil, note].
      def record_for(model, run, tr, type, at, dir)
        spec = Builder.run_spec(run)
        ins = Builder.run_settings(run)['insulation_mm'].to_f
        r = spec.od / 2.0 + ins
        at_w = H.transform_mm(tr, at)
        dir_w = Vec.unit(H.from_vec(H.to_vec(dir).transform(tr)))
        inv = tr.inverse
        rec = { 'type' => type, 'at' => at, 'dir' => dir }
        note = nil
        case Supports::TYPES[type][:mount]
        when :above
          hit = cast(model, at_w, UP)
          target = hit ? hit[:point] : Vec.add(at_w, [0, 0, r + FALLBACK_DROP])
          note = 'ไม่พบโครงสร้างด้านบน – ใช้ความยาวก้านแขวนสมมติ (no structure found above, assumed drop)' unless hit
          rec['target'] = H.transform_mm(inv, target)
        when :pipe_above
          hit = cast(model, at_w, UP, want: :pipe, exclude_run: run)
          return [nil, 'ไม่พบท่อใหญ่ด้านบน (no pipe above to hang from)'] unless hit

          upper_r = hit[:pipe].get_attribute(H::DICT, 'od').to_f / 2.0
          rec['upper_r'] = upper_r
          rec['target'] = H.transform_mm(inv, Vec.add(hit[:point], [0, 0, upper_r]))
        when :below
          hit = cast(model, at_w, Vec.scale(UP, -1.0))
          if hit
            rec['target'] = H.transform_mm(inv, hit[:point])
          elsif at_w[2] > r + 100
            rec['target'] = H.transform_mm(inv, [at_w[0], at_w[1], 0.0])
            note = 'ไม่พบพื้น – ใช้ระดับ 0 ของโมเดล (no floor found, model ground used)'
          else
            return [nil, 'ท่ออยู่ต่ำเกินไปสำหรับขาตั้ง (pipe too low for a floor support)']
          end
        when :side
          side = Vec.cross(UP, horizontal(dir_w))
          hits = [side, Vec.scale(side, -1.0)].map { |v| cast(model, at_w, v, max_dist: SIDE_SEARCH) }.compact
          return [nil, 'ไม่พบผนังภายใน 3 m (no wall within 3 m)'] if hits.empty?

          rec['target'] = H.transform_mm(inv, hits.min_by { |h| Vec.dist(h[:point], at_w) }[:point])
        else
          return [nil, "#{type}: ใช้เครื่องมือวางซัพพอร์ตหลายท่อ (use the multi-pipe support tool)"]
        end
        [rec, note]
      end

      # Draw one stored support record inside a run.
      def render(ctx, rec)
        type = rec['type']
        info = Supports::TYPES.fetch(type)
        at = rec['at']
        spec = ctx[:spec]
        r = spec.od / 2.0 + ctx[:ins]
        rod = Supports.rod(spec)
        det = ctx[:lod] == :detailed
        steps = ctx[:steps]
        f = frame(at, rec['dir'])
        extra = {}
        part =
          case type
          when 'clevis', 'beam'
            drop = rec['target'][2] - at[2]
            raise "hanger drop too short (#{drop.round} mm)" if drop < r + 80

            extra['rod_length_mm'] = (drop - 1.6 * r - 20).round
            Supports.clevis(r, drop, rod[:dia], kind: type == 'beam' ? :beam : :slab, steps: steps, detailed: det)
          when 'pipe'
            dist = rec['target'][2] - at[2]
            extra['rod_length_mm'] = (dist - r - rec['upper_r'] - 48).round
            Supports.pipe_hanger(r, rec['upper_r'], dist, rod[:dia], steps: steps)
          when 'stand'
            h = at[2] - rec['target'][2]
            extra['member_length_mm'] = (h - r).round
            extra['member_name'] = 'Pipe post (stand)'
            Supports.stand(r, h, steps: steps, detailed: det)
          when 'shoe'
            h = at[2] - rec['target'][2]
            Supports.shoe(spec.od / 2.0, ctx[:ins], h, steps: steps)
          when 'bracket'
            w = Vec.sub(at, rec['target'])
            w = [w[0], w[1], 0.0]
            wall = Vec.length(w)
            y = Vec.unit(w)
            x = horizontal(rec['dir'])
            x = Vec.scale(x, -1.0) if Vec.dot(Vec.cross(x, y), UP).negative?
            f = Mesh.frame(at, x, y)
            extra['member_length_mm'] = (wall + r + 60 + 0.7 * (wall + r + 60)).round
            extra['member_name'] = 'Steel angle / box 50 (bracket)'
            Supports.bracket(r, wall, steps: steps, detailed: det)
          else
            raise "unknown support #{type}"
          end
        g = H.add_part_group(ctx[:model], ctx[:ents], part, steps: steps)
        g.transformation = H.frame_transform(f)
        g.name = "#{info[:name]} #{spec.size}"
        g.layer = H.tag(ctx[:model], Builder::TAG_SUPPORTS)
        H.set_attrs(g, extra.merge('type' => 'support', 'support_type' => type, 'support_name' => info[:name],
                                   'pipe_size' => spec.size, 'size' => spec.size, 'service' => ctx[:common]['service'],
                                   'line_no' => ctx[:line_no],
                                   'rod_label' => %w[clevis beam pipe].include?(type) ? rod[:label] : nil).reject { |_, v| v.nil? })
        g
      end

      # ---------- supports shared by neighbouring pipes ----------

      COVER = 500.0 # mm: a single support this close to a shared one is redundant

      def group_gap
        H.load_settings['support_group_mm'].to_f
      end

      # Pipes crossing the vertical plane through +point+ (world mm)
      # perpendicular to horizontal +dir+, within reach. Returns
      # [[y offset, radius incl. insulation, z offset, size, run id,
      # insulation], …].
      def crossing_pipes(model, point, dir, reach: Supports::GROUP_WIDTH, rise: 800.0)
        x = horizontal(dir)
        y = Vec.cross(UP, x)
        out = []
        H.active_runs(model).each do |run, tr|
          ins = Builder.run_settings(run)['insulation_mm'].to_f
          run.entities.each do |e|
            next unless H.instance?(e) && H.type_of(e) == 'pipe'

            g = H.get_json(e, 'geom')
            a = H.transform_mm(tr, g['a'])
            b = H.transform_mm(tr, g['b'])
            ab = Vec.sub(b, a)
            next if Vec.length(ab) < 1.0
            next if Vec.dot(horizontal(ab), x).abs < Math.cos(Supports::GROUP_ANGLE * Math::PI / 180) # not parallel

            den = Vec.dot(ab, x)
            next if den.abs < 1e-6

            t = Vec.dot(Vec.sub(point, a), x) / den
            next if t.negative? || t > 1.0

            q = Vec.add(a, Vec.scale(ab, t))
            off = Vec.dot(Vec.sub(q, point), y)
            dz = q[2] - point[2]
            next if off.abs > reach || dz.abs > rise

            out << [off.round(1), e.get_attribute(H::DICT, 'od').to_f / 2.0 + ins, dz.round(1),
                    e.get_attribute(H::DICT, 'size'), run.persistent_id, ins]
          end
        end
        out.uniq { |o| [o[0], o[2]] }
      end

      # The clicked pipe and the neighbours that share its support.
      def members(model, point, dir, gap: group_gap)
        Supports.group(crossing_pipes(model, point, dir), gap: gap)
      end

      # Place a support of +type+ where the user clicked a pipe (hit from
      # Picker.nearest_pipe). Neighbouring pipes are carried too: the
      # support becomes its multi-pipe form. Returns a note or nil.
      def place(model, type, hit, lod: :detailed, steps: 16, gap: group_gap)
        mem = members(model, hit[:proj], hit[:dir], gap: gap)
        multi = Supports::TYPES[type][:multi] ? type : (mem.size > 1 && Supports::MULTI_OF[type])
        return add_record(model, hit[:run], hit[:tr], type, hit[:proj], hit[:dir]) unless multi

        model.start_operation('Plant Piping: Support', true)
        _g, note = create_multi(model, multi, hit[:proj], hit[:dir], base: type, lod: lod, steps: steps, pipes: mem)
        drop_covered(model, hit[:proj], mem)
        model.commit_operation
        note
      rescue StandardError
        model.abort_operation
        raise
      end

      # Single-pipe support stored on its run.
      def add_record(model, run, tr, type, at_w, dir_w)
        inv = tr.inverse
        at = H.transform_mm(inv, at_w)
        dir = Vec.unit(H.from_vec(H.to_vec(dir_w).transform(inv)))
        rec, note = record_for(model, run, tr, type, at, dir)
        return note unless rec

        model.start_operation('Plant Piping: Add Support', true)
        H.set_json(run, 'supports', H.get_json(run, 'supports', []) + [rec])
        Builder.render(model, run, Builder.run_settings(run))
        model.commit_operation
        note
      rescue StandardError
        model.abort_operation
        raise
      end

      # Single supports of the member runs right next to a new shared
      # support are now redundant – removed (their runs are rebuilt).
      def drop_covered(model, point, pipes)
        ids = pipes.map { |o| o[4] }
        H.active_runs(model).each do |run, tr|
          next unless ids.include?(run.persistent_id)

          recs = H.get_json(run, 'supports', [])
          keep = recs.reject { |r| Vec.dist(H.transform_mm(tr, r['at']), point) <= COVER }
          next if keep.size == recs.size

          H.set_json(run, 'supports', keep)
          Builder.render(model, run, Builder.run_settings(run))
        end
      end

      def shared_supports(model)
        out = []
        H.each_instance(model.active_entities) do |e, _t|
          out << e if H.type_of(e) == 'support' && e.get_attribute(H::DICT, 'at')
        end
        out
      end

      # Positions (world) of shared supports that carry run +pid+.
      def shared_points(model, pid)
        shared_supports(model).filter_map do |g|
          next unless H.get_json(g, 'members', []).include?(pid)

          JSON.parse(g.get_attribute(H::DICT, 'at'))
        end
      end

      # After pipes were drawn, rebuilt or resized: shared supports near
      # them take in / let go of neighbours, and single supports that now
      # have a neighbour become shared ones. runs: the runs that changed
      # (nil = whole model). Returns the number of supports changed.
      def adapt(model, runs = nil, gap: group_gap)
        return 0 if gap <= 0

        near = lambda do |pt|
          runs.nil? || runs.any? do |run|
            tr = H.edit_transform(model) * run.transformation
            H.get_json(run, 'cl', []).any? do |a, b|
              Vec.dist(pt, closest(H.transform_mm(tr, a), H.transform_mm(tr, b), pt)) <= Supports::GROUP_WIDTH
            end
          end
        end
        model.start_operation('Plant Piping: Adapt Supports', true, false, true)
        n = 0
        shared_supports(model).each do |g|
          at = JSON.parse(g.get_attribute(H::DICT, 'at'))
          next unless near.call(at)

          dir = JSON.parse(g.get_attribute(H::DICT, 'dir'))
          mem = members(model, at, dir, gap: gap)
          next if mem.empty? || signature(mem) == g.get_attribute(H::DICT, 'signature')

          base = g.get_attribute(H::DICT, 'base_type') || g.get_attribute(H::DICT, 'support_type')
          type = g.get_attribute(H::DICT, 'support_type')
          s = H.load_settings
          g.erase!
          create_multi(model, type, at, dir, base: base, lod: s['lod'].to_sym, steps: s['segments'], pipes: mem, op: false)
          drop_covered(model, at, mem)
          n += 1
        end
        H.active_runs(model).each do |run, tr|
          H.get_json(run, 'supports', []).each do |rec|
            multi = Supports::MULTI_OF[rec['type']]
            next unless multi && H.get_json(run, 'supports', []).include?(rec) # not dropped meanwhile

            at = H.transform_mm(tr, rec['at'])
            next unless near.call(at)

            dir = Vec.unit(H.from_vec(H.to_vec(rec['dir']).transform(tr)))
            mem = members(model, at, dir, gap: gap)
            next if mem.size < 2

            s = H.load_settings
            g, = create_multi(model, multi, at, dir, base: rec['type'], lod: s['lod'].to_sym, steps: s['segments'],
                                                     pipes: mem, op: false)
            drop_covered(model, at, mem) if g
            n += 1 if g
          end
        end
        model.commit_operation
        n
      rescue StandardError
        model.abort_operation
        raise
      end

      # A column beside the pipe at +point+: the nearest object within
      # SIDE_SEARCH sideways whose width along the pipe is column-like
      # (≤ 1.2 m). Returns the support point moved along the pipe to just
      # outside the column's side face nearest the click:
      # { at:, v: (toward the column), wall:, depth:, out: (unit, away
      # from the column along the pipe), moved: } or nil.
      def find_column(model, point, dir)
        x = horizontal(dir)
        lat = Vec.cross(UP, x)
        cands = [lat, Vec.scale(lat, -1.0)].filter_map do |v|
          h = cast(model, point, v, max_dist: SIDE_SEARCH) or next
          inside = Vec.add(h[:point], Vec.scale(v, 5.0))
          fwd = cast(model, inside, x, max_dist: 1500.0) or next
          back = cast(model, inside, Vec.scale(x, -1.0), max_dist: 1500.0) or next
          next if Vec.dist(fwd[:point], back[:point]) > 1200.0

          deep = cast(model, inside, v, max_dist: 1500.0)
          { h: h[:point], v: v, fwd: fwd[:point], back: back[:point],
            depth: deep ? Vec.dist(deep[:point], h[:point]) : 300.0 }
        end
        c = cands.min_by { |cc| Vec.dist(cc[:h], point) } or return nil

        # the side face nearer the click; the arm stands just outside it
        df = Vec.dot(Vec.sub(c[:fwd], point), x)
        db = Vec.dot(Vec.sub(c[:back], point), x)
        face, out = df.abs <= db.abs ? [df, x] : [db, Vec.scale(x, -1.0)]
        shift = face + Vec.dot(out, x) * (Supports::COLUMN_PLATE + Supports::COLUMN_ARM / 2.0)
        at = Vec.add(point, Vec.scale(x, shift))
        { at: at, v: c[:v], wall: Vec.dot(Vec.sub(c[:h], point), c[:v]), depth: c[:depth], out: out,
          moved: shift.abs > 1.0 }
      end

      def closest(a, b, p)
        ab = Vec.sub(b, a)
        l2 = Vec.dot(ab, ab)
        return a if l2 < 1e-9

        t = [[Vec.dot(Vec.sub(p, a), ab) / l2, 0.0].max, 1.0].min
        Vec.add(a, Vec.scale(ab, t))
      end

      def signature(pipes)
        pipes.map { |y, r, z, _s, id| [y.round, r.round(1), z.round, id] }.to_json
      end

      # Create a shared support (trapeze, H-frame, sleeper or bracket)
      # across +pipes+ (default: the clicked pipe and its neighbours) at
      # +point+ (world mm). base: the support type the user chose.
      def create_multi(model, type, point, dir, base: nil, lod: :detailed, steps: 16, pipes: nil, op: true)
        pipes ||= members(model, point, dir)
        raise 'ไม่พบท่อที่ตัดผ่านตำแหน่งนี้ (no pipes cross this point)' if pipes.empty?

        base ||= type
        f = frame(point, dir)
        offsets = pipes.map { |y, r, z, _| [y, r, z] }
        z_low = offsets.map { |_, r, z| z - r }.min
        bottom = Vec.add(point, [0, 0, z_low])
        det = lod == :detailed
        note = nil
        ys = offsets.map(&:first)
        rmax = offsets.map { |_, r, _| r }.max
        case type
        when 'trapeze'
          hit = cast(model, bottom, UP)
          drop = hit ? hit[:point][2] - point[2] : z_low + FALLBACK_DROP + 300
          note = 'ไม่พบโครงสร้างด้านบน – ใช้ความยาวก้านแขวนสมมติ' unless hit
          rod = rmax > 60 ? 12.7 : 9.5
          part = Supports.trapeze(offsets, drop, rod, kind: base == 'beam' ? :beam : :slab, steps: steps, detailed: det)
          span = ys.max - ys.min + 2 * rmax + 200
          attrs = { 'member_name' => 'Strut channel 41×41', 'member_length_mm' => span.round,
                    'rod_label' => rod > 10 ? '1/2" (M12)' : '3/8" (M10)', 'rod_length_mm' => (2 * (drop - z_low)).round }
        when 'hframe'
          hit = cast(model, bottom, Vec.scale(UP, -1.0))
          height = hit ? point[2] - hit[:point][2] : point[2]
          note = 'ไม่พบพื้น – ใช้ระดับ 0 ของโมเดล' unless hit
          part = Supports.hframe(offsets, height, steps: steps, detailed: det)
          span = ys.max - ys.min + 2 * rmax + 400
          attrs = { 'member_name' => 'Steel section 100×100 (H-frame)',
                    'member_length_mm' => (span + 2 * (height + z_low)).round }
        when 'sleeper'
          hit = cast(model, bottom, Vec.scale(UP, -1.0))
          height = hit ? point[2] - hit[:point][2] : point[2]
          note = 'ไม่พบพื้น – ใช้ระดับ 0 ของโมเดล' unless hit
          part = Supports.sleeper(pipes.map { |y, r, z, _s, _id, ins| [y, r - ins.to_f, z, ins.to_f] }, height, steps: steps)
          attrs = { 'member_name' => 'Pipe shoe (T)', 'member_length_mm' => (300 * pipes.size).round }
        when 'column'
          col = find_column(model, point, dir) or
            raise 'ไม่พบเสาข้างท่อภายใน 3 m – คลิกท่อตรงช่วงที่ผ่านเสา (no column beside the pipe)'
          point = col[:at]
          if col[:moved] # the pipes beside the column face
            pipes = members(model, point, dir)
            raise 'ท่อไม่ผ่านหน้าเสา (the pipe does not pass the column face)' if pipes.empty?
          end
          x = horizontal(dir)
          y = Vec.scale(col[:v], -1.0) # from the column toward the pipes
          x = Vec.scale(x, -1.0) if Vec.dot(Vec.cross(x, y), UP).negative?
          f = Mesh.frame(point, x, y)
          lat = Vec.cross(UP, horizontal(dir))
          sgn = Vec.dot(y, lat).positive? ? 1.0 : -1.0
          offsets = pipes.map { |yy, r, z| [sgn * yy, r, z] }
                         .select { |yy, r, _| yy > -col[:wall] + r && col[:wall] + yy + r <= Supports::BRACKET_REACH || yy.abs < 1.0 }
          pipes = pipes.select { |yy, r, z, *| offsets.any? { |oy, orr, oz| (oy - sgn * yy).abs < 0.5 && orr == r && oz == z } }
          side = Vec.dot(col[:out], x).positive? ? 1.0 : -1.0
          part = Supports.column_bracket(offsets, col[:wall], col[:depth], side, steps: steps, detailed: det)
          reach = col[:wall] + offsets.map { |yy, r, _| yy + r }.max + 60
          arm = reach + [[col[:depth] - 20, 120].max, 400].min
          attrs = { 'member_name' => 'Steel SHS 75×75 (column bracket)',
                    'member_length_mm' => (arm + (reach > 450 ? 0.85 * reach : 0)).round }
        when 'bracket'
          side = Vec.cross(UP, horizontal(dir))
          hits = [side, Vec.scale(side, -1.0)].map { |v| [v, cast(model, point, v, max_dist: SIDE_SEARCH)] }
                                              .reject { |_, h| h.nil? }
          raise 'ไม่พบผนัง/เสาภายใน 3 m (no wall or column within 3 m)' if hits.empty?

          v, h = hits.min_by { |_, hh| Vec.dist(hh[:point], point) }
          wall = Vec.dist([h[:point][0], h[:point][1], 0], [point[0], point[1], 0])
          # bracket frame: y from the wall toward the pipes
          sgn = Vec.dot(v, side).positive? ? -1.0 : 1.0
          offsets = offsets.map { |y, r, z| [sgn * y, r, z] }
                           .select { |y, r, _| y > -wall + r && wall + y + r <= Supports::BRACKET_REACH || y.abs < 1.0 }
          f = Mesh.frame(point, horizontal(dir), Vec.scale(v, -1.0))
          f = Mesh.frame(point, Vec.scale(horizontal(dir), -1.0), Vec.scale(v, -1.0)) if Vec.dot(Vec.cross(f[:x], f[:y]), UP).negative?
          part = Supports.bracket(offsets, wall, steps: steps, detailed: det)
          reach = wall + offsets.map { |y, r, _| y + r }.max + 60
          attrs = { 'member_name' => "Steel angle / box #{offsets.size > 1 ? 75 : 50} (bracket)",
                    'member_length_mm' => (reach + 0.7 * reach).round }
          pipes = pipes.select { |y, r, z, *| offsets.any? { |oy, orr, oz| (oy - sgn * y).abs < 0.5 && orr == r && oz == z } }
        else
          raise "unknown support #{type}"
        end
        model.start_operation('Plant Piping: Multi-pipe Support', true) if op
        started = op
        g = H.add_part_group(model, model.active_entities, part, steps: steps)
        g.transformation = H.edit_transform(model).inverse * H.frame_transform(f)
        info = Supports::TYPES[type] || { name: 'Sleeper + pipe shoes', th: 'คานรองท่อ + Pipe shoe (หลายท่อ)' }
        g.name = "#{info[:name]} (#{pipes.size} pipes)"
        g.layer = H.tag(model, Builder::TAG_SUPPORTS)
        H.set_attrs(g, attrs.merge('type' => 'support', 'support_type' => type, 'base_type' => base,
                                   'support_name' => info[:name],
                                   'pipe_size' => "#{pipes.size} pipes", 'size' => "#{pipes.size} pipes",
                                   'service' => 'multi', 'pipes' => pipes.map { |o| o[3] }.join(', '),
                                   'at' => point.to_json, 'dir' => horizontal(dir).to_json,
                                   'members' => pipes.map { |o| o[4] }.to_json, 'signature' => signature(pipes)))
        model.commit_operation if op
        [g, note]
      rescue StandardError
        model.abort_operation if started
        raise
      end
    end
  end
end
