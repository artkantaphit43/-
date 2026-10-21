# frozen_string_literal: true

module ArtK
  module SteelSupport
    # Finding the structure a support fixes to by ray tests: a wall /
    # column beside the pipes, a truss chord above them, truss chords
    # below them. Rays pass through our supports, Plant Piping's model and
    # the pipes found (skip: cylinders { point:, axis:, radius: }).
    module Probe
      UP = Vec::UP
      DOWN = [0.0, 0.0, -1.0].freeze
      SIDE = 3000.0 # mm, farthest wall

      module_function

      def cast(model, origin, dir, max: SIDE, skip: [])
        pt = origin
        40.times do
          hit = model.raytest([H.to_pt(pt), H.to_vec(dir)], true)
          return nil unless hit

          hp = H.from_pt(hit[0])
          d = Vec.dist(origin, hp)
          return nil if d > max

          path = hit[1] || []
          pass = path.any? { |e| H.ours?(e) || Link.pp_entity?(e) } || in_pipe?(hp, skip)
          return { point: hp, dist: d, path: path } unless pass

          pt = Vec.along(hp, dir, 1.0)
        end
        nil
      end

      def in_pipe?(p, cyls)
        cyls.any? do |c|
          v = Vec.sub(p, c[:point])
          off = Vec.sub(v, Vec.scale(c[:axis], Vec.dot(v, c[:axis])))
          Vec.length(off) <= c[:radius] + 3.0
        end
      end

      # Nearest wall / column face across the pipe: { side: +1 (along y) /
      # −1, dist: } or nil.
      def wall(model, origin, y, skip: [])
        [[y, 1], [Vec.scale(y, -1.0), -1]].filter_map do |v, s|
          h = cast(model, origin, v, skip: skip)
          h && { side: s, dist: h[:dist], path: h[:path] }
        end.min_by { |w| w[:dist] }
      end

      # Heights (relative to origin) of the first structure met by rays
      # along +dir+ from points origin + axis·s + UP·dz.
      def samples(model, origin, axis, dz, from, to, step, dir, skip)
        s = from
        out = []
        while s <= to + 1e-9
          o = Vec.add(Vec.along(origin, axis, s), [0, 0, dz])
          h = cast(model, o, dir, max: 4000.0, skip: skip)
          out << [s, h && h[:point][2] - origin[2]]
          s += step
        end
        out
      end

      # Runs of neighbouring samples on one smooth surface.
      def groups(samples, jump)
        out = []
        cur = []
        samples.each do |s, z|
          if z.nil? || (cur.any? && (z - cur.last[1]).abs > jump)
            out << cur if cur.size > 1
            cur = z.nil? ? [] : [[s, z]]
          else
            cur << [s, z]
          end
        end
        out << cur if cur.size > 1
        out
      end

      # Round member from a run of samples along s: { s:, z:, r: } (centre)
      # or nil when it is not a circle of 8–200 mm radius.
      def circle(group)
        c = Pipes.fit_circle(group)
        return nil unless c

        cs, cz, r = c
        return nil unless r.between?(8.0, 200.0)

        res = group.map { |s, z| (Math.hypot(s - cs, z - cz) - r).abs }.max
        res <= [0.05 * r, 1.5].max ? { s: cs, z: cz, r: r } : nil
      end

      # The truss chord (or soffit) above the pipes near origin: rays up
      # from z_from at offsets along the pipes (x) up to ±range.
      # { kind: :round, x:, z:, r: } (axis across the pipes) or
      # { kind: :flat, x: 0, z: } or nil.
      def above(model, origin, x, z_from, range: 600.0, skip: [])
        coarse = samples(model, origin, x, z_from, -range, range, 10.0, UP, skip)
        hits = coarse.reject { |_, z| z.nil? }
        return nil if hits.empty?

        lo = hits.min_by { |s, z| [z.round, s.abs] }
        fine = samples(model, origin, x, z_from, lo[0] - 60.0, lo[0] + 60.0, 2.0, UP, skip)
        g = groups(fine, 12.0).find { |gg| gg.any? { |s, _| (s - lo[0]).abs < 2.5 } }
        c = g && g.size >= 4 && circle(g)
        return { kind: :round, x: c[:s], z: c[:z], r: c[:r] } if c

        flat = hits.select { |_, z| (z - lo[1]).abs < 2.0 }
        flat.size >= 3 ? { kind: :flat, x: 0.0, z: lo[1] } : nil
      end

      # Round chords along the pipes below them: rays down from z_from at
      # offsets across (y) from y0 to y1. [{ y:, z:, r: }] of the top level.
      def below(model, origin, y, z_from, y0, y1, skip: [])
        coarse = samples(model, origin, y, z_from, y0, y1, 10.0, DOWN, skip)
        found = []
        groups(coarse, 30.0).each do |g|
          next if g.map(&:last).minmax.reduce(:-).abs < 2.0 # flat: a floor, a beam flange

          top = g.max_by { |_, z| z }
          fine = samples(model, origin, y, z_from, top[0] - 60.0, top[0] + 60.0, 2.0, DOWN, skip)
          gg = groups(fine, 12.0).find { |q| q.any? { |s, _| (s - top[0]).abs < 2.5 } }
          c = gg && gg.size >= 4 && circle(gg)
          found << { y: c[:s], z: c[:z], r: c[:r] } if c && found.none? { |f| (f[:y] - c[:s]).abs < 5.0 }
        end
        return [] if found.empty?

        high = found.map { |c| c[:z] + c[:r] }.max
        found.select { |c| high - (c[:z] + c[:r]) <= 100.0 }.sort_by { |c| c[:y] }
      end
    end
  end
end
