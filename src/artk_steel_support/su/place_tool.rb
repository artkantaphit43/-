# frozen_string_literal: true

module ArtK
  module SteelSupport
    # Point at a pipe beside a column – or at the column face, at the
    # level the pipes sit on (lock point, marked): the support (A–D) is worked out at the
    # column's centre and outlined (orange; red = a check fails / cannot
    # be placed); click places it. Tab cycles A → B → C → D → E → E2 → F → G.
    #
    # E, F (hung from a round member): point at a Plant Piping pipe under it,
    # or click the round member itself (centred on its axis by the
    # plugin), then type the drop from its underside to the pipes'
    # undersides or click a point at that level.
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
        @right = right(view)
        if Std.hung?(@detail)
          hanger_move(view)
        else
          @hit = pipe_hit(view) || face_hit(view, x, y)
          @plan = @hit && plan_for(@hit)
        end
        view.tooltip = tip
        status
        view.invalidate
      end

      def onLButtonDown(_flags, _x, _y, view)
        if Std.hung?(@detail) && !@chord && @cand && !(@plan && !@plan[:error])
          @chord = @cand # the round member: now the level
          @cache.clear
          status
          return view.invalidate
        end
        return UI.beep unless @plan && !@plan[:error]

        model = Sketchup.active_model
        g = Builder.create(model, @plan)
        Builder.forget
        @cache.clear
        Sketchup.status_text = "วาง #{g.get_attribute(H::DICT, 'number')} แล้ว – #{@plan[:result].notes.join(' · ')}"
        UI.messagebox(@plan[:result].notes.join("\n")) if @plan[:result].notes.any? { |n| n.include?('ไม่') }
        @plan = nil
        @chord = nil
        status
        view.invalidate
      rescue StandardError => e
        UI.messagebox("ซัพพอร์ตเหล็ก: วางไม่สำเร็จ\n#{e.message}")
      end

      def enableVCB?
        !@chord.nil?
      end

      # E: the drop from the round member's underside to the pipes' undersides.
      def onUserText(text, view)
        return unless @chord

        mm = begin
          text.to_l.to_f * 25.4
        rescue ArgumentError
          return UI.beep
        end
        @plan = chord_plan(chord_under - mm)
        return UI.messagebox("ซัพพอร์ตเหล็ก: วางไม่สำเร็จ\n#{@plan[:error]}") if @plan[:error]

        onLButtonDown(0, 0, 0, view)
      end

      def onKeyDown(key, _repeat, _flags, view)
        return false unless key == 9 # Tab

        @detail = DETAILS[(DETAILS.index(@detail) + 1) % DETAILS.size]
        H.save_settings(H.settings.merge('detail' => @detail))
        @cache.clear
        @chord = nil if @chord && !Std.hung?(@detail)
        @plan = @hit && plan_for(@hit)
        status
        view.invalidate
        true
      end

      def onCancel(_reason, view)
        @plan = nil
        @chord = nil
        status
        view.invalidate
      end

      def draw(view)
        @ip.draw(view) if @ip.valid? && @ip.respond_to?(:display?) && @ip.display?
        if (c = @chord || (!@plan && @cand)) # the round member to hang from: its axis
          cyl = c[:cyl]
          view.drawing_color = PIPE
          view.line_width = 3
          view.draw(GL_LINES, [H.to_pt(cyl[:point]), H.to_pt(Vec.along(cyl[:point], cyl[:axis], cyl[:length] || 1000.0))])
        end
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
      # the column (arm top at the face / bottom member at the frame post);
      # E: the middle of its bottom member's top.
      def lock_point
        s = Std.type(@plan[:detail])
        if s[:mount] # G: the arm's top at the face
          m = Std.mount_geo(@plan[:struct])
          return Vec.add(Vec.along(@plan[:origin], @plan[:y], m[:face]), [0.0, 0.0, m[:z]])
        end
        inner = case s[:form]
                when :hanger then s[:length] / 2.0
                when :rod then 0.0
                else Std.bearing(s)[0]
                end
        Vec.along(@plan[:origin], @plan[:y], inner)
      end

      def getExtents
        bb = Geom::BoundingBox.new
        bb.add(H.to_pt(@plan[:origin])) if @plan && @plan[:origin]
        bb
      end

      private

      # Camera's right (E's member is seen from its end on the left).
      def right(view)
        cam = view.respond_to?(:camera) && view.camera
        cam.respond_to?(:xaxis) ? Vec.horizontal(H.from_vec(cam.xaxis)) : nil
      rescue StandardError
        nil
      end

      # E: a Plant Piping pipe → the plan at once; another round member
      # (horizontal) → the one to hang from, the level next; after it is
      # clicked, the cursor's height is the pipes' undersides.
      def hanger_move(view)
        @hit = nil
        @cand = nil
        if @chord
          @plan = @ip.valid? ? chord_plan(H.from_pt(@ip.position)[2]) : nil
          Sketchup.vcb_label = 'ระยะลง (มม.)'
          Sketchup.vcb_value = (chord_under - @plan[:bop]).round.to_s if @plan && @plan[:bop]
          return
        end
        hit = pipe_hit(view)
        if hit && hit[:src] == 'pp'
          @hit = hit
          @plan = plan_for(hit)
          return unless @plan[:error] && hit[:dir][2].abs <= 0.2

          # no round member over it: this one (drawn with Plant Piping) is it
          @cand = { cyl: { point: hit[:point], axis: Vec.unit(hit[:dir]), radius: hit[:pipe][:r] }, at: hit[:point] }
          @plan = nil
        elsif hit && hit[:cyl] && hit[:cyl][:axis][2].abs <= 0.2
          @cand = { cyl: hit[:cyl], at: hit[:point] }
          @plan = nil
        else
          @plan = nil
        end
      end

      # World z of the clicked round member's underside at the point clicked.
      def chord_under
        cyl = @chord[:cyl]
        ax = Vec.unit(cyl[:axis])
        c = Vec.add(cyl[:point], Vec.scale(ax, Vec.dot(Vec.sub(@chord[:at], cyl[:point]), ax)))
        c[2] - cyl[:radius]
      end

      def chord_plan(bop)
        key = [:chord, @chord[:cyl].object_id, @detail, (bop / 5.0).round]
        @cache.clear if @cache.size > 200
        @cache[key] ||= begin
          model = Sketchup.active_model
          pl = if Std.type(@detail)[:form] == :rod
                 Placer.from_chord_rod(model, @detail, @chord[:cyl], @chord[:at], bop, H.settings)
               else
                 Placer.from_chord(model, @detail, @chord[:cyl], @chord[:at], bop, H.settings, right: @right)
               end
          pl.merge(bop: bop)
        rescue StandardError => e
          { error: e.message, origin: @chord[:at], bop: bop }
        end
      end

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
          if Std.type(@detail)[:mount]
            if hit[:face]
              Placer.from_face_angle(model, @detail, hit[:point], hit[:normal], hit[:eye], H.settings, face: hit[:obj])
            else
              Placer.from_pipe_angle(model, @detail, hit, H.settings)
            end
          elsif Std.type(@detail)[:form] == :rod
            Placer.from_pipe_rod(model, @detail, hit, H.settings)
          elsif Std.hung?(@detail)
            Placer.from_pipe_hanger(model, @detail, hit, H.settings, right: @right)
          elsif hit[:face]
            Placer.from_face(model, @detail, hit[:point], hit[:normal], hit[:eye], H.settings, face: hit[:obj])
          else
            Placer.from_pipe(model, @detail, hit, H.settings)
          end
        rescue StandardError => e
          { error: e.message, origin: hit[:point] }
        end
      end

      def tip
        if @cand && !@plan
          return "ท่อกลม Ø#{(2 * @cand[:cyl][:radius]).round} – คลิกเพื่อแขวน (เข้ากึ่งกลางท่อกลมเอง) " \
                 'แล้วพิมพ์ระยะลง หรือคลิกจุดที่ระดับท้องท่อ'
        end
        return '' unless @plan
        return @plan[:error] if @plan[:error]

        res = @plan[:result]
        info = res.info
        txt = info[:title] || Std.type(@detail)[:th]
        txt += " · #{Steel.get(info[:section])[:name]}" if Std.type(@detail)[:mount] && info[:section]
        txt += " · เหล็กเส้น #{Hardware.label(info[:rod])} ×#{info[:rods] || 2}" if info[:rod]
        txt += " · พุก #{Hardware.label(info[:anchor])} ×#{info[:anchors]}" if info[:anchor]
        txt += info[:nominal] ? ' · ยังไม่มีท่อ: U-bolt ตามแบบ + จุดไกด์' : " · รัด #{res.carried.size} ท่อ"
        if Std.hung?(@detail)
          txt += ' · กลางท่อกลมด้านบน'
          txt += " · ระยะลงจากใต้ท่อกลม #{(chord_under - @plan[:bop]).round} มม." if @chord && @plan[:bop]
        else
          col = @plan[:struct][:column]
          txt += if @plan[:struct][:hang] then ' · กลางท่อกลมด้านบน (pipe shoe 2 ตัว ไม่ยึดผนัง)'
                 elsif col then " · กลางเสา (กว้าง #{col} มม.)"
                 else ' · ผนัง: วางตรงที่ชี้'
                 end
        end
        txt += ' · จุดล็อก ✕ = ท้องท่อ' if (@hit && @hit[:face]) || @chord
        ([txt] + res.notes).join("\n")
      end

      def status
        Sketchup.status_text =
          if @chord
            "ซัพพอร์ต #{@detail}: พิมพ์ระยะจากใต้ท่อกลมลงถึงท้องท่อ (มม.) หรือคลิกจุดที่ระดับท้องท่อ | Esc = เลือกท่อกลมใหม่"
          elsif Std.hung?(@detail)
            "ซัพพอร์ต #{@detail}: ชี้ท่อ (Plant Piping) ใต้ท่อกลม หรือคลิกท่อกลมที่จะแขวน | Tab = A–G"
          elsif Std.type(@detail)[:mount]
            "ซัพพอร์ต #{@detail}: ชี้ท่อที่วิ่งตามผนัง/คาน หรือหน้าผนัง/คานที่ระดับหลังแขนเหล็กฉาก แล้วคลิก | Tab = A–G"
          elsif Std.type(@detail)[:hang]
            "ซัพพอร์ต #{@detail} (แขวนท่อกลมด้านบน ไม่ยึดผนัง): ชี้ท่อข้างผนัง หรือหน้าผนังที่ระดับท้องท่อ แล้วคลิก | Tab = A–G"
          else
            "ซัพพอร์ต #{@detail}: ชี้ที่ท่อข้างเสา หรือหน้าเสาที่ระดับท้องท่อ (มุมในบนเหล็กรับท่อ) แล้วคลิก | " \
              'Tab = A–G'
          end
      end
    end
  end
end
