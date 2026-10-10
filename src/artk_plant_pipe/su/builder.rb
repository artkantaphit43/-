# frozen_string_literal: true

module ArtK
  module PlantPipe
    # Builds and rebuilds piping runs in the SketchUp model.
    #
    # Model structure
    #   Run group  (type=run, name = line number, tag = service)
    #     ├─ Pipe groups        – hollow tube meshes (type=pipe)
    #     ├─ Elbow / Tee        – component instances (type=elbow|tee)
    #     ├─ Valve              – component instances (type=valve)
    #     ├─ Insulation groups  (type=insulation, tag PP-Insulation)
    #     ├─ Support groups     (type=support, tag PP-Supports)
    #     ├─ Centerline group   (type=centerline, tag PP-Centerline)
    #     └─ Line-number label  (tag PP-Labels)
    #
    # The run stores its centreline ('cl'), branch connections ('tees'),
    # supports ('supports') and settings as attributes. Every piece is
    # regenerated from that data, so a run can be resized, re-materialled or
    # extended at any time without redrawing – and its valves and supports
    # follow the new size.
    #
    # Fittings and valves are ComponentDefinitions built once per
    # type/size/material/detail level and instanced, so a plant model with
    # hundreds of detailed valves stays light. Their pipe-coloured faces are
    # unpainted and take the instance material, so one definition serves
    # every service colour.
    module Builder
      H = ModelHelpers
      TAG_SUPPORTS = 'PP-Supports'

      module_function

      # Create a run from centreline segments in active-context coordinates.
      # op: false when the caller wraps several runs in one undo step.
      # smooth: points the pipe bends through (drawn arcs / curves).
      def create_run(model, segs, settings, tees: [], joins: [], op: true, smooth: [])
        settings = Settings.sanitize(settings)
        model.start_operation('Plant Piping: Draw Run', true) if op
        run = model.active_entities.add_group
        H.set_attrs(run, 'type' => 'run')
        H.set_json(run, 'cl', segs)
        H.set_json(run, 'tees', tees)
        H.set_json(run, 'joins', joins)
        H.set_json(run, 'smooth', smooth) unless smooth.nil? || smooth.empty?
        warnings = render(model, run, settings)
        model.commit_operation if op
        [run, warnings]
      rescue StandardError
        model.abort_operation if op
        raise
      end

      # Append segments (run-local coordinates) and rebuild.
      def extend_run(model, run, segs, tees: [], op: true)
        model.start_operation('Plant Piping: Extend Run', true) if op
        H.set_json(run, 'cl', H.get_json(run, 'cl', []) + segs)
        H.set_json(run, 'tees', H.get_json(run, 'tees', []) + tees)
        warnings = render(model, run, run_settings(run))
        model.commit_operation if op
        warnings
      rescue StandardError
        model.abort_operation if op
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
        H.purge_parts(model)
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

          changed = false
          links = %w[tees joins].map do |key|
            recs = H.get_json(run, key, [])
            recs.each do |t|
              main = by_pid[t['main_pid']]
              next unless main

              t['main_catalog'] = main.get_attribute(H::DICT, 'catalog')
              t['main_size'] = main.get_attribute(H::DICT, 'size')
              t['main_rating'] = main.get_attribute(H::DICT, 'rating')
              t['main_service'] = main.get_attribute(H::DICT, 'service')
              t['main_color'] = run_settings(main)['pipe_color']
              t['main_joint'] = run_settings(main)['hdpe_joint']
              changed = true
            end
            [key, recs]
          end
          next unless changed

          links.each { |key, recs| H.set_json(run, key, recs) }
          warnings.concat(render(model, run, run_settings(run)).map { |w| "#{run.name}: #{w}" })
        end
        warnings
      end

      # Keys that a rebuild applies from the current settings.
      def settings_for_rebuild(settings)
        settings.select do |k, _|
          %w[service catalog size rating insulation_mm elbow_type segments centerline labels lod pipe_color
             hdpe_joint].include?(k)
        end
      end

      def run_settings(run)
        Settings.sanitize(H.get_json(run, 'settings', {}))
      end

      def run_spec(run)
        Settings.spec(run_settings(run))
      end

      # ------------------------------------------------------------------

      # (Re)generate all geometry of +run+ from its stored data.
      # Returns an array of warning strings.
      def render(model, run, settings)
        if Migrate.entity(model, run, rebuild: false) == :newer
          return ['วาดด้วยเวอร์ชันใหม่กว่า – อัปเดตปลั๊กอินก่อนแก้ไข (ไม่ได้แก้ไขท่อนี้)']
        end

        settings = Settings.sanitize(settings)
        spec = Settings.spec(settings)
        svc = Services.get(settings['service'])
        code = svc[:code]

        seq = run.get_attribute(H::DICT, 'seq')
        seq = H.next_seq(model, code) if seq.nil? || run.get_attribute(H::DICT, 'service') != code
        line_no = H.line_number(spec.size, code, seq)

        ents = run.entities
        prune_deleted(run, ents)
        cl = H.get_json(run, 'cl', [])
        tees = H.get_json(run, 'tees', [])
        joins = H.get_json(run, 'joins', [])
        warnings = []

        valves = ents.select { |e| H.instance?(e) && H.type_of(e) == 'valve' }.map { |v| H.attrs(v) }
        end_parts = end_part_records(ents)
        ents.clear!
        ctx = context(model, run, settings, spec, svc, line_no)
        segs = apply_branch_trims(cl, tees, warnings, ctx)
        segs = apply_join_trims(segs, joins, spec, warnings, settings['hdpe_joint'])

        ctx[:cl] = cl
        ctx[:warnings] = warnings
        links = tees + joins
        ctx[:open_ends] = Collector.open_ends(cl).reject { |p| links.any? { |t| Vec.dist(p, t['at']) <= 1.0 } }

        extras = []
        tees.each { |t| premark_branch(ctx, t) }
        unless segs.empty?
          net = Network.new(segs, network_spec(spec, ctx[:opts]), tol: 1.0,
                                        radius_type: spec.flexible ? :lr : settings['elbow_type'].to_sym,
                                        takes: fitting_takes(ctx, spec),
                                        smooth: H.get_json(run, 'smooth', [])).solve
          warnings.concat(spec.flexible ? flexible_warnings(net, ctx[:opts]) : net.warnings)
          ctx[:mitres] = net.pieces.select { |pc| pc.type == :mitre }.map { |pc| pc.data[:at] }
          # fittings first: real fittings record their socket depths, which
          # the pipes then run into
          net.pieces.sort_by { |pc| %i[pipe curve].include?(pc.type) ? 1 : 0 }.each { |pc| render_piece(ctx, pc, extras, warnings) }
          add_label(ctx, net) if settings['labels']
        end
        tees.each { |t| render_branch_tee(ctx, t, warnings) }
        joins.each { |j| render_join(ctx, j, warnings) }
        valves.each do |v|
          place_valve(ctx, v['valve_type'], JSON.parse(v['at']), JSON.parse(v['dir']), model: v['model'])
        rescue StandardError => e
          warnings << "Valve could not be rebuilt: #{e.message}"
        end
        end_parts.each { |rec| place_end_part(ctx, rec, warnings) }
        H.get_json(run, 'supports', []).each do |rec|
          SupportBuilder.render(ctx, rec)
        rescue StandardError => e
          warnings << "Support: #{e.message}"
        end
        add_centerline(ctx, cl) if settings['centerline']

        extras.each { |x| x['remark'] ||= 'wall thickness estimated' } if spec.estimated
        H.set_attrs(run, ctx[:common].merge('type' => 'run', 'seq' => seq, 'joint' => spec.joint,
                                            DataFormat::KEY => DataFormat::CURRENT))
        H.set_json(run, 'settings', settings)
        H.set_json(run, 'extras', extras)
        H.set_json(run, 'warnings', warnings.uniq.first(50))
        H.set_json(run, 'drawn', drawn_pieces(ents))
        run.name = line_no
        run.layer = ctx[:tag]
        run.material = ctx[:mat]
        warnings
      end

      # ---- pieces deleted in SketchUp stay deleted ----
      #
      # Every run is regenerated from its centre line, so a pipe or fitting
      # the user deleted (to re-route) used to come back on the next rebuild
      # or when drawing on from it. The pieces drawn last time are recorded
      # ('drawn'); the ones missing now were deleted, and the centre line
      # gives them up before the run is drawn again.

      # { 'pipes' => [centre line pts], 'fittings' => [[node, [arm ends]]] }
      def drawn_pieces(ents)
        pipes = []
        fittings = []
        ents.each do |e|
          next unless e.valid? && H.instance?(e)

          g = H.get_json(e, 'geom') or next
          case H.type_of(e)
          when 'pipe'
            # a coiled-HDPE bend (arc, no path) stands for a corner, not a pipe
            bend = !e.get_attribute(H::DICT, 'bend_radius_mm').nil? && g['path'].nil?
            pipes << H.pipe_path(g) if g['a'] && g['b'] && !bend
          when 'elbow'
            fittings << [g['vertex'], [g['start'], g['end']]] if g['vertex']
          when 'tee'
            next unless e.get_attribute(H::DICT, 'role') == 'run'

            fittings << [g['center'], g['arms'].map { |u| Vec.add(g['center'], Vec.scale(u, g['c'].to_f)) }]
          end
        end
        { 'pipes' => pipes, 'fittings' => fittings }
      end

      # [deleted pipe centre lines, deleted fittings] of +run+.
      def deleted_pieces(run, ents = run.entities)
        drawn = H.get_json(run, 'drawn') or return [[], []]
        now = drawn_pieces(ents)
        same = ->(p, q) { p.size == q.size && p.zip(q).all? { |x, y| Vec.dist(x, y) <= 1.0 } }
        pipes = drawn['pipes'].reject { |p| now['pipes'].any? { |q| same.call(p, q) } }
        fits = drawn['fittings'].reject { |n, _| now['fittings'].any? { |m, _| Vec.dist(n, m) <= 1.0 } }
        [pipes, fits]
      end

      def deletions?(run)
        pipes, fits = deleted_pieces(run)
        !(pipes.empty? && fits.empty?)
      end

      # Give up the centre line under deleted pieces, and what sat on it
      # (supports, valves, branch connections of this run).
      def prune_deleted(run, ents)
        pipes, fits = deleted_pieces(run, ents)
        return if pipes.empty? && fits.empty?

        cl = RunEdit.prune(H.get_json(run, 'cl', []), pipes, fits)
        on = ->(p) { !RunEdit.segment_index(cl, p).nil? }
        H.set_json(run, 'cl', cl)
        H.set_json(run, 'supports', H.get_json(run, 'supports', []).select { |r| on.call(r['at']) })
        %w[tees joins].each do |k|
          H.set_json(run, k, H.get_json(run, k, []).select { |t| cl.flatten(1).any? { |p| Vec.dist(p, t['at']) <= 1.0 } })
        end
        ents.to_a.each do |e|
          next unless e.valid? && H.instance?(e) && H.type_of(e) == 'valve'

          at = JSON.parse(e.get_attribute(H::DICT, 'at').to_s) rescue nil
          e.erase! unless at && on.call(at)
        end
      end

      def context(model, run, settings, spec, svc, line_no)
        steps = settings['segments']
        {
          model: model, run: run, ents: run.entities, spec: spec, settings: settings, svc: svc,
          line_no: line_no, steps: steps, ins: settings['insulation_mm'].to_f,
          lod: settings['lod'].to_sym, opts: Parts.opts(spec, lod: settings['lod'], steps: steps, joint: settings['hdpe_joint']),
          refs: refs_enabled?(settings), ext: {},
          tag: H.service_tag(model, svc[:code]),
          mat: H.pipe_material(model, svc[:code], spec.family, settings['color_scheme'], settings['pipe_color']),
          open_ends: [], mitres: [], cl: [],
          common: {
            'service' => svc[:code], 'catalog' => spec.catalog_key, 'catalog_name' => spec.catalog_name,
            'material' => spec.material, 'size' => spec.size, 'rating' => spec.rating,
            'od' => spec.od, 'wall' => spec.wall, 'line_no' => line_no
          }
        }
      end

      # Branch connections start/end at the centre of a tee on another run:
      # pull the segment end back by the tee's centre-to-end so the new pipe
      # starts at the tee outlet.
      def apply_branch_trims(cl, tees, warnings, ctx)
        segs = cl.map { |a, b| [a.dup, b.dup] }
        tees.each do |t|
          at = t['at']
          c = branch_c(t, ctx)
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

      # Centre-to-branch-end of the tee on the main line: the real tee when
      # it is an equal tee from the reference library, else the standard C.
      def branch_c(t, ctx)
        item = branch_ref_tee(t, ctx)
        return Vec.length(item['ports'][2]['p']) if item

        br = branch_reducer(main_opts(t, ctx), ctx[:opts])
        main_tee_c(t, ctx) + (br ? br[:len] : 0.0)
      end

      # A smaller HDPE branch off a butt fusion / EF main is made as on
      # site: an equal tee, then a stepped spigot reducer down to the
      # branch size (its long small leg joined by the branch's own system).
      # Compression mains keep their reducing tees.
      def branch_reducer(mo, bo)
        return nil unless Hdpe.style?(mo) && Hdpe.style?(bo) && mo.style != :compression && bo.od < mo.od - 0.5

        big = mo.dup.tap { |x| x.style = :fusion }
        small = bo.dup.tap { |x| x.style = :fusion }
        lead = mo.style == :electrofusion ? Hdpe.ef_socket(mo.od) + 15.0 : 0.6 * Hdpe.leg(mo.od)
        tail = Hdpe.leg(bo.od).to_f
        { big: big, small: small, lead: lead, tail: tail,
          len: Hdpe.stepped_length(big, small, lead: lead, tail: tail) }
      end

      def main_opts(t, ctx)
        Parts.opts(main_spec(t), lod: ctx[:lod], steps: ctx[:steps], joint: t['main_joint'])
      end

      def main_tee_c(t, ctx)
        mo = main_opts(t, ctx)
        Hdpe.style?(mo) ? Hdpe.tee_c(mo) : main_spec(t).tee_c
      end

      def branch_ref_tee(t, ctx)
        return nil unless ctx[:refs]

        main = main_spec(t)
        spec = ctx[:spec]
        return nil unless main.catalog_key == spec.catalog_key && main.size == spec.size

        ref_tee(main)
      end

      def main_spec(t)
        Catalog.spec(t['main_catalog'], t['main_size'], t['main_rating'])
      rescue ArgumentError
        Catalog.spec('CS_B36_10', '2"')
      end

      # Length of the reducer / adaptor joining the main run's pipe to ours.
      def join_length(main, spec, main_joint: nil, joint: nil)
        mo = Parts.opts(main, joint: main_joint)
        so = Parts.opts(spec, joint: joint)
        if Hdpe.style?(mo) || Hdpe.style?(so)
          big, small = [mo, so].sort_by { |x| -x.od }
          return Hdpe.reducer_length(big, small)
        end
        big, small = [main, spec].sort_by { |x| -x.od }
        style = big.style == small.style ? big.style : :butt_weld
        FittingsData.reducer_length(big.od, small.od, style)
      end

      # A run that continues another run at a different size/material starts
      # (or ends) with a reducer: pull that segment end back by its length.
      def apply_join_trims(segs, joins, spec, warnings, joint = nil)
        joins.each do |j|
          len = join_length(main_spec(j), spec, main_joint: j['main_joint'], joint: joint)
          segs.each_with_index do |(a, b), i|
            if Vec.dist(a, j['at']) <= 1.0
              next warnings << 'ท่อสั้นกว่า Reducer (pipe shorter than reducer)' if Vec.dist(a, b) <= len + 1.0

              segs[i][0] = Vec.add(a, Vec.scale(Vec.unit(Vec.sub(b, a)), len))
            elsif Vec.dist(b, j['at']) <= 1.0
              next warnings << 'ท่อสั้นกว่า Reducer (pipe shorter than reducer)' if Vec.dist(a, b) <= len + 1.0

              segs[i][1] = Vec.sub(b, Vec.scale(Vec.unit(Vec.sub(b, a)), len))
            end
          end
        end
        segs
      end

      # Reducer / expander / adaptor at a join: main size at 'at', our size
      # at 'at' + dir × length.
      def render_join(ctx, j, warnings)
        main = main_spec(j)
        spec = ctx[:spec]
        dir = Vec.unit(j['dir'])
        len = join_length(main, spec, main_joint: j['main_joint'], joint: ctx[:settings]['hdpe_joint'])
        mo = main_opts(j, ctx)
        kind = (main.od - spec.od).abs < 0.5 ? 'Adaptor' : (main.od > spec.od ? 'Concentric Reducer' : 'Concentric Expander')
        f = Mesh.frame(j['at'], dir)
        sgn = Hdpe.style?(mo) || Hdpe.style?(ctx[:opts]) ? up_sign(f) : 1
        name = "PP #{kind} #{len} | #{spec_key(main)} > #{spec_key(spec)} | #{lod_key(ctx)}" \
               "#{style_key(mo)}#{style_key(ctx[:opts])}#{sgn.negative? ? ' | dn' : ''}"
        inst = place_part(ctx, name, f) { Hdpe.flip(sgn) { Parts.reducer(len, mo, ctx[:opts]) } }
        main_code = j['main_service'] || ctx[:common]['service']
        big, small = [main, spec].sort_by { |x| -x.od }
        finish_piece(ctx, inst, "#{kind} #{main.size} x #{spec.size}", ctx[:mat],
                     'type' => 'reducer', 'kind' => kind, 'size' => "#{big.size} x #{small.size}",
                     'joint_desc' => joint_attrs(Hdpe.style?(ctx[:opts]) ? ctx[:opts] : mo)['joint_desc'],
                     'service' => ctx[:common]['service'], 'main_service' => main_code,
                     'geom' => JSON.generate('a' => j['at'], 'b' => Vec.add(j['at'], Vec.scale(dir, len)),
                                             'r' => Parts.body_radius(main.od >= spec.od ? mo : ctx[:opts])))
      rescue StandardError => e
        warnings << "Reducer: #{e.message}"
      end

      # ------------------------------------------------------------------

      # Any failure falls back to a recorded mitre joint instead of leaving
      # a hole in the model, and is reported.
      def render_piece(ctx, pc, extras, warnings)
        d = pc.data
        case pc.type
        when :pipe then render_pipe(ctx, d)
        when :curve then render_curve(ctx, d, warnings)
        when :elbow then render_elbow(ctx, d, extras)
        when :tee, :lateral, :cross, :manifold then render_tee(ctx, pc.type, d)
        when :mitre
          extras << ctx[:common].merge('type' => 'mitre', 'angle' => d[:angle])
        end
      rescue StandardError => e
        warnings << "#{pc.type}: #{e.message}"
      end

      # Place a reusable part as a component instance. If the component
      # cannot be created or ends up without faces, the same geometry is drawn
      # as a plain group instead – a fitting is never silently missing.
      def place_part(ctx, name, frame, recolor: {}, &build)
        defn = H.part_definition(ctx[:model], name, steps: ctx[:steps], recolor: recolor, &build)
        ctx[:ents].add_instance(defn, H.frame_transform(frame))
      rescue StandardError => e
        (ctx[:warnings] ||= []) << "#{name.split(' | ').first}: component failed (#{e.message}) – drawn as group"
        g = H.add_part_group(ctx[:model], ctx[:ents], build.call, steps: ctx[:steps], recolor: recolor)
        g.transformation = H.frame_transform(frame)
        raise "#{name.split(' | ').first}: no faces could be created" unless H.faces?(g.entities)

        g
      end

      def spec_key(spec)
        "#{spec.catalog_key} #{spec.size} #{spec.rating}"
      end

      def lod_key(ctx)
        "#{ctx[:lod] == :detailed ? 'D' : 'L'}#{ctx[:steps]}"
      end

      def render_pipe(ctx, d)
        spec = ctx[:spec]
        o = ctx[:opts]
        a = d[:from]
        b = d[:to]
        dir = Vec.unit(Vec.sub(b, a))
        ins = Parts.insertion(o)
        # Pipe continues into sockets / threads of the fittings at each end
        # (not at open ends or mitre joints) – that is the real cut length.
        ea = pipe_ext(ctx, a) || (joined?(ctx, a) ? ins : 0.0)
        eb = pipe_ext(ctx, b) || (joined?(ctx, b) ? ins : 0.0)
        pa = Vec.sub(a, Vec.scale(dir, ea))
        pb = Vec.add(b, Vec.scale(dir, eb))
        part = Mesh::Part.new.add(:pipe, Mesh.cylinder(pa, pb, o.ro, ri: o.ri, steps: ctx[:steps]))
        add_stripes(ctx, part, [pa, pb])
        g = H.add_part_group(ctx[:model], ctx[:ents], part, steps: ctx[:steps])
        cut = Vec.dist(pa, pb)
        finish_piece(ctx, g, "Pipe #{spec.size} L=#{cut.round}", ctx[:mat],
                     'type' => 'pipe', 'length_mm' => cut.round(1),
                     'weight_kg_m' => spec.weight_kg_m.round(3), 'stick_m' => spec.stick_length_m,
                     'geom' => JSON.generate('a' => a, 'b' => b, 'ea' => ea, 'eb' => eb),
                     'remark' => spec.estimated ? 'wall thickness estimated' : nil)
        [[a, pa], [b, pb]].each do |end_pt, at|
          add_end_center(ctx, g, at, dir, o.ro) if ctx[:open_ends].any? { |p| Vec.dist(p, end_pt) <= 1.0 }
        end
        add_stick_joints(ctx, [pa, pb])
        insulate(ctx, Mesh.cylinder(a, b, o.ro + ctx[:ins], ri: o.ro + 0.5, steps: ctx[:steps]), d[:length])
      end

      # Co-extruded colour stripes of PE pipe (ISO 4427 / TIS 982: blue for
      # water, brown for sewer) – four, as on the pipe. Drawn only with the
      # true-material colour scheme, where the pipe itself is black.
      STRIPE_SERVICES = {
        stripe_blue: %w[CW HW HWR CHWS CHWR CDW PW DI],
        stripe_brown: %w[SAN SD V IWW]
      }.freeze

      def stripe_role(ctx)
        s = ctx[:settings]
        return nil unless ctx[:spec].family == 'HDPE' && s['color_scheme'] == 'material' && s['pipe_color'].to_s.empty?

        code = ctx[:svc][:code]
        STRIPE_SERVICES.find { |_, codes| codes.include?(code) }&.first
      end

      def add_stripes(ctx, part, path)
        role = stripe_role(ctx) or return
        ro = ctx[:opts].ro
        w = [0.025 * 2 * ro, 2.0].max
        h = 0.6
        path.each_cons(2) do |p, q|
          dir = Vec.unit(Vec.sub(q, p))
          up = stem_direction(dir)
          side = Vec.cross(dir, up)
          4.times do |k|
            t = Math::PI / 4 + k * Math::PI / 2
            u = Vec.add(Vec.scale(up, Math.cos(t)), Vec.scale(side, Math.sin(t)))
            off = Vec.scale(u, ro + h / 2.0 - 0.1)
            part.add(role, Mesh.bar(Vec.add(p, off), Vec.add(q, off), w, h, u))
          end
        end
        part
      end

      # HDPE: a joint every stock length along the pipe (6 m sticks, 50 /
      # 100 m coils) – EF or compression coupler, or the bead of a butt
      # fusion weld. Couplers go in the BOM; the joint count already comes
      # from the pipe length.
      def add_stick_joints(ctx, path)
        o = ctx[:opts]
        spec = ctx[:spec]
        return unless Hdpe.style?(o) && spec.stick_length_m.to_f.positive?
        return if o.style == :fusion && !o.detailed? # a bead is detail only

        stick = spec.stick_length_m * 1000.0
        spans = path.each_cons(2).map { |p, q| [p, q, Vec.dist(p, q)] }.reject { |_, _, l| l < 1e-6 }
        total = spans.sum { |_, _, l| l }
        n = ((total - 300.0) / stick).floor
        return if n < 1

        desc = case o.style
               when :electrofusion then 'EF coupler'
               when :compression then 'Compression coupler (PP)'
               end
        (1..n).each do |k|
          at, dir = Supports.point_along(spans, k * stick)
          up = stem_direction(dir)
          name = "PP Coupler | #{spec_key(spec)} | #{lod_key(ctx)}#{style_key(o)}"
          inst = place_part(ctx, name, Mesh.frame(at, dir, Vec.cross(up, dir))) { Hdpe.coupler(o) }
          attrs = desc ? { 'type' => 'coupling', 'fitting_desc' => desc } : { 'type' => 'bead' }
          finish_piece(ctx, inst, desc ? "#{desc} #{spec.size}" : "Butt fusion joint #{spec.size}", ctx[:mat],
                       attrs.merge(joint_attrs(o)).merge('at' => JSON.generate(at)))
        end
      rescue StandardError => e
        (ctx[:warnings] ||= []) << "Coupler: #{e.message}"
      end

      # Pipe bent along a drawn curve: one continuous tube through the
      # curve's points (no fittings), cut length measured along it.
      def render_curve(ctx, d, warnings)
        spec = ctx[:spec]
        o = ctx[:opts]
        pts = d[:points]
        a = pts.first
        b = pts.last
        da = Vec.unit(Vec.sub(pts[1], a))
        db = Vec.unit(Vec.sub(b, pts[-2]))
        ins = Parts.insertion(o)
        ea = pipe_ext(ctx, a) || (joined?(ctx, a) ? ins : 0.0)
        eb = pipe_ext(ctx, b) || (joined?(ctx, b) ? ins : 0.0)
        path = pts.dup
        path[0] = Vec.sub(a, Vec.scale(da, ea))
        path[-1] = Vec.add(b, Vec.scale(db, eb))
        solid, end_ref = Mesh.sweep(path, o.ro, o.ri, steps: ctx[:steps])
        part = Mesh::Part.new.add(:pipe, solid)
        add_stripes(ctx, part, path)
        g = H.add_part_group(ctx[:model], ctx[:ents], part, steps: ctx[:steps])
        cut = d[:length] + ea + eb
        r = d[:radius].round
        finish_piece(ctx, g, "Pipe #{spec.size} L=#{cut.round} bent R=#{r}", ctx[:mat],
                     'type' => 'pipe', 'length_mm' => cut.round(1), 'bend_radius_mm' => r,
                     'bend_angle' => d[:angle_deg], 'weight_kg_m' => spec.weight_kg_m.round(3),
                     'stick_m' => spec.stick_length_m,
                     'geom' => JSON.generate('a' => a, 'b' => b, 'ea' => ea, 'eb' => eb, 'path' => pts),
                     'remark' => spec.estimated ? 'wall thickness estimated' : nil)
        add_end_center(ctx, g, path[0], da, o.ro) if ctx[:open_ends].any? { |p| Vec.dist(p, a) <= 1.0 }
        add_end_center(ctx, g, path[-1], db, o.ro, ref: end_ref) if ctx[:open_ends].any? { |p| Vec.dist(p, b) <= 1.0 }
        warnings.concat(bend_warnings(spec, d))
        add_stick_joints(ctx, path)
        insulate(ctx, Mesh.sweep(pts, o.ro + ctx[:ins], o.ro + 0.5, steps: ctx[:steps]).first, d[:length]) if ctx[:ins].positive?
        g
      end

      # Tightest radius each pipe material may be bent to (mm) and why, or
      # nil when there is no general rule (PP-R: see the maker's guide).
      def bend_limit(spec)
        od = spec.od
        if spec.flexible
          [spec.bend_radius, "ท่อ HDPE ม้วนดัดได้ไม่ต่ำกว่า #{(spec.bend_radius / od).round}×OD"]
        elsif spec.family == 'HDPE'
          [25.0 * od, 'ท่อ PE100 ดัดเย็นได้ไม่ต่ำกว่า 25×OD']
        elsif spec.family.start_with?('PVC')
          [300.0 * od, 'ท่อ PVC ดัดตามยาวได้ไม่ต่ำกว่า ~300×OD (AWWA C605)']
        elsif spec.density > 5000
          [3.0 * od, 'ท่อโลหะดัดด้วยเครื่องได้ไม่ต่ำกว่า 3D (โค้งดัด 3D/5D)']
        end
      end

      def bend_warnings(spec, d)
        out = []
        at = "@ (#{d[:points][d[:points].size / 2].map(&:round).join(', ')}) mm"
        lim, why = bend_limit(spec)
        if lim && d[:radius] < lim - 0.5
          out << "ท่อโค้งรัศมี #{d[:radius].round} mm แคบเกินไป – #{why} = #{lim.round} mm: " \
                 "ขยายรัศมีโค้ง หรือใช้ข้องอ (bend radius below the material's minimum) #{at}"
        end
        if spec.family.start_with?('PVC') && spec.od > 170.0
          out << "ท่อ PVC ใหญ่กว่า 6\" ไม่แนะนำให้ดัด (AWWA C605) – ใช้ข้องอ หรือมุมเบี่ยงที่ข้อต่อแหวนยาง #{at}"
        end
        out
      end

      # Real circle (ArcCurve) + construction point at an open pipe end, in
      # its own group so it never merges with the pipe mesh. SketchUp's own
      # tools (Move, Line, Tape, …) then infer "Center" / the point there.
      # The circle starts where the pipe mesh starts (same ref axis and
      # segment count), so its edges lie exactly on the pipe rim.
      def add_end_center(ctx, pipe, at, axis, ro, ref: nil)
        g = pipe.entities.add_group
        ax = Vec.unit(axis)
        c = H.to_pt(at)
        g.entities.add_arc(c, H.to_vec(ref || Vec.perpendicular(ax)), H.to_vec(ax), H.mm(ro), 0.0, 2 * Math::PI, ctx[:steps])
        g.entities.add_cpoint(c)
        g.name = 'Pipe End Center'
        H.set_attrs(g, 'type' => 'end_center')
        g
      rescue StandardError => e
        (ctx[:warnings] ||= []) << "Pipe end center: #{e.message}"
        nil
      end

      def joined?(ctx, pt)
        ctx[:open_ends].none? { |p| Vec.dist(p, pt) <= 1.0 } && ctx[:mitres].none? { |p| Vec.dist(p, pt) <= 1.0 }
      end

      # Coiled HDPE turns by bending the pipe itself (LR = the minimum bend
      # radius); the SR alternative is an electrofusion elbow.
      def network_spec(spec, o = nil)
        return spec unless spec.flexible || (o && Hdpe.style?(o))

        s = spec.dup
        s.elbow_radius_lr = spec.bend_radius if spec.flexible
        s.tee_c = Hdpe.tee_c(o) if o && Hdpe.style?(o)
        s
      end

      # Take-outs for the network: HDPE fittings of the run's joint system,
      # else the real fittings of the reference library (detailed LOD).
      def fitting_takes(ctx, spec)
        o = ctx[:opts]
        if Hdpe.style?(o)
          flexible = spec.flexible
          return {
            elbow: lambda do |deg, rtype|
              next nil if flexible && rtype == :lr # bent pipe, not a fitting

              Hdpe.elbow_take(o, deg, rtype == :sr ? spec.elbow_radius_sr : spec.elbow_radius_lr)
            end
          }
        end
        ctx[:refs] ? ref_takes(spec) : nil
      end

      # Tee centre-to-end for a run's spec / settings (pipe tool stubs).
      def tee_c_for(spec, settings)
        o = Parts.opts(spec, joint: settings['hdpe_joint'])
        Hdpe.style?(o) ? Hdpe.tee_c(o) : spec.tee_c
      end

      # Elbow tangent length at +deg+ for a run's spec / settings.
      def elbow_take_for(spec, settings, deg)
        o = Parts.opts(spec, joint: settings['hdpe_joint'])
        return Hdpe.elbow_take(o, deg, spec.elbow_radius_lr) if Hdpe.style?(o) && !spec.flexible

        r = spec.flexible ? spec.bend_radius : spec.elbow_radius_lr
        r * Math.tan(deg * Math::PI / 360.0)
      end

      # ' | EF' etc. – HDPE part names carry the joint system, so a run
      # switched to another system never reuses the old definitions.
      def style_key(o)
        Hdpe.style?(o) ? " | #{o.style}#{Hdpe.segmented?(o) ? '-seg' : ''}" : ''
      end

      # Terminals face up: built on −Z when the part frame's Z points down.
      def up_sign(frame)
        frame[:z][2] < -0.1 ? -1 : 1
      end

      def joint_attrs(o)
        return {} unless Hdpe.style?(o)

        { 'joint_desc' => Hdpe.segmented?(o) ? 'Butt fusion – fabricated (segmented)' : Hdpe.name(o.style, 1) }
      end

      def flexible_warnings(net, o)
        out = net.warnings.reject { |w| w.include?('Long Radius') }
        net.pieces.each do |pc|
          next unless pc.type == :elbow && pc.data[:radius_type] == :sr

          at = pc.data[:vertex].map(&:round).join(', ')
          kind = Hdpe.name(o.style).split(' ').first
          out << "ระยะท่อไม่พอดัดโค้งท่อ HDPE ม้วน – ใช้ข้องอ#{kind}แทน @ (#{at}) mm " \
                 "(no room for the minimum bend radius, #{Hdpe.name(o.style, 1).downcase} elbow used)"
        end
        out
      end

      def render_bend(ctx, d)
        spec = ctx[:spec]
        o = ctx[:opts]
        arc_steps = [(d[:angle] / (Math::PI / 2) * 12).ceil, 3].max
        solid = Mesh.bend(d[:center], d[:xaxis], d[:normal], d[:radius], d[:angle], o.ro, o.ri,
                          steps: ctx[:steps], arc_steps: arc_steps)
        g = H.add_part_group(ctx[:model], ctx[:ents], Mesh::Part.new.add(:pipe, solid), steps: ctx[:steps])
        len = d[:radius] * d[:angle]
        # continuous pipe: the straight lengths butt onto the bend
        mark_ext(ctx, d[:start], nil)
        mark_ext(ctx, d[:end], nil)
        finish_piece(ctx, g, "Pipe bend #{spec.size} R=#{d[:radius].round}", ctx[:mat],
                     'type' => 'pipe', 'length_mm' => len.round(1), 'bend_radius_mm' => d[:radius].round,
                     'bend_angle' => d[:angle_deg], 'weight_kg_m' => spec.weight_kg_m.round(3),
                     'stick_m' => spec.stick_length_m, 'geom' => JSON.generate('a' => d[:start], 'b' => d[:end]))
        return g unless ctx[:ins].positive?

        insulate(ctx, Mesh.bend(d[:center], d[:xaxis], d[:normal], d[:radius], d[:angle], o.ro + ctx[:ins], o.ro + 0.5,
                                steps: ctx[:steps], arc_steps: arc_steps), len)
        g
      end

      def render_elbow(ctx, d, extras)
        spec = ctx[:spec]
        return render_bend(ctx, d) if spec.flexible && d[:radius_type] == :lr

        o = ctx[:opts]
        ang = d[:angle]
        n1 = Vec.unit(Vec.sub(d[:center], d[:start]))
        f = Mesh.frame(d[:start], d[:dir_in], n1)
        sgn = Hdpe.style?(o) ? up_sign(f) : 1
        name = "PP Elbow #{d[:angle_deg].round(1)}° #{d[:radius_type].to_s.upcase} | #{spec_key(spec)} | #{lod_key(ctx)}" \
               "#{style_key(o)}#{sgn.negative? ? ' | dn' : ''}"
        item = ctx[:refs] && ref_elbow(spec, d[:angle_deg], d[:radius_type])
        inst = item && ref_or_nil(ctx, item) { render_ref_elbow(ctx, d, item) }
        item = nil unless inst
        inst ||= place_part(ctx, name, f) { Hdpe.flip(sgn) { Parts.elbow(ang, d[:radius], o) } }
        attrs = {
          'type' => 'elbow', 'angle' => d[:angle_deg], 'radius_type' => d[:radius_type].to_s,
          'radius_mm' => d[:radius].round(1),
          'geom' => JSON.generate('center' => d[:center], 'xaxis' => d[:xaxis], 'normal' => d[:normal],
                                  'radius' => d[:radius], 'angle' => d[:angle],
                                  'start' => d[:start], 'end' => d[:end], 'vertex' => d[:vertex])
        }
        attrs['nominal_angle'] = d[:nominal_angle] if d[:nominal_angle]
        attrs.merge!(joint_attrs(o))
        attrs['fitting_desc'] = hdpe_elbow_desc(o, d) if Hdpe.style?(o)
        attrs.merge!(ref_attrs(item)) if item
        finish_piece(ctx, inst, "Elbow #{d[:angle_deg].round}° #{spec.size}", ctx[:mat], attrs)
        return unless ctx[:ins].positive?

        arc_len = d[:radius] * ang
        r_ins = Parts.body_radius(o) + ctx[:ins]
        if r_ins < 0.95 * d[:radius]
          arc_steps = [(ang / (Math::PI / 2) * (ctx[:steps] / 2)).ceil, 2].max
          insulate(ctx, Mesh.bend(d[:center], d[:xaxis], d[:normal], d[:radius], ang, r_ins, Parts.body_radius(o) + 0.5,
                                  steps: ctx[:steps], arc_steps: arc_steps), arc_len)
        else
          # Insulation thicker than the bend radius cannot be modelled as a
          # solid; still count it in the BOM.
          extras << ctx[:common].merge('type' => 'insulation', 'thickness' => ctx[:ins],
                                       'length_mm' => arc_len.round(1))
        end
      end

      def hdpe_elbow_desc(o, d)
        ang = "#{Bom.fmt_angle(d[:nominal_angle] || d[:angle_deg])}°"
        case o.style
        when :electrofusion then "EF elbow #{ang}"
        when :compression then "Compression elbow #{ang} (PP)"
        else
          take = d[:radius] * Math.tan(d[:angle] / 2.0)
          r = ((take - [Hdpe.leg(o.od), take * 0.9].min) / Math.tan(d[:angle] / 2.0) / o.od).round(1)
          if Hdpe.segmented?(o)
            "Segmented bend #{ang} R=#{Bom.fmt_angle(r)}D, #{Hdpe.welds(d[:angle])} welds (fabricated)"
          else
            "Elbow #{ang} R=#{Bom.fmt_angle(r)}D, spigot (butt fusion)"
          end
        end
      end

      # Local frame for a junction: x = first arm, y = the most
      # perpendicular other arm, z = x × y.
      def junction_frame(center, arms)
        x = arms[0]
        other = arms[1..].max_by { |u| Vec.length(Vec.cross(x, u)) }
        Mesh.frame(center, x, other)
      end

      def local_dirs(f, arms)
        arms.map { |u| [Vec.dot(u, f[:x]), Vec.dot(u, f[:y]), Vec.dot(u, f[:z])].map { |c| c.round(6) } }
      end

      def render_tee(ctx, kind, d)
        spec = ctx[:spec]
        o = ctx[:opts]
        c = d[:c]
        f = junction_frame(d[:center], d[:arms])
        loc = local_dirs(f, d[:arms])
        sig = loc.map { |u| u.map { |v| v.round(3) }.join(',') }.join(' / ')
        sgn = Hdpe.style?(o) ? up_sign(f) : 1
        name = "PP #{kind.to_s.capitalize} #{sig} | #{spec_key(spec)} | #{lod_key(ctx)}#{style_key(o)}#{sgn.negative? ? ' | dn' : ''}"
        item = kind == :tee && ctx[:refs] && d[:run] && ref_tee(spec)
        inst = item && ref_or_nil(ctx, item) { render_ref_tee(ctx, d, item) }
        item = nil unless inst
        inst ||= place_part(ctx, name, f) { Hdpe.flip(sgn) { Parts.branch(loc.map { |u| [u, c, o] }) } }
        attrs = { 'type' => 'tee', 'kind' => kind.to_s, 'role' => 'run',
                  'geom' => JSON.generate('center' => d[:center], 'arms' => d[:arms], 'c' => c) }.merge(joint_attrs(o))
        attrs.merge!(ref_attrs(item)) if item
        attrs['branch_angle'] = d[:branch_angle] if d[:branch_angle]
        label = { cross: 'Cross', lateral: 'Lateral' }.fetch(kind, 'Tee')
        finish_piece(ctx, inst, "#{label} #{spec.size}", ctx[:mat], attrs)
        d[:arms].each do |u|
          insulate(ctx, Mesh.cylinder(d[:center], Vec.add(d[:center], Vec.scale(u, c)), Parts.body_radius(o) + ctx[:ins],
                                      ri: Parts.body_radius(o) + 0.5, steps: ctx[:steps]), c)
        end
      end

      # [centre, main direction, branch direction] of a branch tee.
      def branch_geometry(ctx, t)
        at = t['at']
        seg = ctx[:cl].find { |a, b| Vec.dist(a, at) <= 1.0 || Vec.dist(b, at) <= 1.0 }
        return nil unless seg

        other = Vec.dist(seg[0], at) <= 1.0 ? seg[1] : seg[0]
        [at, Vec.unit(t['main_dir']), Vec.unit(Vec.sub(other, at))]
      end

      # Socket depth at the branch outlet of a real tee (before the pipes).
      def premark_branch(ctx, t)
        item = branch_ref_tee(t, ctx) or return
        at, main_dir, bdir = branch_geometry(ctx, t)
        return unless at && (Vec.angle(main_dir, bdir) * 180.0 / Math::PI - 90.0).abs <= 1.0

        mark_ext(ctx, Vec.add(at, Vec.scale(bdir, Vec.length(item['ports'][2]['p']))), item['ports'][2])
      end

      # Tee placed on another run's pipe where this run branches off.
      def render_branch_tee(ctx, t, warnings)
        main = main_spec(t)
        spec = ctx[:spec]
        at, main_dir, bdir = branch_geometry(ctx, t)
        return warnings << 'Branch tee: centreline not found' unless at

        c = main_tee_c(t, ctx)
        mo = main_opts(t, ctx)
        br = branch_reducer(mo, ctx[:opts])
        bo = br ? mo : ctx[:opts] # equal tee when a reducer follows
        bsize = br ? main.size : spec.size
        arms = [main_dir, Vec.scale(main_dir, -1.0), bdir]
        f = junction_frame(at, arms)
        loc = local_dirs(f, arms)
        angle = Vec.angle(bdir, main_dir) * 180.0 / Math::PI
        angle = 180.0 - angle if angle > 90.0
        kind = (angle - 90.0).abs <= 1.0 ? 'tee' : 'lateral'
        sgn = Hdpe.style?(mo) ? up_sign(f) : 1
        name = "PP Branch #{kind} #{angle.round(1)} | #{spec_key(main)} x #{bsize} | #{lod_key(ctx)}" \
               "#{style_key(mo)}#{style_key(bo)}#{sgn.negative? ? ' | dn' : ''}"
        main_code = t['main_service'] || ctx[:common]['service']
        mat = H.pipe_material(ctx[:model], main_code, main.family, ctx[:settings]['color_scheme'], t['main_color'])
        item = kind == 'tee' && branch_ref_tee(t, ctx)
        inst = item && ref_or_nil(ctx, item) { place_ref(ctx, item, Mesh.frame(at, main_dir, bdir), mat, plain: true) }
        item = nil unless inst
        inst ||= place_part(ctx, name, f) do
          Hdpe.flip(sgn) { Parts.branch([[loc[0], c, mo], [loc[1], c, mo], [loc[2], c, bo]]) }
        end
        render_branch_reducer(ctx, br, Vec.add(at, Vec.scale(bdir, c)), bdir, main, mat, main_code) if br
        finish_piece(ctx, inst, "Branch #{kind} #{main.size} x #{bsize}", mat,
                     'type' => 'tee', 'kind' => kind, 'role' => 'branch', 'branch_angle' => angle.round(1),
                     'size' => main.size, 'branch_size' => bsize, 'rating' => main.rating,
                     'service' => main_code, 'catalog_name' => main.catalog_name, 'material' => main.material,
                     'od' => main.od,
                     'geom' => JSON.generate('center' => at, 'arms' => arms, 'c' => c)).tap do |e|
          H.set_attrs(e, joint_attrs(mo))
          H.set_attrs(e, ref_attrs(item)) if item
        end
      rescue StandardError => e
        warnings << "Branch tee: #{e.message}"
      end

      # Stepped reducer on the tee's branch outlet (+start+, along +dir+) and
      # the joint onto the branch pipe: a bead (butt fusion) or the branch
      # system's coupler.
      def render_branch_reducer(ctx, br, start, dir, main, mat, main_code)
        spec = ctx[:spec]
        bo = ctx[:opts]
        up = stem_direction(dir)
        f = Mesh.frame(start, dir, Vec.cross(up, dir))
        len = br[:len]
        name = "PP Branch reducer #{len} | #{spec_key(main)} > #{spec_key(spec)} | #{lod_key(ctx)}#{style_key(bo)}"
        inst = place_part(ctx, name, f) do
          part = Hdpe.stepped_reducer(br[:big], br[:small], lead: br[:lead], tail: br[:tail], ends: false)
          bo.style == :fusion ? Hdpe.bead(part, [len, 0.0, 0.0], [1.0, 0.0, 0.0], br[:small]) : part
        end
        finish_piece(ctx, inst, "Reducer #{main.size} x #{spec.size}", mat,
                     'type' => 'reducer', 'kind' => 'Concentric Reducer', 'size' => "#{main.size} x #{spec.size}",
                     'service' => main_code, 'catalog_name' => main.catalog_name, 'material' => main.material,
                     'od' => main.od, 'joint_desc' => 'Butt fusion spigot, stepped',
                     'geom' => JSON.generate('a' => start, 'b' => Vec.add(start, Vec.scale(dir, len)), 'r' => main.od / 2.0))
        return if bo.style == :fusion

        at = Vec.add(start, Vec.scale(dir, len))
        desc = bo.style == :electrofusion ? 'EF coupler' : 'Compression coupler (PP)'
        cn = "PP Coupler | #{spec_key(spec)} | #{lod_key(ctx)}#{style_key(bo)}"
        ci = place_part(ctx, cn, Mesh.frame(at, dir, Vec.cross(up, dir))) { Hdpe.coupler(bo) }
        finish_piece(ctx, ci, "#{desc} #{spec.size}", ctx[:mat],
                     { 'type' => 'coupling', 'fitting_desc' => desc, 'at' => JSON.generate(at) }.merge(joint_attrs(bo)))
      end

      # ------------------------------------------------------------------
      # Valves
      # ------------------------------------------------------------------

      # Stem up on horizontal lines (never down: packing leaks onto the
      # operator and dirt collects in the bonnet); horizontal on risers.
      def stem_direction(dir)
        z = [0.0, 0.0, 1.0]
        u = Vec.sub(z, Vec.scale(dir, Vec.dot(dir, z)))
        Vec.length(u) < 0.2 ? Vec.perpendicular(dir) : Vec.unit(u)
      end

      # model: a reference-library key chosen by the user (kept on rebuild).
      def place_valve(ctx, type, at, dir, model: nil)
        spec = ctx[:spec]
        chosen = model && Refs.get(model)
        if chosen && Refs.sized_type?(chosen)
          # meters / taps come in standard sizes; a pipe outside their range
          # keeps the part (scaled, as drawn before) and gets a warning
          sized = Refs.sized_item(chosen, spec)
          (ctx[:warnings] ||= []) << "#{Refs.display_name(chosen).split(' – ').first}: ไม่มีขนาดมาตรฐานสำหรับท่อ #{spec.size}" unless sized
          chosen = sized || chosen
        end
        dir = Vec.unit(dir)
        up = stem_direction(dir)
        if chosen # picked by the user from the reference library
          inst = ref_or_nil(ctx, chosen) { place_ref_valve(ctx, type, chosen, at, dir, up) }
          return inst if inst
        end
        info = FittingsData.valve(type)
        metallic = spec.density > 5000
        f = Mesh.frame(at, dir, Vec.cross(up, dir))
        o = ctx[:opts]
        stubs = Hdpe.style?(o) && o.style != :compression
        fam = stubs ? :flanged : ValveModels.family(o, metallic)
        len = stubs ? Parts.valve_length(type, o) : FittingsData.face_to_face(type, spec.od, fam)
        entry = Library.find(type, spec.size)
        if entry
          # A real model registered by the user: exact size at 1:1,
          # otherwise scaled to the standard face-to-face for this size.
          defn = Library.load_definition(ctx[:model], entry)
          inst = ctx[:ents].add_instance(defn, Library.transform(entry, at, dir, up, entry['size'] ? nil : len))
          finish_piece(ctx, inst, "#{info[:name]} #{spec.size}", nil,
                       valve_attrs(type, info, fam, spec, len, at, dir).merge('model' => entry['file']))
          return inst
        end
        item = ref_valve(ctx, type)
        if item
          inst = ref_or_nil(ctx, item) { place_ref_valve(ctx, type, item, at, dir, up) }
          return inst if inst
        end

        name = "PP Valve #{type} #{fam} v2 | #{spec_key(spec)} | #{lod_key(ctx)}#{style_key(o)}"
        inst = place_part(ctx, name, f) { Parts.valve(type, o, metallic: metallic) }
        attrs = valve_attrs(type, info, fam, spec, len, at, dir)
        attrs.merge!(hdpe_valve_attrs(type, o)) if Hdpe.style?(o)
        finish_piece(ctx, inst, "#{info[:name]} #{spec.size}", ctx[:mat], attrs)
      end

      # HDPE: fusion lines bolt flanged valves on with PE stub ends + steel
      # backing rings (counted in the BOM); compression lines use PP valves.
      def hdpe_valve_attrs(type, o)
        if o.style == :compression
          return { 'end_type' => 'Compression (PP)', 'valve_rating' => 'PN16' }
        end

        dn = Hdpe.dn(o.od)
        out = { 'end_type' => "Flanged DN#{dn} – PE stub ends + backing rings", 'valve_rating' => 'Class 150',
                'stub_ends' => 2, 'stub_dn' => dn, 'joint_desc' => Hdpe.name(o.style, 1) }
        if type == 'flange'
          out['valve_name'] = "Gasket + bolt set DN#{dn} (flanged joint, PE stub ends)"
        end
        out
      end

      VALVE_ENDS = {
        flanged: ['Flanged RF', 'Class 150'], socket_weld: ['Socket weld', 'Class 800'],
        threaded: ['Threaded BSPT', 'PN16 / 200 WOG'], plastic: ['True union (socket)', nil]
      }.freeze

      def valve_attrs(type, info, fam, spec, len, at, dir)
        fr = FittingsData.flange(spec.od).od / 2.0
        end_type, rating = VALVE_ENDS[fam]
        { 'type' => 'valve', 'valve_type' => type, 'valve_name' => info[:name],
          'valve_rating' => rating || spec.rating, 'valve_family' => fam.to_s,
          'end_type' => end_type,
          'face_to_face' => len, 'at' => JSON.generate(at), 'dir' => JSON.generate(dir),
          'geom' => JSON.generate('a' => Vec.sub(at, Vec.scale(dir, len / 2.0)),
                                  'b' => Vec.add(at, Vec.scale(dir, len / 2.0)), 'r' => fr) }
      end

      # Insert a valve into a run (run-local coordinates).
      def add_valve(model, run, type, at, dir, model_key: nil)
        settings = run_settings(run)
        spec = Settings.spec(settings)
        svc = Services.get(settings['service'])
        model.start_operation('Plant Piping: Insert Valve', true)
        ctx = context(model, run, settings, spec, svc, run.name)
        inst = place_valve(ctx, type, at, dir, model: model_key)
        model.commit_operation
        inst
      rescue StandardError
        model.abort_operation
        raise
      end

      # ---- library fittings fixed to an open pipe end ----
      #
      # An elbow, cap, flange, faucet … put on an open end from the
      # reference library belongs to the run: its record ('end_part' on the
      # instance: library key, end point, roll angle) is read back on every
      # rebuild, so the part follows the end when the pipe is stretched and
      # changes size with the run. Deleting the instance removes it.

      def end_part_records(ents)
        ents.select { |e| H.instance?(e) && e.get_attribute(H::DICT, 'end_part') }.map do |e|
          JSON.parse(e.get_attribute(H::DICT, 'end_part'))
        rescue JSON::ParserError
          nil
        end.compact
      end

      # Direction out of the open end +at+ of centreline +cl+, or nil.
      def open_end_dir(cl, at)
        seg = cl.find { |a, b| Vec.dist(a, at) <= 1.0 || Vec.dist(b, at) <= 1.0 } or return nil
        other = Vec.dist(seg[0], at) <= 1.0 ? seg[1] : seg[0]
        Vec.unit(Vec.sub(at, other))
      end

      # The library part for this run's size: the same part in that size,
      # else the chosen one scaled. Returns [item, k].
      # Parts made in standard sizes (taps, meters) take that size; with no
      # standard size for the pipe the part stays, scaled, with a warning.
      def fit_ref(base, spec)
        if Refs.sized_type?(base)
          it = Refs.sized_item(base, spec)
          return it ? [it, 1.0] : [base, Refs.scale_for(base, spec.od)]
        end
        it = base['scalable'] ? nil : Refs.variant_for(base, spec)
        it ? [it, 1.0] : [base, Refs.scale_for(base, spec.od)]
      end

      # Canonical +Y of an end part: world up turned by +angle+ about u.
      def end_roll(u, angle)
        base = [0.0, 0.0, 1.0]
        y = Vec.sub(base, Vec.scale(u, Vec.dot(base, u)))
        y = Vec.perpendicular(u) if Vec.length(y) < 1e-3
        Vec.rotate(Vec.unit(y), Vec.unit(u), angle.to_f)
      end

      def place_end_part(ctx, rec, warnings)
        base = Refs.get(rec['key'])
        return warnings << "ไม่พบอุปกรณ์ในคลัง #{rec['key']} (library part missing)" unless base

        at = rec['at']
        unless ctx[:open_ends].any? { |p| Vec.dist(p, at) <= 1.0 }
          return warnings << "#{Refs.display_name(base).split(' – ').first}: ปลายท่อไม่ได้เปิดแล้ว " \
                             'จึงถอดออก (pipe end no longer open – fitting removed)'
        end

        u = open_end_dir(ctx[:cl], at)
        it, k = fit_ref(base, ctx[:spec])
        if Refs.sized_type?(base) && !it['sized_from']
          warnings << "#{Refs::TYPE_NAMES[base['type']][0]}: ไม่มีขนาดมาตรฐานสำหรับท่อ #{ctx[:spec].size} " \
                      "(มี #{Refs::SIZED_TEXT[base['type']]})"
        end
        m = Refs.mouth_point(it, 0, at, u, k)
        frame = Refs.port_frame(it, 0, m, u, end_roll(u, rec['angle']), k)
        tr = H.frame_transform(frame)
        tr *= Geom::Transformation.scaling(k) if k != 1.0
        inst = ctx[:ents].add_instance(RefModels.definition(ctx[:model], it), tr)
        inst.material = RefModels.role_material(ctx[:model], it['material'])
        inst.name = Refs.display_name(it)
        inst.layer = ctx[:tag]
        H.set_attrs(inst, RefBrowser.component_attrs(it, k).merge(
          'line_no' => ctx[:line_no], 'service' => ctx[:common]['service'],
          'end_part' => JSON.generate('key' => rec['key'], 'at' => at, 'angle' => rec['angle'].to_f)
        ))
        inst
      rescue StandardError => e
        warnings << "End fitting #{rec['key']}: #{e.message}"
        nil
      end

      # Put a library part on an open end of +run+ (run-local end point).
      def add_end_part(model, run, key, at, angle)
        model.start_operation('Plant Piping: Fit Part to Pipe End', true)
        settings = run_settings(run)
        spec = Settings.spec(settings)
        svc = Services.get(settings['service'])
        ctx = context(model, run, settings, spec, svc, run.name)
        cl = H.get_json(run, 'cl', [])
        links = H.get_json(run, 'tees', []) + H.get_json(run, 'joins', [])
        ctx[:cl] = cl
        ctx[:open_ends] = Collector.open_ends(cl).reject { |p| links.any? { |t| Vec.dist(p, t['at']) <= 1.0 } }
        # one part per end: a new one replaces the old
        run.entities.to_a.each do |e|
          next unless H.instance?(e) && (s = e.get_attribute(H::DICT, 'end_part'))

          e.erase! if Vec.dist(JSON.parse(s)['at'], at) <= 1.0
        end
        warnings = []
        inst = place_end_part(ctx, { 'key' => key, 'at' => at, 'angle' => angle }, warnings)
        raise warnings.first || 'could not place part' unless inst

        model.commit_operation
        inst
      rescue StandardError
        model.abort_operation
        raise
      end

      # ------------------------------------------------------------------

      def finish_piece(ctx, ent, name, mat, attrs)
        ent.name = name
        ent.material = mat if mat
        ent.layer = ctx[:tag]
        H.set_attrs(ent, ctx[:common].merge(attrs).reject { |_, v| v.nil? })
        ent
      end

      def insulate(ctx, solid, length_mm)
        return unless ctx[:ins].positive?

        g = H.add_part_group(ctx[:model], ctx[:ents], Mesh::Part.new.add(:insulation, solid), steps: ctx[:steps])
        g.name = "Insulation #{ctx[:ins].round} mm"
        g.material = H.insulation_material(ctx[:model])
        g.layer = H.tag(ctx[:model], H::TAG_INSULATION)
        H.set_attrs(g, ctx[:common].merge('type' => 'insulation', 'thickness' => ctx[:ins],
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
        longest = net.pieces.select { |p| %i[pipe curve].include?(p.type) }.max_by { |p| p.data[:length] }
        return unless longest

        d = longest.data
        mid = d[:points] ? d[:points][d[:points].size / 2] : Vec.lerp(d[:from], d[:to], 0.5)
        lift = ctx[:spec].od / 2.0 + ctx[:ins] + 300.0
        txt = ctx[:ents].add_text("#{ctx[:line_no]}  #{ctx[:spec].material}", H.to_pt(mid),
                                  Geom::Vector3d.new(0, 0, H.mm(lift)))
        txt.layer = H.tag(ctx[:model], H::TAG_LABELS)
      end
    end
  end
end
