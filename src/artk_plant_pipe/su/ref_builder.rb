# frozen_string_literal: true

module ArtK
  module PlantPipe
    # Builder part that uses the reference models (exact copies of the
    # user's library) instead of the generated fittings / valves, in the
    # "detailed" level of detail. Everything falls back to the generated
    # parts when the library has no model of that type and size.
    module Builder
      module_function

      REF_END_TYPES = {
        'gi_thrd' => ['Threaded BSPT', 'PN16 / 200 WOG'], 'cs_sw' => ['Socket weld', 'Class 3000'],
        'flg150' => ['Flanged RF', 'Class 150'], 'lug150' => ['Lug (flanged Class 150)', 'Class 150'],
        'wafer150' => ['Wafer (between Class 150 flanges)', 'Class 150'],
        'jis10k' => ['Wafer (between flanges)', 'JIS 10K'], 'pl_flg' => ['Flanged PN10', 'PN10'],
        'pl_union' => ['True union (solvent socket)', 'PN10–PN16']
      }.freeze

      def refs_enabled?(settings)
        settings['lod'].to_s == 'detailed' && Refs.available?
      end

      # Real elbow for a deflection within ±1° of 90° / 45°, or nil.
      def ref_elbow(spec, deg, rtype)
        if (deg - 90.0).abs <= 1.0
          Refs.fitting_for('elbow90', spec, variant: rtype.to_s)
        elsif (deg - 45.0).abs <= 1.0
          Refs.fitting_for('elbow45', spec)
        end
      end

      def ref_tee(spec)
        t = Refs.fitting_for('tee', spec)
        t && t['ports'].size >= 3 ? t : nil
      end

      # Take-outs of the real fittings for the network solver.
      def ref_takes(spec)
        takes = {
          elbow: lambda do |deg, rtype|
            it = ref_elbow(spec, deg, rtype)
            it && it['ports'].first(2).map { |p| Vec.length(p['p']) }.max
          end
        }
        tee = ref_tee(spec)
        if tee
          takes[:tee_run] = tee['ports'].first(2).map { |p| Vec.length(p['p']) }.max
          takes[:tee_branch] = Vec.length(tee['ports'][2]['p'])
        end
        takes
      end

      # Pipes run into the sockets of real fittings up to the socket bottom;
      # weld / threaded end faces are butted (depth 0).
      def pt_key(p)
        p.map { |v| (v.to_f * 10).round }.join(',')
      end

      def mark_ext(ctx, pt, port)
        (ctx[:ext] ||= {})[pt_key(pt)] = (port && port['depth']).to_f
      end

      def pipe_ext(ctx, pt)
        (ctx[:ext] || {})[pt_key(pt)]
      end

      # Runs the block; on failure records a warning and returns nil so the
      # caller draws the generated part instead (never a gap in the line).
      def ref_or_nil(ctx, item)
        yield
      rescue StandardError => e
        (ctx[:warnings] ||= []) << "#{item['key']}: reference model failed (#{e.message}) – generated part used"
        nil
      end

      def place_ref(ctx, item, frame, mat, scale: nil, plain: false)
        defn = RefModels.definition(ctx[:model], item, plain: plain)
        tr = H.frame_transform(frame)
        tr *= Geom::Transformation.scaling(*scale) if scale && scale != [1.0, 1.0, 1.0]
        inst = ctx[:ents].add_instance(defn, tr)
        inst.material = mat if mat
        inst
      end

      def ref_attrs(item)
        { 'model' => item['sized_from'] || item['key'], 'model_source' => item['src_name'], 'standard' => item['standard'] }
      end

      def render_ref_elbow(ctx, d, item)
        f = Mesh.frame(d[:vertex], d[:dir_in], d[:dir_out])
        inst = place_ref(ctx, item, f, ctx[:mat], plain: true)
        mark_ext(ctx, d[:start], item['ports'][0])
        mark_ext(ctx, d[:end], item['ports'][1])
        inst
      end

      # Equal tee: run along X (port 0 at −X), branch toward +Y.
      def render_ref_tee(ctx, d, item)
        run_a, run_b = d[:run]
        f = Mesh.frame(d[:center], run_b, d[:branch])
        inst = place_ref(ctx, item, f, ctx[:mat], plain: true)
        [[run_a, 0], [run_b, 1], [d[:branch], 2]].each do |u, i|
          mark_ext(ctx, Vec.add(d[:center], Vec.scale(u, Vec.length(item['ports'][i]['p']))), item['ports'][i])
        end
        inst
      end

      # ---------------- valves ----------------

      def ref_valve(ctx, type)
        return nil unless ctx[:refs]

        Refs.valve_for(type, ctx[:spec]) || Refs.scalable_valve(type, ctx[:spec])
      end

      # [axial, radial] scale of a real valve used for another size (1, 1
      # when the size matches).
      def valve_scale(type, spec, item)
        return [1.0, 1.0] if item['size'] == spec.size && !item['scalable']

        if Refs::SCALABLE[item['type']] == [item['family'], item['operator']] && FittingsData::VALVES.key?(type)
          # flanged gate: standard face-to-face along the pipe, standard
          # flange diameter across it
          src = Catalog.spec('CS_B36_10', item['size'])
          ff = FittingsData.face_to_face(type, spec.od, :flanged)
          return [ff / port_gap(item), FittingsData.flange(spec.od).od / FittingsData.flange(src.od).od]
        end
        k = Refs.scale_for(item, spec.od)
        [k, k]
      rescue ArgumentError
        [1.0, 1.0]
      end

      def port_gap(item)
        a, b = item['ports']
        Vec.dist(a['p'], b['p'])
      end

      # Face-to-face of the valve plus its companion flanges.
      def ref_valve_length(spec, item, type = item['type'])
        len = port_gap(item) * valve_scale(type, spec, item)[0]
        fl = flanged?(item) && Refs.companion_flange(spec, item)
        len += 2.0 * port_gap(fl) if fl
        len
      end

      def flanged?(item)
        Refs::FLANGED.include?(item['family'])
      end

      def place_ref_valve(ctx, type, item, at, dir, up)
        spec = ctx[:spec]
        info = valve_info(type, item)
        f = Mesh.frame(at, dir, up)
        kx, kr = valve_scale(type, spec, item)
        inst = place_ref(ctx, item, f, RefModels.role_material(ctx[:model], item['material']), scale: [kx, kr, kr])
        half = port_gap(item) * kx / 2.0
        fl = flanged?(item) && Refs.companion_flange(spec, item)
        if fl
          lf = port_gap(fl)
          # flange face (port 1, +X) against the valve end, hub on the pipe
          [[1.0, half], [-1.0, half]].each do |sgn, h|
            face_at = Vec.add(at, Vec.scale(dir, sgn * h))
            x = Vec.scale(dir, -sgn)
            o = Vec.sub(face_at, Vec.scale(x, lf / 2.0))
            fi = place_ref(ctx, fl, Mesh.frame(o, x, up), ctx[:mat], plain: true)
            finish_piece(ctx, fi, "Flange #{spec.size} (companion)", ctx[:mat],
                         { 'type' => 'flange', 'kind' => 'companion', 'rating' => REF_END_TYPES.dig(fl['family'], 1) ||
                           (fl['family'] == 'flgpn' ? 'PN16' : 'Class 150') }.merge(ref_attrs(fl)))
          end
        end
        len = ref_valve_length(spec, item, type)
        end_type, rating = REF_END_TYPES.fetch(item['family'], ['', nil])
        attrs = valve_attrs(type, info, item['family'].to_sym, spec, len, at, dir)
        attrs['valve_family'] = item['family']
        attrs['end_type'] = end_type
        attrs['valve_rating'] = rating || spec.rating
        attrs['operator'] = item['operator'] if item['operator']
        attrs['model_scaled_from'] = item['size'] if kx != 1.0 || kr != 1.0
        name = item['type'] == type || !FittingsData::VALVES.key?(item['type']) ? info[:name] : "#{info[:name]} (#{item['type']})"
        finish_piece(ctx, inst, "#{name} #{spec.size}", nil, attrs.merge(ref_attrs(item)))
      end

      # Name / data of an in-line item: a standard valve type, or any other
      # in-line library part (union, flowmeter, steam trap …).
      def valve_info(type, item = nil)
        FittingsData::VALVES[type] || begin
          th, en = Refs::TYPE_NAMES.fetch(item ? item['type'] : type, [type, type])
          { name: en, th: th, k: 0.0 }
        end
      end

      # Valve length along the pipe for the valve tool (mm).
      def valve_length(type, spec, settings)
        item = refs_enabled?(settings) && (Refs.valve_for(type, spec) || Refs.scalable_valve(type, spec))
        return ref_valve_length(spec, item, type) if item

        Parts.valve_length(type, Parts.opts(spec), metallic: spec.density > 5000)
      end
    end
  end
end
