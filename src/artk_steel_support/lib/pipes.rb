# frozen_string_literal: true

require_relative 'vec'

module ArtK
  module SteelSupport
    # Pipes the supports carry: [{ y:, z:, od:, ins:, r:, kg_m:, span_m:,
    # label:, pid: }] in support coordinates (x along the pipes, y across,
    # z up, origin on the clicked pipe's axis). r = od / 2 + insulation.
    module Pipes
      # Steel pipe (ASME B36.10 Sch 40) by nominal size: OD, wall – used to
      # estimate the weight of pipes not drawn with Plant Piping.
      SCH40 = [[21.3, 2.77], [26.7, 2.87], [33.4, 3.38], [42.2, 3.56], [48.3, 3.68], [60.3, 3.91],
               [73.0, 5.16], [88.9, 5.49], [114.3, 6.02], [141.3, 6.55], [168.3, 7.11], [219.1, 8.18],
               [273.1, 9.27], [323.8, 10.31]].freeze
      # MSS SP-69 maximum span of steel pipe, water service (OD mm → m).
      SPAN = [[21.3, 2.1], [33.4, 2.1], [48.3, 2.7], [60.3, 3.0], [88.9, 3.7], [114.3, 4.3],
              [168.3, 5.2], [219.1, 5.8], [273.1, 6.7], [323.8, 7.0]].freeze
      INS_RHO = 60.0 # kg/m³ insulation + jacket
      WIDTH = 2500.0 # mm, widest support

      module_function

      def sch40_wall(od)
        SCH40.min_by { |o, _| (o - od).abs }[1]
      end

      # kg/m of an assumed steel pipe full of water (+ insulation).
      def generic_kg_m(od, ins = 0.0, water: true)
        t = [sch40_wall(od), od / 4.0].min
        steel = Math::PI * t * (od - t) * 7.85e-3
        id = od - 2 * t
        content = water ? Math::PI * id * id / 4.0 * 1e-3 : 0.0
        steel + content + insulation_kg_m(od, ins)
      end

      def insulation_kg_m(od, ins)
        return 0.0 unless ins.to_f.positive?

        Math::PI * ins * (od + ins) * INS_RHO * 1e-6
      end

      def default_span_m(od)
        return SPAN.first[1] if od <= SPAN.first[0]
        return SPAN.last[1] if od >= SPAN.last[0]

        SPAN.each_cons(2) do |(o1, s1), (o2, s2)|
          return s1 + (s2 - s1) * (od - o1) / (o2 - o1) if od.between?(o1, o2)
        end
      end

      # Load one pipe puts on a support (N): its weight over the spacing.
      def load_n(pipe, spacing_m)
        pipe[:kg_m].to_f * spacing_m * 9.81
      end

      # The pipes that share one support with the clicked pipe (y = 0):
      # neighbours along y whose clear gap to the next is ≤ gap and whose
      # underside is within rise of the clicked one's; width limit.
      def group(pipes, gap: 600.0, rise: 300.0, width: WIDTH, below: nil)
        return [] if pipes.empty?

        list = pipes.sort_by { |p| p[:y] }
        i0 = list.index(list.min_by { |p| p[:y].abs + p[:z].abs })
        base = bottom(list[i0])
        below ||= rise
        ok = ->(p) { (bottom(p) - base) <= rise && (base - bottom(p)) <= below }
        out = [list[i0]]
        [1, -1].each do |step|
          k = i0
          last = list[i0]
          loop do
            k += step
            break if k.negative? || k >= list.size

            c = list[k]
            next unless ok.call(c)
            break if (c[:y] - last[:y]).abs - c[:r] - last[:r] > gap

            all = out + [c]
            break if all.map { |p| p[:y] + p[:r] }.max - all.map { |p| p[:y] - p[:r] }.min > width

            out << c
            last = c
          end
        end
        out.sort_by { |p| p[:y] }
      end

      def bottom(p)
        p[:z] - p[:r]
      end

      def top(p)
        p[:z] + p[:r]
      end

      def bare_bottom(p)
        p[:z] - p[:od] / 2.0
      end

      def signature(pipes)
        pipes.map { |p| [p[:y].round, p[:z].round, p[:od].round(1), p[:ins].to_f.round, p[:pid]] }
      end

      # ---------- cylinders from faceted geometry ----------

      # Axis, radius and extent of a (faceted) cylinder from its side
      # faces: normals (unit, outward) and their vertices, world mm.
      # nil when the faces are not one round surface.
      def fit_cylinder(normals, points)
        n0 = normals.first
        other = normals.max_by { |n| Vec.length(Vec.cross(n0, n)) }
        return nil if other.nil? || Vec.length(Vec.cross(n0, other)) < 0.15

        axis = Vec.unit(Vec.cross(n0, other))
        return nil unless normals.all? { |n| Vec.dot(n, axis).abs < 0.08 }

        u = Vec.perpendicular(axis)
        v = Vec.cross(axis, u)
        pts2 = points.map { |p| [Vec.dot(p, u), Vec.dot(p, v)] }
        c = fit_circle(pts2)
        return nil unless c

        cu, cv, r = c
        res = pts2.map { |a, b| (Math.hypot(a - cu, b - cv) - r).abs }.max
        return nil if r < 5.0 || res > [0.04 * r, 2.0].max

        ts = points.map { |p| Vec.dot(p, axis) }
        centre = Vec.add(Vec.scale(u, cu), Vec.scale(v, cv))
        { axis: axis, point: Vec.add(centre, Vec.scale(axis, ts.min)), radius: r,
          length: ts.max - ts.min }
      end

      # Least-squares circle through 2D points: [cx, cy, r] or nil.
      def fit_circle(pts)
        return nil if pts.size < 3

        mx = pts.sum { |p| p[0] } / pts.size
        my = pts.sum { |p| p[1] } / pts.size
        suu = suv = svv = suuu = svvv = suvv = svuu = 0.0
        pts.each do |x, y|
          u = x - mx
          v = y - my
          suu += u * u
          suv += u * v
          svv += v * v
          suuu += u**3
          svvv += v**3
          suvv += u * v * v
          svuu += v * u * u
        end
        det = suu * svv - suv * suv
        return nil if det.abs < 1e-9

        b1 = 0.5 * (suuu + suvv)
        b2 = 0.5 * (svvv + svuu)
        uc = (b1 * svv - b2 * suv) / det
        vc = (suu * b2 - suv * b1) / det
        r = Math.sqrt(uc * uc + vc * vc + (suu + svv) / pts.size)
        [uc + mx, vc + my, r]
      end
    end
  end
end
