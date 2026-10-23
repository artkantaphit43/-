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
        col = extent(model, face, x, y, Generic.face_of(w[:path]), skip: skip)
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

        hang?(t, opts) ? hang_frame(model, t, pl, opts) : pl
      end

      ISO_GAP = 20.0 # C / D hung: off the (Iso) wall

      # C / D hung from the round member above (setting hang_cd: an Iso wall
      # nothing may be fixed to)?
      def hang?(t, opts)
        Std.type(t)[:form] == :frame && (opts['hang_cd'] || opts[:hang_cd]) ? true : false
      end

      # The frame as placed, hung from the round member over it (across
      # the pipes – found by rays up from its top, ±0.6 m along the pipes):
      # moved along the pipes onto its axis, ISO_GAP off the wall, two pipe
      # shoes on its top member; noted when the member does not reach them.
      def hang_frame(model, t, pl, opts)
        s = Std.type(t)
        x = pl[:x]
        y = pl[:y]
        zt = Std.top_level(s)
        mid = Vec.along(pl[:origin], y, s[:width] / 2.0)
        c = Probe.above(model, mid, x, zt + 10.0)
        unless c && c[:kind] == :round
          raise 'ไม่พบท่อกลมเหนือซัพพอร์ตที่จะแขวน (โหมดแขวนท่อกลม) – ปิดโหมดนี้ (Alt) เพื่อยึดเสา/ผนังด้วยพุก'
        end

        origin = Vec.along(Vec.along(pl[:origin], x, c[:x]), y, ISO_GAP)
        pipes = section(model, origin, x, y, pl[:hit][:src] == 'generic' ? pl[:hit] : nil)
        struct = pl[:struct].merge(hang: { z: c[:z], r: c[:r] })
        out = plan(t, origin, x, y, pipes, opts, pl[:hit], struct)
        under = origin[2] + c[:z] - c[:r]
        [Std::PSHOE[:at], s[:width] - Std::PSHOE[:at]].each do |sy|
          start = Vec.add(Vec.along(origin, y, sy), [0.0, 0.0, zt + 10.0])
          h = Probe.cast(model, start, UP, max: 4000.0)
          next if h && (h[:point][2] - under).abs <= 30.0

          out[:result].notes << "ท่อกลมด้านบนไม่ถึง pipe shoe ที่ #{(sy / 1000.0).round(2)} ม. – ตรวจตำแหน่ง/ความยาวท่อกลม"
        end
        out
      end

      # Click on a column / wall face at the level the pipes sit on – the
      # lock point: the inner corner of the steel at the column (arm top /
      # top of a frame's bottom member), the pipes' undersides; 2.0.2–2.0.7
      # took the support's top. normal: the face's (world); eye: the camera,
      # to know its front. Pipes passing there – any number – get U-bolts.
      # face: [face, transformation] when known – its own outline gives the
      # column's width (a click on its edge / corner still centres).
      def from_face(model, t, point, normal, eye, opts = {}, face: nil)
        raise 'คลิกที่ผิวด้านข้างของเสา/ผนัง (vertical face)' if normal[2].abs > 0.3

        y = Vec.horizontal(normal)
        y = Vec.scale(y, -1.0) if eye && Vec.dot(y, Vec.sub(eye, point)).negative?
        x = Vec.cross(y, UP)
        col = extent(model, point, x, y, face)
        origin = Vec.along(point, x, centre(col))
        pipes = section(model, origin, x, y, nil)
        pl = plan(t, origin, x, y, pipes, opts, nil, { face: 0.0, column: column(col) })
        hang?(t, opts) ? hang_frame(model, t, pl, opts) : pl
      end

      # Rebuild a placed support where it is (fixed to the column at the
      # level placed – it never moves), for the pipes there now.
      def refit_plan(model, g)
        t = g.get_attribute(H::DICT, 'detail')
        origin = H.get_json(g, 'origin')
        x = H.get_json(g, 'xdir')
        y = H.get_json(g, 'ydir')
        ref = H.get_json(g, 'ref', {})
        hit = ref['src'] == 'generic' ? { src: 'generic' } : nil
        pipes = section(model, origin, x, y, hit, min_y: Std.type(t)[:form] == :rod ? -Float::INFINITY : -50.0)
        plan(t, origin, x, y, pipes, H.get_json(g, 'opts', {}), hit, H.get_json(g, 'struct', {}))
      end

      def plan(t, origin, x, y, pipes, opts, hit, struct)
        res = Std.build(t, pipes, opts, struct)
        { detail: t, origin: origin, x: x, y: y, result: res, struct: struct, opts: opts,
          hit: hit || { src: 'face', dir: x } }
      end

      # Pipes crossing the support's plane, from the face (y) and the given
      # level (z): Plant Piping's, and round ones found by rays.
      def section(model, origin, x, y, hit, min_y: -50.0)
        list = Link.pipes_across(model, origin, x, reach: 1500.0, rise: WINDOW + 600.0)
        list = list.select { |p| p[:y] > min_y }
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

      # The column face's extent along x from face_pt: from the face's own
      # vertices when we have it ([face, transformation]), else by rays.
      def extent(model, face_pt, x, y, face, skip: [])
        return span(model, face_pt, x, y, skip: skip) unless face && face[0].respond_to?(:vertices)

        f, tr = face
        s = f.vertices.map { |v| Vec.dot(Vec.sub(H.transform_mm(tr, H.from_pt(v.position)), face_pt), x) }
        lo, hi = s.minmax
        return span(model, face_pt, x, y, skip: skip) unless lo && lo < hi && lo <= 1.0 && hi >= -1.0

        [lo, hi]
      end

      # Extent of the face along x from face_pt by rays: [lo, hi] (mm) or
      # nil. Picked right on an edge the first ray may miss – a few mm in
      # either way is tried.
      def span(model, face_pt, x, y, skip: [])
        front = Vec.along(face_pt, y, FRONT)
        on = lambda do |s|
          h = Probe.cast(model, Vec.along(front, x, s), Vec.scale(y, -1.0), max: FRONT + 40.0, skip: skip)
          h && (h[:dist] - FRONT).abs < 12.0
        end
        s0 = [0.0, 10.0, -10.0, 30.0, -30.0].find { |s| on.call(s) }
        return nil unless s0

        [-1, 1].map do |k|
          lo = k.positive? ? [s0, 0.0].max : [-s0, 0.0].max
          lo += 25.0 while lo < 1600.0 && on.call(k * (lo + 25.0))
          hi = lo + 25.0
          6.times do
            m = (lo + hi) / 2.0
            on.call(k * m) ? lo = m : hi = m
          end
          k * lo
        end.sort
      end

      # ---------- E: hung from a round member ----------

      # E from a Plant Piping pipe under a round member: centred on that
      # member's axis (found by rays – no need to pick its centre), across
      # the pipes of the tier(s) there, its bottom member level with the
      # lowest pipe's underside; pipes stacked above get the upper tier.
      # right: the camera's right (the member's end on the left as seen).
      def from_pipe_hanger(model, t, hit, opts, right: nil)
        raise 'ท่อแนวตั้ง – ใช้ riser clamp ที่ระดับพื้น' if hit[:dir][2].abs > 0.5

        s = Std.type(t)
        x = Vec.horizontal(hit[:dir])
        x = Vec.scale(x, -1.0) if right && Vec.dot(Vec.cross(UP, x), right).negative?
        y = Vec.cross(UP, x)
        o = hit[:point]
        skip = hit[:cyl] ? [hit[:cyl]] : []
        c = Probe.above(model, o, x, (hit[:pipe] ? hit[:pipe][:r].to_f : 0.0) + 5.0, skip: skip)
        raise 'ไม่พบท่อกลมด้านบนที่จะแขวน (เหนือท่อ ±0.6 ม. ตามแนวท่อ)' unless c && c[:kind] == :round

        centre = Vec.along(o, x, c[:x])
        lo, hi = Std.bearing(s)
        list = section(model, centre, x, y, hit, min_y: -Float::INFINITY)
        me = list.min_by { |p| p[:y].abs + p[:z].abs }
        under = list.select do |p|
          (p[:y] - me[:y]).abs <= hi - lo && p[:z] + p[:r] + 15.0 < c[:z] - c[:r]
        end
        tiers = stacks(under)
        i = tiers.index { |tr| tr.include?(me) } or raise 'ท่อที่ชี้อยู่สูงเกินท่อกลมด้านบน'
        pick = if tiers.size < 2 then [tiers[i]]
               elsif i.zero? then tiers[0, 2]
               else tiers[i - 1, 2]
               end
        bop = pick.first.map { |p| Pipes.bottom(p) }.min
        gap = pick[1] ? pick[1].map { |p| Pipes.bottom(p) }.min - bop : (s[:tiers] == 2 ? s[:gap] : nil)
        y0 = window(pick.flatten, me, lo, hi)
        origin = Vec.add(Vec.along(centre, y, y0), [0.0, 0.0, bop])
        pipes = list.map { |p| p.merge(y: p[:y] - y0, z: p[:z] - bop) }
        pl = plan(t, origin, x, y, pipes, opts, hit, { chord: { z: c[:z] - bop, r: c[:r] }, gap: gap })
        mine = pl[:result].carried.any? { |p| (p[:y] - (me[:y] - y0)).abs < 1.0 && (p[:z] - (me[:z] - bop)).abs < 1.0 }
        raise "ท่อ #{me[:label]} ไม่อยู่ในตำแหน่งที่ซัพพอร์ต #{t} รับได้" unless mine

        rods_hung(model, pl)
      end

      # F from a pipe under a round member: the cradle on that member's
      # axis (found by rays – along the pipe over it, or across it), the
      # pipe in its clamp; the origin under the axis at the pipe's
      # underside.
      def from_pipe_rod(model, t, hit, opts)
        raise 'ท่อแนวตั้ง – ใช้ riser clamp ที่ระดับพื้น' if hit[:dir][2].abs > 0.5

        x = Vec.horizontal(hit[:dir])
        y = Vec.cross(UP, x)
        o = hit[:point]
        skip = hit[:cyl] ? [hit[:cyl]] : []
        r = hit[:pipe] ? hit[:pipe][:r].to_f : 0.0
        if (c = Probe.over(model, o, y, r + 5.0, skip: skip))
          origin = Vec.add(Vec.along(o, y, c[:y]), [0.0, 0.0, -r])
          chord = { z: c[:z] + r, r: c[:r], along: 'x' }
        elsif (c = Probe.above(model, o, x, r + 5.0, skip: skip)) && c[:kind] == :round
          origin = Vec.add(Vec.along(o, x, c[:x]), [0.0, 0.0, -r])
          chord = { z: c[:z] + r, r: c[:r], along: 'y' }
        else
          raise 'ไม่พบท่อกลมเหนือท่อที่จะแขวน (ตามแนวท่อ ±0.4 ม. / ขวางท่อ ±0.6 ม.)'
        end
        pipes = section(model, origin, x, y, hit, min_y: -Float::INFINITY)
        pl = plan(t, origin, x, y, pipes, opts, hit, { chord: chord })
        me = pl[:result].carried.first
        unless me && (me[:z] - r).abs < 1.0 && me[:y].abs <= 250.0
          raise "ท่อ #{hit[:pipe] && hit[:pipe][:label]} อยู่ใกล้ท่อกลมเกินไป / ไม่อยู่ใต้ท่อกลม"
        end

        pl
      end

      # F without pipes: hung from the clicked round member, the pipe (to
      # be drawn) under it along it, its underside at world z +bop+.
      def from_chord_rod(model, t, chord, at, bop, opts)
        ax = Vec.unit(chord[:axis])
        raise 'ท่อกลมที่จะแขวนต้องวางแนวนอน' if ax[2].abs > 0.2

        x = Vec.horizontal(ax)
        y = Vec.cross(UP, x)
        c = Vec.add(chord[:point], Vec.scale(ax, Vec.dot(Vec.sub(at, chord[:point]), ax)))
        geo = { chord: { z: c[2] - bop, r: chord[:radius], along: 'x' } }
        need = Std.rod_geo(geo)[:r] + 60.0 + 2.0 * Std.nominal(t).first[:r] + Std.clamp_ear(Std.nominal(t).first) + 80.0
        raise "ระดับท้องท่อสูงเกินไป – ใต้ท่อกลมต้องสูงกว่าท้องท่ออย่างน้อย #{need.round} มม." if c[2] - bop < need

        origin = [c[0], c[1], bop]
        pipes = section(model, origin, x, y, nil, min_y: -Float::INFINITY)
        plan(t, origin, x, y, pipes, opts, { src: 'chord', dir: x }, geo)
      end

      # G from a pipe along a wall / beam: the face beside it above it (the
      # lowest height over the pipe where the face takes the post – rays
      # across), centred on a column; the arm out to the rod over the pipe.
      def from_pipe_angle(model, t, hit, opts)
        raise 'ท่อแนวตั้ง – ใช้ riser clamp ที่ระดับพื้น' if hit[:dir][2].abs > 0.5

        x = Vec.horizontal(hit[:dir])
        y = Vec.cross(UP, x)
        o = hit[:point]
        skip = hit[:cyl] ? [hit[:cyl]] : []
        me = hit[:pipe] || { r: 0.0, od: 0.0 }
        r = me[:r].to_f
        start = r + Std.clamp_ear(me.merge(od: me[:od].to_f)) + 200.0
        w = nil
        dz = start
        while dz <= start + 2500.0
          a = Probe.wall(model, Vec.add(o, [0.0, 0.0, dz + 20.0]), y, skip: skip)
          b = a && a[:dist] <= Std::ARM_MAX + 300.0 && Probe.wall(model, Vec.add(o, [0.0, 0.0, dz + 230.0]), y, skip: skip)
          if b && b[:side] == a[:side] && (b[:dist] - a[:dist]).abs <= 15.0
            w = a.merge(dz: dz)
            break
          end
          dz += 25.0
        end
        raise 'ไม่พบผนัง/คานข้างท่อด้านบน (ภายใน 1 ม. จากท่อ)' unless w

        if w[:side].positive? # y out of the face
          x = Vec.scale(x, -1.0)
          y = Vec.scale(y, -1.0)
        end
        face = Vec.add(Vec.along(o, y, -w[:dist]), [0.0, 0.0, w[:dz]])
        col = extent(model, face, x, y, Generic.face_of(w[:path]), skip: skip)
        origin = Vec.add(Vec.along(o, x, centre(col)), [0.0, 0.0, -r])
        pipes = section(model, origin, x, y, hit, min_y: -Float::INFINITY)
        geo = { mount: { z: w[:dz] + r, face: -w[:dist] }, face: w[:dist].round(1), column: column(col) }
        pl = plan(t, origin, x, y, pipes, opts, hit, geo)
        mine = pl[:result].carried.first
        raise "ท่อ #{me[:label]} ไม่อยู่ใต้แขนเหล็กฉาก" unless mine && mine[:y].abs < 1.0 && (mine[:z] - r).abs < 1.0

        pl
      end

      # G by a click on the face at the level of the arm's top (the lock
      # point): centred on a column; the pipe under it (the nearest below
      # the arm, out from the face) or, none yet, a 4" 0.25 out and 0.40
      # under the arm (pipes drawn later go there: its guide).
      def from_face_angle(model, t, point, normal, eye, opts = {}, face: nil)
        raise 'คลิกที่ผิวด้านข้างของผนัง/คาน/เสา (vertical face)' if normal[2].abs > 0.3

        y = Vec.horizontal(normal)
        y = Vec.scale(y, -1.0) if eye && Vec.dot(y, Vec.sub(eye, point)).negative?
        x = Vec.cross(y, UP)
        col = extent(model, point, x, y, face)
        at = Vec.along(point, x, centre(col))
        under = section(model, at, x, y, nil).select do |p|
          p[:y].between?(p[:r] + 20.0, Std::ARM_MAX) && p[:z] + p[:r] < -Steel.get(Std::ANGLES.last)[:a] - 60.0
        end
        me = under.max_by { |p| [p[:z] + p[:r], -p[:y]] }
        yf, bop = me ? [me[:y], Pipes.bottom(me)] : [250.0, -400.0]
        origin = Vec.add(Vec.along(at, y, yf), [0.0, 0.0, bop])
        pipes = section(model, origin, x, y, nil, min_y: -Float::INFINITY)
        plan(t, origin, x, y, pipes, opts, { src: 'face', dir: x },
             { mount: { z: -bop, face: -yf }, face: 0.0, column: column(col) })
      end

      # E hung from the round member +chord+ the user clicked ({ point:,
      # axis:, radius: } – read from its faces), centred on its axis at the
      # point clicked (+at+), the bottom member's top (the pipes'
      # undersides) at world z +bop+.
      def from_chord(model, t, chord, at, bop, opts, right: nil)
        ax = Vec.unit(chord[:axis])
        raise 'ท่อกลมที่จะแขวนต้องวางแนวนอน' if ax[2].abs > 0.2

        s = Std.type(t)
        y = Vec.horizontal(ax)
        y = Vec.scale(y, -1.0) if right && Vec.dot(y, right).negative?
        x = Vec.cross(y, UP)
        c = Vec.add(chord[:point], Vec.scale(ax, Vec.dot(Vec.sub(at, chord[:point]), ax)))
        gap = s[:tiers] == 2 ? s[:gap] : nil
        drop = c[2] - chord[:radius] - bop - (gap || 0.0)
        if drop < Std.min_drop
          raise "ระดับท้องท่อสูงเกินไป – ใต้ท่อกลมต้องสูงกว่าคาน#{gap ? 'บน' : ''} อย่างน้อย #{Std.min_drop.round} มม."
        end

        origin = Vec.add(Vec.along([c[0], c[1], 0.0], y, -s[:length] / 2.0), [0.0, 0.0, bop])
        pipes = section(model, origin, x, y, nil)
        pl = plan(t, origin, x, y, pipes, opts, { src: 'chord', dir: x },
                  { chord: { z: c[2] - bop, r: chord[:radius] }, gap: gap })
        return pl unless chord[:length] # a Plant Piping pipe: its extent is not known here

        s[:rods].each do |ry|
          along = Vec.dot(Vec.sub(Vec.along(origin, y, ry), chord[:point]), ax)
          next if along.between?(-5.0, chord[:length] + 5.0)

          pl[:result].notes << "ท่อกลมด้านบนไม่ถึงเหล็กเส้นที่ #{(ry / 1000.0).round(2)} ม. – ตรวจตำแหน่ง/ความยาวท่อกลม"
        end
        pl
      end

      # Pipes in tiers, bottom up: one above all of a tier's pipes starts
      # the next.
      def stacks(pipes)
        pipes.sort_by { |p| Pipes.bottom(p) }.each_with_object([]) do |p, out|
          if out.empty? || Pipes.bottom(p) > out.last.map { |q| Pipes.top(q) }.max
            out << [p]
          else
            out.last << p
          end
        end
      end

      # Where E's y = 0 goes (from the centre) so the pipes there lie
      # between the rods: centred on them; too wide – the clicked pipe's
      # nearest neighbours that fit.
      def window(pipes, me, lo, hi)
        span = ->(list) { [list.map { |q| q[:y] - Std.side(q) }.min, list.map { |q| q[:y] + Std.side(q) }.max] }
        take = []
        pipes.sort_by { |p| (p[:y] - me[:y]).abs }.each do |p|
          a, b = span.call(take + [p])
          take << p if b - a <= hi - lo
        end
        take = [me] if take.empty?
        a, b = span.call(take)
        (a + b) / 2.0 - (lo + hi) / 2.0
      end

      # The round member over both rods? (rays up from the top tier) –
      # noted when not.
      def rods_hung(model, pl)
        res = pl[:result]
        geo = Std.hanger_geo(pl[:detail], pl[:struct])
        under = pl[:origin][2] + geo[:chord][:z] - geo[:chord][:r]
        from = pl[:origin][2] + Std.levels(pl[:detail], pl[:struct]).last + 10.0
        Std.type(pl[:detail])[:rods].each do |ry|
          start = Vec.add(Vec.along(pl[:origin], pl[:y], ry), [0.0, 0.0, from - pl[:origin][2]])
          h = Probe.cast(model, start, UP, max: 4000.0)
          next if h && (h[:point][2] - under).abs <= 30.0

          res.notes << "ท่อกลมด้านบนไม่อยู่เหนือเหล็กเส้นที่ #{(ry / 1000.0).round(2)} ม. – ตรวจตำแหน่ง/ความยาวท่อกลม"
        end
        pl
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
