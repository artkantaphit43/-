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
    # Multi-pipe supports (trapeze, H-frame) are standalone groups.
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

      # ---------- multi-pipe supports ----------

      # Pipes crossing the vertical plane through +point+ (world mm)
      # perpendicular to horizontal +dir+, within reach. Returns
      # [[y offset, radius incl. insulation, z offset, size], ...].
      def crossing_pipes(model, point, dir, reach: 1500.0, rise: 800.0)
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
            next if Vec.dot(horizontal(ab), x).abs < Math.cos(10 * Math::PI / 180) # not parallel

            den = Vec.dot(ab, x)
            next if den.abs < 1e-6

            t = Vec.dot(Vec.sub(point, a), x) / den
            next if t.negative? || t > 1.0

            q = Vec.add(a, Vec.scale(ab, t))
            off = Vec.dot(Vec.sub(q, point), y)
            dz = q[2] - point[2]
            next if off.abs > reach || dz.abs > rise

            out << [off.round(1), e.get_attribute(H::DICT, 'od').to_f / 2.0 + ins, dz.round(1),
                    e.get_attribute(H::DICT, 'size')]
          end
        end
        out.uniq { |o| o[0] }
      end

      # Create a trapeze or H-frame across the pipes at +point+ (world mm).
      def create_multi(model, type, point, dir, lod: :detailed, steps: 16)
        pipes = crossing_pipes(model, point, dir)
        raise 'ไม่พบท่อที่ตัดผ่านตำแหน่งนี้ (no pipes cross this point)' if pipes.empty?

        f = frame(point, dir)
        offsets = pipes.map { |y, r, z, _| [y, r, z] }
        z_low = offsets.map { |_, r, z| z - r }.min
        base = Vec.add(point, [0, 0, z_low])
        det = lod == :detailed
        note = nil
        if type == 'trapeze'
          hit = cast(model, base, UP)
          drop = hit ? hit[:point][2] - point[2] : z_low + FALLBACK_DROP + 300
          note = 'ไม่พบโครงสร้างด้านบน – ใช้ความยาวก้านแขวนสมมติ' unless hit
          rod = pipes.map { |_, r, _, _| r }.max > 60 ? 12.7 : 9.5
          part = Supports.trapeze(offsets, drop, rod, steps: steps, detailed: det)
          ys = offsets.map(&:first)
          span = ys.max - ys.min + 2 * offsets.map { |_, r, _| r }.max + 200
          attrs = { 'member_name' => 'Strut channel 41×41', 'member_length_mm' => span.round,
                    'rod_label' => rod > 10 ? '1/2" (M12)' : '3/8" (M10)', 'rod_length_mm' => (2 * (drop - z_low)).round }
        else
          hit = cast(model, base, Vec.scale(UP, -1.0))
          height = hit ? point[2] - hit[:point][2] : point[2]
          note = 'ไม่พบพื้น – ใช้ระดับ 0 ของโมเดล' unless hit
          part = Supports.hframe(offsets, height, steps: steps, detailed: det)
          ys = offsets.map(&:first)
          span = ys.max - ys.min + 2 * offsets.map { |_, r, _| r }.max + 400
          attrs = { 'member_name' => 'Steel section 100×100 (H-frame)',
                    'member_length_mm' => (span + 2 * (height + z_low)).round }
        end
        model.start_operation('Plant Piping: Multi-pipe Support', true)
        started = true
        g = H.add_part_group(model, model.active_entities, part, steps: steps)
        g.transformation = H.edit_transform(model).inverse * H.frame_transform(f)
        info = Supports::TYPES[type]
        g.name = "#{info[:name]} (#{pipes.size} pipes)"
        g.layer = H.tag(model, Builder::TAG_SUPPORTS)
        H.set_attrs(g, attrs.merge('type' => 'support', 'support_type' => type, 'support_name' => info[:name],
                                   'pipe_size' => "#{pipes.size} pipes", 'size' => "#{pipes.size} pipes",
                                   'service' => 'multi', 'pipes' => pipes.map(&:last).join(', ')))
        model.commit_operation
        [g, note]
      rescue StandardError
        model.abort_operation if started
        raise
      end
    end
  end
end
