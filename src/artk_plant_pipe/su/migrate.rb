# frozen_string_literal: true

module ArtK
  module PlantPipe
    # Brings the data of runs and placed library parts drawn with an older
    # version up to the current format (see lib/data_format.rb). Runs when a
    # model is opened and before any run is rebuilt, so files – and parts
    # copied in from older files – keep working after an update.
    module Migrate
      H = ModelHelpers
      TYPES = %w[run component].freeze

      module_function

      # Upgrades every record in the model. Returns
      # { upgraded: n, newer: n, rebuilt: n, parts: n, insulated: n, respec: n }.
      def model(model)
        res = { upgraded: 0, newer: 0, rebuilt: 0, parts: 0, insulated: 0, respec: 0 }
        recs = records(model.entities)
        todo = recs.reject { |e| DataFormat.version(H.attrs(e)) == DataFormat::CURRENT }
        bare = recs.select { |e| H.run?(e) && DataFormat.version(H.attrs(e)) <= DataFormat::CURRENT && bare_elbows?(e) }
        respec = respec_runs(model, recs)
        parts, mats = RefModels.stale(model)
        return res if todo.empty? && parts.empty? && mats.empty? && bare.empty? && respec.empty?

        respec = [] unless respec.empty? || UI.messagebox(respec_question(respec), MB_YESNO) == IDYES
        model.start_operation('Plant Piping: Upgrade Data', true)
        res[:parts] = RefModels.refresh(model, parts, mats)
        res[:respec] = respec.each { |run| respec!(model, run) }.size
        model.set_attribute(H::DICT, SPEC_KEY, 1)
        todo.each do |e|
          st = entity(model, e)
          res[st] += 1 if res.key?(st)
          res[:upgraded] += 1 if st == :rebuilt
        end
        bare.select { |e| bare_elbows?(e) }.each do |run|
          Builder.render(model, run, Builder.run_settings(run))
          res[:insulated] += 1
        end
        model.set_attribute(H::DICT, DataFormat::KEY, DataFormat::CURRENT)
        model.commit_operation
        SupportBuilder.notify_changed(model, respec) unless respec.empty? # steel supports follow
        res
      rescue StandardError
        model.abort_operation
        raise
      end

      SPEC_KEY = 'ins_spec' # the file drawn by 1.17+ (or asked)

      # A file from before 1.17.0: runs with insulation set as 2" × 2 layers
      # (100 / 101.6) – the user's BOQ says 1-1/2" (38.1), one layer.
      def respec_runs(model, recs)
        return [] if model.get_attribute(H::DICT, SPEC_KEY)

        recs.select do |e|
          H.run?(e) && DataFormat.version(H.attrs(e)) <= DataFormat::CURRENT &&
            Settings.two_layers?(Builder.run_settings(e)['insulation_mm'])
        end
      end

      def respec_question(runs)
        "Plant Piping TH – ไฟล์นี้มีท่อหุ้มฉนวน 100 มม. #{runs.size} แนว (ตั้งไว้ตอนเข้าใจว่าฉนวน 2\" × 2 ชั้น)\n" \
          "สเปกตาม BOQ: ใยแก้ว 1-1/2\" (38 มม.) ชั้นเดียว\n\n" \
          "เปลี่ยนเป็น 1-1/2\" ให้เลยไหม?\n" \
          '• ท่อเลื่อนลงเท่าที่ฉนวนบางลง (~62 มม.) ท้องฉนวนยังวางบนซัพพอร์ตเหมือนเดิม ซัพพอร์ตเหล็กปรับตามเอง\n' \
          '• ท่อที่ต่อแยก/ต่อกับท่ออื่นอยู่ที่เดิม เปลี่ยนแค่ฉนวน\n• กด Undo ย้อนได้'
      end

      # 38.1 on +run+, dropped by what the insulation lost (its underside
      # stays where it lay) unless tied to another run; hangers keep their
      # tops (the steel they hang from does not move).
      def respec!(model, run)
        s = Builder.run_settings(run)
        drop = s['insulation_mm'] - Settings::SPEC_MM
        s = s.merge('insulation_mm' => Settings::SPEC_MM)
        H.set_json(run, 'settings', s)
        before = RunEditor.data(run)
        unless tied?(model, run, before)
          moves = before['cl'].flatten(1).uniq { |p| p.map { |c| c.round(3) } }.map { |p| [p, Vec.add(p, [0.0, 0.0, -drop])] }
          after, = RunEdit.move_points(before, moves)
          if after
            after['supports'].zip(before['supports']).each { |a, b| a['target'] = b['target'] if b.key?('target') }
            RunEditor.store(run, after)
          end
        end
        Builder.render(model, run, s)
      end

      # Branched / joined: to another run, or another run to this one.
      def tied?(model, run, data)
        return true unless (data['tees'] + data['joins']).empty?

        pid = run.persistent_id
        Collector.all_runs(model).any? do |r, _|
          r != run && (H.get_json(r, 'tees', []) + H.get_json(r, 'joins', [])).any? { |t| t['main_pid'] == pid }
        end
      end

      # Drawn with 1.16.4 or before: insulation thicker than an elbow's
      # bend was left off it (a BOM record instead) – drawn again, the
      # elbow is covered (1.16.5).
      def bare_elbows?(run)
        H.get_json(run, 'extras', []).any? { |x| x['type'] == 'insulation' }
      end

      # Runs and placed parts anywhere in the model; each definition's
      # contents are visited once, so large models open quickly.
      def records(ents, seen = {}, out = [])
        ents.each do |e|
          next unless H.instance?(e)

          out << e if TYPES.include?(H.type_of(e))
          d = e.definition
          next if seen[d] || H.run?(e)

          seen[d] = true
          records(d.entities, seen, out)
        end
        out
      end

      # Upgrades one run / part. Returns :current, :upgraded, :rebuilt or
      # :newer. rebuild: false when the caller regenerates the run itself.
      def entity(model, e, rebuild: true)
        rec = H.attrs(e) or return :current
        out, st = DataFormat.upgrade(rec)
        return st unless st == :upgraded

        rebuild = out.delete('rebuild') && rebuild
        out.each { |k, v| e.set_attribute(H::DICT, k, v) unless rec[k] == v }
        (rec.keys - out.keys).each { |k| e.delete_attribute(H::DICT, k) }
        return :upgraded unless rebuild && H.run?(e)

        Builder.render(model, e, Builder.run_settings(e))
        :rebuilt
      end

      def newer_warning
        'ไฟล์นี้มีท่อที่วาดด้วย Plant Piping TH เวอร์ชันใหม่กว่าที่ติดตั้งอยู่ – ' \
          'ควรอัปเดตปลั๊กอินก่อนแก้ไขท่อเหล่านั้น'
      end

      # Upgrades the opened model; warns once when it holds data from a
      # newer version.
      class AppObserver < (defined?(Sketchup::AppObserver) ? Sketchup::AppObserver : Object)
        def onOpenModel(model)
          res = Migrate.model(model)
          UI.messagebox(Migrate.newer_warning) if res[:newer].positive?
        rescue StandardError => e
          puts "Plant Piping: data upgrade failed – #{e.message}"
        end
      end
    end
  end
end
