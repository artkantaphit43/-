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

          run_data(run)[:pipes].each do |e, r, path|
            # a pipe bent along a curve: the straight span under the cursor
            path.map { |p| H.transform_mm(tr, p) }.each_cons(2) do |a, b|
              ab = Vec.sub(b, a)
              len = Vec.length(ab)
              next if len < 1.0

              t = Vec.dot(Vec.sub(pt, a), ab) / (len * len)
              next if t < 0.0 || t > 1.0

              proj = Vec.add(a, Vec.scale(ab, t))
              d = Vec.dist(proj, pt)
              next if d > r + extra
              next if best && d >= best[:dist]

              best = { run: run, tr: tr, pipe: e, a: a, b: b,
                       dir: Vec.scale(ab, 1.0 / len), proj: proj, t: t, len: len, dist: d }
            end
          end
        end
        best[:attrs] = H.attrs(best[:pipe]) if best
        best
      end

      # ---- per-run cache ----
      #
      # The pipe tool asks on every mouse move; reading each run's centre
      # line and every pipe's attributes again each time made the cursor lag
      # in big models. A run's pickable data is kept until the run is drawn
      # again (its centre line / drawn pieces change) or a piece is deleted.
      def run_data(run)
        stamp = %w[cl drawn od smooth].map { |k| run.get_attribute(H::DICT, k) }
        @cache ||= {}
        c = @cache[run]
        return c[:data] if c && c[:stamp] == stamp && c[:data][:pipes].all? { |e, _, _| e.valid? }

        @cache.clear if @cache.size > 2000
        data = build_run_data(run)
        @cache[run] = { stamp: stamp, data: data }
        data
      end

      def clear_cache
        @cache = {}
      end

      def build_run_data(run)
        cl = H.get_json(run, 'cl', [])
        pipes = run.entities.map do |e|
          next unless H.instance?(e) && %w[pipe draft_pipe].include?(H.type_of(e))

          g = H.get_json(e, 'geom') or next
          [e, e.get_attribute(H::DICT, 'od').to_f / 2.0, H.pipe_path(g)]
        end.compact
        spec = Builder.run_spec(run)
        smooth = H.get_json(run, 'smooth', [])
        nodes = cl.flatten(1).uniq { |p| p.map { |c| c.round(1) } }.map do |p|
          arms = cl.count { |a, b| Vec.dist(a, p) <= 1.0 || Vec.dist(b, p) <= 1.0 }
          next if arms < 2
          # a point a curve bends through is not a corner
          next if arms == 2 && smooth.any? { |q| Vec.dist(q, p) <= 1.0 }

          [p, arms]
        end.compact
        { pipes: pipes, nodes: nodes, ends: Collector.open_ends(cl),
          node_tol: [spec.od / 2.0 + 0.6 * spec.elbow_radius_lr, 40.0].max }
      end

      # Corner / junction of a run (a centreline point shared by two or more
      # segments – where an elbow or tee sits) near pt: clicking anywhere on
      # that fitting counts. Returns { run:, tr:, local:, world:, arms: }.
      def run_node(model, pt, exclude_run: nil)
        best = nil
        H.active_runs(model).each do |run, tr|
          next if exclude_run && run == exclude_run

          data = run_data(run)
          data[:nodes].each do |p, arms|
            w = H.transform_mm(tr, p)
            d = Vec.dist(w, pt)
            next if d > data[:node_tol] || (best && d >= best[:dist])

            best = { run: run, tr: tr, local: p, world: w, arms: arms, dist: d }
          end
        end
        best
      end

      # Open end of a run centreline near pt. Returns { run:, tr:, local:, world: }.
      def run_end(model, pt, tol: 30.0)
        H.active_runs(model).each do |run, tr|
          # anywhere on the end ring or the end face counts (the "Center"
          # of the pipe end), plus a margin for the cursor
          od = run.get_attribute(H::DICT, 'od').to_f
          r = od / 2.0 + [tol, 0.25 * od].max
          run_data(run)[:ends].each do |p|
            w = H.transform_mm(tr, p)
            return { run: run, tr: tr, local: p, world: w } if Vec.dist(w, pt) <= r
          end
        end
        nil
      end
    end
  end
end
