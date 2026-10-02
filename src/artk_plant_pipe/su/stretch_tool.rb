# frozen_string_literal: true

module ArtK
  module PlantPipe
    # Stretch / move tool: edit a run after it was drawn.
    #
    #   Click an open pipe end   – stretch or shorten that pipe along its
    #                              line (type a distance for an exact value)
    #   Click a corner / elbow   – move that point; the pipes either side and
    #                              the fitting follow
    #   → / ← / ↑                – lock to red / green / blue axis, ↓ unlocks
    #   Esc                      – drop the picked point
    # Valves, supports and library fittings on the run move with it.
    class StretchTool
      H = ModelHelpers
      MIN_LEN = 10.0 # mm, shortest pipe left after a stretch

      def activate
        @model = Sketchup.active_model
        RunEditor.sync_context(@model) if defined?(RunEditor)
        @ip = Sketchup::InputPoint.new
        reset
      end

      def deactivate(view)
        view.invalidate
      end

      def resume(view)
        status
        view.invalidate
      end

      def enableVCB?
        true
      end

      def onCancel(_reason, view)
        reset
        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        if @grab
          @ip.pick(view, x, y, @anchor)
          @target = @ip.valid? ? constrain(H.from_pt(@ip.position)) : nil
          view.tooltip = target_tip || ''
          Sketchup.vcb_value = @target ? Sketchup.format_length(H.mm(Vec.dist(@grab[:world], @target))) : ''
        else
          @ip.pick(view, x, y)
          @hover = @ip.valid? ? pick_point(H.from_pt(@ip.position)) : nil
          view.tooltip = @hover ? hover_tip(@hover) : ''
        end
        view.invalidate
      end

      def onLButtonDown(_flags, _x, _y, view)
        if @grab
          commit(@target) if @target
        elsif @hover
          grab(@hover)
        else
          UI.beep
        end
        view.invalidate
      end

      def onUserText(text, view)
        return UI.beep unless @grab

        len = begin
          text.to_l.to_f * H::MM_PER_INCH
        rescue ArgumentError
          UI.beep
          return
        end
        d = @target ? Vec.sub(@target, @grab[:world]) : nil
        u = d && Vec.length(d) > 1e-6 ? Vec.unit(d) : (@lock || @grab[:u])
        return UI.beep unless u

        commit(Vec.add(@grab[:world], Vec.scale(u, len)))
        view.invalidate
      end

      def onKeyDown(key, _repeat, _flags, view)
        case key
        when VK_RIGHT then toggle([1.0, 0.0, 0.0])
        when VK_LEFT then toggle([0.0, 1.0, 0.0])
        when VK_UP then toggle([0.0, 0.0, 1.0])
        when VK_DOWN then @lock = nil
        else return false
        end
        status
        view.invalidate
        true
      end

      def draw(view)
        @ip.draw(view) if @ip.valid? && @ip.display?
        orange = Sketchup::Color.new(255, 140, 0)
        if @grab
          view.draw_points([H.to_pt(@grab[:world])], 12, 4, orange)
          if @target
            view.line_width = 3
            view.line_stipple = '-'
            view.drawing_color = lock_color || orange
            view.draw(GL_LINES, H.to_pt(@grab[:world]), H.to_pt(@target))
            view.line_stipple = ''
            view.draw_points([H.to_pt(@target)], 10, 2, orange)
          end
        elsif @hover
          view.draw_points([H.to_pt(@hover[:world])], 14, 4, orange)
        end
      end

      def getExtents
        bb = Geom::BoundingBox.new
        [@grab && @grab[:world], @target, @hover && @hover[:world]].compact.each { |p| bb.add(H.to_pt(p)) }
        bb
      end

      # ---- picking (world mm) ----

      # Open end or corner of a run near pt.
      def pick_point(pt)
        e = Picker.run_end(@model, pt, tol: 80.0)
        return e.merge(kind: :end) if e

        n = Picker.run_node(@model, pt)
        n&.merge(kind: :node)
      end

      def grab(hit)
        locked = RunEdit.locked_points(RunEditor.data(hit[:run]))
        if locked.any? { |p| Vec.dist(p, hit[:local]) <= RunEdit::TOL }
          UI.beep
          Sketchup.status_text = 'จุดนี้ต่อกับแนวท่ออื่นอยู่ ย้ายไม่ได้ (connected to another run)'
          return
        end
        cl = H.get_json(hit[:run], 'cl', [])
        if hit[:kind] == :end
          u_local = Builder.open_end_dir(cl, hit[:local])
          seg = cl.find { |a, b| Vec.dist(a, hit[:local]) <= 1.0 || Vec.dist(b, hit[:local]) <= 1.0 }
          other = Vec.dist(seg[0], hit[:local]) <= 1.0 ? seg[1] : seg[0]
          hit = hit.merge(u: Vec.unit(H.from_vec(H.to_vec(u_local).transform(hit[:tr]))),
                          other: H.transform_mm(hit[:tr], other))
        end
        @grab = hit
        @anchor = Sketchup::InputPoint.new(H.to_pt(hit[:world]))
        @target = nil
        status
      end

      # Open ends move along their pipe unless an axis is locked; corners
      # move freely (with SketchUp's inference) or along a locked axis.
      def constrain(raw)
        o = @grab[:world]
        dir = @lock || (@grab[:kind] == :end ? @grab[:u] : nil)
        return raw unless dir

        Vec.add(o, Vec.scale(dir, Vec.dot(Vec.sub(raw, o), dir)))
      end

      def commit(target)
        g = @grab
        if g[:kind] == :end && !@lock && Vec.dot(Vec.sub(target, g[:other]), g[:u]) < MIN_LEN
          UI.beep
          Sketchup.status_text = 'หดท่อจนสั้นเกินไป (pipe would be too short)'
          return
        end
        to = H.transform_mm(g[:tr].inverse, target)
        ok, warnings = RunEditor.apply(@model, g[:run], [[g[:local], to]])
        Commands.show_warnings(warnings, ok ? "ยืด/ย้ายท่อ #{g[:run].name} แล้ว (pipe edited)" : 'ย้ายไม่ได้')
        reset
      rescue StandardError => e
        reset
        UI.messagebox("Plant Piping: แก้ท่อไม่สำเร็จ (edit failed)\n#{e.message}")
      end

      private

      def reset
        @grab = nil
        @target = nil
        @hover = nil
        @lock = nil
        @anchor = Sketchup::InputPoint.new
        status
      end

      def toggle(axis)
        @lock = @lock == axis ? nil : axis
      end

      def lock_color
        case @lock
        when [1.0, 0.0, 0.0] then Sketchup::Color.new(255, 0, 0)
        when [0.0, 1.0, 0.0] then Sketchup::Color.new(0, 170, 0)
        when [0.0, 0.0, 1.0] then Sketchup::Color.new(0, 0, 255)
        end
      end

      def hover_tip(h)
        h[:kind] == :end ? "ปลายท่อ #{h[:run].name} – คลิกเพื่อยืด/หด" : "มุมท่อ #{h[:run].name} – คลิกเพื่อย้าย"
      end

      def target_tip
        return nil unless @target

        d = Vec.dist(@grab[:world], @target)
        if @grab[:kind] == :end && !@lock
          s = Vec.dot(Vec.sub(@target, @grab[:world]), @grab[:u])
          len = Vec.dot(Vec.sub(@target, @grab[:other]), @grab[:u])
          "#{s >= 0 ? 'ยืด +' : 'หด '}#{s.round} mm → ท่อช่วงนี้ยาว #{len.round} mm"
        else
          "ย้าย #{d.round} mm"
        end
      end

      def status
        Sketchup.status_text =
          if @grab
            @grab[:kind] == :end ? 'ลากตามแนวท่อแล้วคลิก หรือพิมพ์ระยะที่จะยืด | ลูกศรล็อกแกน | Esc ยกเลิก' :
              'คลิกตำแหน่งใหม่ของมุมท่อ หรือพิมพ์ระยะ | ลูกศรล็อกแกน | Esc ยกเลิก'
          else
            'ยืด/ย้ายท่อ: คลิกปลายท่อ (ยืด/หด) หรือมุมท่อ (ย้าย)'
          end
      end
    end
  end
end
