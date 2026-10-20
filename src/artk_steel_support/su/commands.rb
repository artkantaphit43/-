# frozen_string_literal: true

module ArtK
  module SteelSupport
    module Commands
      module_function

      def place(detail)
        H.save_settings(H.settings.merge('detail' => detail))
        Sketchup.active_model.select_tool(PlaceTool.new(detail))
      end

      # Supports of +detail+ along the selected Plant Piping runs at their
      # maximum span, leaving out stretches already supported.
      def auto(detail = H.settings['detail'])
        model = Sketchup.active_model
        Link.register
        unless Link.available?
          UI.messagebox("วางตามแนวท่อใช้กับท่อของ Plant Piping TH\n#{Link.status}")
          return
        end
        runs = Link.selected_runs(model)
        if runs.empty?
          UI.messagebox('เลือกแนวท่อ (Plant Piping) ที่ต้องการใส่ซัพพอร์ตก่อน (select pipe runs first)')
          return
        end
        opts = H.settings
        span = opts['spacing_m'].to_f.positive? ? opts['spacing_m'].to_f : nil
        placed = 0
        notes = []
        model.start_operation('Steel Supports: วางตามแนวท่อ', true)
        runs.each do |run|
          Builder.forget
          Link.support_points(model, run, span_m: span).each do |s|
            pp = Link.pipe_at(model, s[:at])
            next unless pp

            hit = { point: pp[:point], dir: pp[:dir], src: 'pp', pipe: Builder.pipe_record(pp) }
            plan = Planner.plan(model, detail, hit, opts)
            Builder.create(model, plan, op: false)
            placed += 1
            notes.concat(plan[:result].notes.map { |n| "#{run.name}: #{n}" })
          rescue StandardError => e
            notes << "#{run.name} (#{s[:at].map(&:round).join(', ')}): #{e.message}"
          end
        end
        model.commit_operation
        Builder.forget
        msg = "วาง #{Details::TYPES[detail][:th]} #{placed} ตัว"
        UI.messagebox(([msg] + notes.uniq.first(25)).join("\n"))
        placed
      rescue StandardError => e
        model.abort_operation
        UI.messagebox("ซัพพอร์ตเหล็ก: วางไม่สำเร็จ\n#{e.message}")
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
