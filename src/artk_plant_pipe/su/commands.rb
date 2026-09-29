# frozen_string_literal: true

module ArtK
  module PlantPipe
    # Menu / toolbar command implementations.
    module Commands
      H = ModelHelpers
      MARKER_TAG = 'PP-Check Markers'

      module_function

      def draw_pipe
        Sketchup.active_model.select_tool(PipeTool.new)
      end

      def insert_valve(type = nil)
        type ||= H.load_settings['valve_type']
        Sketchup.active_model.select_tool(ValveTool.new(type))
      end

      # Convert selected edges (drawn with the normal Line tool) into runs –
      # handy for tracing pipes over imported CAD plans. Each connected set
      # of edges becomes one run; junctions become tees/crosses.
      def convert_selection
        model = Sketchup.active_model
        edges = model.selection.grep(Sketchup::Edge)
        if edges.empty?
          UI.messagebox('เลือกเส้น (Edges) ที่เป็นแนวศูนย์กลางท่อก่อน (select centreline edges first)')
          return
        end
        segs = edges.map { |e| [H.from_pt(e.start.position), H.from_pt(e.end.position)] }
        settings = H.load_settings
        comps = Network.components(segs)
        warnings = []
        model.start_operation('Plant Piping: Convert Edges', true)
        comps.each do |c|
          _run, w = Builder.create_run(model, c, settings, op: false)
          warnings.concat(w)
        end
        free = edges.select { |e| e.valid? && e.faces.empty? }
        if !free.empty? &&
           UI.messagebox("ลบเส้นต้นแบบ #{free.size} เส้น? (delete the source edges?)", MB_YESNO) == IDYES
          model.active_entities.erase_entities(free)
        end
        model.commit_operation
        summary = "สร้าง #{comps.size} แนวท่อ (created #{comps.size} run(s))"
        show_warnings(warnings, summary)
      rescue StandardError => e
        model.abort_operation
        UI.messagebox("Plant Piping: แปลงเส้นไม่สำเร็จ (convert failed)\n#{e.message}")
      end

      def rebuild_selection
        model = Sketchup.active_model
        runs = H.selected_runs(model)
        if runs.empty?
          UI.messagebox('เลือกแนวท่อที่ต้องการปรับ (select one or more pipe runs)')
          return
        end
        s = H.load_settings
        msg = "ปรับ #{runs.size} แนวท่อ เป็น #{s['service']} #{s['size']} " \
              "#{Catalog.get(s['catalog'])[:material]} #{s['rating']} ?\n" \
              "(apply current settings to #{runs.size} run(s))"
        return unless UI.messagebox(msg, MB_OKCANCEL) == IDOK

        warnings = Builder.rebuild(model, runs, s)
        show_warnings(warnings, 'ปรับแนวท่อเรียบร้อย (runs rebuilt)')
      rescue StandardError => e
        UI.messagebox("Plant Piping: ปรับแนวท่อไม่สำเร็จ\n#{e.message}")
      end

      def set_design_flow
        model = Sketchup.active_model
        runs = H.selected_runs(model)
        if runs.empty?
          UI.messagebox('เลือกแนวท่อก่อน (select pipe runs first)')
          return
        end
        current = runs.first.get_attribute(H::DICT, 'design_flow_m3h').to_f
        res = UI.inputbox(['อัตราการไหลออกแบบ (m³/h)', 'หรือ (or) L/s'], [current.round(3).to_s, '0'],
                          'Design Flow')
        return unless res

        q = res[0].to_f
        q = res[1].to_f * 3.6 if res[1].to_f.positive?
        model.start_operation('Plant Piping: Design Flow', true)
        runs.each { |r| r.set_attribute(H::DICT, 'design_flow_m3h', q) }
        model.commit_operation
        Sketchup.status_text = "Design flow #{q.round(3)} m³/h → #{runs.size} run(s)"
      end

      # ---------- hydraulic report ----------

      def hydraulic_report
        model = Sketchup.active_model
        runs = H.selected_runs(model)
        runs = Collector.all_runs(model).map(&:first) if runs.empty?
        if runs.empty?
          UI.messagebox('ยังไม่มีแนวท่อในโมเดล (no pipe runs in the model)')
          return
        end
        world = Collector.all_runs(model).to_h
        results = runs.map { |r| [r, RunCheck.check(Collector.run_data(r))] }
        place_profile_markers(model, results, world)

        headers = ['Line No.', 'Service', 'Size / ID (mm)', 'Q (m³/h)', 'v (m/s)', 'L (m)', 'hf/100m',
                   'ΣK', 'Δz (m)', 'Total loss (m / bar)', 'Status / ข้อสังเกต']
        rows = results.map do |run, r|
          s = Builder.run_settings(run)
          loss = r[:total_head] ? "#{r[:total_head]} / #{r[:total_bar]}" : '-'
          if r[:capacity_m3h]
            loss = "Cap. ½-full #{r[:capacity_m3h]} m³/h @ #{r[:min_slope_pct]}%"
          end
          [run.name, s['service'], "#{s['size']} / #{r[:id_mm]}", r[:flow_m3h], r[:velocity] || '-',
           r[:length_m], r[:hf100] || '-', r[:k_sum] || '-', r[:dz] || '-', loss,
           (r[:ok] ? 'OK. ' : 'CHECK. ') + r[:messages].join(' | ')]
        end
        note = '<p class="mut">Darcy–Weisbach + Swamee–Jain (ท่อแรงดัน), ΣK ของข้อต่อ/วาล์ว ' \
               '(ค่าทั่วไปจาก Crane TP-410), Manning n=0.011 ที่ความลึกครึ่งท่อ (ท่อระบาย). ' \
               'จุดสูง/ต่ำที่พบถูกทำเครื่องหมายไว้ใน Tag "PP-Check Markers". ' \
               'Tee ภายในแนวท่อคิดเป็นการไหลผ่านตรง (run) – ปรับตามการกระจายการไหลจริง.</p>'
        Reports.show('Hydraulic Check – ตรวจสอบไฮดรอลิก',
                     note + Reports.table(headers, rows, row_class: ->(i) { results[i][1][:ok] ? 'ok' : 'bad' }))
      end

      def place_profile_markers(model, results, world)
        model.start_operation('Plant Piping: Check Markers', true)
        clear_markers(model)
        grp = nil
        results.each do |run, r|
          tr = world[run] || run.transformation
          [[r[:low_points], 'LOW PT'], [r[:high_points], 'HIGH PT']].each do |pts, label|
            (pts || []).each do |p|
              grp ||= new_marker_group(model)
              pos = H.to_pt(H.transform_mm(tr, p))
              grp.entities.add_cpoint(pos)
              grp.entities.add_text("#{label} #{run.name}", pos, Geom::Vector3d.new(0, 0, H.mm(400)))
            end
          end
        end
        model.commit_operation
      end

      def new_marker_group(model)
        g = model.entities.add_group
        g.name = 'Plant Piping Check Markers'
        g.layer = H.tag(model, MARKER_TAG)
        H.set_attrs(g, 'type' => 'markers')
        g
      end

      def clear_markers(model)
        old = model.entities.select { |e| H.instance?(e) && H.type_of(e) == 'markers' }
        model.entities.erase_entities(old) unless old.empty?
      end

      # ---------- BOM ----------

      def bom
        model = Sketchup.active_model
        runs = H.selected_runs(model)
        records = runs.empty? ? Collector.records(model) : Collector.records(model, runs: runs)
        if records.empty?
          UI.messagebox('ไม่พบท่อที่สร้างด้วย Plant Piping (no Plant Piping objects found)')
          return
        end
        settings = H.load_settings
        rows = Bom.aggregate(records, waste: settings['waste_pct'] / 100.0)
        joints = Bom.joint_estimate(records)
        scope = runs.empty? ? 'ทั้งโมเดล (whole model)' : "#{runs.size} แนวท่อที่เลือก (selected runs)"
        title = "BOM – #{model.title.empty? ? 'Untitled' : model.title} – #{scope}"
        csv = Bom.to_csv(rows, title: title, joints: joints)
        table_rows = rows.each_with_index.map do |r, i|
          [i + 1, "#{r.category} (#{Bom::CATEGORY_TH[r.category]})", r.description, r.service, r.material,
           r.size, r.rating, r.qty, r.unit, r.sticks, r.weight, r.remark]
        end
        note = "<p class='mut'>#{Reports.esc(scope)} · เผื่อเศษตัด (cutting waste) #{settings['waste_pct']}% " \
               "สำหรับจำนวนท่อน · รอยต่อหน้างานโดยประมาณ (est. field joints): <b>#{joints}</b></p>"
        Reports.show('Bill of Materials – รายการวัสดุ', note + Reports.table(Bom::HEADER, table_rows),
                     csv: csv, csv_name: 'PlantPiping_BOM.csv')
      end

      # ---------- clash ----------

      def clash_check
        model = Sketchup.active_model
        res = UI.inputbox(['ระยะห่างต่ำสุด Min. clearance (mm)'], ['25'], 'Clash / Clearance Check')
        return unless res

        clearance = res[0].to_f
        items = Collector.clash_items(model)
        clashes = Clash.find(items, clearance: clearance, connections: Collector.connections(model))
        names = {}
        Collector.all_runs(model).each { |r, _| names[r.persistent_id] = r.name }

        model.start_operation('Plant Piping: Clash Markers', true)
        old = model.entities.select { |e| H.instance?(e) && H.type_of(e) == 'clash' }
        model.entities.erase_entities(old) unless old.empty?
        unless clashes.empty?
          g = model.entities.add_group
          g.name = 'Plant Piping Clashes'
          g.layer = H.tag(model, H::TAG_CLASH)
          H.set_attrs(g, 'type' => 'clash')
          clashes.each_with_index do |c, i|
            pos = H.to_pt(c[:point])
            g.entities.add_cpoint(pos)
            g.entities.add_text("C#{i + 1}: #{c[:gap]} mm", pos, Geom::Vector3d.new(0, 0, H.mm(300)))
          end
        end
        model.commit_operation

        if clashes.empty?
          UI.messagebox("ไม่พบการชนกัน ที่ระยะห่าง #{clearance} mm (no clashes found)")
          return
        end
        rows = clashes.each_with_index.map do |c, i|
          kind = c[:gap].negative? ? 'ชนกัน (HARD CLASH)' : 'ระยะห่างไม่พอ (clearance)'
          ["C#{i + 1}", c[:labels][0], c[:labels][1], c[:gap], kind,
           c[:point].map { |v| v.round }.join(', ')]
        end
        Reports.show('Clash Check – ตรวจสอบการชนกัน',
                     "<p class='mut'>ระยะรวมฉนวนแล้ว (insulation included). " \
                     "ตำแหน่งถูกทำเครื่องหมายใน Tag \"#{H::TAG_CLASH}\".</p>" +
                     Reports.table(['#', 'Run A', 'Run B', 'Gap (mm)', 'Type', 'Location (mm)'], rows,
                                   row_class: ->(i) { clashes[i][:gap].negative? ? 'bad' : nil }))
      end

      # ---------- misc ----------

      def show_warnings(warnings, summary)
        uniq = warnings.uniq
        if uniq.empty?
          Sketchup.status_text = summary
          return
        end
        more = uniq.size > 12 ? "\n… (+#{uniq.size - 12})" : ''
        UI.messagebox("#{summary}\n\nข้อควรตรวจสอบ (review):\n• #{uniq.first(12).join("\n• ")}#{more}")
      end

      def help
        UI.messagebox(<<~TXT)
          Plant Piping TH #{VERSION}

          Draw Pipe: คลิกจุดแนวศูนย์กลางท่อ | พิมพ์ความยาว | ลูกศร → ← ↑ ล็อกแกน X Y Z, ↓ ปลด
          Shift ค้าง = ล็อกทิศทาง | Backspace = ลบจุดล่าสุด | ดับเบิลคลิก/Enter = จบ | Esc = ยกเลิก
          คลิกจุดแรกบนท่อเดิม = แยกท่อด้วย Tee | คลิกที่ปลายท่อเดิม = ต่อท่อ

          Insert Valve: คลิกบนท่อตรง | Tab = เปลี่ยนชนิดวาล์ว
          Convert Edges: วาดเส้นด้วย Line tool แล้วแปลงเป็นท่อ (รองรับ Tee/Cross)
          Rebuild: เปลี่ยนขนาด/วัสดุ/ระบบของท่อที่เลือก ตามค่าในหน้าต่าง Settings
        TXT
      end
    end
  end
end
