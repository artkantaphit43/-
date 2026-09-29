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
        'flowmeter' => 'instruments', 'gauge' => 'instruments'
      }.freeze

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
              snap: inline?(i), src: i['src_name'], thumb: Refs.thumb_name(i) }
          end
        end

        def inline?(item)
          item['ports'].size == 2 && Vec.dot(item['ports'][0]['d'], item['ports'][1]['d']) < -0.99
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

    # Places one reference part. In-line parts (valves, unions, flowmeters,
    # strainers …) snap onto a straight pipe of the same size and become part
    # of that run (kept through rebuilds); anything else is placed freely,
    # upright, and ← → rotate it by 90°.
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
        Sketchup.status_text = "วาง: #{Refs.display_name(@item)} – คลิกบนท่อ (อุปกรณ์แบบอินไลน์) หรือจุดใดก็ได้ | ← → หมุน 90°"
      end

      def deactivate(view)
        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        @ip.pick(view, x, y)
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

        if @place[:hit]
          hit = @place[:hit]
          inv = hit[:tr].inverse
          at = H.transform_mm(inv, @place[:at])
          dir = Vec.unit(H.from_vec(H.to_vec(hit[:dir]).transform(inv)))
          Builder.add_valve(@model, hit[:run], @item['type'], at, dir, model_key: @item['key'])
        else
          place_free(@place[:at])
        end
        view.invalidate
      rescue StandardError => e
        UI.messagebox("Plant Piping: วางไม่สำเร็จ (could not place)\n#{e.message}")
      end

      def draw(view)
        @ip.draw(view) if @ip.valid? && @ip.display?
        return unless @place

        view.line_width = 2
        view.drawing_color = @place[:hit] ? Sketchup::Color.new(0, 150, 0) : Sketchup::Color.new(20, 90, 200)
        tr = transform(@place)
        mn, mx = @item['bbox']
        c = [mn, mx].then { |a, b| [[a[0], b[0]], [a[1], b[1]], [a[2], b[2]]] }
        pts = c[0].product(c[1], c[2]).map { |p| H.to_pt(p).transform(tr) }
        [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]].each do |i, j|
          view.draw(GL_LINES, pts[i], pts[j])
        end
      end

      def getExtents
        bb = Geom::BoundingBox.new
        bb.add(H.to_pt(@place[:at])) if @place
        bb
      end

      private

      def placement(pt)
        if RefBrowser.inline?(@item)
          hit = Picker.nearest_pipe(@model, pt, extra: 50.0)
          if hit && hit[:attrs]['size'] == @item['size']
            len = Vec.dist(@item['ports'][0]['p'], @item['ports'][1]['p'])
            if hit[:len] >= len
              s = [[hit[:t] * hit[:len], len / 2.0].max, hit[:len] - len / 2.0].min
              at = Vec.add(hit[:a], Vec.scale(hit[:dir], s))
              return { hit: hit, at: at, tip: "#{Refs.display_name(@item)} บน #{hit[:run].name}" }
            end
          end
        end
        tip = RefBrowser.inline?(@item) ? "วางอิสระ – ชี้บนท่อขนาด #{@item['size']} เพื่อสแนปเข้าแนวท่อ" : 'วางอิสระ (← → หมุน)'
        { hit: nil, at: pt, tip: tip }
      end

      # Canonical +Y (stem / up) → world Z; +X turned by the arrow keys.
      def transform(place)
        if place[:hit]
          dir = place[:hit][:dir]
          up = Builder.stem_direction(dir)
          H.frame_transform(Mesh.frame(place[:at], dir, up))
        else
          x = [Math.cos(@angle), Math.sin(@angle), 0.0]
          H.frame_transform(Mesh.frame(place[:at], x, [0.0, 0.0, 1.0]))
        end
      end

      def place_free(at)
        @model.start_operation('Plant Piping: Place Library Part', true)
        defn = RefModels.definition(@model, @item)
        tr = @model.edit_transform.inverse * transform(hit: nil, at: at)
        inst = @model.active_entities.add_instance(defn, tr)
        inst.material = RefModels.role_material(@model, @item['material'])
        inst.name = Refs.display_name(@item)
        cat = case @item['type']
              when 'elbow90', 'elbow45' then 'elbow'
              when 'tee', 'san_tee', 'wye', 'double_wye', 'cross', 'san_cross' then 'tee'
              when 'reducer' then 'reducer'
              else Bom.inline_category(@item['type'])
              end
        H.set_attrs(inst, 'type' => 'component', 'category' => cat, 'name_desc' => Refs::TYPE_NAMES.fetch(@item['type'], [nil, @item['type']])[1],
                          'size' => [@item['size'], @item['size2']].compact.join(' x '), 'material' => @item['standard'],
                          'model' => @item['key'])
        @model.commit_operation
      rescue StandardError
        @model.abort_operation
        raise
      end
    end
  end
end
