# frozen_string_literal: true

module ArtK
  module SteelSupport
    # Statics for the support checks (N, mm, MPa).
    module Beam
      module_function

      # Beam from x0 to x1 on two supports s1 < s2 with point loads
      # [[x, P]] (P downward, N). EI in N·mm². Returns reactions, the
      # largest bending moment (N·mm) and deflection (mm, between and
      # beyond the supports), by numerical integration.
      def two_support(x0, x1, s1, s2, loads, ei, n: 400)
        span = s2 - s1
        raise ArgumentError, 'supports coincide' if span.abs < 1e-6

        total = loads.sum { |_, p| p }
        r2 = loads.sum { |x, p| p * (x - s1) } / span
        r1 = total - r2
        forces = [[s1, -r1], [s2, -r2]] + loads # downward positive
        xs = (0..n).map { |i| x0 + (x1 - x0) * i / n.to_f }
        xs = (xs + loads.map(&:first) + [s1, s2]).select { |x| x.between?(x0, x1) }.uniq.sort
        moment = lambda do |x| # sagging positive
          forces.sum { |fx, p| fx < x ? -p * (x - fx) : 0.0 }
        end
        ms = xs.map { |x| moment.call(x) }
        # slope and deflection by trapezoids, then fit v(s1) = v(s2) = 0
        th = [0.0]
        v = [0.0]
        (1...xs.size).each do |i|
          dx = xs[i] - xs[i - 1]
          th << th[-1] + (ms[i] + ms[i - 1]) / 2.0 * dx / ei
          v << v[-1] + (th[i] + th[i - 1]) / 2.0 * dx
        end
        vi = ->(x) { interp(xs, v, x) }
        k = (vi.call(s2) - vi.call(s1)) / span
        defl = xs.each_with_index.map { |x, i| v[i] - vi.call(s1) - k * (x - s1) }
        { r1: r1, r2: r2, m_max: ms.map(&:abs).max || 0.0, defl: defl.map(&:abs).max || 0.0 }
      end

      def interp(xs, ys, x)
        i = xs.bsearch_index { |q| q >= x } || (xs.size - 1)
        return ys[i] if i.zero? || (xs[i] - x).abs < 1e-9

        t = (x - xs[i - 1]) / (xs[i] - xs[i - 1])
        ys[i - 1] + t * (ys[i] - ys[i - 1])
      end

      # Allowable axial compression (MPa), AISC ASD.
      def fa(kl_r, fy: Steel::FY, e: Steel::E)
        cc = Math.sqrt(2.0 * Math::PI**2 * e / fy)
        if kl_r <= cc
          q = kl_r / cc
          (1.0 - q * q / 2.0) * fy / (5.0 / 3.0 + 3.0 * q / 8.0 - q**3 / 8.0)
        else
          12.0 * Math::PI**2 * e / (23.0 * kl_r**2)
        end
      end

      # Anchor group on a line (heights from the pivot at the bottom of the
      # plate): tension in the most loaded anchor for an overturning
      # moment m (N·mm).
      def anchor_tension(m, heights)
        sum = heights.sum { |h| h * h }
        return 0.0 if sum < 1e-9

        m * heights.max / sum
      end
    end
  end
end
