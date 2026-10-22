# frozen_string_literal: true

module ArtK
  module SteelSupport
    # Working with Plant Piping TH when it is installed: its pipes (size,
    # insulation, weight, span), its Auto Supports leaving out what these
    # supports carry, its own hangers removed where ours go, and refits
    # when it redraws pipes. Only Plant Piping's API module is used.
    module Link
      LEVEL = 1
      NAME = 'SteelSupport'

      module_function

      def api
        defined?(::ArtK::PlantPipe::API) ? ::ArtK::PlantPipe::API : nil
      end

      def available?
        a = api
        !a.nil? && a::LEVEL >= LEVEL
      end

      # Plant Piping is there but too old for this extension.
      def outdated?
        defined?(::ArtK::PlantPipe::VERSION) && !available?
      end

      def status
        if rests? then "เชื่อมกับ Plant Piping TH #{api.version} แล้ว"
        elsif available? then "เชื่อมกับ Plant Piping TH #{api.version} แล้ว – อัปเดตเป็น 1.16.4 ให้ท่อที่วาดลงซัพพอร์ตวางบนเหล็กเอง"
        elsif outdated? then 'Plant Piping TH เวอร์ชันเก่า – อัปเดตเป็น 1.16.4 ขึ้นไปเพื่อใช้ร่วมกัน'
        else 'ไม่พบ Plant Piping TH – ใช้กับท่อทั่วไป (ทรงกระบอก) ได้'
        end
      end

      def pp_entity?(e)
        available? && api.ours?(e)
      end

      def pipe_at(model, point)
        available? ? api.pipe_at(model, point, extra: 30.0) : nil
      end

      def pipes_across(model, point, dir, reach:, rise:)
        return [] unless available?

        api.pipes_across(model, point, dir, reach: reach, rise: rise).map do |p|
          { y: p[:y], z: p[:z], od: p[:od], ins: p[:ins], r: p[:od] / 2.0 + p[:ins], kg_m: p[:kg_m],
            span_m: p[:span_m], label: p[:label], pid: p[:pid], hot: p[:hot], src: 'pp' }
        end
      end

      def selected_runs(model)
        available? ? api.runs(model, selected: true) : []
      end

      def support_points(model, run, span_m: nil)
        available? ? api.support_points(model, run, span_m: span_m) : []
      end

      def drop_hangers(model, point, pids)
        api.drop_hangers(model, point, pids) if available? && pids.any?
      rescue StandardError => e
        puts "Steel Supports: Plant Piping hangers not removed – #{e.message}"
      end

      # Plant Piping's pipe tool lays pipes drawn onto our supports on the
      # steel (1.16.2 and later; the pipe's size from 1.16.3).
      def rests?
        available? && api.respond_to?(:register_rests)
      end

      # Hooks into Plant Piping (once): Auto Supports counts our supports,
      # pipes redrawn next to them refit them, pipes drawn onto them lie
      # on the steel.
      def register
        return false unless available?
        return true if @registered

        api.register_supports(NAME) { |model, pid| Builder.points_for(model, pid) }
        api.on_runs_changed(NAME) { |model, runs| Builder.refit_near(model, runs) }
        api.register_rests(NAME) { |model, path, point, pipe| Builder.rest_at(path, point, pipe, model: model) } if rests?
        @registered = true
      end
    end
  end
end
