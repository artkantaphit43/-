# frozen_string_literal: true

require_relative 'vec'

module ArtK
  module SteelSupport
    # Polygon geometry (pure Ruby, mm). Every member, bolt and nut is a
    # closed solid of planar polygons wound outward, handed to SketchUp as
    # one PolygonMesh per material – fast, and testable outside SketchUp
    # (each edge shared by exactly two polygons in opposite directions).
    module Mesh
      TWO_PI = 2.0 * Math::PI
      ROUND = 16 # facets of rods, U-bolts and anchors (soft edges → round)

      class Solid
        attr_reader :polys

        def initialize(polys = [])
          @polys = polys
        end

        def size
          @polys.size
        end
      end

      # Solids by material role (:steel, :galv …), kept apart so each can be
      # validated.
      class Part
        attr_reader :solids

        def initialize
          @solids = []
        end

        def add(role, solid)
          @solids << [role, solid] unless solid.nil? || solid.polys.empty?
          self
        end

        def bodies
          out = Hash.new { |h, k| h[k] = [] }
          @solids.each { |role, s| out[role].concat(s.polys) }
          out
        end

        def points
          @solids.flat_map { |_, s| s.polys.flatten(1) }
        end
      end

      module_function

      # ---------- checks ----------

      def closed?(solid, tol: 1e-4)
        count = Hash.new(0)
        key = ->(p) { p.map { |c| (c / tol).round } }
        solid.polys.each do |poly|
          poly.each_with_index do |p, i|
            q = poly[(i + 1) % poly.size]
            count[[key.call(p), key.call(q)]] += 1
          end
        end
        count.all? { |(a, b), n| n == 1 && count[[b, a]] == 1 }
      end

      def volume(solid)
        v = 0.0
        solid.polys.each do |poly|
          (1...poly.size - 1).each do |i|
            v += Vec.dot(poly[0], Vec.cross(poly[i], poly[i + 1])) / 6.0
          end
        end
        v
      end

      # ---------- 2D ----------

      def cross2(a, b, c)
        (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
      end

      def area2d(poly)
        poly.each_with_index.sum { |p, i| q = poly[(i + 1) % poly.size]; p[0] * q[1] - q[0] * p[1] } / 2.0
      end

      def in_triangle?(p, a, b, c)
        cross2(a, b, p) >= -1e-9 && cross2(b, c, p) >= -1e-9 && cross2(c, a, p) >= -1e-9
      end

      # Ear clipping of a simple counter-clockwise polygon → index triples.
      def triangulate(poly)
        idx = (0...poly.size).to_a
        tris = []
        while idx.size > 3
          n = idx.size
          k = (0...n).find do |j|
            a = poly[idx[j - 1]]
            b = poly[idx[j]]
            c = poly[idx[(j + 1) % n]]
            next false unless cross2(a, b, c) > 1e-9

            others = idx - [idx[j - 1], idx[j], idx[(j + 1) % n]]
            others.none? { |o| in_triangle?(poly[o], a, b, c) }
          end
          k ||= (0...n).max_by { |j| cross2(poly[idx[j - 1]], poly[idx[j]], poly[idx[(j + 1) % n]]) }
          tris << [idx[k - 1], idx[k], idx[(k + 1) % n]]
          idx.delete_at(k)
        end
        tris << idx
        tris
      end

      # Arc points around c from angle a0 to a1 (radians), both ends included.
      def arc2d(c, r, a0, a1, n)
        (0..n).map do |i|
          t = a0 + (a1 - a0) * i / n.to_f
          [c[0] + r * Math.cos(t), c[1] + r * Math.sin(t)]
        end
      end

      # ---------- 3D primitives ----------

      # Prism of a counter-clockwise profile [[u, v]] on axes u, v at o,
      # along a (unit, a = u × v) for len – or between the planes cut0 /
      # cut1 ([point, normal]) when given (mitred / sloped ends).
      def extrude(profile, o, u, v, a, len, cut0: nil, cut1: nil)
        base = profile.map { |pu, pv| Vec.add(o, Vec.add(Vec.scale(u, pu), Vec.scale(v, pv))) }
        p0 = base.map { |b| cut0 ? on_plane(b, a, cut0) : b }
        p1 = base.map { |b| cut1 ? on_plane(b, a, cut1) : Vec.along(b, a, len) }
        polys = []
        triangulate(profile).each do |i, j, k|
          polys << [p1[i], p1[j], p1[k]]
          polys << [p0[k], p0[j], p0[i]]
        end
        n = base.size
        n.times do |i|
          j = (i + 1) % n
          polys << [p0[i], p0[j], p1[j], p1[i]]
        end
        Solid.new(polys)
      end

      def on_plane(b, a, plane)
        pt, nrm = plane
        Vec.along(b, a, Vec.dot(Vec.sub(pt, b), nrm) / Vec.dot(a, nrm))
      end

      # Axis-aligned box from its min / max corners.
      def box(min, max)
        x0, y0, z0 = min
        x1, y1, z1 = max
        prof = [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]
        extrude(prof, [0.0, 0.0, z0], [1.0, 0, 0], [0, 1.0, 0], [0, 0, 1.0], z1 - z0)
      end

      # Round (or n-sided) tube of radius r along the centre points of a
      # path lying in the plane square to +bin+; closed with end caps.
      def tube(pts, bin, r, seg: ROUND)
        bin = Vec.unit(bin)
        n = pts.size
        tan = pts.each_index.map do |i|
          a = pts[[i - 1, 0].max]
          b = pts[[i + 1, n - 1].min]
          Vec.unit(Vec.sub(b, a))
        end
        rings = pts.each_with_index.map do |p, i|
          nrm = Vec.unit(Vec.cross(bin, tan[i]))
          (0...seg).map do |k|
            t = TWO_PI * k / seg
            Vec.add(p, Vec.add(Vec.scale(nrm, r * Math.cos(t)), Vec.scale(bin, r * Math.sin(t))))
          end
        end
        polys = []
        rings.each_cons(2) do |ra, rb|
          seg.times do |k|
            k2 = (k + 1) % seg
            polys << [ra[k], ra[k2], rb[k2], rb[k]]
          end
        end
        polys << rings.first.reverse
        polys << rings.last
        Solid.new(polys)
      end

      def cylinder(a, b, r, seg: ROUND)
        tube([a, b], Vec.perpendicular(Vec.sub(b, a)), r, seg: seg)
      end

      # Hex nut / bolt head: across-flats s, from a to b.
      def hex(a, b, s)
        tube([a, b], Vec.perpendicular(Vec.sub(b, a)), s / Math.sqrt(3.0), seg: 6)
      end
    end
  end
end
