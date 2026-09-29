# frozen_string_literal: true

module ArtK
  module PlantPipe
    # Click on a straight pipe to insert a valve/flange of the chosen type.
    # The valve is centred on the click, shifted if needed so its full
    # face-to-face length lies on straight pipe (never across a fitting).
    # Tab cycles the valve type.
    class ValveTool
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
        @type = @fixed || H.load_settings['valve_type']
        @model = Sketchup.active_model
        @ip = Sketchup::InputPoint.new
        @place = nil
        update_status
      end

      def deactivate(view)
        self.class.active = nil
        view.invalidate
      end

      # Called when the settings dialog changes.
      def reload_settings
        @fixed = nil
        @type = H.load_settings['valve_type']
        update_status
      end

      def resume(view)
        update_status
        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        @ip.pick(view, x, y)
        @place = @ip.valid? ? placement(H.from_pt(@ip.position)) : nil
        view.tooltip = @place ? @place[:tip] : @ip.tooltip
        view.invalidate
      end

      def onLButtonDown(_flags, _x, _y, view)
        return UI.beep unless @place
        unless @place[:ok]
          UI.messagebox(@place[:tip])
          return
        end
        hit = @place[:hit]
        inv = hit[:tr].inverse
        at = H.transform_mm(inv, @place[:at])
        dir = Vec.unit(H.from_vec(H.to_vec(hit[:dir]).transform(inv)))
        Builder.add_valve(@model, hit[:run], @type, at, dir)
        view.invalidate
      rescue StandardError => e
        UI.messagebox("Plant Piping: ใส่วาล์วไม่สำเร็จ (could not insert valve)\n#{e.message}")
      end

      def onKeyDown(key, _repeat, _flags, view)
        return false unless key == 9 # Tab

        types = FittingsData.valve_types
        @type = types[(types.index(@type).to_i + 1) % types.size]
        H.save_settings(H.load_settings.merge('valve_type' => @type)) # keep the dialog in sync
        SettingsDialog.refresh if defined?(SettingsDialog)
        update_status
        view.invalidate
        true
      end

      def draw(view)
        @ip.draw(view) if @ip.valid? && @ip.display?
        return unless @place

        color = @place[:ok] ? Sketchup::Color.new(0, 170, 0) : Sketchup::Color.new(220, 0, 0)
        a = H.to_pt(Vec.sub(@place[:at], Vec.scale(@place[:hit][:dir], @place[:len] / 2.0)))
        b = H.to_pt(Vec.add(@place[:at], Vec.scale(@place[:hit][:dir], @place[:len] / 2.0)))
        view.line_width = 8
        view.drawing_color = color
        view.draw(GL_LINES, a, b)
        view.draw_points([a, b], 10, 1, color)
      end

      def getExtents
        bb = Geom::BoundingBox.new
        bb.add(H.to_pt(@place[:at])) if @place
        bb
      end

      private

      def placement(pt)
        hit = Picker.nearest_pipe(@model, pt, extra: 50.0)
        return nil unless hit

        od = hit[:attrs]['od'].to_f
        len = valve_length(hit[:attrs], od)
        name = FittingsData.valve(@type)[:name]
        if hit[:len] < len
          return { ok: false, hit: hit, at: hit[:proj], len: len,
                   tip: "ท่อตรงสั้นกว่าวาล์ว (#{hit[:len].round} < #{len.round} mm) – straight pipe too short for #{name}" }
        end
        s = hit[:t] * hit[:len]
        s = [[s, len / 2.0].max, hit[:len] - len / 2.0].min
        at = Vec.add(hit[:a], Vec.scale(hit[:dir], s))
        { ok: true, hit: hit, at: at, len: len,
          tip: "#{name} #{hit[:attrs]['size']} บน (on) #{hit[:run].name} – F-F #{len.round} mm" }
      end

      # Face-to-face of the valve family this pipe gets (flanged / forged /
      # brass threaded / plastic true-union).
      def valve_length(attrs, od)
        spec = Catalog.spec(attrs['catalog'], attrs['size'], attrs['rating'])
        Parts.valve_length(@type, Parts.opts(spec), metallic: spec.density > 5000)
      rescue StandardError
        FittingsData.face_to_face(@type, od)
      end

      def update_status
        info = FittingsData.valve(@type)
        src = Library.find(@type, nil) ? 'โมเดลจากไลบรารี' : 'โมเดลในตัว'
        Sketchup.status_text = "ใส่ #{info[:th]} (#{src}) – คลิกบนท่อตรง | Tab = เปลี่ยนชนิดวาล์ว (cycle type)"
      end
    end
  end
end
