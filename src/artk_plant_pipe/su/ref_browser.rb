# frozen_string_literal: true

require 'json'

module ArtK
  module PlantPipe
    # Browser for the reference library (every part copied from the user's
    # reference files) and the tool that places one.
    module RefBrowser
      H = ModelHelpers

      GROUPS = {
        'elbow90' => 'fittings', 'elbow45' => 'fittings', 'tee' => 'fittings', 'san_tee' => 'fittings',
        'wye' => 'fittings', 'double_wye' => 'fittings', 'cross' => 'fittings', 'san_cross' => 'fittings',
        'coupling' => 'fittings', 'reducer' => 'fittings', 'union' => 'fittings', 'cap' => 'fittings',
        'hex_nipple' => 'fittings', 'nipple' => 'fittings', 'hose' => 'fittings', 'p_trap' => 'fittings',
        'u_trap' => 'fittings', 'flange' => 'flanges', 'flange_wn' => 'flanges', 'blind' => 'flanges',
        'flowmeter' => 'instruments', 'gauge' => 'instruments', 'water_meter' => 'instruments'
      }.freeze

      MOUNT_TEXT = { inline: 'สแนปเข้าแนวท่อ', end: 'สแนปที่ปลายท่อ', top: 'ติดบนท่อ' }.freeze

      class << self
        def show
          if @dialog&.visible?
            @dialog.bring_to_front
            return
          end
          @dialog = UI::HtmlDialog.new(
            dialog_title: 'Plant Piping TH – Reference Library / คลังอุปกรณ์จริง',
            preferences_key: 'ArtK_PlantPipe_RefLibrary',
            width: 520, height: 760, min_width: 420, resizable: true,
            style: UI::HtmlDialog::STYLE_UTILITY
          )
          @dialog.set_file(File.join(PLUGIN_ROOT, 'ui', 'library.html'))
          @dialog.add_action_callback('ready') { |_ctx| push }
          @dialog.add_action_callback('insert') { |_ctx, key| insert(key) }
          @dialog.show
        end

        def payload
          Refs.items.map do |i|
            { key: i['key'], name: Refs.display_name(i), type: i['type'], family: i['family'],
              family_name: Refs::FAMILY_NAMES[i['family']] || i['family'], size: i['size'].to_s,
              nps: i['nps'] || 0, group: GROUPS.fetch(i['type'], 'valves'), standard: i['standard'].to_s,
              snap: MOUNT_TEXT[Refs.mount(i)], sized: Refs::SIZED_TEXT[i['type']] || (i['scalable'] ? true : false), src: i['src_name'],
              thumb: Refs.thumb_name(i) }
          end
        end

        # BOM record of a part placed on its own (not inside a run).
        def component_attrs(item, k = 1.0)
          cat = case item['type']
                when 'elbow90', 'elbow45' then 'elbow'
                when 'tee', 'san_tee', 'wye', 'double_wye', 'cross', 'san_cross' then 'tee'
                when 'reducer' then 'reducer'
                else Bom.inline_category(item['type'])
                end
          size = [item['size'], item['size2']].compact.join(' x ')
          size = "#{size} ×#{k.round(2)}" if k != 1.0
          { 'type' => 'component', 'category' => cat, 'size' => size, 'material' => item['standard'],
            'name_desc' => Refs::TYPE_NAMES.fetch(item['type'], [nil, item['type']])[1],
            'model' => item['sized_from'] || item['key'], DataFormat::KEY => DataFormat::CURRENT }
        end

        def insert(key)
          item = Refs.get(key) or return
          Sketchup.active_model.select_tool(RefPlaceTool.new(item))
        end

        private

        def push
          @dialog.execute_script("PP.init(#{JSON.generate(payload)})")
        end
      end
    end

    # Places one reference part, fitted to the pipe it is put on:
    #   in-line parts (valves, unions, meters, flowmeters …) sit on a straight
    #     pipe with their end circles on the pipe axis, and become part of
    #     that run (kept through rebuilds);
    #   end parts (elbows, tees, caps, flanges, faucets …) put their first
    #     end circle onto an open pipe end and become part of that run, so
    #     they follow the end when the pipe is stretched;
    #   gauges go on top of the pipe at their own size.
    # The library part of the pipe's size is used when it exists, otherwise
    # the chosen part is scaled from the pipe it was modelled for. Anything
    # else (or away from pipes) is placed freely. ← → turn it 90°.
    class RefPlaceTool
      H = ModelHelpers

      def initialize(item)
        @item = item
        @angle = 0.0
      end

      def activate
        @model = Sketchup.active_model
        @ip = Sketchup::InputPoint.new
        @place = nil
        RunEditor.sync_context(@model) if defined?(RunEditor)
        how = { inline: 'คลิกบนท่อตรง', end: 'คลิกที่ปลายท่อ', top: 'คลิกบนท่อ (ติดด้านบน)' }
                .fetch(Refs.mount(@item), 'คลิกตำแหน่งที่ต้องการ')
        Sketchup.status_text = "วาง: #{Refs.display_name(@item)} – #{how} (ขนาดปรับตามท่อ) | ← → หมุน 90°"
      end

      def deactivate(view)
        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        @ip.pick(view, x, y)
        @view_dir = H.from_vec(view.camera.direction) if view.respond_to?(:camera)
        @place = @ip.valid? ? placement(H.from_pt(@ip.position)) : nil
        view.tooltip = @place ? @place[:tip] : ''
        view.invalidate
      end

      def onKeyDown(key, _repeat, _flags, view)
        return false unless [VK_LEFT, VK_RIGHT].include?(key)

        @angle += (key == VK_RIGHT ? 1 : -1) * Math::PI / 2.0
        view.invalidate
        true
      end

      def onLButtonDown(_flags, _x, _y, view)
        return UI.beep unless @place

        commit(@place)
        view.invalidate
      rescue StandardError => e
        UI.messagebox("Plant Piping: วางไม่สำเร็จ (could not place)\n#{e.message}")
      end

      def draw(view)
        @ip.draw(view) if @ip.valid? && @ip.display?
        return unless @place

        view.line_width = 2
        view.drawing_color = @place[:mode] == :free ? Sketchup::Color.new(20, 90, 200) : Sketchup::Color.new(0, 150, 0)
        tr = H.frame_transform(@place[:frame]) * Geom::Transformation.scaling(@place[:k])
        mn, mx = @place[:item]['bbox']
        c = [[mn[0], mx[0]], [mn[1], mx[1]], [mn[2], mx[2]]]
        pts = c[0].product(c[1], c[2]).map { |p| H.to_pt(p).transform(tr) }
        [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]].each do |i, j|
          view.draw(GL_LINES, pts[i], pts[j])
        end
      end

      def getExtents
        bb = Geom::BoundingBox.new
        bb.add(H.to_pt(@place[:frame][:o])) if @place
        bb
      end

      # ---- placement (world mm) ----

      def placement(pt)
        case Refs.mount(@item)
        when :inline then inline_place(pt)
        when :end then end_place(pt)
        when :top then top_place(pt)
        end || free_place(pt)
      end

      private

      # Part for this pipe: the library part of that size, else the chosen
      # one scaled to the pipe.
      def fit(spec)
        if Refs.sized_type?(@item)
          it = Refs.sized_item(@item, spec)
          return it && [it, 1.0]
        end
        it = @item['scalable'] ? nil : Refs.variant_for(@item, spec)
        it ? [it, 1.0] : [@item, Refs.scale_for(@item, spec.od)]
      end

      def size_tip(it, k, spec)
        return "ขนาด #{spec.size}" if k == 1.0

        "ขนาด #{spec.size} (ปรับจากโมเดล #{it['size'] || '-'} ×#{k.round(2)})"
      end

      def roll(u, base)
        y = Vec.sub(base, Vec.scale(u, Vec.dot(base, u)))
        y = Vec.perpendicular(u) if Vec.length(y) < 1e-3
        Vec.rotate(Vec.unit(y), Vec.unit(u), @angle)
      end

      def inline_place(pt)
        hit = Picker.nearest_pipe(@model, pt, extra: 50.0) or return nil
        spec = Builder.run_spec(hit[:run])
        it, = fit(spec)
        return no_size(pt, spec) unless it

        type = it['type']
        kx, kr = Builder.valve_scale(type, spec, it)
        len = Builder.ref_valve_length(spec, it, type)
        return { mode: :free, item: it, k: 1.0, frame: Mesh.frame(pt, [1.0, 0, 0], [0, 0, 1.0]),
                 tip: "ท่อตรงสั้นกว่าอุปกรณ์ (#{len.round} mm)" } if hit[:len] < len

        s = [[hit[:t] * hit[:len], len / 2.0].max, hit[:len] - len / 2.0].min
        at = Vec.add(hit[:a], Vec.scale(hit[:dir], s))
        up = Builder.stem_direction(hit[:dir])
        { mode: :inline, item: it, hit: hit, at: at, k: [kx, kr, kr].uniq.size == 1 ? kx : 1.0,
          frame: Mesh.frame(at, hit[:dir], up),
          tip: "#{Refs.display_name(it).split(' – ').first} บน #{hit[:run].name} – #{size_tip(it, kx, spec)}" }
      end

      def end_place(pt)
        e = Picker.run_end(@model, pt, tol: 80.0) or return nil
        run = e[:run]
        seg = H.get_json(run, 'cl', []).find { |a, b| Vec.dist(a, e[:local]) <= 1.0 || Vec.dist(b, e[:local]) <= 1.0 }
        return nil unless seg

        other = Vec.dist(seg[0], e[:local]) <= 1.0 ? seg[1] : seg[0]
        u_local = Vec.unit(Vec.sub(e[:local], other))
        u = Vec.unit(H.from_vec(H.to_vec(u_local).transform(e[:tr])))
        spec = Builder.run_spec(run)
        it, k = fit(spec)
        return no_size(pt, spec) unless it

        m = Refs.mouth_point(it, 0, e[:world], u, k)
        frame = Refs.port_frame(it, 0, m, u, roll(u, [0.0, 0.0, 1.0]), k)
        { mode: :end, item: it, k: k, frame: frame, run: run, local: e[:local],
          tip: "#{Refs.display_name(it).split(' – ').first} ที่ปลาย #{run.name} – #{size_tip(it, k, spec)}" }
      end

      def top_place(pt)
        hit = Picker.nearest_pipe(@model, pt, extra: 50.0) or return nil
        n = Builder.stem_direction(hit[:dir])
        r = hit[:attrs]['od'].to_f / 2.0
        m = Vec.add(hit[:proj], Vec.scale(n, r))
        face = @view_dir ? Vec.scale(@view_dir, -1.0) : Vec.perpendicular(n)
        frame = Refs.port_frame(@item, 0, m, n, roll(n, face), 1.0)
        { mode: :top, item: @item, k: 1.0, frame: frame, tip: "#{Refs.display_name(@item).split(' – ').first} บน #{hit[:run].name}" }
      end

      def no_size(pt, spec)
        free_place(pt).merge(tip: "#{Refs::TYPE_NAMES[@item['type']][0]} มีขนาดมาตรฐาน " \
                                  "#{Refs::SIZED_TEXT[@item['type']]} – ไม่มีสำหรับท่อ #{spec.size}")
      end

      def free_place(pt)
        x = [Math.cos(@angle), Math.sin(@angle), 0.0]
        tip = Refs.mount(@item) ? 'วางอิสระ – ชี้ที่ท่อเพื่อสแนป' : 'วางอิสระ (← → หมุน)'
        { mode: :free, item: @item, k: 1.0, frame: Mesh.frame(pt, x, [0.0, 0.0, 1.0]), tip: tip }
      end

      # ---- commit ----

      def commit(place)
        if place[:mode] == :inline
          hit = place[:hit]
          inv = hit[:tr].inverse
          at = H.transform_mm(inv, place[:at])
          dir = Vec.unit(H.from_vec(H.to_vec(hit[:dir]).transform(inv)))
          Builder.add_valve(@model, hit[:run], place[:item]['type'], at, dir, model_key: place[:item]['sized_from'] || place[:item]['key'])
        elsif place[:mode] == :end
          # fixed to the run: follows the end when the pipe is stretched
          Builder.add_end_part(@model, place[:run], @item['key'], place[:local], @angle)
        else
          place_instance(place)
        end
      end

      def place_instance(place)
        it = place[:item]
        @model.start_operation('Plant Piping: Place Library Part', true)
        defn = RefModels.definition(@model, it)
        tr = @model.edit_transform.inverse * H.frame_transform(place[:frame])
        tr *= Geom::Transformation.scaling(place[:k]) if place[:k] != 1.0
        inst = @model.active_entities.add_instance(defn, tr)
        inst.material = RefModels.role_material(@model, it['material'])
        inst.name = Refs.display_name(it)
        H.set_attrs(inst, RefBrowser.component_attrs(it, place[:k]))
        @model.commit_operation
        inst
      rescue StandardError
        @model.abort_operation
        raise
      end
    end
  end
end
