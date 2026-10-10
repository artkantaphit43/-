# frozen_string_literal: true

module ArtK
  module PlantPipe
    # Eyedropper for the pipe colour: click any pipe, part or surface in the
    # model and its displayed colour becomes the pipe colour. (The colour
    # box's own eyedropper cannot read the SketchUp viewport.)
    class ColorPickTool
      H = ModelHelpers
      CURSOR = File.join(__dir__, '..', 'icons', 'eyedropper_cursor.png')
      SWATCH = 18

      # Colour shown for +leaf+ (a face, or an edge when the pointer is on
      # an outline) seen through the instances in +path+ (outermost first):
      # the face's own material, else the material of the nearest enclosing
      # group / component. [r, g, b] or nil.
      def self.color_of(leaf, path = [])
        mat = leaf.is_a?(Sketchup::Face) ? leaf.material : nil
        mat ||= path.reverse.find { |e| !e.equal?(leaf) && e.respond_to?(:material) && e.material }&.material
        c = mat&.color
        return nil unless c

        c.respond_to?(:red) ? [c.red, c.green, c.blue] : c.rgb.first(3)
      end

      # First colour found along the picked +paths+ (each outermost first,
      # leaf last) – the PickHelper fallback when the input point has no
      # face, e.g. on a pipe's outline or a face hidden behind glass.
      def self.color_of_paths(paths)
        paths.each do |p|
          next if p.nil? || p.empty?

          rgb = color_of(p.last, p)
          return rgb if rgb
        end
        nil
      end

      def self.hex(rgb)
        format('#%02x%02x%02x', *rgb.map { |v| v.to_i.clamp(0, 255) })
      end

      def self.cursor
        return @cursor if defined?(@cursor)

        @cursor = File.exist?(CURSOR) ? UI.create_cursor(CURSOR, 2, 21) : nil
      rescue StandardError
        @cursor = nil
      end

      def activate
        @ip = Sketchup::InputPoint.new
        @hover = nil
        Sketchup.status_text = 'ดูดสี: คลิกที่ท่อ/อุปกรณ์/ผิวในโมเดล (Esc = ยกเลิก)'
      end

      def deactivate(view)
        view.invalidate
      end

      def onCancel(_reason, _view)
        Sketchup.active_model.select_tool(nil)
      end

      def onSetCursor
        id = self.class.cursor
        id ? UI.set_cursor(id) : false
      end

      def pick(view, x, y)
        @ip.pick(view, x, y)
        face = @ip.face
        if face
          path = @ip.respond_to?(:instance_path) ? @ip.instance_path.to_a : []
          rgb = self.class.color_of(face, path)
          return rgb if rgb
        end
        ph = view.pick_helper
        ph.do_pick(x, y)
        self.class.color_of_paths((0...ph.count).map { |i| ph.path_at(i) })
      end

      def onMouseMove(_flags, x, y, view)
        rgb = pick(view, x, y)
        @hover = rgb ? [x, y, rgb] : nil
        view.tooltip = rgb ? "สี #{self.class.hex(rgb)} – คลิกเพื่อใช้" : 'ชี้ที่ผิวที่มีสี'
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        rgb = pick(view, x, y)
        return UI.beep unless rgb

        apply(self.class.hex(rgb))
      end

      # Swatch of the colour under the pointer, beside the cursor.
      def draw(view)
        return unless @hover

        x, y, rgb = @hover
        x += 14
        y += 14
        pts = [[x, y], [x + SWATCH, y], [x + SWATCH, y + SWATCH], [x, y + SWATCH]].map { |a, b| Geom::Point3d.new(a, b, 0) }
        view.drawing_color = Sketchup::Color.new(*rgb)
        view.draw2d(GL_QUADS, pts)
        view.line_width = 1
        view.drawing_color = 'black'
        view.draw2d(GL_LINE_LOOP, pts)
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
