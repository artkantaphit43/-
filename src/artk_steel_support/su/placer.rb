# frozen_string_literal: true

module ArtK
  module SteelSupport
    # Standard supports A–D on a column: centred on the column face (a face
    # wider than COLUMN_MAX along the pipes is a wall – the support stays
    # where clicked), steel as drawn, U-bolts on the pipes found there.
    module Placer
      UP = Vec::UP
      COLUMN_MAX = 1200.0 # mm
      FRONT = 60.0        # rays for the face's width start this far in front of it
      WINDOW = 900.0      # pipes looked for up / down from the level

      module_function

      def std?(t)
        Std::TYPES.key?(t)
      end

      # Clicked pipe (hit as Planner.plan's) → the support at the column
      # beside it, its steel level with the underside of the lowest pipe.
      def from_pipe(model, t, hit, opts = {})
        raise 'ท่อแนวตั้ง – ใช้ riser clamp ที่ระดับพื้น' if hit[:dir][2].abs > 0.5

        x = Vec.horizontal(hit[:dir])
        y = Vec.cross(UP, x)
        o = hit[:point]
        skip = hit[:cyl] ? [hit[:cyl]] : []
        w = Probe.wall(model, o, y, skip: skip) or
          raise 'ไม่พบเสา/ผนังข้างท่อภายใน 3 m (no column beside the pipe)'
        if w[:side].positive? # y out of the face
          x = Vec.scale(x, -1.0)
          y = Vec.scale(y, -1.0)
        end
        face = Vec.along(o, y, -w[:dist])
        col = span(model, face, x, y, skip: skip)
        sc = centre(col)
        at = Vec.along(face, x, sc)
        list = section(model, at, x, y, hit)
        me = list.min_by { |p| (p[:y] - w[:dist]).abs + p[:z].abs }
        reach = Std.reach(t)
        if me[:y] + me[:r] > reach + 50.0
          raise "ท่ออยู่ห่างหน้าเสา #{(me[:y] - me[:r]).round} มม. – เกินระยะของซัพพอร์ต #{t} (#{reach.round} มม.)"
        end

        below = Std.type(t)[:top] ? 700.0 : Std::RISE
        cb = Pipes.bottom(me)
        foot = list.select { |p| p[:y] - p[:r] < reach && Pipes.bottom(p).between?(cb - below, cb + Std::RISE) }
        level = foot.map { |p| Pipes.bottom(p) }.min
        origin = Vec.add(at, [0, 0, level])
        pipes = list.map { |p| p.merge(z: p[:z] - level) }
        pl = plan(t, origin, x, y, pipes, opts, hit, { face: w[:dist].round(1), column: column(col) })
        mine = pl[:result].carried.any? { |p| (p[:y] - me[:y]).abs < 1.0 && (p[:z] - (me[:z] - level)).abs < 1.0 }
        raise "ท่อ #{me[:label]} อยู่ชิดเสาเกินไป / ไม่อยู่ในตำแหน่งที่ซัพพอร์ต #{t} รับได้" unless mine

        pl
      end

      # Click on a column / wall face at the height of the support's top
      # (arm top / frame top). normal: the face's (world); eye: the camera,
      # to know its front. Pipes passing there – any number – get U-bolts.
      def from_face(model, t, point, normal, eye, opts = {})
        raise 'คลิกที่ผิวด้านข้างของเสา/ผนัง (vertical face)' if normal[2].abs > 0.3

        y = Vec.horizontal(normal)
        y = Vec.scale(y, -1.0) if eye && Vec.dot(y, Vec.sub(eye, point)).negative?
        x = Vec.cross(y, UP)
        col = span(model, point, x, y)
        origin = Vec.add(Vec.along(point, x, centre(col)), [0, 0, -Std.top(t)])
        pipes = section(model, origin, x, y, nil)
        plan(t, origin, x, y, pipes, opts, nil, { face: 0.0, column: column(col) })
      end

      # Rebuild a placed support where it is, for the pipes there now.
      def refit_plan(model, g)
        t = g.get_attribute(H::DICT, 'detail')
        origin = H.get_json(g, 'origin')
        x = H.get_json(g, 'xdir')
        y = H.get_json(g, 'ydir')
        ref = H.get_json(g, 'ref', {})
        hit = ref['src'] == 'generic' ? { src: 'generic' } : nil
        pipes = section(model, origin, x, y, hit)
        plan(t, origin, x, y, pipes, H.get_json(g, 'opts', {}), hit, H.get_json(g, 'struct', {}))
      end

      def plan(t, origin, x, y, pipes, opts, hit, struct)
        res = Std.build(t, pipes, opts)
        { detail: t, origin: origin, x: x, y: y, result: res, struct: struct, opts: opts,
          hit: hit || { src: 'face', dir: x } }
      end

      # Pipes crossing the support's plane, from the face (y) and the given
      # level (z): Plant Piping's, and round ones found by rays.
      def section(model, origin, x, y, hit)
        list = Link.pipes_across(model, origin, x, reach: 1500.0, rise: WINDOW + 600.0)
        list = list.select { |p| p[:y] > -50.0 }
        if (hit && hit[:src] == 'generic') || !Link.available?
          known = list.map { |p| { point: Vec.add(Vec.along(origin, y, p[:y]), [0, 0, p[:z]]), axis: x, radius: p[:r] } }
          known << hit[:cyl] if hit && hit[:cyl]
          Generic.scan(model, Vec.along(origin, y, 5.0), x, y, known: known, reach: 1500.0,
                                                          dz0: -WINDOW, dz1: WINDOW + 600.0).each do |c|
            list << Generic.pipe(c, origin, x, y)
          end
          if hit && hit[:cyl] && list.none? { |p| p[:cyl].equal?(hit[:cyl]) }
            list << Generic.pipe(hit[:cyl], origin, x, y).merge(cyl: hit[:cyl])
          end
        end
        list.uniq { |p| [(p[:y] / 5.0).round, (p[:z] / 5.0).round] }
      end

      # Extent of the face along x from face_pt: [lo, hi] (mm) or nil.
      def span(model, face_pt, x, y, skip: [])
        front = Vec.along(face_pt, y, FRONT)
        on = lambda do |s|
          h = Probe.cast(model, Vec.along(front, x, s), Vec.scale(y, -1.0), max: FRONT + 40.0, skip: skip)
          h && (h[:dist] - FRONT).abs < 12.0
        end
        return nil unless on.call(0.0)

        [-1, 1].map do |k|
          lo = 0.0
          lo += 25.0 while lo < 1600.0 && on.call(k * (lo + 25.0))
          hi = lo + 25.0
          6.times do
            m = (lo + hi) / 2.0
            on.call(k * m) ? lo = m : hi = m
          end
          k * lo
        end.sort
      end

      # Width of a column face (nil: a wall, or not found).
      def column(col)
        col && col[1] - col[0] <= COLUMN_MAX ? (col[1] - col[0]).round : nil
      end

      # Centre of a column face; 0 (where clicked) for a wall or nothing.
      def centre(col)
        return 0.0 unless col && col[1] - col[0] <= COLUMN_MAX

        (col[0] + col[1]) / 2.0
      end
    end
  end
end
