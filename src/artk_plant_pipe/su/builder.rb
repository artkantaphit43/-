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
      def create_run(model, segs, settings, tees: [], joins: [], op: true)
        settings = Settings.sanitize(settings)
        model.start_operation('Plant Piping: Draw Run', true) if op
        run = model.active_entities.add_group
        H.set_attrs(run, 'type' => 'run')
        H.set_json(run, 'cl', segs)
        H.set_json(run, 'tees', tees)
        H.set_json(run, 'joins', joins)
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
          %w[service catalog size rating insulation_mm elbow_type segments centerline labels lod].include?(k)
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
        settings = Settings.sanitize(settings)
        spec = Settings.spec(settings)
        svc = Services.get(settings['service'])
        code = svc[:code]

        seq = run.get_attribute(H::DICT, 'seq')
        seq = H.next_seq(model, code) if seq.nil? || run.get_attribute(H::DICT, 'service') != code
        line_no = H.line_number(spec.size, code, seq)

        cl = H.get_json(run, 'cl', [])
        tees = H.get_json(run, 'tees', [])
        joins = H.get_json(run, 'joins', [])
        warnings = []

        ents = run.entities
        valves = ents.select { |e| H.instance?(e) && H.type_of(e) == 'valve' }.map { |v| H.attrs(v) }
        ents.clear!
        segs = apply_branch_trims(cl, tees, warnings)
        segs = apply_join_trims(segs, joins, spec, warnings)

        ctx = context(model, run, settings, spec, svc, line_no)
        ctx[:cl] = cl
        ctx[:warnings] = warnings
        links = tees + joins
        ctx[:open_ends] = Collector.open_ends(cl).reject { |p| links.any? { |t| Vec.dist(p, t['at']) <= 1.0 } }

        extras = []
        unless segs.empty?
          net = Network.new(segs, spec, tol: 1.0, radius_type: settings['elbow_type'].to_sym).solve
          warnings.concat(net.warnings)
          ctx[:mitres] = net.pieces.select { |pc| pc.type == :mitre }.map { |pc| pc.data[:at] }
          net.pieces.each { |pc| render_piece(ctx, pc, extras, warnings) }
          add_label(ctx, net) if settings['labels']
        end
        tees.each { |t| render_branch_tee(ctx, t, warnings) }
        joins.each { |j| render_join(ctx, j, warnings) }
        valves.each do |v|
          place_valve(ctx, v['valve_type'], JSON.parse(v['at']), JSON.parse(v['dir']))
        rescue StandardError => e
          warnings << "Valve could not be rebuilt: #{e.message}"
        end
        H.get_json(run, 'supports', []).each do |rec|
          SupportBuilder.render(ctx, rec)
        rescue StandardError => e
          warnings << "Support: #{e.message}"
        end
        add_centerline(ctx, cl) if settings['centerline']

        extras.each { |x| x['remark'] ||= 'wall thickness estimated' } if spec.estimated
        H.set_attrs(run, ctx[:common].merge('type' => 'run', 'seq' => seq, 'joint' => spec.joint))
        H.set_json(run, 'settings', settings)
        H.set_json(run, 'extras', extras)
        H.set_json(run, 'warnings', warnings.uniq.first(50))
        run.name = line_no
        run.layer = ctx[:tag]
        run.material = ctx[:mat]
        warnings
      end

      def context(model, run, settings, spec, svc, line_no)
        steps = settings['segments']
        {
          model: model, run: run, ents: run.entities, spec: spec, settings: settings, svc: svc,
          line_no: line_no, steps: steps, ins: settings['insulation_mm'].to_f,
          lod: settings['lod'].to_sym, opts: Parts.opts(spec, lod: settings['lod'], steps: steps),
          tag: H.service_tag(model, svc[:code]),
          mat: H.pipe_material(model, svc[:code], spec.family, settings['color_scheme']),
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

      # Length of the reducer / adaptor joining the main run's pipe to ours.
      def join_length(main, spec)
        big, small = [main, spec].sort_by { |x| -x.od }
        style = big.style == small.style ? big.style : :butt_weld
        FittingsData.reducer_length(big.od, small.od, style)
      end

      # A run that continues another run at a different size/material starts
      # (or ends) with a reducer: pull that segment end back by its length.
      def apply_join_trims(segs, joins, spec, warnings)
        joins.each do |j|
          len = join_length(main_spec(j), spec)
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
        len = join_length(main, spec)
        mo = Parts.opts(main, lod: ctx[:lod], steps: ctx[:steps])
        kind = (main.od - spec.od).abs < 0.5 ? 'Adaptor' : (main.od > spec.od ? 'Concentric Reducer' : 'Concentric Expander')
        name = "PP #{kind} #{len} | #{spec_key(main)} > #{spec_key(spec)} | #{lod_key(ctx)}"
        inst = place_part(ctx, name, Mesh.frame(j['at'], dir)) { Parts.reducer(len, mo, ctx[:opts]) }
        main_code = j['main_service'] || ctx[:common]['service']
        big, small = [main, spec].sort_by { |x| -x.od }
        finish_piece(ctx, inst, "#{kind} #{main.size} x #{spec.size}", ctx[:mat],
                     'type' => 'reducer', 'kind' => kind, 'size' => "#{big.size} x #{small.size}",
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
        ea = joined?(ctx, a) ? ins : 0.0
        eb = joined?(ctx, b) ? ins : 0.0
        pa = Vec.sub(a, Vec.scale(dir, ea))
        pb = Vec.add(b, Vec.scale(dir, eb))
        part = Mesh::Part.new.add(:pipe, Mesh.cylinder(pa, pb, o.ro, ri: o.ri, steps: ctx[:steps]))
        g = H.add_part_group(ctx[:model], ctx[:ents], part, steps: ctx[:steps])
        cut = Vec.dist(pa, pb)
        finish_piece(ctx, g, "Pipe #{spec.size} L=#{cut.round}", ctx[:mat],
                     'type' => 'pipe', 'length_mm' => cut.round(1),
                     'weight_kg_m' => spec.weight_kg_m.round(3), 'stick_m' => spec.stick_length_m,
                     'geom' => JSON.generate('a' => a, 'b' => b),
                     'remark' => spec.estimated ? 'wall thickness estimated' : nil)
        insulate(ctx, Mesh.cylinder(a, b, o.ro + ctx[:ins], ri: o.ro + 0.5, steps: ctx[:steps]), d[:length])
      end

      def joined?(ctx, pt)
        ctx[:open_ends].none? { |p| Vec.dist(p, pt) <= 1.0 } && ctx[:mitres].none? { |p| Vec.dist(p, pt) <= 1.0 }
      end

      def render_elbow(ctx, d, extras)
        spec = ctx[:spec]
        o = ctx[:opts]
        ang = d[:angle]
        name = "PP Elbow #{d[:angle_deg].round(1)}° #{d[:radius_type].to_s.upcase} | #{spec_key(spec)} | #{lod_key(ctx)}"
        n1 = Vec.unit(Vec.sub(d[:center], d[:start]))
        inst = place_part(ctx, name, Mesh.frame(d[:start], d[:dir_in], n1)) { Parts.elbow(ang, d[:radius], o) }
        attrs = {
          'type' => 'elbow', 'angle' => d[:angle_deg], 'radius_type' => d[:radius_type].to_s,
          'radius_mm' => d[:radius].round(1),
          'geom' => JSON.generate('center' => d[:center], 'xaxis' => d[:xaxis], 'normal' => d[:normal],
                                  'radius' => d[:radius], 'angle' => d[:angle],
                                  'start' => d[:start], 'end' => d[:end])
        }
        attrs['nominal_angle'] = d[:nominal_angle] if d[:nominal_angle]
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
        name = "PP #{kind.to_s.capitalize} #{sig} | #{spec_key(spec)} | #{lod_key(ctx)}"
        inst = place_part(ctx, name, f) { Parts.branch(loc.map { |u| [u, c, o] }) }
        attrs = { 'type' => 'tee', 'kind' => kind.to_s, 'role' => 'run',
                  'geom' => JSON.generate('center' => d[:center], 'arms' => d[:arms], 'c' => c) }
        attrs['branch_angle'] = d[:branch_angle] if d[:branch_angle]
        label = { cross: 'Cross', lateral: 'Lateral' }.fetch(kind, 'Tee')
        finish_piece(ctx, inst, "#{label} #{spec.size}", ctx[:mat], attrs)
        d[:arms].each do |u|
          insulate(ctx, Mesh.cylinder(d[:center], Vec.add(d[:center], Vec.scale(u, c)), Parts.body_radius(o) + ctx[:ins],
                                      ri: Parts.body_radius(o) + 0.5, steps: ctx[:steps]), c)
        end
      end

      # Tee placed on another run's pipe where this run branches off.
      def render_branch_tee(ctx, t, warnings)
        main = main_spec(t)
        spec = ctx[:spec]
        at = t['at']
        main_dir = Vec.unit(t['main_dir'])
        seg = ctx[:cl].find { |a, b| Vec.dist(a, at) <= 1.0 || Vec.dist(b, at) <= 1.0 }
        return warnings << 'Branch tee: centreline not found' unless seg

        other = Vec.dist(seg[0], at) <= 1.0 ? seg[1] : seg[0]
        bdir = Vec.unit(Vec.sub(other, at))
        c = main.tee_c
        mo = Parts.opts(main, lod: ctx[:lod], steps: ctx[:steps])
        arms = [main_dir, Vec.scale(main_dir, -1.0), bdir]
        f = junction_frame(at, arms)
        loc = local_dirs(f, arms)
        angle = Vec.angle(bdir, main_dir) * 180.0 / Math::PI
        angle = 180.0 - angle if angle > 90.0
        kind = (angle - 90.0).abs <= 1.0 ? 'tee' : 'lateral'
        name = "PP Branch #{kind} #{angle.round(1)} | #{spec_key(main)} x #{spec.size} | #{lod_key(ctx)}"
        inst = place_part(ctx, name, f) { Parts.branch([[loc[0], c, mo], [loc[1], c, mo], [loc[2], c, ctx[:opts]]]) }
        main_code = t['main_service'] || ctx[:common]['service']
        mat = H.pipe_material(ctx[:model], main_code, main.family, ctx[:settings]['color_scheme'])
        finish_piece(ctx, inst, "Branch #{kind} #{main.size} x #{spec.size}", mat,
                     'type' => 'tee', 'kind' => kind, 'role' => 'branch', 'branch_angle' => angle.round(1),
                     'size' => main.size, 'branch_size' => spec.size, 'rating' => main.rating,
                     'service' => main_code, 'catalog_name' => main.catalog_name, 'material' => main.material,
                     'od' => main.od,
                     'geom' => JSON.generate('center' => at, 'arms' => arms, 'c' => c))
      rescue StandardError => e
        warnings << "Branch tee: #{e.message}"
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

      def place_valve(ctx, type, at, dir)
        spec = ctx[:spec]
        info = FittingsData.valve(type)
        metallic = spec.density > 5000
        dir = Vec.unit(dir)
        up = stem_direction(dir)
        f = Mesh.frame(at, dir, Vec.cross(up, dir))
        name = "PP Valve #{type} | #{spec_key(spec)} | #{lod_key(ctx)}"
        recolor = metallic ? {} : { valve: :fitting }
        inst = place_part(ctx, name, f, recolor: recolor) { Parts.valve(type, ctx[:opts], metallic: metallic) }
        len = FittingsData.face_to_face(type, spec.od)
        fr = FittingsData.flange(spec.od).od / 2.0
        finish_piece(ctx, inst, "#{info[:name]} #{spec.size}", ctx[:mat],
                     'type' => 'valve', 'valve_type' => type, 'valve_name' => info[:name],
                     'valve_rating' => metallic ? 'Class 150' : spec.rating,
                     'end_type' => metallic ? 'Flanged' : 'Socket / union',
                     'face_to_face' => len, 'at' => JSON.generate(at), 'dir' => JSON.generate(dir),
                     'geom' => JSON.generate('a' => Vec.sub(at, Vec.scale(dir, len / 2.0)),
                                             'b' => Vec.add(at, Vec.scale(dir, len / 2.0)), 'r' => fr))
      end

      # Insert a valve into a run (run-local coordinates).
      def add_valve(model, run, type, at, dir)
        settings = run_settings(run)
        spec = Settings.spec(settings)
        svc = Services.get(settings['service'])
        model.start_operation('Plant Piping: Insert Valve', true)
        ctx = context(model, run, settings, spec, svc, run.name)
        inst = place_valve(ctx, type, at, dir)
        model.commit_operation
        inst
      rescue StandardError
        model.abort_operation
        raise
      end

      # ------------------------------------------------------------------

      def finish_piece(ctx, ent, name, mat, attrs)
        ent.name = name
        ent.material = mat
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
        longest = net.pipes.max_by { |p| p.data[:length] }
        return unless longest

        mid = Vec.lerp(longest.data[:from], longest.data[:to], 0.5)
        lift = ctx[:spec].od / 2.0 + ctx[:ins] + 300.0
        txt = ctx[:ents].add_text("#{ctx[:line_no]}  #{ctx[:spec].material}", H.to_pt(mid),
                                  Geom::Vector3d.new(0, 0, H.mm(lift)))
        txt.layer = H.tag(ctx[:model], H::TAG_LABELS)
      end
    end
  end
end
