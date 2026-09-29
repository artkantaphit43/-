# frozen_string_literal: true

module ArtK
  module PlantPipe
    # Minimal 3D vector maths on plain [x, y, z] arrays (millimetres).
    #
    # The engineering core (network solver, hydraulics, BOM) deliberately does
    # not depend on SketchUp's Geom module so it can be unit-tested with plain
    # Ruby outside SketchUp. The SketchUp layer converts at the boundary.
    module Vec
      module_function

      def add(a, b)
        [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
      end

      def sub(a, b)
        [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
      end

      def scale(a, s)
        [a[0] * s, a[1] * s, a[2] * s]
      end

      def dot(a, b)
        a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
      end

      def cross(a, b)
        [a[1] * b[2] - a[2] * b[1],
         a[2] * b[0] - a[0] * b[2],
         a[0] * b[1] - a[1] * b[0]]
      end

      def length(a)
        Math.sqrt(dot(a, a))
      end

      def dist(a, b)
        length(sub(a, b))
      end

      def unit(a)
        l = length(a)
        raise ArgumentError, 'zero-length vector' if l < 1e-9

        scale(a, 1.0 / l)
      end

      # Angle between two vectors in radians, clamped for numeric safety.
      def angle(a, b)
        c = dot(unit(a), unit(b))
        c = 1.0 if c > 1.0
        c = -1.0 if c < -1.0
        Math.acos(c)
      end

      def lerp(a, b, t)
        add(a, scale(sub(b, a), t))
      end

      def near?(a, b, tol = 1e-6)
        dist(a, b) <= tol
      end

      # Any unit vector perpendicular to +a+.
      def perpendicular(a)
        u = unit(a)
        ref = u[2].abs < 0.9 ? [0.0, 0.0, 1.0] : [1.0, 0.0, 0.0]
        unit(cross(u, ref))
      end

      # Rotate vector +v+ about unit axis +k+ by +ang+ radians (Rodrigues).
      def rotate(v, k, ang)
        k = unit(k)
        c = Math.cos(ang)
        s = Math.sin(ang)
        add(add(scale(v, c), scale(cross(k, v), s)), scale(k, dot(k, v) * (1 - c)))
      end
    end
  end
end
