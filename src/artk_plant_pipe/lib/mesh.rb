# frozen_string_literal: true

require_relative 'vec'

module ArtK
  module PlantPipe
    # Polygon-mesh geometry kernel (pure Ruby, millimetres).
    #
    # Every pipe, fitting, valve and support is generated here as a list of
    # planar convex polygons with outward winding, then handed to SketchUp as
    # a PolygonMesh. Compared with Follow Me / Push-Pull this is:
    # * deterministic – no silent failures on small arcs or tight bends
    #   (the cause of gaps in v1.0)
    # * fast – one mesh call per part instead of hundreds of edge operations
    # * verifiable – tests assert every part is a closed, consistently
    #   oriented solid (each edge shared by exactly two polygons in opposite
    #   directions) and check volumes against formulas.
    module Mesh
      TWO_PI = 2.0 * Math::PI
      EPS = 1e-7

      # A solid is just an array of polygons ([[x,y,z], ...]).
      class Solid
        attr_reader :polys

        def initialize(polys = [])
          @polys = polys
        end

        def add(poly)
          @polys << poly
          self
        end

        def concat(other)
          @polys.concat(other.is_a?(Solid) ? other.polys : other)
          self
        end

        def transform(frame)
          Solid.new(@polys.map { |p| p.map { |q| Mesh.apply(frame, q) } })
        end

        def size
          @polys.size
        end
      end

      # A part is a set of solids keyed by material role
      # (:pipe, :fitting, :valve, :handle, :bolt, :steel, :galv, :concrete ...).
      class Part
        # [[role, Solid], ...] – individual closed solids, kept separate so
        # they can be validated one by one.
        attr_reader :solids

        def initialize
          @solids = []
        end

        def add(role, solid)
          @solids << [role, solid]
          self
        end

        def merge(other, frame = nil)
          other.solids.each { |role, s| add(role, frame ? s.transform(frame) : s) }
          self
        end

        def transform(frame)
          p = Part.new
          @solids.each { |role, s| p.add(role, s.transform(frame)) }
          p
        end

        # role => merged Solid (what SketchUp receives, one mesh per role)
        def bodies
          out = Hash.new { |h, k| h[k] = Solid.new }
          @solids.each { |role, s| out[role].concat(s) }
          out
        end

        def poly_count
          @solids.sum { |_, s| s.size }
        end
      end

      module_function

      # ---------- frames ----------

      # Frame = { o: origin, x:, y:, z: unit axes } (all mm / unit vectors).
      def frame(o, x, y = nil, z = nil)
        x = Vec.unit(x)
        if y.nil?
          y = Vec.perpendicular(x)
        else
          y = Vec.unit(Vec.sub(y, Vec.scale(x, Vec.dot(x, y))))
        end
        z ||= Vec.cross(x, y)
        { o: o.map(&:to_f), x: x, y: y, z: Vec.unit(z) }
      end

      IDENTITY = { o: [0.0, 0.0, 0.0], x: [1.0, 0.0, 0.0], y: [0.0, 1.0, 0.0], z: [0.0, 0.0, 1.0] }.freeze

      def apply(f, p)
        [f[:o][0] + f[:x][0] * p[0] + f[:y][0] * p[1] + f[:z][0] * p[2],
         f[:o][1] + f[:x][1] * p[0] + f[:y][1] * p[1] + f[:z][1] * p[2],
         f[:o][2] + f[:x][2] * p[0] + f[:y][2] * p[1] + f[:z][2] * p[2]]
      end

      # ---------- polygon helpers ----------

      # Newell normal (not normalised).
      def normal(poly)
        n = [0.0, 0.0, 0.0]
        poly.each_with_index do |a, i|
          b = poly[(i + 1) % poly.size]
          n[0] += (a[1] - b[1]) * (a[2] + b[2])
          n[1] += (a[2] - b[2]) * (a[0] + b[0])
          n[2] += (a[0] - b[0]) * (a[1] + b[1])
        end
        n
      end

      def centroid(poly)
        n = poly.size.to_f
        [poly.sum { |p| p[0] } / n, poly.sum { |p| p[1] } / n, poly.sum { |p| p[2] } / n]
      end

      # Orient +poly+ so its normal agrees with +expected+.
      def orient(poly, expected)
        Vec.dot(normal(poly), expected).negative? ? poly.reverse : poly
      end

      # Drop consecutive duplicates (collapses quads on the axis to triangles).
      def clean(poly)
        out = []
        poly.each { |p| out << p if out.empty? || Vec.dist(out.last, p) > 1e-6 }
        out.pop while out.size > 1 && Vec.dist(out.first, out.last) <= 1e-6
        out
      end

      def signed_area(loop2d)
        a = 0.0
        loop2d.each_with_index do |p, i|
          q = loop2d[(i + 1) % loop2d.size]
          a += p[0] * q[1] - q[0] * p[1]
        end
        a / 2.0
      end

      def circle2d(cu, cv, r, n, start = 0.0)
        (0...n).map do |k|
          t = start + TWO_PI * k / n
          [cu + r * Math.cos(t), cv + r * Math.sin(t)]
        end
      end

      # ---------- revolve ----------

      # Revolve closed 2D loops about an axis.
      #   loops – [[u, v], ...] loops; u along the axis, v = distance from it
      #           (v >= 0). The first loop is the outer boundary; any further
      #           loops are holes (e.g. the bore of an elbow section).
      #   axis  – { o:, x: (axis direction), y: (angle-zero direction) }
      #   angle – sweep angle (full turn = closed ring, otherwise capped)
      # Material is kept on the left of each loop: outer CCW, holes CW.
      def revolve(loops, axis_o:, axis:, ref: nil, angle: TWO_PI, steps: 16)
        ax = Vec.unit(axis)
        ref = ref ? Vec.unit(Vec.sub(ref, Vec.scale(ax, Vec.dot(ax, ref)))) : Vec.perpendicular(ax)
        bin = Vec.cross(ax, ref)
        full = angle >= TWO_PI - 1e-9
        nseg = steps
        thetas = (0..nseg).map { |j| angle * j / nseg }

        oriented = loops.each_with_index.map do |lp, i|
          ccw = signed_area(lp).positive?
          want_ccw = i.zero?
          ccw == want_ccw ? lp : lp.reverse
        end

        radial = ->(t) { Vec.add(Vec.scale(ref, Math.cos(t)), Vec.scale(bin, Math.sin(t))) }
        pt = lambda do |u, v, t|
          Vec.add(Vec.add(axis_o, Vec.scale(ax, u)), Vec.scale(radial.call(t), v))
        end

        solid = Solid.new
        oriented.each do |lp|
          lp.each_with_index do |a, i|
            b = lp[(i + 1) % lp.size]
            next if a[1].abs < EPS && b[1].abs < EPS # edge on the axis

            du = b[0] - a[0]
            dv = b[1] - a[1]
            nseg.times do |j|
              t0 = thetas[j]
              t1 = thetas[j + 1]
              poly = clean([pt.call(a[0], a[1], t0), pt.call(b[0], b[1], t0),
                            pt.call(b[0], b[1], t1), pt.call(a[0], a[1], t1)])
              next if poly.size < 3

              tm = (t0 + t1) / 2.0
              expected = Vec.add(Vec.scale(ax, dv), Vec.scale(radial.call(tm), -du))
              solid.add(orient(poly, expected))
            end
          end
        end

        unless full
          # End caps: outer loop, minus a hole if present (paired by index).
          [[0.0, -1.0], [angle, 1.0]].each do |t, sgn|
            tangent = Vec.add(Vec.scale(ref, -Math.sin(t)), Vec.scale(bin, Math.cos(t)))
            expected = Vec.scale(tangent, sgn)
            outer = loops[0].map { |u, v| pt.call(u, v, t) }
            if loops.size == 1
              solid.add(orient(clean(outer), expected))
            else
              inner = loops[1].map { |u, v| pt.call(u, v, t) }
              raise ArgumentError, 'cap loops must have equal point counts' unless inner.size == outer.size

              outer.each_index do |k|
                k2 = (k + 1) % outer.size
                poly = clean([outer[k], outer[k2], inner[k2], inner[k]])
                solid.add(orient(poly, expected)) if poly.size >= 3
              end
            end
          end
        end
        solid
      end

      # ---------- primitives ----------

      # Tube / rod from a to b. ri = inner radius (nil or 0 = solid).
      def cylinder(a, b, ro, ri: nil, steps: 16, ref: nil)
        frustum(a, b, ro, ro, ri1: ri, ri2: ri, steps: steps, ref: ref)
      end

      # Cone frustum (reducers, bonnets, hubs), optionally hollow.
      def frustum(a, b, r1, r2, ri1: nil, ri2: nil, steps: 16, ref: nil)
        len = Vec.dist(a, b)
        raise ArgumentError, 'zero-length cylinder' if len < 1e-6

        i1 = ri1.to_f
        i2 = ri2.to_f
        loop2d = [[0.0, i1], [0.0, r1.to_f], [len, r2.to_f], [len, i2]]
        revolve([loop2d], axis_o: a, axis: Vec.sub(b, a), ref: ref, steps: steps)
      end

      def sphere(c, r, steps: 16)
        half = [(steps / 2), 4].max
        lp = (0..half).map do |k|
          phi = -Math::PI / 2 + Math::PI * k / half
          [r * Math.sin(phi), r * Math.cos(phi)]
        end
        revolve([lp], axis_o: Vec.add(c, [0.0, 0.0, 0.0]), axis: [0.0, 0.0, 1.0], steps: steps)
      end

      # Ring of circular section (handwheel rims, weld beads).
      def torus(c, axis, big_r, small_r, steps: 24, sec_steps: 8)
        lp = circle2d(0.0, big_r, small_r, sec_steps)
        revolve([lp], axis_o: c, axis: axis, steps: steps)
      end

      # Hollow bend: annulus section (od/id) swept about a bend axis.
      #   center – bend centre, xaxis – from centre to the start point,
      #   normal – bend-plane normal, radius – centreline radius.
      def bend(center, xaxis, normal, radius, angle, ro, ri, steps: 16, arc_steps: 8)
        outer = circle2d(0.0, radius, ro, steps)
        loops = [outer]
        loops << circle2d(0.0, radius, ri, steps) if ri && ri.positive?
        revolve(loops, axis_o: center, axis: normal, ref: xaxis, angle: angle, steps: arc_steps)
      end

      # Prism: convex planar polygon extruded by vector.
      def extrude(poly, vec)
        top = poly.map { |p| Vec.add(p, vec) }
        solid = Solid.new
        c = Vec.add(centroid(poly), Vec.scale(vec, 0.5))
        all = [poly, top.reverse]
        poly.each_index do |i|
          j = (i + 1) % poly.size
          all << [poly[i], poly[j], top[j], top[i]]
        end
        all.each { |p| solid.add(orient(p, Vec.sub(centroid(p), c))) }
        solid
      end

      # Axis-aligned box in a frame: centre (local), size [sx, sy, sz].
      def box(f, center, size)
        hx, hy, hz = size.map { |s| s / 2.0 }
        cx, cy, cz = center
        base = [[cx - hx, cy - hy, cz - hz], [cx + hx, cy - hy, cz - hz],
                [cx + hx, cy + hy, cz - hz], [cx - hx, cy + hy, cz - hz]].map { |p| apply(f, p) }
        up = Vec.scale(f[:z], 2.0 * hz)
        extrude(base, up)
      end

      # Box between two points with a square/rect section (struts, braces).
      def bar(a, b, w, h, up = nil)
        x = Vec.unit(Vec.sub(b, a))
        f = frame(a, x, up ? Vec.cross(up, x) : nil)
        len = Vec.dist(a, b)
        box(f, [len / 2.0, 0.0, 0.0], [len, w, h])
      end

      # Regular n-gon prism (hex nuts, union nuts, knurled rings).
      def ngon_prism(a, b, r, n, ref: nil)
        ax = Vec.unit(Vec.sub(b, a))
        ref = ref ? Vec.unit(Vec.sub(ref, Vec.scale(ax, Vec.dot(ax, ref)))) : Vec.perpendicular(ax)
        bin = Vec.cross(ax, ref)
        poly = (0...n).map do |k|
          t = TWO_PI * k / n + Math::PI / n
          Vec.add(a, Vec.add(Vec.scale(ref, r * Math.cos(t)), Vec.scale(bin, r * Math.sin(t))))
        end
        extrude(poly, Vec.sub(b, a))
      end

      # Flat disc/annulus with a circle of bolt holes (flanges).
      # Front face at a, back face at a + axis*thickness.
      # The face is triangulated sector by sector around each hole
      # (each sector is star-shaped about its hole centre), so no polygon
      # has holes and neighbouring sectors share identical boundary points.
      def holed_disc(a, axis, ro, ri, thickness, bolt_circle_r, holes, hole_r, steps: 24, hole_steps: 8, ref: nil)
        ax = Vec.unit(axis)
        ref = ref ? Vec.unit(Vec.sub(ref, Vec.scale(ax, Vec.dot(ax, ref)))) : Vec.perpendicular(ax)
        bin = Vec.cross(ax, ref)
        steps = (steps.to_f / holes).ceil * holes # sector corners on the grid
        per = steps / holes
        p2 = lambda do |x, y, w|
          Vec.add(Vec.add(a, Vec.scale(ax, w)), Vec.add(Vec.scale(ref, x), Vec.scale(bin, y)))
        end
        solid = Solid.new
        faces2d = [] # [[outer boundary 2d], [hole 2d]] per sector
        holes.times do |k|
          j0 = k * per
          outer_arc = (0..per).map do |j|
            t = TWO_PI * (j0 + j) / steps
            [ro * Math.cos(t), ro * Math.sin(t)]
          end
          inner_arc = (0..per).map do |j|
            t = TWO_PI * (j0 + per - j) / steps
            [ri * Math.cos(t), ri * Math.sin(t)]
          end
          boundary = outer_arc + inner_arc # CCW
          hc_t = TWO_PI * (j0 + per / 2.0) / steps
          hc = [bolt_circle_r * Math.cos(hc_t), bolt_circle_r * Math.sin(hc_t)]
          hole = circle2d(hc[0], hc[1], hole_r, hole_steps, hc_t)
          faces2d << [boundary, hole, hc]
        end

        faces2d.each do |boundary, hole, hc|
          tris = star_strip(boundary, hole, hc)
          tris.each do |tri|
            solid.add(orient(tri.map { |x, y| p2.call(x, y, 0.0) }, Vec.scale(ax, -1.0)))
            solid.add(orient(tri.map { |x, y| p2.call(x, y, thickness) }, ax))
          end
          # hole wall (outward from material = towards hole centre)
          hole.each_index do |i|
            q = hole[(i + 1) % hole.size]
            pa = hole[i]
            poly = [p2.call(pa[0], pa[1], 0.0), p2.call(q[0], q[1], 0.0),
                    p2.call(q[0], q[1], thickness), p2.call(pa[0], pa[1], thickness)]
            mid = [(pa[0] + q[0]) / 2.0, (pa[1] + q[1]) / 2.0]
            inward = [hc[0] - mid[0], hc[1] - mid[1]]
            solid.add(orient(poly, Vec.add(Vec.scale(ref, inward[0]), Vec.scale(bin, inward[1]))))
          end
        end
        # rim and bore
        steps.times do |j|
          t0 = TWO_PI * j / steps
          t1 = TWO_PI * (j + 1) / steps
          [[ro, 1.0], [ri, -1.0]].each do |r, sgn|
            next if r < EPS

            poly = [p2.call(r * Math.cos(t0), r * Math.sin(t0), 0.0), p2.call(r * Math.cos(t1), r * Math.sin(t1), 0.0),
                    p2.call(r * Math.cos(t1), r * Math.sin(t1), thickness), p2.call(r * Math.cos(t0), r * Math.sin(t0), thickness)]
            tm = (t0 + t1) / 2.0
            solid.add(orient(poly, Vec.scale(Vec.add(Vec.scale(ref, Math.cos(tm)), Vec.scale(bin, Math.sin(tm))), sgn)))
          end
        end
        solid
      end

      # Triangulate the region between a star-shaped boundary and an inner
      # loop around centre c by merging both loops by polar angle.
      def star_strip(boundary, hole, c)
        ang = ->(p) { Math.atan2(p[1] - c[1], p[0] - c[0]) % TWO_PI }
        sort = lambda do |lp|
          s = lp.each_with_index.min_by { |p, _| ang.call(p) }[1]
          lp.rotate(s)
        end
        b = sort.call(boundary)
        h = sort.call(hole)
        ab = b.map { |p| ang.call(p) }
        ah = h.map { |p| ang.call(p) }
        tris = []
        i = 0
        j = 0
        nb = b.size
        nh = h.size
        while i < nb || j < nh
          bi = b[i % nb]
          hj = h[j % nh]
          next_b = i < nb ? (i + 1 < nb ? ab[i + 1] : ab[0] + TWO_PI) : Float::INFINITY
          next_h = j < nh ? (j + 1 < nh ? ah[j + 1] : ah[0] + TWO_PI) : Float::INFINITY
          if next_b <= next_h
            tris << [bi, b[(i + 1) % nb], hj]
            i += 1
          else
            tris << [bi, h[(j + 1) % nh], hj]
            j += 1
          end
        end
        tris
      end

      # ---------- checks (used by tests) ----------

      # True when every directed edge has exactly one opposite partner:
      # the surface is closed and consistently oriented.
      def closed?(solid, tol: 1e-4)
        key = ->(p) { p.map { |c| (c / tol).round } }
        count = Hash.new(0)
        solid.polys.each do |poly|
          poly.each_with_index do |a, i|
            b = poly[(i + 1) % poly.size]
            count[[key.call(a), key.call(b)]] += 1
          end
        end
        count.all? { |(a, b), n| n == 1 && count[[b, a]] == 1 }
      end

      # Signed volume (divergence theorem); positive = outward normals.
      def volume(solid)
        v = 0.0
        solid.polys.each do |poly|
          (1...poly.size - 1).each do |i|
            v += Vec.dot(poly[0], Vec.cross(poly[i], poly[i + 1])) / 6.0
          end
        end
        v
      end
    end
  end
end
