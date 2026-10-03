# frozen_string_literal: true

module ArtK
  module PlantPipe
    # Finds existing runs/pipes near a world point (mm) in the active context.
    module Picker
      H = ModelHelpers

      module_function

      # Nearest straight pipe whose axis is within its radius (+extra) of pt.
      # Returns { run:, tr:, pipe:, attrs:, a:, b:, dir:, proj:, t:, len:, dist: }
      # with world coordinates, or nil.
      def nearest_pipe(model, pt, extra: 25.0, exclude_run: nil)
        best = nil
        H.active_runs(model).each do |run, tr|
          next if exclude_run && run == exclude_run

          run.entities.each do |e|
            next unless H.instance?(e) && H.type_of(e) == 'pipe'

            g = H.get_json(e, 'geom')
            next unless g

            a = H.transform_mm(tr, g['a'])
            b = H.transform_mm(tr, g['b'])
            ab = Vec.sub(b, a)
            len = Vec.length(ab)
            next if len < 1.0

            t = Vec.dot(Vec.sub(pt, a), ab) / (len * len)
            next if t < 0.0 || t > 1.0

            proj = Vec.add(a, Vec.scale(ab, t))
            d = Vec.dist(proj, pt)
            r = e.get_attribute(H::DICT, 'od').to_f / 2.0
            next if d > r + extra
            next if best && d >= best[:dist]

            best = { run: run, tr: tr, pipe: e, attrs: H.attrs(e), a: a, b: b,
                     dir: Vec.scale(ab, 1.0 / len), proj: proj, t: t, len: len, dist: d }
          end
        end
        best
      end

      # Corner / junction of a run (a centreline point shared by two or more
      # segments – where an elbow or tee sits) near pt: clicking anywhere on
      # that fitting counts. Returns { run:, tr:, local:, world:, arms: }.
      def run_node(model, pt, exclude_run: nil)
        best = nil
        H.active_runs(model).each do |run, tr|
          next if exclude_run && run == exclude_run

          cl = H.get_json(run, 'cl', [])
          spec = Builder.run_spec(run)
          tol = [spec.od / 2.0 + 0.6 * spec.elbow_radius_lr, 40.0].max
          cl.flatten(1).uniq { |p| p.map { |c| c.round(1) } }.each do |p|
            arms = cl.count { |a, b| Vec.dist(a, p) <= 1.0 || Vec.dist(b, p) <= 1.0 }
            next if arms < 2

            w = H.transform_mm(tr, p)
            d = Vec.dist(w, pt)
            next if d > tol || (best && d >= best[:dist])

            best = { run: run, tr: tr, local: p, world: w, arms: arms, dist: d }
          end
        end
        best
      end

      # Open end of a run centreline near pt. Returns { run:, tr:, local:, world: }.
      def run_end(model, pt, tol: 30.0)
        H.active_runs(model).each do |run, tr|
          cl = H.get_json(run, 'cl', [])
          # anywhere on the end ring or the end face counts (the "Center"
          # of the pipe end), plus a margin for the cursor
          od = run.get_attribute(H::DICT, 'od').to_f
          r = od / 2.0 + [tol, 0.25 * od].max
          Collector.open_ends(cl).each do |p|
            w = H.transform_mm(tr, p)
            return { run: run, tr: tr, local: p, world: w } if Vec.dist(w, pt) <= r
          end
        end
        nil
      end
    end
  end
end
