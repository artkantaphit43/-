# frozen_string_literal: true

module ArtK
  module SteelSupport
    # Point at a pipe: the support is worked out and outlined (orange =
    # passes the checks, red = does not / cannot be placed); click places
    # it. Tab cycles the detail.
    class PlaceTool
      OK = Sketchup::Color.new(255, 120, 0)
      BAD = Sketchup::Color.new(220, 30, 30)
      PIPE = Sketchup::Color.new(0, 120, 255)
      DETAILS = Details::TYPES.keys.freeze

      def initialize(detail)
        @detail = detail
        @ip = Sketchup::InputPoint.new
        @cache = {}
      end

      def activate
        Link.register
        status
      end

      def deactivate(view)
        view.invalidate
      end

      def resume(_view)
        status
      end

      def onMouseMove(_flags, x, y, view)
        @ip.pick(view, x, y)
        @hit = pipe_hit(view)
        @plan = @hit && plan_for(@hit)
        view.tooltip = tip
        status
        view.invalidate
      end

      def onLButtonDown(_flags, _x, _y, view)
        return UI.beep unless @plan && !@plan[:error]

        model = Sketchup.active_model
        g = Builder.create(model, @plan)
        Builder.forget
        @cache.clear
        Sketchup.status_text = "วาง #{g.get_attribute(H::DICT, 'number')} แล้ว – #{@plan[:result].notes.join(' · ')}"
        UI.messagebox(@plan[:result].notes.join("\n")) if @plan[:result].notes.any? { |n| n.include?('ไม่') }
        @plan = nil
        view.invalidate
      rescue StandardError => e
        UI.messagebox("ซัพพอร์ตเหล็ก: วางไม่สำเร็จ\n#{e.message}")
      end

      def onKeyDown(key, _repeat, _flags, view)
        return false unless key == 9 # Tab

        @detail = DETAILS[(DETAILS.index(@detail) + 1) % DETAILS.size]
        H.save_settings(H.settings.merge('detail' => @detail))
        @cache.clear
        @plan = @hit && plan_for(@hit)
        status
        view.invalidate
        true
      end

      def onCancel(_reason, view)
        @plan = nil
        view.invalidate
      end

      def draw(view)
        @ip.draw(view) if @ip.valid? && @ip.respond_to?(:display?) && @ip.display?
        return unless @plan

        if @plan[:error]
          view.drawing_color = BAD
          view.draw_points([H.to_pt(@hit[:point])], 12, 2, BAD)
          return
        end
        tr = H.frame_transform(@plan[:origin], @plan[:x], @plan[:y])
        res = @plan[:result]
        view.line_width = 2
        view.drawing_color = res.ok? ? OK : BAD
        pts = res.lines.flat_map { |a, b| [H.to_pt(a).transform(tr), H.to_pt(b).transform(tr)] }
        view.draw(GL_LINES, pts) unless pts.empty?
        view.drawing_color = PIPE
        res.carried.each do |p|
          c = Vec.add(Vec.add(@plan[:origin], Vec.scale(@plan[:y], p[:y])), [0, 0, p[:z]])
          view.draw(GL_LINES, [H.to_pt(Vec.along(c, @plan[:x], -400)), H.to_pt(Vec.along(c, @plan[:x], 400))])
        end
      end

      def getExtents
        bb = Geom::BoundingBox.new
        bb.add(H.to_pt(@plan[:origin])) if @plan && @plan[:origin]
        bb
      end

      private

      def pipe_hit(view)
        return nil unless @ip.valid?

        model = Sketchup.active_model
        pos = H.from_pt(@ip.position)
        if (pp = Link.pipe_at(model, pos))
          return { point: pp[:point], dir: pp[:dir], src: 'pp', pipe: Builder.pipe_record(pp), key: [pp[:pid]] }
        end

        face = @ip.respond_to?(:face) && @ip.face
        return nil unless face

        tr = @ip.respond_to?(:transformation) ? @ip.transformation : Geom::Transformation.new
        cyl = Generic.cylinder(face, tr)
        return nil unless cyl

        v = Vec.sub(pos, cyl[:point])
        on = Vec.along(cyl[:point], cyl[:axis], Vec.dot(v, cyl[:axis]))
        y = Vec.cross(Vec::UP, Vec.horizontal(cyl[:axis]))
        { point: on, dir: cyl[:axis], src: 'generic', cyl: cyl, key: [face.object_id],
          pipe: Generic.pipe(cyl, on, Vec.horizontal(cyl[:axis]), y) }
      end

      # One plan per pipe and 50 mm step along it (the rays are not free).
      def plan_for(hit)
        along = Vec.dot(hit[:point], Vec.horizontal(hit[:dir]))
        key = hit[:key] + [@detail, (along / 50.0).round]
        @cache.clear if @cache.size > 200
        @cache[key] ||= begin
          Planner.plan(Sketchup.active_model, @detail, hit, H.settings)
        rescue StandardError => e
          { error: e.message, origin: hit[:point] }
        end
      end

      def tip
        return '' unless @plan
        return @plan[:error] if @plan[:error]

        res = @plan[:result]
        sec = Steel.get(res.info[:section])
        txt = "#{Details::TYPES[@detail][:th]}: #{sec[:name]} · #{res.carried.size} ท่อ"
        txt += " · พุก #{Hardware.label(res.info[:anchor])} ×#{res.info[:anchors]}" if res.info[:anchor]
        txt += " · ก้าน #{Hardware.label(res.info[:rod])}" if res.info[:rod]
        txt += ' · ไม่ผ่านการตรวจ' unless res.ok?
        ([txt] + res.notes).join("\n")
      end

      def status
        Sketchup.status_text = "ซัพพอร์ตเหล็ก: #{Details::TYPES[@detail][:th]} – ชี้ที่ท่อแล้วคลิก | Tab = เปลี่ยนแบบ"
      end
    end
  end
end
