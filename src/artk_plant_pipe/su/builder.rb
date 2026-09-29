# frozen_string_literal: true

module ArtK
  module PlantPipe
    # Builds and rebuilds piping runs in the SketchUp model.
    #
    # Model structure
    #   Run group  (type=run, name = line number, tag = service)
    #     ├─ Pipe / Elbow / Tee groups  (type=pipe|elbow|tee, one per piece)
    #     ├─ Insulation groups          (type=insulation, tag PP-Insulation)
    #     ├─ Valve groups               (type=valve)
    #     ├─ Centerline group           (type=centerline, tag PP-Centerline)
    #     └─ Line-number label          (tag PP-Labels)
    #
    # The run stores its centreline ('cl'), branch connections ('tees') and
    # settings as attributes. Every piece is regenerated from that data, so a
    # run can be resized, re-materialled or extended at any time without
    # redrawing – the way piping design actually iterates.
    module Builder
      H = ModelHelpers

      module_function

      # Create a run from centreline segments in active-context coordinates.
      # op: false when the caller wraps several runs in one undo step.
      def create_run(model, segs, settings, tees: [], op: true)
        settings = Settings.sanitize(settings)
        model.start_operation('Plant Piping: Draw Run', true) if op
        run = model.active_entities.add_group
        H.set_attrs(run, 'type' => 'run')
        H.set_json(run, 'cl', segs)
        H.set_json(run, 'tees', tees)
        warnings = render(model, run, settings)
        model.commit_operation if op
        [run, warnings]
      rescue StandardError
        model.abort_operation if op
        raise
      end

      # Append segments (run-local coordinates) and rebuild.
      def extend_run(model, run, segs, tees: [])
        model.start_operation('Plant Piping: Extend Run', true)
        H.set_json(run, 'cl', H.get_json(run, 'cl', []) + segs)
        H.set_json(run, 'tees', H.get_json(run, 'tees', []) + tees)
        warnings = render(model, run, run_settings(run))
        model.commit_operation
        warnings
      rescue StandardError
        model.abort_operation
        raise
      end

      # Rebuild with new settings (resize, change material/service...).
      def rebuild(model, runs, settings)
        warnings = []
        model.start_operation('Plant Piping: Rebuild Runs', true)
        runs.each do |run|
          merged = run_settings(run).merge(settings_for_rebuild(settings))
          warnings.concat(render(model, run, merged).map { |w| "#{run.name}: #{w}" })
        end
        warnings.concat(refresh_branches(model, runs))
        model.commit_operation
        warnings
      rescue StandardError
        model.abort_operation
        raise
      end

      # Branch runs keep a copy of their main line's spec in their tee
      # records; after main lines change, update those copies and redraw the
      # branch tees (reducing tee sizes follow the new main size).
      def refresh_branches(model, mains)
        by_pid = mains.map { |r| [r.persistent_id, r] }.to_h
        warnings = []
        Collector.all_runs(model).each do |run, _tr|
          next if by_pid.key?(run.persistent_id)

          tees = H.get_json(run, 'tees', [])
          changed = false
          tees.each do |t|
            main = by_pid[t['main_pid']]
            next unless main

            t['main_catalog'] = main.get_attribute(H::DICT, 'catalog')
            t['main_size'] = main.get_attribute(H::DICT, 'size')
            t['main_rating'] = main.get_attribute(H::DICT, 'rating')
            t['main_service'] = main.get_attribute(H::DICT, 'service')
            changed = true
          end
          next unless changed

          H.set_json(run, 'tees', tees)
          warnings.concat(render(model, run, run_settings(run)).map { |w| "#{run.name}: #{w}" })
        end
        warnings
      end

      # Keys that a rebuild applies from the current settings.
      def settings_for_rebuild(settings)
        settings.select do |k, _|
          %w[service catalog size rating insulation_mm elbow_type segments centerline labels].include?(k)
        end
      end

      def run_settings(run)
        Settings.sanitize(H.get_json(run, 'settings', {}))
      end

      def run_spec(run)
        Settings.spec(run_settings(run))
      end

      # ------------------------------------------------------------------

      # (Re)generate all geometry of +run+ from its stored centreline.
      # Returns an array of warning strings.
      def render(model, run, settings)
        settings = Settings.sanitize(settings)
        spec = Settings.spec(settings)
        svc = Services.get(settings['service'])
        code = svc[:code]

        seq = run.get_attribute(H::DICT, 'seq')
        seq = H.next_seq(model, code) if seq.nil? || run.get_attribute(H::DICT, 'service') != code
        line_no = H.line_number(spec.size, code, seq)

        cl = H.get_json(run, 'cl', [])
        tees = H.get_json(run, 'tees', [])
        warnings = []

        ents = run.entities
        valves = ents.select { |e| H.instance?(e) && H.type_of(e) == 'valve' }.map { |v| H.attrs(v) }
        ents.clear!
        segs = apply_branch_trims(cl, tees, warnings)

        ctx = {
          model: model, ents: ents, spec: spec, settings: settings, svc: svc, line_no: line_no,
          segs: settings['segments'], ins: settings['insulation_mm'].to_f, cl: cl,
          tag: H.service_tag(model, code),
          mat: H.service_material(model, code, settings['color_scheme']),
          fit_mat: H.service_material(model, code, settings['color_scheme'], fitting: true),
          common: {
            'service' => code, 'catalog' => spec.catalog_key, 'catalog_name' => spec.catalog_name,
            'material' => spec.material, 'size' => spec.size, 'rating' => spec.rating,
            'od' => spec.od, 'wall' => spec.wall, 'line_no' => line_no
          }
        }

        extras = []
        unless segs.empty?
          net = Network.new(segs, spec, tol: 1.0, radius_type: settings['elbow_type'].to_sym).solve
          warnings.concat(net.warnings)
          net.pieces.each { |pc| render_piece(ctx, pc, extras, warnings) }
          add_label(ctx, net) if settings['labels']
        end
        tees.each { |t| render_branch_tee(ctx, t, warnings) }
        valves.each do |v|
          Valves.build(ctx, v['valve_type'], JSON.parse(v['at']), JSON.parse(v['dir']))
        rescue StandardError => e
          warnings << "Valve could not be rebuilt: #{e.message}"
        end
        add_centerline(ctx, cl) if settings['centerline']

        if spec.estimated
          extras.each { |x| x['remark'] ||= 'wall thickness estimated' }
        end
        H.set_attrs(run, ctx[:common].merge('type' => 'run', 'seq' => seq, 'joint' => spec.joint))
        H.set_json(run, 'settings', settings)
        H.set_json(run, 'extras', extras)
        run.name = line_no
        run.layer = ctx[:tag]
        warnings
      end

      # Branch connections start/end at the centre of a tee on another run:
      # pull the segment end back by the tee's centre-to-end so the new pipe
      # starts at the tee outlet.
      def apply_branch_trims(cl, tees, warnings)
        segs = cl.map { |a, b| [a.dup, b.dup] }
        tees.each do |t|
          at = t['at']
          c = main_spec(t).tee_c
          hits = []
          segs.each_with_index do |(a, b), i|
            hits << [i, 0] if Vec.dist(a, at) <= 1.0
            hits << [i, 1] if Vec.dist(b, at) <= 1.0
          end
          next unless hits.size == 1

          i, end_idx = hits.first
          a, b = segs[i]
          len = Vec.dist(a, b)
          if len <= c + 1.0
            warnings << "ท่อแยกสั้นกว่าระยะ Tee (#{len.round} mm) (branch shorter than tee outlet)"
            next
          end
          if end_idx.zero?
            segs[i][0] = Vec.add(a, Vec.scale(Vec.unit(Vec.sub(b, a)), c))
          else
            segs[i][1] = Vec.sub(b, Vec.scale(Vec.unit(Vec.sub(b, a)), c))
          end
        end
        segs
      end

      def main_spec(t)
        Catalog.spec(t['main_catalog'], t['main_size'], t['main_rating'])
      rescue ArgumentError
        Catalog.spec('CS_B36_10', '2"')
      end

      # ------------------------------------------------------------------

      def render_piece(ctx, pc, extras, warnings)
        d = pc.data
        case pc.type
        when :pipe then render_pipe(ctx, d)
        when :elbow then render_elbow(ctx, d, extras)
        when :tee, :lateral, :cross, :manifold then render_tee(ctx, pc.type, d)
        when :mitre
          extras << ctx[:common].merge('type' => 'mitre', 'angle' => d[:angle])
        end
      rescue StandardError => e
        warnings << "#{pc.type}: #{e.message}"
      end

      def render_pipe(ctx, d)
        spec = ctx[:spec]
        g = H.sweep(ctx[:ents], spec.od / 2.0, ctx[:segs], line: [d[:from], d[:to]])
        finish_piece(ctx, g, "Pipe #{spec.size}", ctx[:mat],
                     'type' => 'pipe', 'length_mm' => d[:length].round(1),
                     'weight_kg_m' => spec.weight_kg_m.round(3), 'stick_m' => spec.stick_length_m,
                     'geom' => JSON.generate('a' => d[:from], 'b' => d[:to]),
                     'remark' => spec.estimated ? 'wall thickness estimated' : nil)
        return unless ctx[:ins].positive?

        gi = H.sweep(ctx[:ents], spec.od / 2.0 + ctx[:ins], ctx[:segs], line: [d[:from], d[:to]])
        insulation(ctx, gi, d[:length])
      end

      def render_elbow(ctx, d, extras)
        spec = ctx[:spec]
        arc_segs = [((d[:angle_deg] / 90.0) * (ctx[:segs] / 2)).ceil, 2].max
        g = H.sweep(ctx[:ents], spec.fitting_od / 2.0, ctx[:segs], arc: d, arc_segs: arc_segs)
        attrs = {
          'type' => 'elbow', 'angle' => d[:angle_deg], 'radius_type' => d[:radius_type].to_s,
          'radius_mm' => d[:radius].round(1),
          'geom' => JSON.generate('center' => d[:center], 'xaxis' => d[:xaxis], 'normal' => d[:normal],
                                  'radius' => d[:radius], 'angle' => d[:angle],
                                  'start' => d[:start], 'end' => d[:end])
        }
        attrs['nominal_angle'] = d[:nominal_angle] if d[:nominal_angle]
        finish_piece(ctx, g, "Elbow #{d[:angle_deg].round}° #{spec.size}", ctx[:fit_mat], attrs)
        return unless ctx[:ins].positive?

        arc_len = d[:radius] * d[:angle]
        r_ins = spec.fitting_od / 2.0 + ctx[:ins]
        if r_ins < 0.95 * d[:radius]
          gi = H.sweep(ctx[:ents], r_ins, ctx[:segs], arc: d, arc_segs: arc_segs)
          insulation(ctx, gi, arc_len)
        else
          # Insulation thicker than the bend radius cannot be swept as a solid;
          # still count it in the BOM.
          extras << ctx[:common].merge('type' => 'insulation', 'thickness' => ctx[:ins],
                                       'length_mm' => arc_len.round(1))
        end
      end

      def render_tee(ctx, kind, d)
        spec = ctx[:spec]
        fg = ctx[:ents].add_group
        r = spec.fitting_od / 2.0
        c = d[:c]
        arm = ->(a, b) { H.sweep(fg.entities, r, ctx[:segs], line: [a, b]) }
        if d[:run]
          arm.call(Vec.add(d[:center], Vec.scale(d[:run][0], c)), Vec.add(d[:center], Vec.scale(d[:run][1], c)))
          arm.call(d[:center], Vec.add(d[:center], Vec.scale(d[:branch], c)))
        else
          d[:arms].each { |u| arm.call(d[:center], Vec.add(d[:center], Vec.scale(u, c))) }
        end
        attrs = { 'type' => 'tee', 'kind' => kind.to_s, 'role' => 'run',
                  'geom' => JSON.generate('center' => d[:center], 'arms' => d[:arms], 'c' => c) }
        attrs['branch_angle'] = d[:branch_angle] if d[:branch_angle]
        name = kind == :cross ? 'Cross' : kind == :lateral ? 'Lateral' : 'Tee'
        finish_piece(ctx, fg, "#{name} #{spec.size}", ctx[:fit_mat], attrs)
        return unless ctx[:ins].positive?

        d[:arms].each do |u|
          gi = H.sweep(ctx[:ents], r + ctx[:ins], ctx[:segs], line: [d[:center], Vec.add(d[:center], Vec.scale(u, c))])
          insulation(ctx, gi, c)
        end
      end

      # Tee placed on another run's pipe where this run branches off.
      def render_branch_tee(ctx, t, warnings)
        main = main_spec(t)
        spec = ctx[:spec]
        at = t['at']
        main_dir = Vec.unit(t['main_dir'])
        seg = ctx[:cl].find do |a, b|
          Vec.dist(a, at) <= 1.0 || Vec.dist(b, at) <= 1.0
        end
        return warnings << 'Branch tee: centreline not found' unless seg

        other = Vec.dist(seg[0], at) <= 1.0 ? seg[1] : seg[0]
        bdir = Vec.unit(Vec.sub(other, at))
        c = main.tee_c
        fg = ctx[:ents].add_group
        H.sweep(fg.entities, main.fitting_od / 2.0, ctx[:segs],
                line: [Vec.sub(at, Vec.scale(main_dir, c)), Vec.add(at, Vec.scale(main_dir, c))])
        H.sweep(fg.entities, spec.fitting_od / 2.0, ctx[:segs], line: [at, Vec.add(at, Vec.scale(bdir, c))])
        angle = Vec.angle(bdir, main_dir) * 180.0 / Math::PI
        angle = 180.0 - angle if angle > 90.0
        kind = (angle - 90.0).abs <= 1.0 ? 'tee' : 'lateral'
        fg.material = ctx[:fit_mat]
        fg.layer = ctx[:tag]
        fg.name = "Branch #{kind} #{main.size} x #{spec.size}"
        H.set_attrs(fg, ctx[:common].merge(
          'type' => 'tee', 'kind' => kind, 'role' => 'branch', 'branch_angle' => angle.round(1),
          'size' => main.size, 'branch_size' => spec.size, 'rating' => main.rating,
          'service' => t['main_service'] || ctx[:common]['service'],
          'catalog_name' => main.catalog_name, 'material' => main.material, 'od' => main.od,
          'geom' => JSON.generate('center' => at, 'arms' => [main_dir, Vec.scale(main_dir, -1.0), bdir], 'c' => c)
        ))
      rescue StandardError => e
        warnings << "Branch tee: #{e.message}"
      end

      def finish_piece(ctx, grp, name, mat, attrs)
        grp.name = name
        grp.material = mat
        grp.layer = ctx[:tag]
        H.set_attrs(grp, ctx[:common].merge(attrs).reject { |_, v| v.nil? })
        grp
      end

      def insulation(ctx, grp, length_mm)
        grp.name = "Insulation #{ctx[:ins].round} mm"
        grp.material = H.insulation_material(ctx[:model])
        grp.layer = H.tag(ctx[:model], H::TAG_INSULATION)
        H.set_attrs(grp, ctx[:common].merge('type' => 'insulation', 'thickness' => ctx[:ins],
                                            'length_mm' => length_mm.round(1),
                                            'insulation_material' => insulation_material_name(ctx)))
      end

      # Typical insulation by service – shown in the BOM for purchasing.
      def insulation_material_name(ctx)
        case ctx[:svc][:fluid]
        when :steam then 'Mineral wool / Calcium silicate + Al jacket'
        when :hot_water then 'Closed-cell elastomeric (EPDM) / PU foam'
        else ctx[:svc][:code].start_with?('CHW') ? 'Closed-cell elastomeric + vapour barrier' : 'Closed-cell elastomeric'
        end
      end

      def add_centerline(ctx, cl)
        g = ctx[:ents].add_group
        cl.each do |a, b|
          next if Vec.dist(a, b) < 0.5

          g.entities.add_line(H.to_pt(a), H.to_pt(b))
        end
        g.name = 'Centerline'
        g.layer = H.tag(ctx[:model], H::TAG_CENTERLINE)
        H.set_attrs(g, 'type' => 'centerline')
      end

      def add_label(ctx, net)
        longest = net.pipes.max_by { |p| p.data[:length] }
        return unless longest

        mid = Vec.lerp(longest.data[:from], longest.data[:to], 0.5)
        lift = ctx[:spec].od / 2.0 + ctx[:ins] + 300.0
        txt = ctx[:ents].add_text("#{ctx[:line_no]}  #{ctx[:spec].material}", H.to_pt(mid),
                                  Geom::Vector3d.new(0, 0, H.mm(lift)))
        txt.layer = H.tag(ctx[:model], H::TAG_LABELS)
      end

      # Insert a valve into a run (run-local coordinates).
      def add_valve(model, run, type, at, dir)
        settings = run_settings(run)
        spec = Settings.spec(settings)
        svc = Services.get(settings['service'])
        model.start_operation('Plant Piping: Insert Valve', true)
        ctx = {
          model: model, ents: run.entities, spec: spec, settings: settings, svc: svc,
          segs: settings['segments'], tag: H.service_tag(model, svc[:code]),
          common: {
            'service' => svc[:code], 'catalog' => spec.catalog_key, 'catalog_name' => spec.catalog_name,
            'material' => spec.material, 'size' => spec.size, 'rating' => spec.rating,
            'od' => spec.od, 'wall' => spec.wall, 'line_no' => run.name
          }
        }
        g = Valves.build(ctx, type, at, dir)
        model.commit_operation
        g
      rescue StandardError
        model.abort_operation
        raise
      end
    end
  end
end
