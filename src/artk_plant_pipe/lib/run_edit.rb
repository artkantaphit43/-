# frozen_string_literal: true

require_relative 'vec'

module ArtK
  module PlantPipe
    # Editing a run's stored centreline after it was drawn (pure Ruby).
    #
    # A run is regenerated from its centreline ('cl'), so stretching a pipe
    # means moving centreline points – everything sitting on the run
    # (valves, supports, library fittings at an open end) is carried along:
    #   * a record exactly at a moved point moves with it;
    #   * a record on a segment keeps its distance from the segment end that
    #     did not move (a valve 1 m from the elbow stays 1 m from the elbow);
    #   * a record that would fall off a shortened segment is clamped onto it
    #     and reported.
    # Points where the run connects to another run (branch tee on a main,
    # reducer join) are locked: moving them would tear the connection.
    module RunEdit
      TOL = 1.0 # mm

      module_function

      # data: { 'cl' => [[a, b], ...], 'tees' => [...], 'joins' => [...],
      #         'valves' => [{ 'at', 'dir', ... }], 'supports' => [...],
      #         'end_parts' => [{ 'at', ... }] }
      # moves: [[from, to], ...] applied together (run-local mm).
      # Returns [new_data, warnings]; new_data is nil when the edit is refused.
      def move_points(data, moves)
        moves = moves.reject { |f, t| Vec.dist(f, t) < 1e-6 }
        return [deep_copy(data), []] if moves.empty?

        locked = locked_points(data)
        moves.each do |f, _|
          next unless locked.any? { |p| Vec.dist(p, f) <= TOL }

          return [nil, ['จุดนี้ต่อกับแนวท่ออื่นอยู่ ย้ายไม่ได้ (point is connected to another run)']]
        end

        warnings = []
        out = deep_copy(data)
        map = ->(p) { (m = moves.find { |f, _| Vec.dist(f, p) <= TOL }) ? m[1].dup : p }
        old_cl = data['cl'] || []
        out['cl'] = old_cl.map { |a, b| [map.call(a), map.call(b)] }
        out['cl'].each do |a, b|
          warnings << 'ท่อบางช่วงยาวเป็นศูนย์ (zero-length segment)' if Vec.dist(a, b) < TOL
        end

        %w[valves supports end_parts].each do |key|
          (out[key] || []).each do |rec|
            note = carry(rec, old_cl, out['cl'], moves)
            warnings << "#{label(key)}: #{note}" if note
          end
        end
        [out, warnings.uniq]
      end

      # Branch / join points: shared with another run.
      def locked_points(data)
        ((data['tees'] || []) + (data['joins'] || [])).map { |t| t['at'] }
      end

      # Moves one record (in place) to follow the edited centreline.
      # Returns a note when it had to be clamped.
      def carry(rec, old_cl, new_cl, moves)
        at = rec['at']
        if (m = moves.find { |f, _| Vec.dist(f, at) <= TOL })
          shift(rec, Vec.sub(m[1], at))
          return nil
        end

        i = segment_index(old_cl, at)
        return nil unless i

        a, b = old_cl[i]
        na, nb = new_cl[i]
        return nil if Vec.dist(a, na) < 1e-6 && Vec.dist(b, nb) < 1e-6

        len = Vec.dist(a, b)
        s = Vec.dist(a, at)
        nlen = Vec.dist(na, nb)
        return nil if nlen < TOL

        u = Vec.unit(Vec.sub(nb, na))
        # keep the distance from the end that stayed put
        d = Vec.dist(a, na) < 1e-6 || Vec.dist(b, nb) >= 1e-6 ? s : nlen - (len - s)
        note = nil
        if d.negative? || d > nlen
          note = 'อยู่เลยปลายท่อที่หดลง ย้ายมาไว้ที่ปลายท่อ (fell off the shortened pipe, moved onto it)'
          d = d.clamp(0.0, nlen)
        end
        new_at = Vec.add(na, Vec.scale(u, d))
        shift(rec, Vec.sub(new_at, at))
        if rec['dir']
          old_u = Vec.unit(Vec.sub(b, a))
          rec['dir'] = Vec.dot(rec['dir'], old_u) >= 0 ? u : Vec.scale(u, -1.0)
        end
        note
      end

      def shift(rec, delta)
        rec['at'] = Vec.add(rec['at'], delta)
        rec['target'] = Vec.add(rec['target'], delta) if rec['target'].is_a?(Array)
      end

      # Segment a point lies on (on the axis, within its length).
      def segment_index(cl, p)
        cl.each_with_index do |(a, b), i|
          ab = Vec.sub(b, a)
          len = Vec.length(ab)
          next if len < 1e-6

          t = Vec.dot(Vec.sub(p, a), ab) / len
          next if t < -TOL || t > len + TOL

          proj = Vec.add(a, Vec.scale(ab, t / len))
          return i if Vec.dist(proj, p) <= TOL
        end
        nil
      end

      # Centre line after pieces were deleted in SketchUp (what you delete
      # stays deleted – a rebuild must not bring it back):
      #   pipes    – centre lines ([pt, …]) of deleted pipe pieces: the
      #              segments under them go, fitting zone to fitting zone;
      #   fittings – [node, [arm end points]] of deleted elbows / tees: each
      #              remaining arm stops where its pipe ended (open end).
      def prune(cl, pipes, fittings)
        out = cl.map { |a, b| [a.dup, b.dup] }
        pipes.each do |path|
          path.each_cons(2) { |p, q| out.reject! { |a, b| on_span?(a, b, p, q) } }
        end
        fittings.each do |node, arms|
          out.each do |seg|
            [0, 1].each do |k|
              next unless Vec.dist(seg[k], node) <= TOL

              far = seg[1 - k]
              arm = arms.find { |m| between?(m, seg[k], far) }
              seg[k] = arm.map(&:to_f) if arm
            end
          end
        end
        out.reject { |a, b| Vec.dist(a, b) <= TOL }
      end

      # Segment a–b lies along span p–q and overlaps its inside.
      def on_span?(a, b, p, q)
        pq = Vec.sub(q, p)
        len = Vec.length(pq)
        return false if len < TOL

        u = Vec.scale(pq, 1.0 / len)
        off = ->(x) { Vec.length(Vec.cross(Vec.sub(x, p), u)) }
        return false unless off.call(a) <= TOL && off.call(b) <= TOL

        ta, tb = [a, b].map { |x| Vec.dot(Vec.sub(x, p), u) }.minmax
        tb > TOL && ta < len - TOL
      end

      # m on segment a–b (strictly past a).
      def between?(m, a, b)
        ab = Vec.sub(b, a)
        len = Vec.length(ab)
        return false if len < TOL

        t = Vec.dot(Vec.sub(m, a), ab) / len
        t > TOL && t <= len + TOL && Vec.dist(Vec.add(a, Vec.scale(ab, t / len)), m) <= TOL
      end

      def label(key)
        { 'valves' => 'วาล์ว (valve)', 'supports' => 'ซัพพอร์ต (support)',
          'end_parts' => 'ข้อต่อปลายท่อ (end fitting)' }.fetch(key, key)
      end

      def deep_copy(obj)
        Marshal.load(Marshal.dump(obj))
      end

      # ---- reading a pipe back from its geometry ----

      # What the pipe's mesh says now, compared with its record.
      #   a, b   – recorded pipe ends (centreline, run-local mm), already
      #            mapped by the pipe group's own transformation if any
      #   ea, eb – how far the mesh runs past a / b (into fittings)
      #   ro     – outside radius
      #   pts    – mesh vertex positions (run-local mm)
      # Returns { a:, b:, da:, db:, lateral:, radial: } where a / b are the
      # pipe ends the mesh implies and da / db the axial change at each end
      # (positive = longer), or nil without usable points.
      def measure_pipe(a, b, ea, eb, ro, pts)
        return nil if pts.nil? || pts.size < 3

        len = Vec.dist(a, b)
        return nil if len < 1e-6

        u = Vec.unit(Vec.sub(b, a))
        ts = []
        perp_sum = [0.0, 0.0, 0.0]
        perps = pts.map do |p|
          d = Vec.sub(p, a)
          t = Vec.dot(d, u)
          ts << t
          pp = Vec.sub(d, Vec.scale(u, t))
          perp_sum = Vec.add(perp_sum, pp)
          pp
        end
        c = Vec.scale(perp_sum, 1.0 / pts.size)
        rmax = perps.map { |pp| Vec.dist(pp, c) }.max
        tmin = ts.min
        tmax = ts.max
        na = Vec.add(Vec.add(a, c), Vec.scale(u, tmin + ea))
        nb = Vec.add(Vec.add(a, c), Vec.scale(u, tmax - eb))
        { a: na, b: nb, da: -(tmin + ea), db: tmax - eb - len, lateral: Vec.length(c),
          radial: ro.positive? && (rmax - ro).abs > [0.03 * ro, 1.0].max }
      end
    end
  end
end
