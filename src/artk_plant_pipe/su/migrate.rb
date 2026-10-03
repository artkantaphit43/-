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
      # { upgraded: n, newer: n, rebuilt: n }.
      def model(model)
        res = { upgraded: 0, newer: 0, rebuilt: 0 }
        todo = records(model.entities).reject { |e| DataFormat.version(H.attrs(e)) == DataFormat::CURRENT }
        return res if todo.empty?

        model.start_operation('Plant Piping: Upgrade Data', true)
        todo.each do |e|
          st = entity(model, e)
          res[st] += 1 if res.key?(st)
          res[:upgraded] += 1 if st == :rebuilt
        end
        model.set_attribute(H::DICT, DataFormat::KEY, DataFormat::CURRENT)
        model.commit_operation
        res
      rescue StandardError
        model.abort_operation
        raise
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
