# frozen_string_literal: true

module ArtK
  module PlantPipe
    # Reads piping data back out of the model (BOM, hydraulic check, clash).
    module Collector
      H = ModelHelpers
      ITEM_TYPES = %w[pipe elbow tee reducer valve flange component insulation support].freeze

      module_function

      # All BOM records in the model (or only inside the given runs).
      def records(model, runs: nil)
        recs = []
        visit = lambda do |ents|
          H.each_instance(ents) do |e, _t|
            a = H.attrs(e)
            next unless a

            if ITEM_TYPES.include?(a['type'])
              recs << a
            elsif a['type'] == 'run'
              recs.concat(H.get_json(e, 'extras', []))
            end
          end
        end
        if runs
          runs.each do |r|
            recs.concat(H.get_json(r, 'extras', []))
            visit.call(r.entities)
          end
        else
          visit.call(model.entities)
        end
        recs
      end

      # All runs in the model with their world transformation.
      def all_runs(model)
        out = []
        H.each_instance(model.entities) { |e, t| out << [e, t] if H.run?(e) }
        out
      end

      def pieces(run, type)
        run.entities.select { |e| H.instance?(e) && H.type_of(e) == type }
      end

      # Input hash for RunCheck.check.
      def run_data(run)
        settings = Builder.run_settings(run)
        {
          spec: Settings.spec(settings),
          service: settings['service'],
          flow_m3h: run.get_attribute(H::DICT, 'design_flow_m3h').to_f,
          cl: H.get_json(run, 'cl', []),
          pipes: pieces(run, 'pipe').map do |p|
            g = H.get_json(p, 'geom', {})
            { from: g['a'], to: g['b'], length_mm: p.get_attribute(H::DICT, 'length_mm').to_f }
          end,
          elbows: pieces(run, 'elbow').map do |e|
            { angle_deg: e.get_attribute(H::DICT, 'angle').to_f,
              radius_type: e.get_attribute(H::DICT, 'radius_type'),
              radius_mm: e.get_attribute(H::DICT, 'radius_mm').to_f }
          end,
          tees: pieces(run, 'tee').map do |t|
            { kind: t.get_attribute(H::DICT, 'kind'), role: t.get_attribute(H::DICT, 'role') }
          end,
          valves: pieces(run, 'valve').map { |v| v.get_attribute(H::DICT, 'valve_type') },
          mitres: H.get_json(run, 'extras', []).select { |x| x['type'] == 'mitre' }
        }
      end

      # Zones around intentional connections, so connected runs are not
      # reported as clashing with each other.
      def connections(model)
        zones = []
        ends = []
        all_runs(model).each do |run, tr|
          od = run.get_attribute(H::DICT, 'od').to_f
          (H.get_json(run, 'tees', []) + H.get_json(run, 'joins', [])).each do |t|
            spec = Builder.main_spec(t)
            zones << { owner: run.persistent_id, point: H.transform_mm(tr, t['at']),
                       radius: spec.tee_c + spec.od + od }
          end
          cl = H.get_json(run, 'cl', [])
          open_ends(cl).each { |p| ends << [run.persistent_id, H.transform_mm(tr, p), od] }
        end
        ends.combination(2).each do |(o1, p1, d1), (o2, p2, d2)|
          next if o1 == o2 || Vec.dist(p1, p2) > 1.0

          r = [d1, d2].max * 1.5
          zones << { owner: o1, point: p1, radius: r }
          zones << { owner: o2, point: p2, radius: r }
        end
        zones
      end

      def open_ends(cl)
        pts = cl.flatten(1)
        pts.select { |p| pts.count { |q| Vec.dist(p, q) <= 1.0 } == 1 }
      end

      # Capsules for clash detection, in world mm.
      def clash_items(model)
        items = []
        all_runs(model).each do |run, tr|
          owner = run.persistent_id
          label = run.name
          ins = Builder.run_settings(run)['insulation_mm'].to_f
          w = ->(p) { H.transform_mm(tr, p) }
          run.entities.each do |e|
            next unless H.instance?(e)

            a = H.attrs(e)
            next unless a && a['geom']

            g = JSON.parse(a['geom'])
            od = a['od'].to_f
            case a['type']
            when 'pipe'
              items << Clash::Item.new(owner: owner, label: label, a: w.call(g['a']), b: w.call(g['b']), r: od / 2.0 + ins)
            when 'elbow'
              Clash.arc_chords(g['center'], g['xaxis'], g['normal'], g['radius'], g['angle']).each do |p, q|
                items << Clash::Item.new(owner: owner, label: label, a: w.call(p), b: w.call(q), r: od / 2.0 + ins)
              end
            when 'tee'
              next if a['role'] == 'branch' # sits on the main run – covered by its pipe

              g['arms'].each do |u|
                tip = Vec.add(g['center'], Vec.scale(u, g['c']))
                items << Clash::Item.new(owner: owner, label: label, a: w.call(g['center']), b: w.call(tip), r: od / 2.0 + ins)
              end
            when 'valve'
              items << Clash::Item.new(owner: owner, label: "#{label} (#{a['valve_name']})",
                                       a: w.call(g['a']), b: w.call(g['b']), r: g['r'].to_f)
            end
          end
        end
        items
      end
    end
  end
end
