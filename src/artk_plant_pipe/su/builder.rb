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
              t['main_color'] = run_settings(main)['pipe_color']
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
          %w[service catalog size rating insulation_mm elbow_type segments centerline labels lod pipe_color].include?(k)
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

        cl = H.get_json(run, 'cl', [])
        tees = H.get_json(run, 'tees', [])
        joins = H.get_json(run, 'joins', [])
        warnings = []

        ents = run.entities
        valves = ents.select { |e| H.instance?(e) && H.type_of(e) == 'valve' }.map { |v| H.attrs(v) }
        end_parts = end_part_records(ents)
        ents.clear!
        ctx = context(model, run, settings, spec, svc, line_no)
        segs = apply_branch_trims(cl, tees, warnings, ctx)
        segs = apply_join_trims(segs, joins, spec, warnings)

        ctx[:cl] = cl
        ctx[:warnings] = warnings
        links = tees + joins
        ctx[:open_ends] = Collector.open_ends(cl).reject { |p| links.any? { |t| Vec.dist(p, t['at']) <= 1.0 } }

        extras = []
        tees.each { |t| premark_branch(ctx, t) }
        unless segs.empty?
          net = Network.new(segs, network_spec(spec), tol: 1.0,
                                        radius_type: spec.flexible ? :lr : settings['elbow_type'].to_sym,
                                        takes: ctx[:refs] ? ref_takes(spec) : nil).solve
          warnings.concat(spec.flexible ? flexible_warnings(net) : net.warnings)
          ctx[:mitres] = net.pieces.select { |pc| pc.type == :mitre }.map { |pc| pc.data[:at] }
          # fittings first: real fittings record their socket depths, which
          # the pipes then run into
          net.pieces.sort_by { |pc| pc.type == :pipe ? 1 : 0 }.each { |pc| render_piece(ctx, pc, extras, warnings) }
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
        item ? Vec.length(item['ports'][2]['p']) : main_spec(t).tee_c
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
        ea = pipe_ext(ctx, a) || (joined?(ctx, a) ? ins : 0.0)
        eb = pipe_ext(ctx, b) || (joined?(ctx, b) ? ins : 0.0)
        pa = Vec.sub(a, Vec.scale(dir, ea))
        pb = Vec.add(b, Vec.scale(dir, eb))
        part = Mesh::Part.new.add(:pipe, Mesh.cylinder(pa, pb, o.ro, ri: o.ri, steps: ctx[:steps]))
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
        insulate(ctx, Mesh.cylinder(a, b, o.ro + ctx[:ins], ri: o.ro + 0.5, steps: ctx[:steps]), d[:length])
      end

      # Real circle (ArcCurve) + construction point at an open pipe end, in
      # its own group so it never merges with the pipe mesh. SketchUp's own
      # tools (Move, Line, Tape, …) then infer "Center" / the point there.
      # The circle starts where the pipe mesh starts (same ref axis and
      # segment count), so its edges lie exactly on the pipe rim.
      def add_end_center(ctx, pipe, at, axis, ro)
        g = pipe.entities.add_group
        ax = Vec.unit(axis)
        c = H.to_pt(at)
        g.entities.add_arc(c, H.to_vec(Vec.perpendicular(ax)), H.to_vec(ax), H.mm(ro), 0.0, 2 * Math::PI, ctx[:steps])
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
      def network_spec(spec)
        return spec unless spec.flexible

        s = spec.dup
        s.elbow_radius_lr = spec.bend_radius
        s
      end

      def flexible_warnings(net)
        out = net.warnings.reject { |w| w.include?('Long Radius') }
        net.pieces.each do |pc|
          next unless pc.type == :elbow && pc.data[:radius_type] == :sr

          at = pc.data[:vertex].map(&:round).join(', ')
          out << "ระยะท่อไม่พอดัดโค้งท่อ HDPE ม้วน – ใช้ข้องอหลอมไฟฟ้าแทน @ (#{at}) mm " \
                 '(no room for the minimum bend radius, electrofusion elbow used)'
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
        name = "PP Elbow #{d[:angle_deg].round(1)}° #{d[:radius_type].to_s.upcase} | #{spec_key(spec)} | #{lod_key(ctx)}"
        n1 = Vec.unit(Vec.sub(d[:center], d[:start]))
        item = ctx[:refs] && ref_elbow(spec, d[:angle_deg], d[:radius_type])
        inst = item && ref_or_nil(ctx, item) { render_ref_elbow(ctx, d, item) }
        item = nil unless inst
        inst ||= place_part(ctx, name, Mesh.frame(d[:start], d[:dir_in], n1)) { Parts.elbow(ang, d[:radius], o) }
        attrs = {
          'type' => 'elbow', 'angle' => d[:angle_deg], 'radius_type' => d[:radius_type].to_s,
          'radius_mm' => d[:radius].round(1),
          'geom' => JSON.generate('center' => d[:center], 'xaxis' => d[:xaxis], 'normal' => d[:normal],
                                  'radius' => d[:radius], 'angle' => d[:angle],
                                  'start' => d[:start], 'end' => d[:end])
        }
        attrs['nominal_angle'] = d[:nominal_angle] if d[:nominal_angle]
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
        item = kind == :tee && ctx[:refs] && d[:run] && ref_tee(spec)
        inst = item && ref_or_nil(ctx, item) { render_ref_tee(ctx, d, item) }
        item = nil unless inst
        inst ||= place_part(ctx, name, f) { Parts.branch(loc.map { |u| [u, c, o] }) }
        attrs = { 'type' => 'tee', 'kind' => kind.to_s, 'role' => 'run',
                  'geom' => JSON.generate('center' => d[:center], 'arms' => d[:arms], 'c' => c) }
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

        c = main.tee_c
        mo = Parts.opts(main, lod: ctx[:lod], steps: ctx[:steps])
        arms = [main_dir, Vec.scale(main_dir, -1.0), bdir]
        f = junction_frame(at, arms)
        loc = local_dirs(f, arms)
        angle = Vec.angle(bdir, main_dir) * 180.0 / Math::PI
        angle = 180.0 - angle if angle > 90.0
        kind = (angle - 90.0).abs <= 1.0 ? 'tee' : 'lateral'
        name = "PP Branch #{kind} #{angle.round(1)} | #{spec_key(main)} x #{spec.size} | #{lod_key(ctx)}"
        main_code = t['main_service'] || ctx[:common]['service']
        mat = H.pipe_material(ctx[:model], main_code, main.family, ctx[:settings]['color_scheme'], t['main_color'])
        item = kind == 'tee' && branch_ref_tee(t, ctx)
        inst = item && ref_or_nil(ctx, item) { place_ref(ctx, item, Mesh.frame(at, main_dir, bdir), mat, plain: true) }
        item = nil unless inst
        inst ||= place_part(ctx, name, f) { Parts.branch([[loc[0], c, mo], [loc[1], c, mo], [loc[2], c, ctx[:opts]]]) }
        finish_piece(ctx, inst, "Branch #{kind} #{main.size} x #{spec.size}", mat,
                     'type' => 'tee', 'kind' => kind, 'role' => 'branch', 'branch_angle' => angle.round(1),
                     'size' => main.size, 'branch_size' => spec.size, 'rating' => main.rating,
                     'service' => main_code, 'catalog_name' => main.catalog_name, 'material' => main.material,
                     'od' => main.od,
                     'geom' => JSON.generate('center' => at, 'arms' => arms, 'c' => c)).tap do |e|
          H.set_attrs(e, ref_attrs(item)) if item
        end
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
        fam = ValveModels.family(ctx[:opts], metallic)
        len = FittingsData.face_to_face(type, spec.od, fam)
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

        name = "PP Valve #{type} #{fam} v2 | #{spec_key(spec)} | #{lod_key(ctx)}"
        inst = place_part(ctx, name, f) { Parts.valve(type, ctx[:opts], metallic: metallic) }
        finish_piece(ctx, inst, "#{info[:name]} #{spec.size}", ctx[:mat],
                     valve_attrs(type, info, fam, spec, len, at, dir))
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
