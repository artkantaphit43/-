# frozen_string_literal: true

require_relative 'vec'

module ArtK
  module PlantPipe
    # Converts a centreline network (line segments, mm) into piping pieces:
    # straight pipes, elbows, tees/crosses/laterals and mitre joints.
    #
    # How it works
    # 1. Merge segment end points that are within +tol+ into nodes.
    # 2. Classify each node by its number of arms (degree) and angles:
    #      1 arm  → :end
    #      2 arms → :pass (collinear, no fitting), :curve (a point the pipe
    #               bends through, from a drawn arc / curve) or :elbow
    #      3 arms → :tee (branch ≈ 90°) or :lateral (e.g. 45° wye)
    #      4 arms → :cross,  >4 → :manifold (warned)
    # 3. Merge segments through :pass nodes into straight "chains", so a
    #    line drawn in several clicks becomes one pipe.
    # 4. Each fitting consumes part of the adjoining chains:
    #      elbow  – tangent length T = R·tan(θ/2)
    #      tee    – centre-to-end C
    #    If a chain is too short for the fittings at both ends, long-radius
    #    elbows are first downgraded to short-radius, then to a mitre joint
    #    (and a warning is issued) – the same decision a piping designer
    #    makes on a tight run.
    # 5. Emit pieces with full 3D geometry ready for rendering. Straight
    #    chains joined through :curve nodes become one :curve piece – a
    #    continuous bent pipe along the drawn curve, no fittings.
    class Network
      Piece = Struct.new(:type, :data)

      STRAIGHT_TOL_DEG = 0.5   # deflection below this is treated as straight
      FOLD_TOL_DEG     = 179.0 # deflection above this cannot be fitted
      CURVE_MAX_DEG    = 30.0  # sharpest step of a drawn curve still bent through
      FACETED_MAX_DEG  = 15.0  # step of an exploded arc (no curve info left)
      FACETED_MIN      = 3     # ... and how many such steps in a row make one

      attr_reader :pieces, :warnings, :nodes

      # spec: object/hash responding to od, elbow_radius_lr, elbow_radius_sr,
      #       tee_c (mm).
      # takes: optional take-outs of real fittings (reference models):
      #   elbow: ->(deflection_deg, radius_type) { mm or nil }
      #   tee_run / tee_branch: centre-to-end of the equal tee (mm)
      # smooth: centre-line points the pipe bends through without a fitting
      #   (vertices of drawn arcs / curves, see Network.curve_points).
      def initialize(segments, spec, tol: 1.0, radius_type: :lr, takes: nil, smooth: [])
        @segments = segments
        @smooth = smooth || []
        @od = fetch(spec, :od)
        @r_lr = fetch(spec, :elbow_radius_lr)
        @r_sr = fetch(spec, :elbow_radius_sr)
        @tee_c = fetch(spec, :tee_c)
        @tol = tol
        @radius_type = radius_type
        @takes = takes || {}
        @warnings = []
        @pieces = []
      end

      # Split segments into connected groups (one piping run each).
      def self.components(segments, tol: 1.0)
        dummy = { od: 1.0, elbow_radius_lr: 1.0, elbow_radius_sr: 1.0, tee_c: 1.0 }
        net = new(segments, dummy, tol: tol)
        net.send(:build_graph)
        net.send(:connected_segments)
      end

      # Points of +segments+ where a drawn curve passes: the vertices of the
      # SketchUp curves in +curves+ (each a list of points, ends included)
      # and runs of FACETED_MIN or more evenly spaced shallow vertices (an
      # arc that was exploded). Corners sharper than CURVE_MAX_DEG stay
      # fittings – that is checked when the network is solved.
      def self.curve_points(segments, curves = [], tol: 1.0)
        dummy = { od: 1.0, elbow_radius_lr: 1.0, elbow_radius_sr: 1.0, tee_c: 1.0 }
        net = new(segments, dummy, tol: tol)
        net.send(:build_graph)
        net.send(:faceted_points) + curves.flatten(1).map { |p| p.map(&:to_f) }.uniq
      end

      def solve
        build_graph
        classify_nodes
        build_chains
        fit_fittings
        emit
        self
      end

      def pipes
        @pieces.select { |p| p.type == :pipe }
      end

      def fittings
        @pieces.reject { |p| %i[pipe curve end].include?(p.type) }
      end

      private

      def fetch(spec, key)
        v = spec.respond_to?(key) ? spec.public_send(key) : spec[key]
        raise ArgumentError, "spec missing #{key}" if v.nil?

        v.to_f
      end

      # ---------- 1. graph ----------

      # Split segments where another segment ends on their interior
      # (T-junction drawn without splitting the through line, typical for
      # imported CAD linework).
      def split_at_junctions(segs)
        segs = segs.map { |a, b| [a.map(&:to_f), b.map(&:to_f)] }
        ends = segs.flatten(1)
        segs.flat_map do |a, b|
          ab = Vec.sub(b, a)
          len = Vec.length(ab)
          next [[a, b]] if len < 2 * @tol

          ts = ends.map do |p|
            t = Vec.dot(Vec.sub(p, a), ab) / (len * len)
            next nil if t * len <= @tol || (1 - t) * len <= @tol

            Vec.dist(Vec.add(a, Vec.scale(ab, t)), p) <= @tol ? t : nil
          end.compact.uniq.sort
          pts = [a] + ts.map { |t| Vec.add(a, Vec.scale(ab, t)) } + [b]
          pts.each_cons(2).to_a
        end
      end

      def build_graph
        @nodes = []          # [{ pt:, arms: [edge ids] }]
        @grid = {}
        @edges = []          # [[i, j]]
        seen = {}
        split_at_junctions(@segments).each do |a, b|
          i = node_for(a.map(&:to_f))
          j = node_for(b.map(&:to_f))
          next if i == j

          key = [i, j].sort
          if seen[key]
            warn_at(@nodes[i][:pt], 'ท่อซ้อนทับกัน / พับกลับ (overlapping or folded-back pipe)') if seen[key] == 1
            seen[key] += 1
            next
          end

          seen[key] = 1
          id = @edges.size
          @edges << [i, j]
          @nodes[i][:arms] << id
          @nodes[j][:arms] << id
        end
        raise ArgumentError, 'no valid segments' if @edges.empty?
      end

      def connected_segments
        comp = Array.new(@nodes.size)
        groups = []
        @nodes.each_index do |start|
          next if comp[start]

          gid = groups.size
          groups << []
          stack = [start]
          comp[start] = gid
          until stack.empty?
            n = stack.pop
            @nodes[n][:arms].each do |e|
              m = other(e, n)
              next if comp[m]

              comp[m] = gid
              stack << m
            end
          end
        end
        @edges.each { |i, j| groups[comp[i]] << [@nodes[i][:pt], @nodes[j][:pt]] }
        groups.reject(&:empty?)
      end

      def cell(pt)
        pt.map { |c| (c / @tol).floor }
      end

      def node_for(pt)
        cx, cy, cz = cell(pt)
        [-1, 0, 1].each do |dx|
          [-1, 0, 1].each do |dy|
            [-1, 0, 1].each do |dz|
              (@grid[[cx + dx, cy + dy, cz + dz]] || []).each do |n|
                return n if Vec.dist(@nodes[n][:pt], pt) <= @tol
              end
            end
          end
        end
        idx = @nodes.size
        @nodes << { pt: pt, arms: [] }
        (@grid[[cx, cy, cz]] ||= []) << idx
        idx
      end

      def other(edge_id, node)
        i, j = @edges[edge_id]
        i == node ? j : i
      end

      # Unit direction from node along an edge.
      def arm_dir(node, edge_id)
        Vec.unit(Vec.sub(@nodes[other(edge_id, node)][:pt], @nodes[node][:pt]))
      end

      # ---------- 2. classify ----------

      def classify_nodes
        @nodes.each_with_index do |n, idx|
          arms = n[:arms]
          n[:kind] =
            case arms.size
            when 0 then :isolated
            when 1 then :end
            when 2 then classify_two(idx, arms)
            when 3 then classify_three(idx, arms)
            when 4 then :cross
            else
              warn_at(n[:pt], "จุดต่อ #{arms.size} ทาง ไม่มีข้อต่อมาตรฐาน – ใช้ header/manifold " \
                              "(#{arms.size}-way junction, use a header)")
              :manifold
            end
        end
      end

      def classify_two(idx, arms)
        d1 = arm_dir(idx, arms[0])
        d2 = arm_dir(idx, arms[1])
        # deflection = angle between incoming and outgoing flow directions
        defl = deg(Vec.angle(Vec.scale(d1, -1.0), d2))
        n = @nodes[idx]
        n[:deflection] = defl
        if defl < STRAIGHT_TOL_DEG
          :pass
        elsif defl <= CURVE_MAX_DEG && smooth?(n[:pt])
          :curve
        elsif defl > FOLD_TOL_DEG
          warn_at(n[:pt], 'ท่อพับกลับ 180° ไม่สามารถใส่ข้องอได้ (pipe folds back on itself)')
          :mitre
        else
          :elbow
        end
      end

      def smooth?(pt)
        @smooth.any? { |p| Vec.dist(p, pt) <= @tol }
      end

      # Vertices of exploded arcs: FACETED_MIN or more 2-arm vertices in a
      # row, each turning 0.5–15°, joined by chords of similar length (max /
      # min ≤ 2). Deliberate small bends (an 11.25° pair) are never three in
      # a row at equal spacing.
      def faceted_points
        shallow = {}
        @nodes.each_with_index do |n, idx|
          next unless n[:arms].size == 2

          d1 = arm_dir(idx, n[:arms][0])
          d2 = arm_dir(idx, n[:arms][1])
          defl = deg(Vec.angle(Vec.scale(d1, -1.0), d2))
          shallow[idx] = true if defl >= STRAIGHT_TOL_DEG && defl <= FACETED_MAX_DEG
        end
        seen = {}
        out = []
        shallow.each_key do |start|
          next if seen[start]

          group = [start]
          seen[start] = true
          stack = [start]
          until stack.empty?
            i = stack.pop
            @nodes[i][:arms].each do |e|
              j = other(e, i)
              next unless shallow[j] && !seen[j]

              seen[j] = true
              group << j
              stack << j
            end
          end
          next if group.size < FACETED_MIN

          chords = @edges.select { |i, j| shallow[i] && shallow[j] && group.include?(i) }
                         .map { |i, j| Vec.dist(@nodes[i][:pt], @nodes[j][:pt]) }
          next if chords.empty? || chords.max > 2.0 * chords.min

          out.concat(group.map { |i| @nodes[i][:pt] })
        end
        out
      end

      def classify_three(idx, arms)
        dirs = arms.map { |e| arm_dir(idx, e) }
        # Run = the most opposite pair of arms; branch = the remaining one.
        best = nil
        [[0, 1], [0, 2], [1, 2]].each do |a, b|
          d = Vec.dot(dirs[a], dirs[b])
          best = [a, b, d] if best.nil? || d < best[2]
        end
        a, b, dotp = best
        br = ([0, 1, 2] - [a, b]).first
        n = @nodes[idx]
        n[:run] = [arms[a], arms[b]]
        n[:branch] = arms[br]
        run_defl = deg(Math.acos([[-dotp, 1.0].min, -1.0].max))
        # Angle between the branch and the run axis (90° for a straight tee).
        n[:branch_angle] = deg(Vec.angle(dirs[br], dirs[a]))
        n[:branch_angle] = 180.0 - n[:branch_angle] if n[:branch_angle] > 90.0
        if run_defl > 1.0
          warn_at(n[:pt], "แนวท่อหลักที่ Tee ไม่ตรงกัน (#{run_defl.round(1)}°) " \
                          '(tee run arms are not collinear)')
        end
        (n[:branch_angle] - 90.0).abs <= 1.0 ? :tee : :lateral
      end

      # ---------- 3. chains ----------

      def build_chains
        @chains = []
        used = Array.new(@edges.size, false)
        @nodes.each_with_index do |n, idx|
          next if n[:kind] == :pass

          n[:arms].each do |e|
            next if used[e]

            @chains << walk_chain(idx, e, used)
          end
        end
        # Any edges left belong to a cycle made only of :pass nodes, which is
        # geometrically impossible for straight lines – kept for safety.
        @edges.each_index do |e|
          next if used[e]

          used[e] = true
          i, j = @edges[e]
          @chains << { a: i, b: j, edges: [e] }
        end
        @nodes.each { |n| n[:chains] = [] }
        @chains.each_with_index do |c, ci|
          @nodes[c[:a]][:chains] << [ci, :a]
          @nodes[c[:b]][:chains] << [ci, :b]
        end
      end

      def walk_chain(start, edge, used)
        edges = []
        node = start
        e = edge
        loop do
          used[e] = true
          edges << e
          node = other(e, node)
          n = @nodes[node]
          break unless n[:kind] == :pass

          e = (n[:arms] - [e]).first
          break if e.nil? || used[e]
        end
        { a: start, b: node, edges: edges }
      end

      def chain_len(c)
        Vec.dist(@nodes[c[:a]][:pt], @nodes[c[:b]][:pt])
      end

      # Direction of the chain leaving the node at end +which+.
      def chain_dir(c, which)
        from, to = which == :a ? [c[:a], c[:b]] : [c[:b], c[:a]]
        Vec.unit(Vec.sub(@nodes[to][:pt], @nodes[from][:pt]))
      end

      # ---------- 4. fitting sizes ----------

      def fit_fittings
        @nodes.each do |n|
          n[:radius_type] = @radius_type if n[:kind] == :elbow
        end
        # Each pass downgrades at most one elbow per offending chain, then
        # re-checks – converges in a few passes (each elbow can only go
        # LR → SR → mitre).
        10.times do
          changed = false
          @chains.each do |c|
            changed = true if !fits?(c) && downgrade_elbow(c)
          end
          break unless changed
        end
        # What still does not fit is caused by tees/crosses.
        @chains.each do |c|
          next if fits?(c)

          c[:overlap] = true
          warn_at(@nodes[c[:a]][:pt], "ท่อตรงระหว่างข้อต่อสั้นเกินไป (#{chain_len(c).round} mm) " \
                                      '(pipe between fittings too short)')
        end
      end

      def fits?(c)
        trim(c[:a], c[:edges].first) + trim(c[:b], c[:edges].last) <= chain_len(c) + 1e-6
      end

      # Prefer LR → SR on either end before giving up an elbow to a mitre;
      # when mitring, drop the elbow that consumes the most pipe.
      def downgrade_elbow(c)
        ends = [c[:a], c[:b]].uniq.select { |ni| @nodes[ni][:kind] == :elbow }
        return false if ends.empty?

        lr = ends.find { |ni| @nodes[ni][:radius_type] == :lr && sr_shorter?(@nodes[ni]) }
        if lr
          n = @nodes[lr]
          n[:radius_type] = :sr
          warn_at(n[:pt], 'ระยะท่อสั้นเกินไปสำหรับข้องอ Long Radius – เปลี่ยนเป็น Short Radius ' \
                          '(run too short for LR elbow, using SR)')
        else
          n = @nodes[ends.max_by { |ni| trim(ni) }]
          n[:kind] = :mitre
          warn_at(n[:pt], 'ระยะท่อสั้นเกินไปสำหรับข้องอ – ใช้รอยต่อเฉียง (mitre) ' \
                          'ควรเพิ่มระยะท่อตรง (run too short for any elbow, mitre used)')
        end
        true
      end

      def sr_shorter?(n)
        lr = trim_for(n, :lr)
        sr = trim_for(n, :sr)
        sr < lr - 1e-6
      end

      def trim_for(n, type)
        old = n[:radius_type]
        n[:radius_type] = type
        elbow_take(n) || radius(n) * Math.tan(rad(n[:deflection]) / 2.0)
      ensure
        n[:radius_type] = old
      end

      def radius(n)
        n[:radius_type] == :sr ? @r_sr : @r_lr
      end

      # Take-out of a real elbow for this node, if one is available.
      def elbow_take(n)
        f = @takes[:elbow]
        f && f.call(n[:deflection], n[:radius_type])
      end

      # Length of pipe consumed at a node by its fitting (on arm +edge+).
      def trim(ni, edge = nil)
        n = @nodes[ni]
        case n[:kind]
        when :elbow
          elbow_take(n) || radius(n) * Math.tan(rad(n[:deflection]) / 2.0)
        when :tee
          if @takes[:tee_run] && edge
            n[:branch] == edge ? @takes[:tee_branch] : @takes[:tee_run]
          else
            @tee_c
          end
        when :lateral, :cross, :manifold
          @tee_c
        else
          0.0
        end
      end

      # ---------- 5. emit ----------

      def emit
        bent = {}
        @chains.each_with_index do |c, ci|
          pa = @nodes[c[:a]][:pt]
          pb = @nodes[c[:b]][:pt]
          dir = Vec.unit(Vec.sub(pb, pa))
          ta = trim(c[:a], c[:edges].first)
          tb = trim(c[:b], c[:edges].last)
          len = chain_len(c)
          if c[:overlap]
            # Split what is available proportionally so geometry stays valid.
            scale = len / (ta + tb)
            ta *= scale
            tb *= scale
          end
          s = Vec.add(pa, Vec.scale(dir, ta))
          e = Vec.sub(pb, Vec.scale(dir, tb))
          if @nodes[c[:a]][:kind] == :curve || @nodes[c[:b]][:kind] == :curve
            bent[ci] = [s, e]
            next
          end
          plen = Vec.dist(s, e)
          next if plen < 0.5

          @pieces << Piece.new(:pipe, { from: s, to: e, length: plen, dir: dir })
        end
        emit_curves(bent)

        @nodes.each_with_index do |n, idx|
          case n[:kind]
          when :elbow then @pieces << elbow_piece(idx)
          when :tee, :lateral, :cross, :manifold then @pieces << branch_piece(idx)
          when :mitre
            @pieces << Piece.new(:mitre, { at: n[:pt], angle: (n[:deflection] || 0.0).round(1) })
          when :end
            @pieces << Piece.new(:end, { at: n[:pt], dir: Vec.scale(arm_dir(idx, n[:arms][0]), -1.0) })
          end
        end
      end

      # Chains meeting at :curve nodes, walked end to end into one bent
      # pipe each: { points:, length:, radius: (tightest), angle_deg: }.
      def emit_curves(bent)
        done = {}
        starts = bent.keys.flat_map do |ci|
          c = @chains[ci]
          %i[a b].reject { |w| @nodes[c[w]][:kind] == :curve }.map { |w| [ci, w] }
        end
        # a closed ring has no free end – start anywhere
        starts += bent.keys.map { |ci| [ci, :a] }
        starts.each do |ci0, from0|
          next if done[ci0]

          pts = []
          turns = []
          ci = ci0
          from = from0
          loop do
            done[ci] = true
            s, e = bent[ci]
            c = @chains[ci]
            seg = from == :a ? [s, e] : [e, s]
            pts << seg[0] if pts.empty?
            pts << seg[1]
            arrive = from == :a ? :b : :a
            ni = c[arrive]
            n = @nodes[ni]
            break unless n[:kind] == :curve

            nxt = n[:chains].find { |cj, w| [cj, w] != [ci, arrive] }
            break if nxt.nil? || done[nxt[0]] || !bent.key?(nxt[0])

            lens = [chain_len(c), chain_len(@chains[nxt[0]])]
            turns << [n[:deflection], lens.min]
            ci, from = nxt
          end
          # drop points closer than 0.5 mm (a chain trimmed to nothing); the
          # ends stay exact
          kept = [pts.first]
          pts[1..].each { |p| kept << p if Vec.dist(p, kept.last) >= 0.5 }
          kept[-1] = pts.last if kept.size > 1
          pts = kept
          next if pts.size < 2

          length = pts.each_cons(2).sum { |p, q| Vec.dist(p, q) }
          next if length < 0.5

          radius = turns.map { |d, l| l / (2.0 * Math.sin(rad(d) / 2.0)) }.min || 0.0
          @pieces << Piece.new(:curve, { points: pts, length: length, radius: radius,
                                         angle_deg: turns.sum(&:first).round(1) })
        end
      end

      def elbow_piece(idx)
        n = @nodes[idx]
        v = n[:pt]
        d_in = Vec.scale(arm_dir(idx, n[:arms][0]), -1.0) # flow toward node
        d_out = arm_dir(idx, n[:arms][1])                 # flow away from node
        theta = rad(n[:deflection])
        take = elbow_take(n)
        r = take ? take / Math.tan(theta / 2.0) : radius(n)
        t = take || r * Math.tan(theta / 2.0)
        t1 = Vec.sub(v, Vec.scale(d_in, t))
        t2 = Vec.add(v, Vec.scale(d_out, t))
        # In-plane normal from t1 toward the bend centre.
        n1 = Vec.unit(Vec.sub(d_out, Vec.scale(d_in, Vec.dot(d_in, d_out))))
        center = Vec.add(t1, Vec.scale(n1, r))
        normal = Vec.unit(Vec.cross(d_in, d_out))
        xaxis = Vec.unit(Vec.sub(t1, center))
        Piece.new(:elbow, {
                    vertex: v, start: t1, end: t2, center: center, radius: r,
                    angle: theta, angle_deg: n[:deflection].round(2),
                    normal: normal, xaxis: xaxis, dir_in: d_in, dir_out: d_out,
                    radius_type: n[:radius_type], nominal_angle: nominal_angle(n[:deflection])
                  })
      end

      def branch_piece(idx)
        n = @nodes[idx]
        dirs = n[:arms].map { |e| arm_dir(idx, e) }
        data = { center: n[:pt], arms: dirs, c: @tee_c, kind: n[:kind] }
        if n[:kind] == :tee && @takes[:tee_run]
          data[:c] = @takes[:tee_run]
          data[:c_branch] = @takes[:tee_branch]
        end
        if n[:kind] == :tee || n[:kind] == :lateral
          data[:run] = n[:run].map { |e| arm_dir(idx, e) }
          data[:branch] = arm_dir(idx, n[:branch])
          data[:branch_angle] = n[:branch_angle].round(1)
        end
        Piece.new(n[:kind], data)
      end

      # Standard elbow angle a fitting would be ordered as.
      def nominal_angle(defl)
        [90.0, 45.0, 22.5, 11.25].each { |a| return a if (defl - a).abs <= 1.0 }
        nil
      end

      def warn_at(pt, msg)
        @warnings << "#{msg} @ (#{pt.map { |c| c.round }.join(', ')}) mm"
      end

      def deg(r)
        r * 180.0 / Math::PI
      end

      def rad(d)
        d * Math::PI / 180.0
      end
    end
  end
end
