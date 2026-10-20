# frozen_string_literal: true

module ArtK
  module SteelSupport
    # 3D vectors as plain [x, y, z] arrays (mm) – the core is tested
    # outside SketchUp, the SketchUp layer converts at the boundary.
    module Vec
      UP = [0.0, 0.0, 1.0].freeze

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
        [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
      end

      def length(a)
        Math.sqrt(dot(a, a))
      end

      def dist(a, b)
        length(sub(a, b))
      end

      def unit(a)
        l = length(a)
        l < 1e-12 ? [0.0, 0.0, 0.0] : scale(a, 1.0 / l)
      end

      # Sum of a + s·b (a point moved along b).
      def along(a, b, s)
        add(a, scale(b, s))
      end

      def horizontal(a)
        unit([a[0], a[1], 0.0])
      end

      # Any unit vector square to a.
      def perpendicular(a)
        a = unit(a)
        ref = a[2].abs < 0.9 ? UP : [1.0, 0.0, 0.0]
        unit(cross(ref, a))
      end
    end
  end
end
