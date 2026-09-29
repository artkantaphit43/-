# frozen_string_literal: true

require 'json'

module ArtK
  module PlantPipe
    # Settings + sizing calculator panel (HtmlDialog, ui/settings.html).
    module SettingsDialog
      H = ModelHelpers

      class << self
        def show
          if @dialog && @dialog.visible?
            @dialog.bring_to_front
            return
          end
          @dialog = UI::HtmlDialog.new(
            dialog_title: 'Plant Piping TH – Settings',
            preferences_key: 'ArtK_PlantPipe_Settings',
            width: 440, height: 820, min_width: 380, resizable: true,
            style: UI::HtmlDialog::STYLE_UTILITY
          )
          @dialog.set_file(File.join(PLUGIN_ROOT, 'ui', 'settings.html'))
          @dialog.add_action_callback('ready') { |_ctx| push_init }
          @dialog.add_action_callback('save') { |_ctx, json| save(json) }
          @dialog.add_action_callback('size') { |_ctx, json| sizing(json) }
          @dialog.add_action_callback('command') { |_ctx, name| command(name) }
          @dialog.show
        end

        # Push current settings to an open dialog (after Tab in a tool).
        def refresh
          js('setSettings', H.load_settings) if @dialog && @dialog.visible?
        end

        # Show the user's valve model library.
        def library
          rows = Library.entries.map do |e|
            [e['type'], e['size'] || 'ทุกขนาด (scaled)', e['name'], e['file']]
          end
          body = "<p class='mut'>โฟลเดอร์: #{Reports.esc(Library.dir)}</p>" +
                 (rows.empty? ? '<p>ยังไม่มีโมเดล – เลือก Component วาล์วแล้วใช้คำสั่ง Register Valve Model</p>' :
                                Reports.table(%w[Type Size Model File], rows))
          Reports.show('Valve Model Library', body)
        end

        private

        def js(fn, data)
          @dialog.execute_script("PP.#{fn}(#{JSON.generate(data)})") if @dialog
        end

        def push_init
          js('init', payload)
        end

        def payload
          {
            version: VERSION,
            settings: H.load_settings,
            services: Services.all.map do |s|
              { code: s[:code], th: s[:th], en: s[:en], gravity: s[:gravity] ? true : false,
                catalog: s[:catalog], size: s[:size], rating: s[:rating], insulation: s[:insulation],
                vmax: s[:vmax], hf_max: s[:hf_max], fluid: s[:fluid].to_s,
                colors: Services::SCHEMES.keys.map { |k| [k, Services.color(s[:code], k)] }.to_h }
            end,
            catalogs: Catalog.all.map do |key, c|
              [key, { name: c[:name], name_th: c[:name_th], material: c[:material], joint: c[:joint],
                      density: c[:density], estimated: c[:estimated] ? true : false,
                      default_rating: c[:default_rating],
                      sizes: c[:sizes].map do |z|
                        { size: z[:size], od: z[:od], walls: z[:walls],
                          min_slope: Services.min_drain_slope_pct(z[:od]) }
                      end }]
            end.to_h,
            schemes: Services::SCHEMES,
            material_colors: Services::MATERIAL_COLORS, painted: Services::PAINTED,
            supports: Supports::TYPES.map { |k, v| { type: k, th: v[:th], name: v[:name], multi: v[:multi] ? true : false } },
            valves: FittingsData::VALVES.map { |k, v| { type: k, th: v[:th], name: v[:name] } }
          }
        end

        def save(json)
          old = H.load_settings
          s = Settings.sanitize(JSON.parse(json))
          H.save_settings(s)
          if old['color_scheme'] != s['color_scheme']
            model = Sketchup.active_model
            model.start_operation('Plant Piping: Colour Scheme', true)
            H.apply_color_scheme(model, s['color_scheme'])
            model.commit_operation
          end
          js('setSettings', s)
          [PipeTool, ValveTool, SupportTool].each { |t| t.active&.reload_settings }
        rescue JSON::ParserError => e
          puts "Plant Piping settings: #{e.message}"
        end

        # Size table for the calculator.
        def sizing(json)
          req = JSON.parse(json)
          q = req['flow_m3h'].to_f
          svc = Services.get(req['service'])
          cat = req['catalog']
          specs = Catalog.sizes(cat).map { |size| Catalog.spec(cat, size, req['rating']) }
          rows =
            if svc[:gravity]
              specs.map do |sp|
                slope = [req['slope_pct'].to_f, Services.min_drain_slope_pct(sp.od)].max
                cap = Hydraulics.manning_capacity(sp.id, slope, fill: RunCheck::DESIGN_FILL)
                { size: sp.size, rating: sp.rating, id: sp.id.round(1), slope: slope,
                  cap: cap[:q_m3h].round(2), v: cap[:v].round(2), ok: cap[:q_m3h] >= q && q.positive? }
              end
            else
              r, = Hydraulics.size_table(specs, q, fluid: svc[:fluid], vmax: svc[:vmax], hf_max: svc[:hf_max])
              r
            end
          rec = rows.find { |r| r[:ok] }
          js('showSizing', { gravity: svc[:gravity] ? true : false, rows: rows,
                             recommended: rec && rec[:size], vmax: svc[:vmax], hf_max: svc[:hf_max],
                             liquid: Hydraulics.liquid?(svc[:fluid]) })
        rescue StandardError => e
          js('showError', e.message)
        end

        def command(name)
          case name
          when 'draw' then Commands.draw_pipe
          when 'valve' then Commands.insert_valve
          when 'convert' then Commands.convert_selection
          when 'rebuild' then Commands.rebuild_selection
          when 'flow' then Commands.set_design_flow
          when 'hydraulic' then Commands.hydraulic_report
          when 'bom' then Commands.bom
          when 'clash' then Commands.clash_check
          when 'auto_support' then Commands.auto_supports
          when 'support' then Commands.support_tool
          when 'clear_support' then Commands.clear_supports
          when 'style' then Commands.technical_style
          when 'help' then Commands.help
          when 'diag' then Commands.diagnostics
          when 'register' then Sketchup.active_model.select_tool(RegisterModelTool.new)
          when 'library' then SettingsDialog.library
          when 'parts' then RefBrowser.show
          end
        end
      end
    end
  end
end
