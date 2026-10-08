# frozen_string_literal: true

module ArtK
  module PlantPipe
    # Click on a pipe to place a support of the current type. Parallel
    # pipes next to it (setting 'support_group_mm') are carried by the same
    # support – it becomes a trapeze, H-frame, sleeper or long bracket.
    # Tab cycles the support type.
    class SupportTool
      H = ModelHelpers

      class << self
        attr_accessor :active
      end

      # type given (menu) = fixed; nil = follow the dialog selection.
      def initialize(type = nil)
        @fixed = type
        @type = type
      end

      def activate
        self.class.active = self
        @model = Sketchup.active_model
        RunEditor.sync_context(@model) if defined?(RunEditor)
        @type = @fixed || H.load_settings['support_type']
        @ip = Sketchup::InputPoint.new
        @hit = nil
        update_status
      end

      def deactivate(view)
        self.class.active = nil
        view.invalidate
      end

      def reload_settings
        @fixed = nil
        @type = H.load_settings['support_type']
        update_status
      end

      def resume(view)
        update_status
        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        @ip.pick(view, x, y)
        @hit = @ip.valid? ? Picker.nearest_pipe(@model, H.from_pt(@ip.position), extra: 60.0) : nil
        view.tooltip = @hit ? "#{Supports::TYPES[@type][:th]} – #{@hit[:run].name}" : @ip.tooltip
        view.invalidate
      end

      def onLButtonDown(_flags, _x, _y, view)
        return UI.beep unless @hit

        st = H.load_settings
        note = SupportBuilder.place(@model, @type, @hit, lod: st['lod'].to_sym, steps: st['segments'])
        Sketchup.status_text = note || 'วางซัพพอร์ตแล้ว (support placed)'
        UI.messagebox(note) if note && note.include?('ไม่')
        view.invalidate
      rescue StandardError => e
        UI.messagebox("Plant Piping: วางซัพพอร์ตไม่สำเร็จ (could not place support)\n#{e.message}")
      end

      def onKeyDown(key, _repeat, _flags, view)
        return false unless key == 9 # Tab

        types = Supports::TYPES.keys
        @type = types[(types.index(@type).to_i + 1) % types.size]
        H.save_settings(H.load_settings.merge('support_type' => @type))
        SettingsDialog.refresh if defined?(SettingsDialog)
        update_status
        view.invalidate
        true
      end

      def draw(view)
        @ip.draw(view) if @ip.valid? && @ip.display?
        return unless @hit

        pts = [H.to_pt(@hit[:proj])]
        view.draw_points(pts, 14, 3, Sketchup::Color.new(0, 150, 60))
        up = Supports::TYPES[@type][:mount] == :below ? -1.0 : 1.0
        view.drawing_color = Sketchup::Color.new(0, 150, 60)
        view.line_width = 2
        view.line_stipple = '-'
        view.draw(GL_LINES, pts[0], H.to_pt(Vec.add(@hit[:proj], [0, 0, up * 800.0])))
        view.line_stipple = ''
      end

      def getExtents
        bb = Geom::BoundingBox.new
        bb.add(H.to_pt(@hit[:proj])) if @hit
        bb
      end

      private

      def update_status
        Sketchup.status_text = "ซัพพอร์ต: #{Supports::TYPES[@type][:th]} – คลิกบนท่อ | Tab = เปลี่ยนชนิด (cycle type)"
      end
    end
  end
end
