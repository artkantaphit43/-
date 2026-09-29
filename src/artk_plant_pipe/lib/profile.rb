# frozen_string_literal: true

require_relative 'vec'

module ArtK
  module PlantPipe
    # Vertical profile analysis of a centreline network.
    #
    # Finds trapped low points and high points independent of the direction
    # the lines were drawn in. A "plateau" (nodes joined by level pipe) is a
    # low point when every pipe leaving it goes up, and a high point when
    # every pipe leaving it goes down. Plateaus containing an open end are
    # ignored – they drain / vent through that end (equipment nozzle).
    #
    # Why it matters in a plant:
    # * liquid lines: high point → air pocket → air release valve (vent);
    #                 low point  → cannot drain → drain valve
    # * steam: low point → condensate pools → drip leg + steam trap
    # * compressed air: low point → condensate → auto drain
    # * gravity drainage: any low point is a sag (blockage), any high point
    #   is a reverse fall – both are defects.
    module Profile
      module_function

      # Returns { low: [[x,y,z], ...], high: [...], slopes: [% per non-vertical segment] }
      def analyse(segments, tol: 1.0, level_tol: 1.0)
        nodes = []
        find = lambda do |p|
          idx = nodes.index { |n| Vec.dist(n[:pt], p) <= tol }
          unless idx
            idx = nodes.size
            nodes << { pt: p.map(&:to_f), nbrs: [] }
          end
          idx
        end
        slopes = []
        segments.each do |a, b|
          i = find.call(a)
          j = find.call(b)
          next if i == j

          nodes[i][:nbrs] << j unless nodes[i][:nbrs].include?(j)
          nodes[j][:nbrs] << i unless nodes[j][:nbrs].include?(i)
          d = Vec.sub(b, a)
          h = Math.hypot(d[0], d[1])
          slopes << (d[2].abs / h * 100.0) if h >= 1.0 && d[2].abs <= h
        end

        level = ->(i, j) { (nodes[i][:pt][2] - nodes[j][:pt][2]).abs <= level_tol }
        seen = {}
        low = []
        high = []
        nodes.each_index do |start|
          next if seen[start]

          # flood-fill the level plateau
          plateau = [start]
          seen[start] = true
          k = 0
          while k < plateau.size
            nodes[plateau[k]][:nbrs].each do |n|
              next if seen[n] || !level.call(plateau[k], n)

              seen[n] = true
              plateau << n
            end
            k += 1
          end
          next if plateau.any? { |i| nodes[i][:nbrs].size <= 1 } # open end

          z = nodes[start][:pt][2]
          outside = plateau.flat_map { |i| nodes[i][:nbrs] }.uniq - plateau
          next if outside.empty?

          zs = outside.map { |i| nodes[i][:pt][2] }
          pt = centroid(plateau.map { |i| nodes[i][:pt] })
          if zs.all? { |oz| oz > z + level_tol }
            low << pt
          elsif zs.all? { |oz| oz < z - level_tol }
            high << pt
          end
        end
        { low: low, high: high, slopes: slopes }
      end

      # Representative point of a plateau (its centroid).
      def centroid(pts)
        n = pts.size.to_f
        [pts.sum { |p| p[0] } / n, pts.sum { |p| p[1] } / n, pts.first[2]]
      end
    end
  end
end
