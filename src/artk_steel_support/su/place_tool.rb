# frozen_string_literal: true

module ArtK
  module SteelSupport
    # Point at a pipe beside a column – or at the column face, at the
    # level the pipes sit on (lock point, marked): the support (A–D) is worked out at the
    # column's centre and outlined (orange; red = a check fails / cannot
    # be placed); click places it. Tab cycles A → B → C → D.
    class PlaceTool
      OK = Sketchup::Color.new(255, 120, 0)
      BAD = Sketchup::Color.new(220, 30, 30)
      PIPE = Sketchup::Color.new(0, 120, 255)
      DETAILS = Std::TYPES.keys.freeze

      def initialize(detail)
        @detail = DETAILS.include?(detail) ? detail : DETAILS.first
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
        @hit = pipe_hit(view) || face_hit(view, x, y)
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
        view.draw_points([H.to_pt(lock_point)], 10, 4, res.ok? ? OK : BAD)
        view.drawing_color = PIPE
        view.line_stipple = res.info[:nominal] ? '-' : ''
        res.carried.each do |p|
          c = Vec.add(Vec.add(@plan[:origin], Vec.scale(@plan[:y], p[:y])), [0, 0, p[:z]])
          view.draw(GL_LINES, [H.to_pt(Vec.along(c, @plan[:x], -400)), H.to_pt(Vec.along(c, @plan[:x], 400))])
        end
        view.line_stipple = ''
      end

      # The lock point: the inner corner of the steel the pipes sit on at
      # the column (arm top at the face / bottom member at the frame post).
      def lock_point
        inner = Std.bearing(Std.type(@plan[:detail]))[0]
        Vec.along(@plan[:origin], @plan[:y], inner)
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

      # A vertical face under the cursor (column / wall): point, normal
      # (world) and where the camera is.
      # The column face the support goes on: the face seen under the
      # cursor (PickHelper – what the user looks at, even when the point
      # snapped to an edge or corner), its out side toward the camera.
      # Fallbacks: the InputPoint's face, then the edge's face turned to
      # the camera.
      def face_hit(view, x = nil, y = nil)
        return nil unless @ip.valid?

        eye = view.respond_to?(:camera) && view.camera ? H.from_pt(view.camera.eye) : nil
        pos = H.from_pt(@ip.position)
        face, tr = column_face(view, x, y, eye, pos)
        return nil unless face

        n = Vec.unit(H.from_vec(face.normal.transform(tr)))
        { face: true, point: pos, normal: n, eye: eye, obj: [face, tr], key: [face.object_id, (pos[2] / 10.0).round] }
      end

      def column_face(view, x, y, eye, pos)
        cands = []
        cands << picked(view, x, y) if x
        ip_tr = @ip.respond_to?(:transformation) ? @ip.transformation : Geom::Transformation.new
        cands << [@ip.face, ip_tr] if @ip.respond_to?(:face) && @ip.face
        if @ip.respond_to?(:edge) && @ip.edge
          edge = @ip.edge.faces.map { |f| [f, ip_tr] }
          cands.concat(edge.sort_by { |f, t| -facing(f, t, eye, pos) }.select { |f, t| facing(f, t, eye, pos) > 0.05 })
        end
        cands.compact.find { |f, t| usable?(f, t, pos) }
      end

      # Face under the cursor pixel and its transformation.
      def picked(view, x, y)
        ph = view.pick_helper
        ph.do_pick(x, y)
        f = ph.respond_to?(:picked_face) && ph.picked_face
        return nil unless f

        i = (0...ph.count).find { |k| ph.leaf_at(k) == f }
        [f, i ? ph.transformation_at(i) : Geom::Transformation.new]
      end

      # Upright, not ours, and the picked point on its plane.
      def usable?(face, tr, pos)
        return false if part_of_ours?(face)

        n = Vec.unit(H.from_vec(face.normal.transform(tr)))
        return false if n[2].abs > 0.3

        v = face.vertices.first
        on = H.transform_mm(tr, H.from_pt(v.position))
        Vec.dot(Vec.sub(pos, on), n).abs < 5.0
      end

      def facing(face, tr, eye, pos)
        return 0.0 unless eye

        n = Vec.horizontal(H.from_vec(face.normal.transform(tr)))
        Vec.dot(n, Vec.unit(Vec.sub(eye, pos)))
      end

      def part_of_ours?(face)
        d = face.respond_to?(:parent) && face.parent
        d.respond_to?(:instances) && d.instances.any? { |i| H.ours?(i) || Link.pp_entity?(i) }
      end

      # One plan per pipe / face and 50 mm step (the rays are not free).
      def plan_for(hit)
        along = hit[:face] ? 0 : (Vec.dot(hit[:point], Vec.horizontal(hit[:dir])) / 50.0).round
        key = hit[:key] + [@detail, along]
        @cache.clear if @cache.size > 200
        @cache[key] ||= begin
          model = Sketchup.active_model
          if hit[:face]
            Placer.from_face(model, @detail, hit[:point], hit[:normal], hit[:eye], H.settings, face: hit[:obj])
          else
            Placer.from_pipe(model, @detail, hit, H.settings)
          end
        rescue StandardError => e
          { error: e.message, origin: hit[:point] }
        end
      end

      def tip
        return '' unless @plan
        return @plan[:error] if @plan[:error]

        res = @plan[:result]
        txt = "#{Std.type(@detail)[:th]} · พุก #{Hardware.label(res.info[:anchor])} ×#{res.info[:anchors]}"
        txt += res.info[:nominal] ? ' · ยังไม่มีท่อ: U-bolt ตามแบบ + จุดไกด์' : " · รัด #{res.carried.size} ท่อ"
        col = @plan[:struct][:column]
        txt += col ? " · กลางเสา (กว้าง #{col} มม.)" : ' · ผนัง: วางตรงที่ชี้'
        txt += ' · จุดล็อก ✕ = ท้องท่อ' if @hit && @hit[:face]
        ([txt] + res.notes).join("\n")
      end

      def status
        Sketchup.status_text = "ซัพพอร์ต #{@detail}: ชี้ที่ท่อข้างเสา หรือหน้าเสาที่ระดับท้องท่อ (มุมในบนเหล็กรับท่อ) แล้วคลิก | " \
                               'Tab = A/B/C/D'
      end
    end
  end
end
