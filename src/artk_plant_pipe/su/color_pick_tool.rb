# frozen_string_literal: true

module ArtK
  module PlantPipe
    # Eyedropper for the pipe colour: click any pipe, part or surface in the
    # model and its displayed colour becomes the pipe colour. (The colour
    # box's own eyedropper cannot read the SketchUp viewport.)
    class ColorPickTool
      H = ModelHelpers

      # Colour shown for +face+ seen through the instances in +path+
      # (outermost first): the face's own material, else the material of
      # the nearest enclosing group / component. [r, g, b] or nil.
      def self.color_of(face, path = [])
        mat = face.respond_to?(:material) ? face.material : nil
        mat ||= path.reverse.find { |e| e.respond_to?(:material) && e.material && !e.equal?(face) }&.material
        c = mat&.color
        return nil unless c

        c.respond_to?(:red) ? [c.red, c.green, c.blue] : c.rgb.first(3)
      end

      def self.hex(rgb)
        format('#%02x%02x%02x', *rgb.map { |v| v.to_i.clamp(0, 255) })
      end

      def activate
        @ip = Sketchup::InputPoint.new
        Sketchup.status_text = 'ดูดสี: คลิกที่ท่อ/อุปกรณ์/ผิวในโมเดล (Esc = ยกเลิก)'
      end

      def deactivate(view)
        view.invalidate
      end

      def onCancel(_reason, _view)
        Sketchup.active_model.select_tool(nil)
      end

      def pick(view, x, y)
        @ip.pick(view, x, y)
        face = @ip.face
        return nil unless face

        path = @ip.respond_to?(:instance_path) ? @ip.instance_path.to_a : []
        self.class.color_of(face, path)
      end

      def onMouseMove(_flags, x, y, view)
        rgb = pick(view, x, y)
        view.tooltip = rgb ? "สี #{self.class.hex(rgb)} – คลิกเพื่อใช้" : 'ชี้ที่ผิวที่มีสี'
      end

      def onLButtonDown(_flags, x, y, view)
        rgb = pick(view, x, y)
        return UI.beep unless rgb

        apply(self.class.hex(rgb))
      end

      # Saves the colour as the pipe colour (custom colour switched on).
      def apply(hex)
        H.save_settings(Settings.sanitize(H.load_settings.merge('pipe_color' => hex)))
        SettingsDialog.refresh if defined?(SettingsDialog)
        Sketchup.status_text = "สีท่อ #{hex} – ใช้กับท่อที่วาดใหม่ / กด ปรับท่อที่เลือก เพื่อเปลี่ยนท่อเดิม"
        Sketchup.active_model.select_tool(nil)
      end
    end
  end
end
