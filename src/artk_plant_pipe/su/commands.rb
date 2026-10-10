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

      # nil = follow the type selected in the settings dialog.
      def insert_valve(type = nil)
        Sketchup.active_model.select_tool(ValveTool.new(type))
      end

      def stretch_tool
        Sketchup.active_model.select_tool(StretchTool.new)
      end

      # Compare every pipe with its record: stretched open ends are taken
      # into the run; anything else is listed and can be put back.
      def check_pipes
        model = Sketchup.active_model
        runs = H.selected_runs(model)
        runs = Collector.all_runs(model).map(&:first) if runs.empty?
        found = runs.map { |r| [r, RunEditor.inspect(r)] }
        stretched = found.reject { |_, f| f[:moves].empty? }
        broken = found.reject { |_, f| f[:issues].empty? }
        if stretched.empty? && broken.empty?
          UI.messagebox("ตรวจ #{runs.size} แนวท่อ: รูปทรงตรงกับข้อมูลทั้งหมด\n(all #{runs.size} run(s) match their data)")
          return
        end

        lines = []
        stretched.each { |r, f| lines << "• #{r.name}: ปลายท่อถูกยืด/หด #{f[:moves].size} จุด → รับค่าใหม่" }
        broken.each { |_, f| f[:issues].first(4).each { |x| lines << "• #{x}" } }
        more = lines.size > 14 ? "\n… (+#{lines.size - 14})" : ''
        msg = "พบท่อที่รูปทรงไม่ตรงกับข้อมูล (pipes that differ from their data):\n#{lines.first(14).join("\n")}#{more}\n\n" \
              "ซ่อมเลยไหม? ปลายที่ยืดจะรับความยาวใหม่ ส่วนที่ผิดรูปจะกลับเป็นตามข้อมูล\n" \
              '(fix: keep stretched ends, rebuild the rest from data)'
        return unless UI.messagebox(msg, MB_YESNO) == IDYES

        res = RunEditor.sync(model, stretched.map(&:first))
        rest = broken.map(&:first) - res[:synced]
        warnings = res[:warnings]
        unless rest.empty?
          model.start_operation('Plant Piping: Restore Pipes', true)
          rest.each do |r|
            warnings.concat(Builder.render(model, r, Builder.run_settings(r)).map { |w| "#{r.name}: #{w}" })
          end
          model.commit_operation
        end
        show_warnings(warnings, "ซ่อม #{res[:synced].size + rest.size} แนวท่อแล้ว (pipes fixed)")
      rescue StandardError => e
        UI.messagebox("Plant Piping: ตรวจท่อไม่สำเร็จ\n#{e.message}")
      end

      def toggle_auto_sync
        AutoSync.enabled = !AutoSync.enabled?
        Sketchup.status_text = AutoSync.enabled? ? 'อ่านความยาวท่อที่ยืดเองอัตโนมัติ: เปิด' : 'อ่านความยาวท่อที่ยืดเองอัตโนมัติ: ปิด'
      end

      def register_model
        Sketchup.active_model.select_tool(RegisterModelTool.new)
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
        # arcs / curves (Arc, Freehand, Bezier, CAD splines) become pipe bent
        # along them instead of an elbow at every facet
        curves = edges.filter_map { |e| e.respond_to?(:curve) && e.curve }.uniq
                      .map { |c| c.vertices.map { |v| H.from_pt(v.position) } }
        smooth = Network.curve_points(segs, curves)
        warnings = []
        model.start_operation('Plant Piping: Convert Edges', true)
        comps.each do |c|
          pts = c.flatten(1)
          own = smooth.select { |p| pts.any? { |q| Vec.dist(p, q) <= 1.0 } }
          _run, w = Builder.create_run(model, c, settings, op: false, smooth: own)
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

        # pipes stretched with SketchUp's own tools keep their new length
        pre = RunEditor.sync(model, runs)
        warnings = pre[:warnings] + Builder.rebuild(model, runs, s)
        SupportBuilder.adapt(model, runs)
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

      # ---------- supports ----------

      def support_tool(type = nil)
        Sketchup.active_model.select_tool(SupportTool.new(type))
      end

      # Place supports along the selected runs at the maximum span for their
      # material & size, near fittings and next to valves.
      def auto_supports
        model = Sketchup.active_model
        runs = H.selected_runs(model)
        if runs.empty?
          UI.messagebox('เลือกแนวท่อที่ต้องการใส่ซัพพอร์ตก่อน (select pipe runs first)')
          return
        end
        st = H.load_settings
        type = st['support_type']
        if type == 'column'
          UI.messagebox('แขนเกาะข้างเสา วางทีละจุด: ใช้ "วางทีละจุด" แล้วคลิกท่อตรงช่วงที่ผ่านเสา ' \
                        '(column brackets go where the columns are – use the Support tool)')
          return
        end
        world = H.edit_transform(model)
        notes = []
        total = 0
        shared = 0
        risers = 0
        paired = 0
        # one-per-pipe types (beam clamps): neighbours get their own at the
        # same sections; every run is written once all are placed
        each = SupportBuilder.each_pipe?(type)
        own = {}
        extra = {}
        model.start_operation('Plant Piping: Auto Supports', true)
        runs.each { |run| H.set_json(run, 'supports', []) } if each
        pending = lambda do
          (own.keys + extra.keys).uniq.to_h do |r|
            t = world * r.transformation
            [r.persistent_id, ((own[r] || []) + (extra[r] || [])).map { |rec| H.transform_mm(t, rec['at']) }]
          end
        end
        runs.each do |run|
          tr = world * run.transformation
          inv = tr.inverse
          spec = Builder.run_spec(run)
          svc = Services.get(Builder.run_settings(run)['service'])
          span = Supports.max_span_m(spec, hot: %i[hot_water steam].include?(svc[:fluid])) * 1000.0
          pipes = Collector.pieces(run, 'pipe').map do |p|
            g = H.get_json(p, 'geom')
            { from: g['a'], to: g['b'], path: g['path'] }
          end
          loads = Collector.pieces(run, 'valve').map { |v| JSON.parse(v.get_attribute(H::DICT, 'at')) }
          # supports shared with neighbouring pipes already carry this run
          fixed = SupportBuilder.shared_points(model, run.persistent_id).map { |w| H.transform_mm(inv, w) }
          fixed += (extra[run] || []).map { |rec| rec['at'] } # hung here already by a neighbour
          res = Supports.place(pipes, span, loads: loads, fixed: fixed)
          risers += res[:risers]
          recs = []
          res[:supports].each do |s|
            at_w = H.transform_mm(tr, s[:at])
            dir_w = Vec.unit(H.from_vec(H.to_vec(s[:dir]).transform(tr)))
            mem = SupportBuilder.members(model, at_w, dir_w)
            multi = Supports::TYPES[type][:multi] ? type : (mem.size > 1 && Supports::MULTI_OF[type])
            if each && mem.size > 1
              # every pipe at this section hangs from the same beam
              level = SupportBuilder.hang_level(model, at_w, Vec.cross([0, 0, 1.0], SupportBuilder.horizontal(dir_w)), mem)
              rec, note = SupportBuilder.record_for(model, run, tr, type, s[:at], s[:dir], level: level)
              recs << rec if rec
              level ||= rec && rec['target'] && H.transform_mm(tr, rec['target'])[2]
              added, ns = SupportBuilder.paired_records(model, type, at_w, dir_w, mem, skip: run.persistent_id,
                                                                                      have: pending.call, level: level)
              added.each { |r2, list| (extra[r2] ||= []).concat(list) }
              paired += added.values.sum(&:size)
              notes.concat(ns)
            elsif multi
              _g, note = SupportBuilder.create_multi(model, multi, at_w, dir_w, base: type, lod: st['lod'].to_sym,
                                                                                steps: st['segments'], pipes: mem, op: false)
              SupportBuilder.drop_covered(model, at_w, mem.reject { |o| o[4] == run.persistent_id })
              shared += 1
            else
              rec, note = SupportBuilder.record_for(model, run, tr, type, s[:at], s[:dir])
              recs << rec if rec
            end
            notes << "#{run.name}: #{note}" if note
          rescue StandardError => e
            notes << "#{run.name}: #{e.message}"
          end
          total += res[:supports].size
          if each
            own[run] = recs
          else
            H.set_json(run, 'supports', recs)
            notes.concat(Builder.render(model, run, Builder.run_settings(run)).map { |w| "#{run.name}: #{w}" })
          end
          notes << "#{run.name}: ระยะห่างสูงสุด #{(span / 1000.0).round(2)} m (#{spec.size} #{spec.material})"
        end
        (own.keys + extra.keys).uniq.each do |run|
          base = own.key?(run) ? own[run] : H.get_json(run, 'supports', [])
          H.set_json(run, 'supports', base + (extra[run] || []))
          notes.concat(Builder.render(model, run, Builder.run_settings(run)).map { |w| "#{run.name}: #{w}" })
        end
        model.commit_operation
        summary = "วางซัพพอร์ต #{total} จุด (placed #{total} supports)"
        summary += " · ที่แขวนท่อข้างเคียงอีก #{paired} ตัว" if paired.positive?
        summary += " · ใช้ร่วมกับท่อข้างเคียง #{shared} จุด" if shared.positive?
        summary += " · ท่อแนวตั้ง #{risers} ช่วง ต้องใช้ riser clamp ที่ระดับพื้น" if risers.positive?
        show_warnings(notes, summary)
      rescue StandardError => e
        model.abort_operation
        UI.messagebox("Plant Piping: วางซัพพอร์ตไม่สำเร็จ\n#{e.message}")
      end

      def clear_supports
        model = Sketchup.active_model
        runs = H.selected_runs(model)
        return if runs.empty?

        model.start_operation('Plant Piping: Clear Supports', true)
        ids = runs.map(&:persistent_id)
        SupportBuilder.shared_supports(model).each do |g|
          mem = H.get_json(g, 'members', [])
          g.erase! if !mem.empty? && (mem - ids).empty?
        end
        runs.each do |run|
          H.set_json(run, 'supports', [])
          Builder.render(model, run, Builder.run_settings(run))
        end
        model.commit_operation
      end

      # ---------- display ----------

      # Technical line style like the reference drawings: black edges,
      # profiles, no depth cue. Only rendering options are changed – undoable.
      def technical_style
        model = Sketchup.active_model
        ro = model.rendering_options
        model.start_operation('Plant Piping: Technical Style', true)
        {
          'EdgeColorMode' => 0, 'ForegroundColor' => Sketchup::Color.new(20, 20, 20),
          'DrawSilhouettes' => true, 'SilhouetteWidth' => 2, 'DrawDepthQue' => false,
          'ExtendLines' => false, 'DrawLineEnds' => false, 'DrawEdges' => true
        }.each do |k, v|
          ro[k] = v
        rescue StandardError
          nil
        end
        model.commit_operation
      end

      # ---------- diagnostics ----------

      # Build a small test run (pipes, elbow, tee, valve, reducer) far from the
      # model, check every piece really has faces, then undo it all. Also list
      # the stored warnings of the selected (or all) runs. The report can be
      # sent to the developer as a screenshot.
      def diagnostics
        model = Sketchup.active_model
        rows = []
        errors = []
        model.start_operation('Plant Piping: Self-test', true)
        begin
          s = H.load_settings
          o = [1_000_000.0, 1_000_000.0, 0.0]
          seg = lambda { |a, b| [Vec.add(o, a), Vec.add(o, b)] }
          segs = [seg.call([0, 0, 0], [3000, 0, 0]), seg.call([3000, 0, 0], [3000, 2000, 0]),
                  seg.call([1500, 0, 0], [1500, 1500, 0])]
          run, warns = Builder.create_run(model, segs, s, op: false)
          errors.concat(warns)
          Builder.place_valve(Builder.context(model, run, s, Settings.spec(s), Services.get(s['service']), run.name),
                              'gate', Vec.add(o, [700, 0, 0]), [1, 0, 0])
          run.entities.each do |e|
            next unless H.instance?(e) && H.type_of(e) != 'centerline'

            ents = e.respond_to?(:definition) ? e.definition.entities : e.entities
            faces = ents.count { |x| x.is_a?(Sketchup::Face) }
            rows << [H.type_of(e) || '-', e.class.name.split('::').last, e.name, faces, faces.positive? ? 'OK' : 'NO FACES']
          end
        rescue StandardError => e
          errors << "#{e.class}: #{e.message} @ #{e.backtrace.to_a.first(3).join(' | ')}"
        ensure
          model.abort_operation
        end

        runs = H.selected_runs(model)
        runs = Collector.all_runs(model).map(&:first) if runs.empty?
        run_rows = runs.first(200).map do |r|
          counts = Hash.new(0)
          r.entities.each { |e| counts[H.type_of(e)] += 1 if H.instance?(e) }
          [r.name, %w[pipe elbow tee reducer valve support].map { |t| "#{t}:#{counts[t]}" }.join(' '),
           H.get_json(r, 'warnings', []).join(' | ')]
        end

        env = "Plant Piping #{VERSION} · SketchUp #{Sketchup.version} · Ruby #{RUBY_VERSION} · #{Sketchup.platform}"
        body = "<p class='mut'>#{Reports.esc(env)}</p><h2>Self-test</h2>" +
               Reports.table(%w[Type Class Name Faces Status], rows, row_class: ->(i) { rows[i][3].positive? ? 'ok' : 'bad' }) +
               (errors.empty? ? '<p>ไม่พบข้อผิดพลาด (no errors)</p>' : "<ul>#{errors.map { |x| "<li>#{Reports.esc(x)}</li>" }.join}</ul>") +
               '<h2>แนวท่อในโมเดล (runs)</h2>' + Reports.table(['Line', 'Pieces', 'Warnings'], run_rows)
        Reports.show('Plant Piping – Diagnostics', body)
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

          ยืด/ย้ายท่อ: คลิกปลายท่อ = ยืด/หดตามแนว (พิมพ์ระยะได้) | คลิกมุมท่อ = ย้ายมุม (ลูกศรล็อกแกน)
          วาล์ว ซัพพอร์ต ข้อต่อจากคลัง ตามไปเอง | ยืดด้วย Push/Pull, Scale, Move ของ SketchUp ก็ได้
          ปลั๊กอินจะอ่านความยาวใหม่ให้อัตโนมัติ | ตรวจท่อ = หาท่อที่รูปทรงไม่ตรงข้อมูลแล้วซ่อม

          คลังอุปกรณ์จริง: เลือกอุปกรณ์ → ชี้ที่ท่อ (วาล์ว/มิเตอร์ = บนท่อตรง, ข้องอ/ก๊อก/ฝาครอบ = ที่ปลายท่อ,
          เกจ = บนท่อ) ขนาดปรับตามท่อที่ชี้ | ← → หมุน 90°
          Convert Edges: วาดเส้นด้วย Line tool แล้วแปลงเป็นท่อ (รองรับ Tee/Cross)
          Rebuild: เปลี่ยนขนาด/วัสดุ/ระบบของท่อที่เลือก ตามค่าในหน้าต่าง Settings

          Supports: เลือกแนวท่อ → Auto Supports วางตามระยะห่างสูงสุดของวัสดุ/ขนาด
          Support tool: คลิกบนท่อ | Tab = เปลี่ยนชนิด | Trapeze/H-frame คลุมทุกท่อที่ขนานกันตรงจุดคลิก
          ซัพพอร์ตยึดกับโครงสร้างที่ตรวจพบในโมเดล (พื้น/ฝ้า/คาน/ผนัง) อัตโนมัติ
        TXT
      end
    end
  end
end
