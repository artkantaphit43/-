# frozen_string_literal: true

require 'cgi'

module ArtK
  module PlantPipe
    # Simple HTML report windows (BOM, hydraulic check, clash list).
    module Reports
      module_function

      def esc(v)
        CGI.escapeHTML(v.to_s)
      end

      def table(headers, rows, row_class: nil)
        th = headers.map { |h| "<th>#{esc(h)}</th>" }.join
        body = rows.each_with_index.map do |r, i|
          cls = row_class ? row_class.call(i) : nil
          "<tr#{cls ? " class=\"#{cls}\"" : ''}>" + r.map { |c| "<td>#{esc(c)}</td>" }.join + '</tr>'
        end.join
        "<table><thead><tr>#{th}</tr></thead><tbody>#{body}</tbody></table>"
      end

      # Show an HTML report. If +csv+ is given an "Export CSV" button saves it.
      def show(title, body_html, csv: nil, csv_name: 'report.csv', width: 1000, height: 640)
        dlg = UI::HtmlDialog.new(dialog_title: title, preferences_key: "ArtK_PlantPipe_#{title.gsub(/\W/, '')}",
                                 width: width, height: height, resizable: true,
                                 style: UI::HtmlDialog::STYLE_DIALOG)
        button = csv ? '<button onclick="sketchup.export_csv()">Export CSV (Excel)</button>' : ''
        dlg.set_html(<<~HTML)
          <!doctype html><html><head><meta charset="utf-8"><title>#{esc(title)}</title>
          <style>
            :root { --bg:#fff; --fg:#1d2330; --mut:#667085; --line:#e4e7ec; --head:#f2f4f7; --bad:#fdecea; --ok:#ecfdf3; --acc:#1570ef; }
            @media (prefers-color-scheme: dark) { :root { --bg:#1e2128; --fg:#e6e8ec; --mut:#98a2b3; --line:#343a46; --head:#262a33; --bad:#4a2323; --ok:#1f3a2b; --acc:#53b1fd; } }
            body { font: 13px/1.45 "Segoe UI", "Leelawadee UI", Tahoma, sans-serif; margin: 16px; background: var(--bg); color: var(--fg); }
            h1 { font-size: 17px; margin: 0 0 4px; } .mut { color: var(--mut); }
            table { border-collapse: collapse; width: 100%; margin: 12px 0; }
            th, td { border-bottom: 1px solid var(--line); padding: 5px 8px; text-align: left; vertical-align: top; }
            th { background: var(--head); position: sticky; top: 0; font-weight: 600; }
            tr.bad td { background: var(--bad); } tr.ok td { background: var(--ok); }
            button { background: var(--acc); color: #fff; border: 0; border-radius: 6px; padding: 7px 14px; cursor: pointer; font: inherit; }
            ul { margin: 4px 0 4px 18px; padding: 0; }
          </style></head><body>
          <h1>#{esc(title)}</h1>#{button}
          #{body_html}
          </body></html>
        HTML
        if csv
          dlg.add_action_callback('export_csv') do |_ctx|
            path = UI.savepanel('Export CSV', '', csv_name)
            if path
              path += '.csv' unless path.downcase.end_with?('.csv')
              File.open(path, 'wb') { |f| f.write(csv) }
              UI.messagebox("บันทึกแล้ว (saved):\n#{path}")
            end
          end
        end
        dlg.show
        dlg
      end
    end
  end
end
