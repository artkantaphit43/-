# frozen_string_literal: true

module ArtK
  module SteelSupport
    # From a clicked pipe to a complete support: the pipes it carries, the
    # structure it fixes to, the frame it sits in and the detail result.
    module Planner
      UP = Vec::UP

      module_function

      # hit: { point: (world, on the pipe axis), dir:, src: 'pp' | 'generic',
      # pipe: (record of the clicked pipe), cyl: (generic) }.
      # Returns { detail:, origin:, x:, y:, result:, struct:, hit: } or raises.
      def plan(model, detail, hit, opts = {})
        raise 'ท่อแนวตั้ง – ใช้ riser clamp ที่ระดับพื้น' if hit[:dir][2].abs > 0.5

        x = Vec.horizontal(hit[:dir])
        y = Vec.cross(UP, x)
        origin = hit[:point]
        gap = (opts['gap'] || opts[:gap] || 600).to_f
        case detail
        when 'wf', 'wb'
          rise = detail == 'wf' ? Details::FRAME_RISE : Details::RISE
          pipes = gather(model, origin, x, y, hit, rise)
          w = Probe.wall(model, origin, y, skip: cyls(pipes)) or
            raise 'ไม่พบผนัง/เสาข้างท่อภายใน 3 m (no wall or column beside the pipe)'
          if w[:side].positive? # frame y away from the wall
            x = Vec.scale(x, -1.0)
            y = Vec.scale(y, -1.0)
            pipes = pipes.map { |p| p.merge(y: -p[:y]) }
          end
          group = Pipes.group(pipes, gap: gap, rise: rise, below: rise)
          res = if detail == 'wf'
                  Details.wall_frame(group, w[:dist], opts)
                else
                  Details.wall_bracket(group, w[:dist], opts)
                end
          struct = { wall: w[:dist].round(1) }
        when 'th'
          pipes = gather(model, origin, x, y, hit, Details::RISE)
          group = Pipes.group(pipes, gap: gap, rise: Details::RISE)
          top = group.map { |p| Pipes.top(p) }.max
          ch = Probe.above(model, origin, x, top + 10.0, skip: cyls(pipes)) or
            raise 'ไม่พบโครง truss / พื้นด้านบนท่อ (no structure above)'
          if ch[:x].abs > 0.5 # under the chord's centre
            origin = Vec.along(origin, x, ch[:x])
            pipes = gather(model, origin, x, y, hit.merge(point: origin), Details::RISE)
            group = Pipes.group(pipes, gap: gap, rise: Details::RISE)
          end
          res = Details.truss_hang(group, ch.merge(x: 0.0), opts)
          check_rods(model, origin, y, res, ch, top, cyls(pipes)) if ch[:kind] == :round
          struct = ch.merge(x: 0.0)
        when 'tt'
          pipes = gather(model, origin, x, y, hit, Details::RISE)
          group = Pipes.group(pipes, gap: gap, rise: Details::RISE)
          low = group.map { |p| Pipes.bottom(p) }.min
          y0 = group.map { |p| p[:y] - p[:r] }.min - 1200.0
          y1 = group.map { |p| p[:y] + p[:r] }.max + 1200.0
          chords = Probe.below(model, origin, y, low - 1.0, y0, y1, skip: cyls(pipes))
          raise 'ไม่พบโครง truss (ท่อกลม) ใต้ท่อ (no round chords below)' if chords.empty?

          res = Details.truss_top(group, chords, opts)
          struct = { chords: chords }
        else
          raise ArgumentError, "unknown detail #{detail}"
        end
        { detail: detail, origin: origin, x: x, y: y, result: res, struct: struct, hit: hit, opts: opts }
      end

      # Plant Piping pipes and round pipes found by rays at the section,
      # one record each; the clicked pipe is always among them.
      def gather(model, origin, x, y, hit, rise)
        list = Link.pipes_across(model, origin, x, reach: Pipes::WIDTH, rise: rise + 300.0)
        if hit[:src] == 'generic' || !Link.available?
          known = list.map { |p| { point: Vec.add(origin, Vec.add(Vec.scale(y, p[:y]), [0, 0, p[:z]])), axis: x, radius: p[:r] } }
          known << hit[:cyl] if hit[:cyl]
          Generic.scan(model, origin, x, y, known: known, dz0: -rise - 100.0, dz1: rise + 400.0).each do |c|
            list << Generic.pipe(c, origin, x, y)
          end
        end
        if list.none? { |p| p[:y].abs < 1.0 && p[:z].abs < 1.0 } && hit[:pipe]
          list << hit[:pipe].merge(y: 0.0, z: 0.0)
        end
        list.uniq { |p| [(p[:y] / 5.0).round, (p[:z] / 5.0).round] }
      end

      def cyls(pipes)
        pipes.filter_map { |p| p[:cyl] }
      end

      # Each rod must find the chord straight above it.
      def check_rods(model, origin, y, res, ch, top, skip)
        res.info[:rods].each do |yr|
          o = Vec.add(Vec.along(origin, y, yr), [0, 0, top + 10.0])
          h = Probe.cast(model, o, UP, max: 4000.0, skip: skip)
          z = h && h[:point][2] - origin[2]
          next if z && (z - (ch[:z] - ch[:r])).abs < 15.0

          res.notes << "ก้านแขวนที่ระยะ #{yr.round} มม. ไม่พบ truss เส้นเดียวกันด้านบน – ตรวจแนว truss"
        end
      end
    end
  end
end
