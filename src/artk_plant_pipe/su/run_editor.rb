# frozen_string_literal: true

require 'json'

module ArtK
  module PlantPipe
    # Keeps a run's stored centreline and the pipe you see in step.
    #
    # Every piece of a run is regenerated from its centreline, so a pipe
    # stretched with SketchUp's own tools (Push/Pull inside the pipe, Scale,
    # Move of the end vertices) used to be ignored: fittings snapped to the
    # old end and a Rebuild shrank the pipe back. Now:
    #   * apply      – moves centreline points and carries valves, supports
    #                  and end fittings along (RunEdit), then rebuilds;
    #   * inspect    – reads every pipe back from its mesh: an open end that
    #                  was stretched along the pipe becomes a centreline move;
    #                  anything else (bent, moved sideways, resized by Scale,
    #                  pushed into a fitting) is reported – it returns to the
    #                  recorded shape on the next rebuild;
    #   * AutoSync   – runs inspect right after you stretch a pipe (or leave
    #                  the pipe you edited), as part of the same undo step.
    module RunEditor
      H = ModelHelpers
      TOL = RunEdit::TOL

      module_function

      # ---- editing ----

      def valve_instances(run)
        Collector.pieces(run, 'valve')
      end

      def end_part_instances(run)
        run.entities.select { |e| H.instance?(e) && e.get_attribute(H::DICT, 'end_part') }
      end

      def data(run)
        {
          'cl' => H.get_json(run, 'cl', []), 'tees' => H.get_json(run, 'tees', []),
          'joins' => H.get_json(run, 'joins', []), 'supports' => H.get_json(run, 'supports', []),
          'valves' => valve_instances(run).map do |v|
            { 'at' => JSON.parse(v.get_attribute(H::DICT, 'at')), 'dir' => JSON.parse(v.get_attribute(H::DICT, 'dir')) }
          end,
          'end_parts' => end_part_instances(run).map { |e| JSON.parse(e.get_attribute(H::DICT, 'end_part')) }
        }
      end

      # Move centreline points of +run+ (run-local mm) and rebuild.
      # Returns [ok, warnings].
      def apply(model, run, moves, name: 'Plant Piping: Stretch Pipe', transparent: false)
        before = data(run)
        after, warnings = RunEdit.move_points(before, moves)
        return [false, warnings] unless after

        model.start_operation(name, true, false, transparent)
        H.set_json(run, 'cl', after['cl'])
        H.set_json(run, 'supports', after['supports'])
        valve_instances(run).zip(after['valves']).each do |v, rec|
          v.set_attribute(H::DICT, 'at', JSON.generate(rec['at']))
          v.set_attribute(H::DICT, 'dir', JSON.generate(rec['dir']))
        end
        end_part_instances(run).zip(after['end_parts']).each do |e, rec|
          e.set_attribute(H::DICT, 'end_part', JSON.generate(rec))
        end
        warnings += Builder.render(model, run, Builder.run_settings(run))
        warnings += branch_warnings(model, run)
        model.commit_operation
        [true, warnings.uniq]
      rescue StandardError
        model.abort_operation
        raise
      end

      # Runs branching off +run+ whose connection point is no longer on it.
      def branch_warnings(model, run)
        runs = Collector.all_runs(model)
        mine = runs.find { |r, _| r == run } or return []
        cl = H.get_json(run, 'cl', [])
        inv = mine[1].inverse
        out = []
        runs.each do |other, tr|
          next if other == run

          (H.get_json(other, 'tees', []) + H.get_json(other, 'joins', [])).each do |t|
            next unless t['main_pid'] == run.persistent_id

            at = H.transform_mm(inv, H.transform_mm(tr, t['at']))
            on = cl.flatten(1).any? { |p| Vec.dist(p, at) <= TOL } || RunEdit.segment_index(cl, at)
            out << "#{other.name}: จุดต่อแยกไม่อยู่บนท่อนี้แล้ว ตรวจจุดต่อ (branch point is off this pipe now)" unless on
          end
        end
        out
      end

      # ---- reading pipes back from their geometry ----

      def open_ends(run)
        cl = H.get_json(run, 'cl', [])
        links = H.get_json(run, 'tees', []) + H.get_json(run, 'joins', [])
        Collector.open_ends(cl).reject { |p| links.any? { |t| Vec.dist(p, t['at']) <= TOL } }
      end

      # Mesh vertices of a pipe group (run-local mm, its transformation
      # applied). Nested groups (the end-centre circle) are left out.
      def pipe_points(pipe)
        tr = pipe.transformation
        pts = []
        pipe.entities.grep(Sketchup::Edge).each do |e|
          pts << e.start.position << e.end.position
        end
        pts.uniq.map { |p| H.from_pt(p.transform(tr)) }
      end

      # { moves: [[from, to], ...], issues: [text, ...] } for one run.
      def inspect(run)
        ends = open_ends(run)
        moves = []
        issues = []
        Collector.pieces(run, 'pipe').each do |pipe|
          g = H.get_json(pipe, 'geom') or next
          a = g['a']
          b = g['b']
          len = Vec.dist(a, b)
          next if len < TOL

          tr = pipe.transformation
          at = H.transform_mm(tr, a)
          bt = H.transform_mm(tr, b)
          open_a = ends.any? { |p| Vec.dist(p, a) <= TOL }
          open_b = ends.any? { |p| Vec.dist(p, b) <= TOL }
          ea, eb, known = extensions(pipe, g, len, open_a, open_b)
          m = RunEdit.measure_pipe(at, bt, ea, eb, pipe.get_attribute(H::DICT, 'od').to_f / 2.0, pipe_points(pipe))
          next unless m

          u = Vec.unit(Vec.sub(b, a))
          name = "#{run.name} ท่อ #{pipe.get_attribute(H::DICT, 'length_mm').to_f.round} mm"
          issues << "#{name}: ขนาดถูกเปลี่ยนด้วย Scale (resized by Scale) – เปลี่ยนขนาดที่ Settings แล้ว Rebuild" if m[:radial]
          unless known
            # older pipe between two fittings: only its total length is known
            issues << "#{name}: #{issue_text(false, false)}" if (m[:da] + m[:db]).abs > TOL || m[:lateral] > TOL
            next
          end
          [[a, m[:a], open_a], [b, m[:b], open_b]].each do |old, now, open|
            next if Vec.dist(old, now) <= TOL

            off_axis = Vec.length(Vec.cross(Vec.sub(now, a), u)) > TOL
            if open && !off_axis
              moves << [old, now]
            else
              issues << "#{name}: #{issue_text(open, off_axis)}"
            end
          end
        end
        { moves: moves.uniq, issues: issues.uniq }
      end

      # How far the mesh runs past each end into its fittings: recorded since
      # 1.6.2; for older pipes open ends have none and a single joined end
      # takes the rest of the cut length. known = false when both ends are
      # joined on an older pipe (only the sum is known then).
      def extensions(pipe, g, len, open_a, open_b)
        return [g['ea'].to_f, g['eb'].to_f, true] if g.key?('ea')

        ext = [pipe.get_attribute(H::DICT, 'length_mm').to_f - len, 0.0].max
        if open_a && open_b then [0.0, 0.0, true]
        elsif open_a then [0.0, ext, true]
        elsif open_b then [ext, 0.0, true]
        else [ext / 2.0, ext / 2.0, false]
        end
      end

      def issue_text(open, off_axis)
        if off_axis
          'ถูกเลื่อน/หมุนออกจากแนว (moved off its line) – ใช้เครื่องมือ "ยืด/ย้ายท่อ" แทน'
        elsif !open
          'ปลายที่ต่อกับข้อต่อถูกยืด (stretched into a fitting) – ใช้เครื่องมือ "ยืด/ย้ายท่อ" แทน'
        end
      end

      # Bring stretched open ends into the centreline. Returns
      # { synced: [run, ...], issues: [...], warnings: [...] }.
      def sync(model, runs, transparent: false)
        out = { synced: [], issues: [], warnings: [] }
        runs.each do |run|
          next unless run.valid?

          r = inspect(run)
          out[:issues].concat(r[:issues])
          next if r[:moves].empty?

          ok, w = apply(model, run, r[:moves], name: 'Plant Piping: Follow Stretched Pipe', transparent: transparent)
          out[:warnings].concat(w.map { |x| "#{run.name}: #{x}" })
          out[:synced] << run if ok
        end
        out
      end

      # Safety net when a tool starts: runs in the active context whose
      # pipes were stretched (and not yet read back) are brought in step, so
      # the tool snaps to the ends you see.
      def sync_context(model)
        return unless defined?(AutoSync) && AutoSync.enabled?

        runs = H.active_runs(model).map(&:first)
        res = sync(model, runs)
        return if res[:synced].empty?

        Sketchup.status_text = "Plant Piping: อัปเดตความยาวท่อตามที่ยืดแล้ว (#{res[:synced].map(&:name).join(', ')})"
      rescue StandardError => e
        puts "Plant Piping sync: #{e.message}"
      end
    end

    # Reads stretched pipes back automatically after each edit.
    module AutoSync
      H = ModelHelpers
      PREF = 'ArtK_PlantPipe'

      class << self
        def enabled?
          Sketchup.read_default(PREF, 'auto_sync', true) ? true : false
        end

        def enabled=(on)
          Sketchup.write_default(PREF, 'auto_sync', on ? true : false)
        end

        def attach(model)
          return unless model && Sketchup.const_defined?(:ModelObserver)

          @observers ||= {}
          return if @observers[model.object_id]

          obs = ModelObs.new
          model.add_observer(obs)
          @observers[model.object_id] = obs
        end

        def later(model)
          return if @busy || @pending || !enabled?

          @pending = true
          UI.start_timer(0, false) do
            @pending = false
            check(model)
          end
        end

        # Runs owning a pipe group that is open for editing right now – wait
        # until the user leaves it (rebuilding would erase the open group).
        def editing(model)
          (model.active_path || []).each_cons(2).map do |owner, child|
            owner if H.run?(owner) && H.type_of(child) == 'pipe'
          end.compact
        end

        def check(model)
          return if @busy || (model.respond_to?(:valid?) && !model.valid?)

          open_now = editing(model)
          candidates = ((@watch || []) + H.selected_runs(model)).select(&:valid?).uniq - open_now
          @watch = open_now
          return if candidates.empty?

          @busy = true
          res = RunEditor.sync(model, candidates, transparent: true)
          unless res[:synced].empty?
            Sketchup.status_text = "Plant Piping: อัปเดตความยาวท่อตามที่ยืดแล้ว (#{res[:synced].map(&:name).join(', ')})"
          end
          if res[:synced].empty? && !res[:issues].empty?
            Sketchup.status_text = "Plant Piping: #{res[:issues].first} (ตรวจท่อ เพื่อดูทั้งหมด)"
          end
        rescue StandardError => e
          puts "Plant Piping auto sync: #{e.message}"
        ensure
          @busy = false
        end
      end

      if Sketchup.const_defined?(:ModelObserver)
        class ModelObs < Sketchup::ModelObserver
          def onTransactionCommit(model)
            AutoSync.later(model)
          end

          def onActivePathChanged(model)
            AutoSync.later(model)
          end
        end
      end

      if Sketchup.const_defined?(:AppObserver)
        class AppObs < Sketchup::AppObserver
          def onNewModel(model)
            AutoSync.attach(model)
          end

          def onOpenModel(model)
            AutoSync.attach(model)
          end
        end
      end
    end
  end
end
