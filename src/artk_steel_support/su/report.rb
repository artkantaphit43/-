# frozen_string_literal: true

module ArtK
  module SteelSupport
    # Bill of materials and check summary of the supports (selection, or
    # all in the active context): HTML window + CSV.
    module Report
      CATS = [['steel', 'เหล็กรูปพรรณ (Steel sections)'], ['plate', 'แผ่นเหล็ก (Packers / clips)'],
              ['ubolt', 'U-bolt'], ['clamp', 'แคลมป์รัดท่อ (Pipe clamps)'], ['rod', 'เหล็กเส้นเกลียว (Threaded rod)'], ['anchor', 'พุก (Anchors)'],
              ['nut', 'น็อต + แหวน (Nuts + washers)']].freeze
      CUT = 1.05 # steel bought: +5 % cutting allowance

      module_function

      def groups(model)
        sel = model.selection.to_a.select { |e| H.ours?(e) }
        sel.empty? ? H.supports(model).map(&:first) : sel
      end

      # [{ cat:, desc:, qty:, length_m:, kg: }] summed over the supports.
      def rows(list)
        out = {}
        list.each do |g|
          H.get_json(g, 'bom', []).each do |b|
            k = [b['cat'], b['cat'] == 'steel' ? b['key'] : b['desc']]
            r = (out[k] ||= { cat: b['cat'], desc: b['desc'], qty: 0, length_m: 0.0, kg: 0.0 })
            if b['cat'] == 'steel'
              r[:length_m] += b['length'].to_f / 1000.0
              r[:kg] += b['kg'].to_f
              r[:qty] += 1
            else
              r[:qty] += b['qty'].to_i
              r[:kg] += b['kg'].to_f
            end
          end
        end
        order = CATS.map(&:first)
        out.values.sort_by { |r| [order.index(r[:cat]) || 99, r[:desc]] }
      end

      def supports(list)
        list.map do |g|
          checks = H.get_json(g, 'checks', [])
          worst = checks.map { |c| c['limit'].to_f.positive? ? c['value'].to_f / c['limit'].to_f : 0.0 }.max || 0.0
          { number: g.get_attribute(H::DICT, 'number'), name: g.name, section: g.get_attribute(H::DICT, 'section'),
            pipes: H.get_json(g, 'pipes', []).map { |p| p['label'] }.join(', '), ratio: worst,
            ok: checks.all? { |c| c['ok'] }, notes: H.get_json(g, 'notes', []), checks: checks }
        end.sort_by { |s| s[:number].to_s }
      end

      def csv(list)
        lines = [%w[หมวด รายการ จำนวน ความยาว(ม.) น้ำหนัก(กก.)].join(',')]
        rows(list).each do |r|
          cat = CATS.to_h[r[:cat]] || r[:cat]
          len = r[:cat] == 'steel' ? (r[:length_m] * CUT).round(2) : ''
          lines << [cat, r[:desc], r[:qty], len, r[:kg].positive? ? (r[:kg] * (r[:cat] == 'steel' ? CUT : 1)).round(1) : ''].map { |v| q(v) }.join(',')
        end
        lines << ''
        lines << %w[เลขที่ ซัพพอร์ต เหล็ก ท่อ ใช้กำลัง(%) หมายเหตุ].join(',')
        supports(list).each do |s|
          lines << [s[:number], s[:name], s[:section], s[:pipes], (s[:ratio] * 100).round, s[:notes].join(' / ')].map { |v| q(v) }.join(',')
        end
        lines.join("\n")
      end

      def q(v)
        s = v.to_s
        s.match?(/[",\n]/) ? "\"#{s.gsub('"', '""')}\"" : s
      end

      def esc(s)
        s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
      end

      def html(list)
        body = +''
        total = 0.0
        CATS.each do |cat, title|
          rs = rows(list).select { |r| r[:cat] == cat }
          next if rs.empty?

          body << "<h3>#{esc(title)}</h3><table><tr><th>รายการ</th><th>จำนวน</th>"
          body << (cat == 'steel' ? '<th>ยาวรวม (ม.) +5%</th><th>น้ำหนัก (กก.)</th>' : '<th>น้ำหนัก (กก.)</th>')
          body << '</tr>'
          rs.each do |r|
            kg = r[:kg] * (cat == 'steel' ? CUT : 1.0)
            total += kg
            body << "<tr><td>#{esc(r[:desc])}</td><td>#{r[:qty]}#{cat == 'steel' ? ' ท่อน' : ''}</td>"
            body << "<td>#{(r[:length_m] * CUT).round(2)}</td>" if cat == 'steel'
            body << "<td>#{kg.positive? ? kg.round(1) : '–'}</td></tr>"
          end
          body << '</table>'
        end
        body << "<p class=tot>น้ำหนักเหล็กรวมโดยประมาณ #{total.round(1)} กก.</p>"
        body << '<h3>ตรวจกำลัง (Checks)</h3><table><tr><th>เลขที่</th><th>เหล็ก</th><th>ท่อ</th><th>ใช้กำลัง</th><th>หมายเหตุ</th></tr>'
        supports(list).each do |s|
          tip = s[:checks].map { |c| "#{c['item']}: #{c['value']} / #{c['limit']} #{c['unit']}" }.join("\n")
          body << "<tr class=#{s[:ok] ? 'ok' : 'bad'} title=\"#{esc(tip)}\"><td>#{esc(s[:number])}</td><td>#{esc(s[:section])}</td>"
          body << "<td>#{esc(s[:pipes])}</td><td>#{(s[:ratio] * 100).round}%</td><td>#{esc(s[:notes].join(' · '))}</td></tr>"
        end
        body << '</table>'
        <<~HTML
          <!doctype html><html><head><meta charset="utf-8"><style>
          :root{--bg:#fff;--fg:#1d2939;--line:#d0d5dd;--head:#f2f4f7;--bad:#b42318}
          @media (prefers-color-scheme:dark){:root{--bg:#1f2329;--fg:#e4e7ec;--line:#475467;--head:#2b3038;--bad:#f97066}}
          body{font:13px system-ui,'Segoe UI',Tahoma,sans-serif;background:var(--bg);color:var(--fg);margin:12px}
          table{border-collapse:collapse;width:100%;margin-bottom:8px}th,td{border:1px solid var(--line);padding:3px 6px;text-align:left}
          th{background:var(--head)}h3{margin:12px 0 4px}tr.bad td{color:var(--bad)}.tot{font-weight:600}
          button{padding:5px 12px;margin-right:6px}
          </style></head><body>
          <div><button onclick="sketchup.csv()">บันทึก CSV</button> <small>#{list.size} ซัพพอร์ต · ชี้ที่แถวตรวจกำลังเพื่อดูรายละเอียด</small></div>
          #{body}
          </body></html>
        HTML
      end

      def show(model)
        list = groups(model)
        if list.empty?
          UI.messagebox('ยังไม่มีซัพพอร์ตเหล็กในโมเดล (no steel supports yet)')
          return
        end
        dlg = UI::HtmlDialog.new(dialog_title: 'ซัพพอร์ตเหล็ก – รายการวัสดุ', preferences_key: 'ArtK_SteelSupport_bom',
                                 width: 760, height: 620, style: UI::HtmlDialog::STYLE_DIALOG)
        dlg.set_html(html(list))
        dlg.add_action_callback('csv') do |_ctx|
          path = UI.savepanel('บันทึก CSV', '', 'steel_supports.csv')
          File.write(path, "﻿" + csv(list)) if path
        end
        dlg.show
        dlg
      end
    end
  end
end
