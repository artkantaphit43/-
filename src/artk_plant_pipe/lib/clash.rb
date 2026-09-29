# frozen_string_literal: true

require_relative 'vec'

module ArtK
  module PlantPipe
    # Clearance / clash detection between piping runs.
    #
    # Every piece is approximated by capsules (segment + radius): pipes and
    # tee arms exactly, elbows by chords through the arc, valves by their
    # flange diameter. Radius includes insulation, because insulation is
    # what actually clashes on site. Pieces of the same run are never
    # compared with each other (they are connected by design).
    module Clash
      Item = Struct.new(:owner, :label, :a, :b, :r, keyword_init: true)

      module_function

      # connections: [{ owner:, point: [mm], radius: mm }] – zones around
      # intentional connections (branch tees, end-to-end joins) where the
      # connected run legitimately touches others.
      # Returns clashes sorted worst first:
      #   [{ owners: [o1, o2], labels: [l1, l2], gap: mm (negative = overlap),
      #      point: [x,y,z] }]
      # Only the worst location per pair of runs is reported.
      def find(items, clearance: 25.0, connections: [])
        boxes = items.map { |item| aabb(item, clearance) }
        worst = {}
        # Sweep on X to avoid the full O(n²) comparison.
        order = (0...items.size).sort_by { |i| boxes[i][0][0] }
        active = []
        order.each do |i|
          bi = boxes[i]
          active.reject! { |j| boxes[j][1][0] < bi[0][0] }
          active.each do |j|
            a = items[i]
            b = items[j]
            next if a.owner == b.owner
            next unless overlap?(bi, boxes[j])

            d, pa, pb = segment_distance(a.a, a.b, b.a, b.b)
            gap = d - a.r - b.r
            next unless gap < clearance

            mid = Vec.lerp(pa, pb, 0.5)
            next if connections.any? do |c|
              (c[:owner] == a.owner || c[:owner] == b.owner) && Vec.dist(c[:point], mid) <= c[:radius]
            end

            key = [a.owner, b.owner].sort_by(&:to_s)
            next if worst[key] && worst[key][:gap] <= gap

            worst[key] = { owners: key, labels: key == [a.owner, b.owner] ? [a.label, b.label] : [b.label, a.label],
                           gap: gap.round(1), point: mid }
          end
          active << i
        end
        worst.values.sort_by { |c| c[:gap] }
      end

      def aabb(item, pad)
        r = item.r + pad
        lo = [0, 1, 2].map { |k| [item.a[k], item.b[k]].min - r }
        hi = [0, 1, 2].map { |k| [item.a[k], item.b[k]].max + r }
        [lo, hi]
      end

      def overlap?(p, q)
        (0..2).all? { |k| p[0][k] <= q[1][k] && q[0][k] <= p[1][k] }
      end

      # Closest points between segments p1-q1 and p2-q2
      # (Ericson, Real-Time Collision Detection §5.1.9).
      # Returns [distance, point_on_1, point_on_2].
      def segment_distance(p1, q1, p2, q2)
        p1, q1, p2, q2 = [p1, q1, p2, q2].map { |v| v.map(&:to_f) }
        d1 = Vec.sub(q1, p1)
        d2 = Vec.sub(q2, p2)
        r = Vec.sub(p1, p2)
        a = Vec.dot(d1, d1)
        e = Vec.dot(d2, d2)
        f = Vec.dot(d2, r)
        eps = 1e-12
        if a <= eps && e <= eps
          s = t = 0.0
        elsif a <= eps
          s = 0.0
          t = clamp(f / e)
        else
          c = Vec.dot(d1, r)
          if e <= eps
            t = 0.0
            s = clamp(-c / a)
          else
            b = Vec.dot(d1, d2)
            denom = a * e - b * b
            s = denom > eps ? clamp((b * f - c * e) / denom) : 0.0
            t = (b * s + f) / e
            if t < 0.0
              t = 0.0
              s = clamp(-c / a)
            elsif t > 1.0
              t = 1.0
              s = clamp((b - c) / a)
            end
          end
        end
        c1 = Vec.add(p1, Vec.scale(d1, s))
        c2 = Vec.add(p2, Vec.scale(d2, t))
        [Vec.dist(c1, c2), c1, c2]
      end

      def clamp(x)
        return 0.0 if x < 0.0
        return 1.0 if x > 1.0

        x
      end

      # Capsule chords approximating an elbow arc (3 chords per 90°).
      def arc_chords(center, xaxis, normal, radius, angle)
        n = [(angle / (Math::PI / 6.0)).ceil, 1].max
        pts = (0..n).map do |k|
          Vec.add(center, Vec.scale(Vec.rotate(xaxis, normal, angle * k / n), radius))
        end
        pts.each_cons(2).to_a
      end
    end
  end
end
