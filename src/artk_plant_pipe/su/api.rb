# frozen_string_literal: true

module ArtK
  module PlantPipe
    # Stable entry points for other extensions (Steel Supports TH,
    # PipeBracket …): they call only these, so Plant Piping can change
    # inside without breaking them. LEVEL rises when something is added;
    # nothing here changes meaning. World millimetres throughout.
    module API
      LEVEL = 1
      H = ModelHelpers
      INS_RHO = 60.0 # kg/m³ insulation + jacket

      module_function

      def version
        VERSION
      end

      # The Plant Piping pipe under +point+ (within its radius, insulation
      # and extra): info (below) + point: (on its axis), dir:, run:.
      def pipe_at(model, point, extra: 25.0)
        hit = Picker.nearest_pipe(model, point, extra: extra + 200.0)
        return nil unless hit

        inf = info(hit[:run])
        return nil if hit[:dist] > hit[:pipe].get_attribute(H::DICT, 'od').to_f / 2.0 + inf[:ins] + extra

        inf.merge(point: hit[:proj], dir: hit[:dir], run: hit[:run])
      end

      # Pipes crossing the vertical plane through +point+ square to +dir+:
      # info + y: (along UP × dir), z: (up) from point, od:, ins:.
      def pipes_across(model, point, dir, reach: 2500.0, rise: 1500.0)
        runs = H.active_runs(model).to_h { |r, _| [r.persistent_id, r] }
        SupportBuilder.crossing_pipes(model, point, dir, reach: reach, rise: rise).filter_map do |y, r, z, _size, pid, ins|
          run = runs[pid]
          run && info(run).merge(y: y, z: z, od: 2.0 * (r - ins.to_f), ins: ins.to_f)
        end
      end

      # What a support needs to know about a run: size, service, insulation,
      # kg/m full (pipe + content + insulation), max support span (m).
      def info(run)
        st = Builder.run_settings(run)
        spec = Settings.spec(st)
        svc = Services.get(st['service'])
        ins = st['insulation_mm'].to_f
        hot = %i[hot_water steam].include?(svc[:fluid])
        content = case svc[:fluid]
                  when :water, :hot_water, :chemical then spec.water_kg_m
                  when :oil then 0.9 * spec.water_kg_m
                  else 0.0
                  end
        ins_kg = ins.positive? ? Math::PI * ins * (spec.od + ins) * INS_RHO * 1e-6 : 0.0
        { pid: run.persistent_id, run: run, size: spec.size, service: svc[:code], label: "#{spec.size} #{svc[:code]}",
          od: spec.od, ins: ins, kg_m: (spec.weight_kg_m + content + ins_kg).round(3),
          span_m: Supports.max_span_m(spec, hot: hot), hot: hot, material: spec.material }
      end

      def runs(model, selected: false)
        selected ? H.selected_runs(model) : H.active_runs(model).map(&:first)
      end

      def run_by_pid(model, pid)
        H.active_runs(model).map(&:first).find { |r| r.persistent_id == pid }
      end

      # Where supports go along +run+ at its max span (or span_m), leaving
      # out the stretches already carried by shared supports and other
      # extensions' supports: [{ at:, dir: }].
      def support_points(model, run, span_m: nil)
        tr = H.edit_transform(model) * run.transformation
        inv = tr.inverse
        span = (span_m || info(run)[:span_m]).to_f * 1000.0
        pipes = Collector.pieces(run, 'pipe').map do |p|
          g = H.get_json(p, 'geom')
          { from: g['a'], to: g['b'], path: g['path'] }
        end
        loads = Collector.pieces(run, 'valve').map { |v| JSON.parse(v.get_attribute(H::DICT, 'at')) }
        fixed = (SupportBuilder.shared_points(model, run.persistent_id) +
                 SupportBuilder.external_points(model, run.persistent_id)).map { |w| H.transform_mm(inv, w) }
        Supports.place(pipes, span, loads: loads, fixed: fixed)[:supports].map do |s|
          { at: H.transform_mm(tr, s[:at]), dir: Vec.unit(H.from_vec(H.to_vec(s[:dir]).transform(tr))) }
        end
      end

      # Plant Piping's own single supports of runs +pids+ next to +point+
      # are removed (another support carries the pipes there).
      def drop_hangers(model, point, pids)
        SupportBuilder.drop_covered(model, point, pids.map { |id| [nil, nil, nil, nil, id] })
      end

      # Another extension's supports: block(model, pid) → world points
      # where it carries run pid. Auto Supports leaves those stretches out.
      def register_supports(name, &block)
        SupportBuilder.register_external(name, &block)
      end

      # Told after Plant Piping drew / rebuilt runs: block(model, runs).
      def on_runs_changed(name, &block)
        SupportBuilder::CHANGED[name.to_s] = block
        true
      end

      def notify_changed(model, runs)
        SupportBuilder.notify_changed(model, runs)
      end

      # Part of Plant Piping's model (run, pipe, fitting, support …)?
      def ours?(entity)
        entity.respond_to?(:get_attribute) && !entity.get_attribute(H::DICT, 'type').nil?
      end
    end
  end
end
