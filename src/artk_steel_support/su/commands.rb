# frozen_string_literal: true

module ArtK
  module SteelSupport
    module Commands
      module_function

      def place(t)
        H.save_settings(H.settings.merge('detail' => t))
        Sketchup.active_model.select_tool(PlaceTool.new(t))
      end

      # Support +t+ at every column the selected Plant Piping runs pass
      # (within the support's reach), centred on each.
      def columns(t = H.settings['detail'])
        model = Sketchup.active_model
        Link.register
        unless Link.available?
          UI.messagebox("วางตามแนวท่อใช้กับท่อของ Plant Piping TH\n#{Link.status}")
          return
        end
        runs = Link.selected_runs(model)
        if runs.empty?
          UI.messagebox('เลือกแนวท่อ (Plant Piping) ก่อน (select pipe runs first)')
          return
        end
        opts = H.settings
        placed = 0
        notes = []
        model.start_operation("Steel Supports: ซัพพอร์ต #{t} ทุกเสา", true)
        runs.each do |run|
          Builder.forget
          column_points(model, run, Std.reach(t)).each do |at|
            pp = Link.pipe_at(model, at)
            next unless pp

            hit = { point: pp[:point], dir: pp[:dir], src: 'pp', pipe: Builder.pipe_record(pp) }
            plan = Placer.from_pipe(model, t, hit, opts)
            next if taken?(model, plan[:origin])

            Builder.create(model, plan, op: false)
            placed += 1
            notes.concat(plan[:result].notes.map { |n| "#{run.name}: #{n}" })
          rescue StandardError => e
            notes << "#{run.name}: #{e.message}"
          end
        end
        model.commit_operation
        Builder.forget
        UI.messagebox((["วางซัพพอร์ต #{t} #{placed} ตัว (ทุกเสาที่แนวท่อผ่าน)"] + notes.uniq.first(25)).join("\n"))
        placed
      rescue StandardError => e
        model.abort_operation
        UI.messagebox("ซัพพอร์ตเหล็ก: วางไม่สำเร็จ\n#{e.message}")
      end

      # Points on the run beside each column face within reach: the run is
      # sampled every 100 mm, faces found sideways, a run of samples on one
      # face no wider than a column gives its middle.
      def column_points(model, run, reach)
        samples = Link.support_points(model, run, span_m: 0.1)
        out = []
        cur = []
        flush = lambda do
          if cur.size >= 2 && Vec.dist(cur.first[:at], cur.last[:at]) <= Placer::COLUMN_MAX
            out << cur[cur.size / 2][:at]
          end
          cur = []
        end
        samples.each do |s|
          y = Vec.cross(Vec::UP, Vec.horizontal(s[:dir]))
          w = Probe.wall(model, s[:at], y)
          hit = w && w[:dist] <= reach + 400.0 ? w : nil
          last = cur.last
          if hit && last && last[:side] == hit[:side] && (last[:dist] - hit[:dist]).abs < 30.0 &&
             Vec.dist(last[:at], s[:at]) < 160.0
            cur << hit.merge(at: s[:at])
          else
            flush.call
            cur = hit ? [hit.merge(at: s[:at])] : []
          end
        end
        flush.call
        out
      end

      # A support of ours already within 300 mm.
      def taken?(model, origin)
        H.supports(model).any? { |g, _| Vec.dist(H.get_json(g, 'origin', [1e9, 0, 0]), origin) < 300.0 }
      end

      # Rebuild the selected supports (or all) for the pipes there now.
      def refit
        model = Sketchup.active_model
        list = Report.groups(model)
        return UI.messagebox('ยังไม่มีซัพพอร์ตเหล็กในโมเดล') if list.empty?

        count = Hash.new(0)
        errors = []
        model.start_operation('Steel Supports: ปรับตามท่อ', true)
        list.each do |g|
          count[Builder.refit(model, g, op: false)] += 1
        rescue StandardError => e
          errors << "#{g.get_attribute(H::DICT, 'number')}: #{e.message}"
        end
        model.commit_operation
        msg = "ปรับใหม่ #{count[:done]} · เหมือนเดิม #{count[:same]}"
        msg += " · ไม่พบท่อเดิม #{count[:lost]}" if count[:lost].positive?
        UI.messagebox(([msg] + errors).join("\n"))
        count
      end

      def report
        Report.show(Sketchup.active_model)
      end

      def settings
        Dialog.show
      end
    end
  end
end
