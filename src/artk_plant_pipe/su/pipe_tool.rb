# frozen_string_literal: true

module ArtK
  module PlantPipe
    # Interactive tool: click the centreline points of a pipe run.
    #
    #   Click            – add a point (first click on an existing pipe makes
    #                      a branch tee; on a run's open end continues it)
    #   Type a length    – exact length along the current direction (VCB);
    #                      for sloped drains the length is the plan length
    #   → / ← / ↑        – lock to red / green / blue axis, ↓ unlocks
    #   Shift (hold)     – lock the current direction
    #   Backspace        – remove the last point
    #   Double-click / Enter – finish the run,  Esc – cancel
    #
    # Design aids
    # * 45° snapping in plan (standard 90°/45° fittings only) and clean
    #   vertical risers, unless you snap to an existing point.
    # * Gravity services get their fall applied automatically on level
    #   segments, in the direction you draw (= flow direction).
    # * Elevation reference "BOP" lifts points picked on geometry by half
    #   the OD, so a pipe drawn on a rack beam sits on the beam.
    class PipeTool
      H = ModelHelpers

      class << self
        attr_accessor :active
      end

      def activate
        @model = Sketchup.active_model
        RunEditor.sync_context(@model) if defined?(RunEditor)
        @ip = Sketchup::InputPoint.new
        @anchor = Sketchup::InputPoint.new
        load_settings
        reset_state
        self.class.active = self
        update_status
      end

      def deactivate(view)
        self.class.active = nil
        view.invalidate
      end

      def resume(view)
        load_settings
        update_status
        view.invalidate
      end

      # Called by the settings dialog when settings change.
      def reload_settings
        load_settings
        update_status
        @model.active_view.invalidate
      end

      def onCancel(_reason, view)
        reset_state
        update_status
        view.invalidate
      end

      def enableVCB?
        true
      end

      def onMouseMove(_flags, x, y, view)
        if @points.empty?
          @ip.pick(view, x, y)
        else
          @ip.pick(view, x, y, @anchor)
        end
        @cursor = @ip.valid? ? constrain(@ip) : nil
        @hover = nil
        if @cursor && @points.empty?
          @hover = detect_link(@cursor)
        elsif @cursor && (@hover = end_target(H.from_pt(@ip.position)))
          @cursor = @hover[:point] # snap to the Center of that pipe end
        end
        view.tooltip = hover_tip || @ip.tooltip
        update_vcb
        view.invalidate
      end

      def onLButtonDown(_flags, _x, _y, view)
        return unless @cursor

        if @points.empty?
          start_run(@cursor)
        else
          return if Vec.dist(@cursor, @points.last) < 1.0

          if @hover && @hover[:kind] == :end
            @points << @hover[:point]
            @end_link = @hover
            return finish(view)
          end
          link = detect_link(@cursor, exclude_run: @start_link && @start_link[:run])
          if link && %i[tee node].include?(link[:kind])
            @points << link[:point]
            @end_link = link
            return finish(view)
          end
          @points << (link ? link[:point] : @cursor)
        end
        set_anchor
        update_status
        view.invalidate
      end

      def onLButtonDoubleClick(_flags, _x, _y, view)
        finish(view)
      end

      def onReturn(view)
        finish(view)
      end

      def onUserText(text, view)
        return if @points.empty? || @cursor.nil?

        len = begin
          text.to_l.to_f * H::MM_PER_INCH
        rescue ArgumentError
          UI.beep
          Sketchup.status_text = "ความยาวไม่ถูกต้อง (invalid length): #{text}"
          return
        end
        return if len <= 0

        last = @points.last
        d = Vec.sub(@cursor, last)
        h = Math.hypot(d[0], d[1])
        pt =
          if gravity? && h >= 1.0 && d[2].abs < h
            # plan length for sloped drains
            u = [d[0] / h, d[1] / h, 0.0]
            p = Vec.add(last, Vec.scale(u, len))
            p[2] = last[2] - len * slope_ratio
            p
          elsif Vec.length(d) >= 1e-6
            Vec.add(last, Vec.scale(Vec.unit(d), len))
          end
        return unless pt

        @points << pt
        set_anchor
        update_status
        view.invalidate
      end

      def onKeyDown(key, _repeat, _flags, view)
        case key
        when VK_RIGHT then toggle_axis([1.0, 0.0, 0.0])
        when VK_LEFT then toggle_axis([0.0, 1.0, 0.0])
        when VK_UP then toggle_axis([0.0, 0.0, 1.0])
        when VK_DOWN then @axis = nil
        when CONSTRAIN_MODIFIER_KEY
          if @cursor && !@points.empty? && Vec.dist(@cursor, @points.last) > 1.0
            @axis = Vec.unit(Vec.sub(@cursor, @points.last))
            @shift_lock = true
          end
        when 8 # Backspace
          @points.pop
          @start_link = nil if @points.empty?
          set_anchor unless @points.empty?
        else
          return false
        end
        update_status
        view.invalidate
        true
      end

      def onKeyUp(key, _repeat, _flags, view)
        return false unless key == CONSTRAIN_MODIFIER_KEY && @shift_lock

        @axis = nil
        @shift_lock = false
        view.invalidate
        true
      end

      def draw(view)
        @ip.draw(view) if @ip.valid? && @ip.display?
        pts = @points.map { |p| H.to_pt(p) }
        pts << H.to_pt(@cursor) if @cursor && !@points.empty?
        color = Sketchup::Color.new(*(Settings.rgb(@settings['pipe_color']) ||
                                      Services.color(@settings['service'], @settings['color_scheme'])))
        if pts.size >= 2
          view.line_stipple = ''
          view.line_width = 4
          view.drawing_color = color
          view.draw(GL_LINE_STRIP, pts[0..-2]) if pts.size > 2
          view.line_stipple = @axis ? '' : '-'
          view.drawing_color = axis_color || color
          view.draw(GL_LINES, pts[-2], pts[-1])
          view.line_stipple = ''
        end
        view.draw_points(pts, 8, 2, color) unless pts.empty?
        if @hover
          view.draw_points([H.to_pt(@hover[:point])], 14, 4, Sketchup::Color.new(255, 140, 0))
        end
        draw_readout(view)
      end

      def getExtents
        bb = Geom::BoundingBox.new
        @points.each { |p| bb.add(H.to_pt(p)) }
        bb.add(H.to_pt(@cursor)) if @cursor
        bb
      end

      private

      def load_settings
        @settings = H.load_settings
        @spec = Settings.spec(@settings)
        return unless @start_link && %i[append node].include?(@start_link[:kind])

        # Continuing a run keeps that run's own size & service.
        @settings = Builder.run_settings(@start_link[:run]).merge(
          'snap45' => @settings['snap45'], 'elevation_ref' => @settings['elevation_ref'],
          'slope_pct' => @settings['slope_pct'], 'color_scheme' => @settings['color_scheme']
        )
        @spec = Settings.spec(@settings)
      end

      def reset_state
        @points = []
        @cursor = nil
        @axis = nil
        @shift_lock = false
        @start_link = nil
        @end_link = nil
        @warn_end = nil
        @hover = nil
        @ip.clear
        @anchor.clear
        load_settings
      end

      def set_anchor
        @anchor = Sketchup::InputPoint.new(H.to_pt(@points.last))
      end

      def gravity?
        Services.gravity?(@settings['service']) && @settings['slope_pct'].to_f.positive?
      end

      def slope_ratio
        @settings['slope_pct'].to_f / 100.0
      end

      def toggle_axis(axis)
        @axis = @axis == axis ? nil : axis
        @shift_lock = false
      end

      def axis_color
        return nil unless @axis

        case @axis
        when [1.0, 0.0, 0.0] then Sketchup::Color.new(255, 0, 0)
        when [0.0, 1.0, 0.0] then Sketchup::Color.new(0, 170, 0)
        when [0.0, 0.0, 1.0] then Sketchup::Color.new(0, 0, 255)
        else Sketchup::Color.new(255, 0, 255)
        end
      end

      # ---------- point constraints ----------

      def constrain(ip)
        raw = H.from_pt(ip.position)
        raw[2] += @spec.od / 2.0 if bop_offset?(ip)
        return raw if @points.empty?

        last = @points.last
        return Vec.add(last, Vec.scale(@axis, Vec.dot(Vec.sub(raw, last), @axis))).then { |p| apply_slope(last, p) } if @axis
        # a snapped point is the user's own geometry – used as it is, for
        # every service (no 45° tidy-up, no automatic drain fall)
        return raw if hard_snap?(ip)

        apply_slope(last, @settings['snap45'] ? snap45(last, raw) : raw)
      end

      # A point the user snapped to (endpoint, edge, guide line or guide
      # point, intersection, axis) is used exactly – the 45° lock and the
      # drain fall only tidy free cursor positions.
      def hard_snap?(ip)
        !ip.vertex.nil? || ip.degrees_of_freedom <= 1
      end

      def bop_offset?(ip)
        return false unless @settings['elevation_ref'] == 'bop'
        # only a pick on a surface (floor, beam top) lifts the pipe onto it;
        # points on edges / guides are taken as the centreline itself
        return false unless ip.face && ip.degrees_of_freedom == 2

        path = ip.respond_to?(:instance_path) ? ip.instance_path.to_a : []
        path.none? { |e| e.respond_to?(:attribute_dictionary) && H.type_of(e) }
      rescue StandardError
        false
      end

      def snap45(last, raw)
        d = Vec.sub(raw, last)
        h = Math.hypot(d[0], d[1])
        return [last[0], last[1], raw[2]] if d[2].abs > h # riser

        step = Math::PI / 4.0
        a = (Math.atan2(d[1], d[0]) / step).round * step
        u = [Math.cos(a), Math.sin(a)]
        len = d[0] * u[0] + d[1] * u[1]
        [last[0] + u[0] * len, last[1] + u[1] * len, last[2]]
      end

      def apply_slope(last, pt)
        return pt unless gravity?

        d = Vec.sub(pt, last)
        h = Math.hypot(d[0], d[1])
        return pt if h < 1.0 || d[2].abs >= 1.0 # only level segments get the fall

        [pt[0], pt[1], last[2] - h * slope_ratio]
      end

      # ---------- links to existing runs ----------

      def detect_link(pt, exclude_run: nil)
        unless exclude_run
          e = Picker.run_end(@model, pt)
          return { kind: :append, run: e[:run], tr: e[:tr], point: e[:world] } if e
        end
        n = Picker.run_node(@model, pt, exclude_run: exclude_run)
        return { kind: :node, run: n[:run], tr: n[:tr], point: n[:world], arms: n[:arms] } if n

        hit = Picker.nearest_pipe(@model, pt, exclude_run: exclude_run)
        return nil unless hit

        { kind: :tee, hit: hit, point: hit[:proj] }
      end

      # Open pipe end (its Center) under the cursor while drawing, other
      # than the end this line started from.
      def end_target(raw)
        e = Picker.run_end(@model, raw) or return nil
        return nil if Vec.dist(e[:world], @points.first) < 1.0 || Vec.dist(e[:world], @points.last) < 1.0

        { kind: :end, run: e[:run], tr: e[:tr], point: e[:world] }
      end

      def hover_tip
        return nil unless @hover

        if @hover[:kind] == :end
          "Center – ต่อเข้าปลายท่อ #{@hover[:run].name}"
        elsif @hover[:kind] == :append
          rs = Builder.run_settings(@hover[:run])
          if same_spec?(rs)
            "ต่อท่อ (continue) #{@hover[:run].name}"
          else
            "ต่อท่อ + Reducer #{rs['size']} → #{@spec.size} (new run)"
          end
        elsif @hover[:kind] == :node
          rs = Builder.run_settings(@hover[:run])
          kind = @hover[:arms] >= 3 ? 'สี่ทาง (cross)' : 'สามทาง (tee)'
          if same_spec?(rs)
            "แยกจากข้อต่อ → #{kind} #{@hover[:run].name}"
          else
            "แยกจากข้อต่อ → #{kind} + Reducer #{rs['size']} → #{@spec.size}"
          end
        else
          "แยกท่อด้วย Tee (branch from) #{@hover[:hit][:run].name}"
        end
      end

      def start_run(pt)
        link = detect_link(pt)
        if link
          # A different size/material selected → reducer + new run;
          # the same spec → simply continue the existing run.
          if %i[append node].include?(link[:kind]) && !same_spec?(Builder.run_settings(link[:run]))
            link[:kind] = :reduce if link[:kind] == :append
            link[:kind] = :node_reduce if link[:kind] == :node
          end
          @start_link = link
          pt = link[:point]
          load_settings if %i[append node].include?(link[:kind])
        end
        @points << pt
      end

      def same_spec?(rs)
        %w[catalog size rating].all? { |k| rs[k] == @settings[k] }
      end

      # Direction (world) in which run +run+ leaves its open end +p_world+.
      def end_direction(run, tr, p_world)
        inv = tr.inverse
        pl = H.transform_mm(inv, p_world)
        seg = H.get_json(run, 'cl', []).find { |a, b| Vec.dist(a, pl) <= 1.0 || Vec.dist(b, pl) <= 1.0 }
        return nil unless seg

        other = Vec.dist(seg[0], pl) <= 1.0 ? seg[1] : seg[0]
        Vec.unit(H.from_vec(H.to_vec(Vec.sub(pl, other)).transform(tr)))
      end

      # Continue run A at another size: if the new line turns, A first gets a
      # short leg in the new direction (so A's own elbow is made), then a
      # reducer in line, then the new run.
      #
      # From a corner / junction of run A (stub: true) A gets a short branch
      # leg first (its elbow becomes a tee), then the reducer and new run.
      def finish_with_reducer(segs, stub: false)
        run = @start_link[:run]
        tr = @start_link[:tr]
        p0 = segs.first[0]
        d1 = Vec.unit(Vec.sub(segs.first[1], p0))
        dir_a = end_direction(run, tr, p0) || d1
        ang = stub ? Math::PI / 2 : Vec.angle(dir_a, d1)
        raise 'ท่อย้อนกลับทางเดิม (line folds back)' if ang > 179.0 * Math::PI / 180

        spec_a = Builder.run_spec(run)
        q = p0
        @model.start_operation('Plant Piping: Reducer + New Run', true)
        warnings = []
        if ang > 0.5 * Math::PI / 180
          leg = stub ? stub_length(run) : spec_a.elbow_radius_lr * Math.tan(ang / 2.0) + 1.0
          q = Vec.add(p0, Vec.scale(d1, leg))
          inv_a = tr.inverse
          warnings.concat(Builder.extend_run(@model, run, [[H.transform_mm(inv_a, p0), H.transform_mm(inv_a, q)]],
                                             op: false))
        end
        segs = [[q, segs.first[1]]] + segs[1..]
        len = Builder.join_length(spec_a, @spec)
        raise "ช่วงแรกสั้นเกินไปสำหรับ Reducer (first segment shorter than #{len.round} mm)" if Vec.dist(*segs.first) <= len

        inv = H.edit_transform(@model).inverse
        a = H.attrs(run)
        join = { 'at' => H.transform_mm(inv, q), 'dir' => Vec.unit(H.from_vec(H.to_vec(d1).transform(inv))),
                 'main_catalog' => a['catalog'], 'main_size' => a['size'], 'main_rating' => a['rating'],
                 'main_service' => a['service'], 'main_pid' => run.persistent_id }
        local = segs.map { |x, y| [H.transform_mm(inv, x), H.transform_mm(inv, y)] }
        new_run, w = Builder.create_run(@model, local, @settings, joins: [join], op: false)
        @model.commit_operation
        adapt_supports(new_run)
        warnings + w
      rescue StandardError
        @model.abort_operation
        raise
      end

      # Branch leg of run A out of its new tee: the tee's branch outlet plus a
      # little pipe for the reducer to start on.
      def stub_length(run)
        spec = Builder.run_spec(run)
        c = spec.tee_c
        rs = Builder.run_settings(run)
        tee = Builder.refs_enabled?(rs) && Builder.ref_tee(spec)
        c = [c, Vec.length(tee['ports'][2]['p'])].max if tee
        c + 20.0
      end

      def tee_record(hit, at_world, inv)
        a = hit[:attrs]
        { 'at' => H.transform_mm(inv, at_world),
          'main_dir' => Vec.unit(H.from_vec(H.to_vec(hit[:dir]).transform(inv))),
          'main_catalog' => a['catalog'], 'main_size' => a['size'], 'main_rating' => a['rating'],
          'main_service' => a['service'], 'main_pid' => hit[:run].persistent_id,
          'main_color' => Builder.run_settings(hit[:run])['pipe_color'] }
      end

      # A branch must leave the main pipe at a real angle.
      def valid_branch?(hit, a, b)
        ang = Vec.angle(Vec.sub(b, a), hit[:dir]) * 180.0 / Math::PI
        ang = 180.0 - ang if ang > 90.0
        ang >= 30.0
      end

      def finish(view)
        if @points.size < 2
          reset_state
          return view.invalidate
        end
        end_on_end(view)
        segs = @points.each_cons(2).map { |a, b| [a, b] }.reject { |a, b| Vec.dist(a, b) < 1.0 }
        if segs.empty?
          reset_state
          return view.invalidate
        end
        if @start_link && %i[reduce node_reduce].include?(@start_link[:kind])
          report(finish_with_reducer(segs, stub: @start_link[:kind] == :node_reduce))
          reset_state
          update_status
          return view.invalidate
        end
        warnings = []
        append = @start_link && %i[append node].include?(@start_link[:kind])
        target = append ? @start_link : nil
        # ending on another run's elbow/tee: join that run so its fitting
        # becomes a tee / cross (same pipe only; different sizes start there)
        if @end_link && @end_link[:kind] == :node
          if append
            warnings << 'ปลายท่อชนข้อต่อของอีกแนวท่อ – ไม่ได้รวมเป็นสามทาง (ให้เริ่มวาดจากข้อต่อนั้นแทน)'
          elsif same_spec?(Builder.run_settings(@end_link[:run]))
            target = @end_link
          else
            warnings << 'ขนาด/วัสดุต่างกัน – เริ่มวาดจากข้อต่อนั้นเพื่อใส่สามทาง + Reducer'
          end
        end
        inv = target ? target[:tr].inverse : H.edit_transform(@model).inverse
        tees = []
        if @start_link && @start_link[:kind] == :tee
          if valid_branch?(@start_link[:hit], segs.first[0], segs.first[1])
            tees << tee_record(@start_link[:hit], @points.first, inv)
          else
            warnings << 'มุมแยกท่อน้อยกว่า 30° – ไม่ใส่ Tee (branch angle < 30°, no tee added)'
          end
        end
        if @end_link && @end_link[:kind] == :tee
          if valid_branch?(@end_link[:hit], segs.last[1], segs.last[0])
            tees << tee_record(@end_link[:hit], @points.last, inv)
          else
            warnings << 'มุมเชื่อมท่อน้อยกว่า 30° – ไม่ใส่ Tee (branch angle < 30°, no tee added)'
          end
        end
        local = segs.map { |a, b| [H.transform_mm(inv, a), H.transform_mm(inv, b)] }

        if target
          warnings += Builder.extend_run(@model, target[:run], local, tees: tees)
          changed = target[:run]
        else
          changed, w = Builder.create_run(@model, local, @settings, tees: tees)
          warnings += w
        end
        adapt_supports(changed)
        warnings << @warn_end if @warn_end
        warnings << flat_drain_warning(segs) if flat_drain_warning(segs)
        report(warnings)
        reset_state
        update_status
        view.invalidate
      rescue StandardError => e
        UI.messagebox("Plant Piping: ไม่สามารถสร้างท่อได้ (could not build run)\n#{e.message}")
        reset_state
        view.invalidate
      end

      # Ending on another run's open end: a line drawn from free space is
      # the same as drawing it out of that end (continue the run, or a
      # reducer + new run). Two linked ends are only met exactly.
      def end_on_end(_view)
        return unless @end_link && @end_link[:kind] == :end

        link = @end_link
        @end_link = nil
        if @start_link
          @warn_end = "ปลายท่อชนปลายท่อ #{link[:run].name} – ต่อตรงจุด Center แต่ไม่ได้รวมแนวท่อ " \
                      '(เริ่มวาดจากปลายท่อนั้นเพื่อให้ต่อเป็นแนวเดียว)'
          return
        end
        @points.reverse!
        kind = same_spec?(Builder.run_settings(link[:run])) ? :append : :reduce
        @start_link = { kind: kind, run: link[:run], tr: link[:tr], point: link[:point] }
        load_settings if kind == :append
      end

      # A drain drawn on snapped points follows them exactly; say so when
      # that leaves it flatter than the code minimum.
      def flat_drain_warning(segs)
        return nil unless Services.gravity?(@settings['service'])

        min = Services.min_drain_slope_pct(@spec.od)
        flat = segs.map do |a, b|
          h = Math.hypot(b[0] - a[0], b[1] - a[1])
          h < 1.0 || (b[2] - a[2]).abs > h ? nil : (a[2] - b[2]) / h * 100.0
        end.compact
        worst = flat.min
        return nil unless worst && worst < min - 1e-6

        "ท่อระบายวาดตามจุดที่สแนป (เส้นไกด์) – ความลาด #{worst.round(2)}% น้อยกว่าขั้นต่ำ #{min}% " \
          '(ปรับระดับเส้นไกด์ หรือวาดโดยไม่สแนปเพื่อให้ใส่ความลาดอัตโนมัติ)'
      end

      # Supports next to the new pipe take it in (shared supports).
      def adapt_supports(run)
        SupportBuilder.adapt(@model, [run]) if run
      rescue StandardError => e
        puts "Plant Piping: supports not adapted – #{e.message}"
      end

      def report(warnings)
        return if warnings.empty?

        shown = warnings.uniq.first(10)
        more = warnings.uniq.size > 10 ? "\n… (+#{warnings.uniq.size - 10})" : ''
        UI.messagebox("Plant Piping – ข้อควรตรวจสอบ (review):\n\n• #{shown.join("\n• ")}#{more}")
      end

      # ---------- UI feedback ----------

      def update_vcb
        Sketchup.vcb_label = 'Length'
        return unless @cursor && !@points.empty?

        len = Vec.dist(@cursor, @points.last)
        Sketchup.vcb_value = Sketchup.format_length(H.mm(len))
      end

      def update_status
        svc = Services.get(@settings['service'])
        mode = if @start_link && @start_link[:kind] == :append
                 "ต่อท่อ #{@start_link[:run].name} | "
               else
                 ''
               end
        slope = gravity? ? " | ลาด #{@settings['slope_pct']}% (min #{Services.min_drain_slope_pct(@spec.od)}%)" : ''
        Sketchup.status_text = "#{mode}#{svc[:code]} #{@spec.size} #{@spec.material} #{@spec.rating}#{slope} | " \
                               'คลิกจุด, พิมพ์ความยาว, ลูกศร=ล็อกแกน, ดับเบิลคลิก/Enter=จบ, Esc=ยกเลิก'
      end

      def draw_readout(view)
        return unless @cursor

        if @points.empty?
          sc = view.screen_coords(H.to_pt(@cursor))
          txt = "#{@spec.size} #{@settings['service']} · #{@spec.material} #{@spec.rating} – คลิกจุดเริ่ม (click start)"
          view.draw_text(Geom::Point3d.new(sc.x + 18, sc.y + 18, 0), txt)
          return
        end

        last = @points.last
        len = Vec.dist(@cursor, last)
        dz = @cursor[2] - last[2]
        txt = "#{@spec.size} #{@settings['service']}  L=#{len.round} mm"
        txt += "  Δz=#{dz.round} mm" if dz.abs >= 1.0
        sc = view.screen_coords(H.to_pt(@cursor))
        view.draw_text(Geom::Point3d.new(sc.x + 18, sc.y + 18, 0), txt)
      end
    end
  end
end
