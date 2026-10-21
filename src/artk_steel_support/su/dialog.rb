# frozen_string_literal: true

require 'json'

module ArtK
  module SteelSupport
    # Settings + commands panel (ui/dialog.html).
    module Dialog
      module_function

      def show
        if @dialog && @dialog.visible?
          @dialog.bring_to_front
          return
        end
        @dialog = UI::HtmlDialog.new(dialog_title: 'ซัพพอร์ตเหล็ก (Steel Supports TH)',
                                     preferences_key: 'ArtK_SteelSupport_dialog', width: 420, height: 760,
                                     min_width: 360, resizable: true, style: UI::HtmlDialog::STYLE_UTILITY)
        @dialog.set_file(File.join(PLUGIN_ROOT, 'ui', 'dialog.html'))
        @dialog.add_action_callback('ready') { |_c| js('init', payload) }
        @dialog.add_action_callback('save') { |_c, json| save(json) }
        @dialog.add_action_callback('command') { |_c, name| command(name) }
        @dialog.show
      end

      def js(fn, data)
        @dialog&.execute_script("SS.#{fn}(#{JSON.generate(data)})")
      end

      def payload
        Link.register
        {
          version: VERSION, link: Link.status, linked: Link.available?, settings: H.settings,
          types: Std::TYPES.map do |k, v|
            { key: k, th: v[:th], section: Steel.get(v[:sec])[:name], anchor: Hardware.label(v[:anchor]),
              anchors: v[:bolts].size }
          end
        }
      end

      def save(json)
        H.save_settings(H.settings.merge(JSON.parse(json)))
      rescue JSON::ParserError
        nil
      end

      def command(name)
        detail = H.settings['detail']
        case name
        when 'place' then Commands.place(detail)
        when 'columns' then Commands.columns(detail)
        when 'refit' then Commands.refit
        when 'report' then Commands.report
        end
      end
    end
  end
end
