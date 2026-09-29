# frozen_string_literal: true

require 'sketchup.rb'
require 'json'

module ArtK
  module PlantPipe
    PLUGIN_ROOT = File.dirname(__FILE__) unless defined?(PLUGIN_ROOT)

    # Pure engineering core (no SketchUp API – unit tested outside SketchUp)
    %w[vec catalog services fittings_data hydraulics network bom settings profile run_check clash].each do |f|
      require File.join(PLUGIN_ROOT, 'lib', f)
    end
    # SketchUp integration
    %w[model_helpers builder valves collector picker pipe_tool valve_tool reports commands dialog].each do |f|
      require File.join(PLUGIN_ROOT, 'su', f)
    end

    # Optional user catalogue: <plugin folder>/custom_catalog.json
    # (format: docs/custom_catalog.example.json in the source repository).
    begin
      Catalog.load_custom(File.join(PLUGIN_ROOT, 'custom_catalog.json'))
    rescue StandardError => e
      puts "Plant Piping: custom catalogue not loaded – #{e.message}"
    end

    def self.icon(name)
      ext = Sketchup.platform == :platform_win ? 'svg' : nil
      dir = File.join(PLUGIN_ROOT, 'icons')
      return [File.join(dir, "#{name}.svg")] * 2 if ext

      [File.join(dir, "#{name}_16.png"), File.join(dir, "#{name}_24.png")]
    end

    def self.command(name, tip, icon_name = nil, &block)
      cmd = UI::Command.new(name, &block)
      cmd.tooltip = name
      cmd.status_bar_text = tip
      if icon_name
        small, large = icon(icon_name)
        cmd.small_icon = small
        cmd.large_icon = large
      end
      cmd
    end

    unless file_loaded?(__FILE__)
      cmds = {
        settings: command('Settings & Sizing / ตั้งค่า', 'เลือกระบบ วัสดุ ขนาด และคำนวณขนาดท่อ', 'settings') { SettingsDialog.show },
        draw: command('Draw Pipe / วาดท่อ', 'วาดแนวท่อพร้อมข้องอ/Tee อัตโนมัติ', 'draw') { Commands.draw_pipe },
        valve: command('Insert Valve / ใส่วาล์ว', 'คลิกบนท่อตรงเพื่อใส่วาล์ว (Tab เปลี่ยนชนิด)', 'valve') { Commands.insert_valve },
        convert: command('Convert Edges to Pipe / แปลงเส้นเป็นท่อ', 'แปลงเส้นที่เลือกเป็นท่อ', 'convert') { Commands.convert_selection },
        rebuild: command('Rebuild Selected Runs / ปรับท่อที่เลือก', 'เปลี่ยนขนาด/วัสดุ/ระบบ ของท่อที่เลือก', 'rebuild') { Commands.rebuild_selection },
        flow: command('Set Design Flow / กำหนดอัตราไหล', 'กำหนดอัตราการไหลออกแบบให้ท่อที่เลือก', 'flow') { Commands.set_design_flow },
        hydraulic: command('Hydraulic Check / ตรวจไฮดรอลิก', 'ตรวจความเร็ว แรงเสียดทาน ความลาด จุดสูง/ต่ำ', 'hydraulic') { Commands.hydraulic_report },
        clash: command('Clash Check / ตรวจการชนกัน', 'ตรวจระยะห่างระหว่างแนวท่อ (รวมฉนวน)', 'clash') { Commands.clash_check },
        bom: command('Bill of Materials / ถอดวัสดุ', 'สรุปรายการวัสดุ ส่งออก CSV', 'bom') { Commands.bom },
        help: command('Help / วิธีใช้', 'คีย์ลัดและวิธีใช้') { Commands.help }
      }

      menu = UI.menu('Extensions').add_submenu('Plant Piping TH')
      %i[settings draw valve convert].each { |k| menu.add_item(cmds[k]) }
      valves = menu.add_submenu('Insert Valve Type / ชนิดวาล์ว')
      FittingsData::VALVES.each do |type, info|
        valves.add_item("#{info[:name]} – #{info[:th]}") { Commands.insert_valve(type) }
      end
      menu.add_separator
      %i[rebuild flow hydraulic clash bom].each { |k| menu.add_item(cmds[k]) }
      menu.add_separator
      menu.add_item(cmds[:help])

      tb = UI::Toolbar.new('Plant Piping TH')
      %i[settings draw valve convert rebuild flow hydraulic clash bom].each { |k| tb.add_item(cmds[k]) }
      tb.get_last_state == TB_NEVER_SHOWN ? tb.show : tb.restore

      UI.add_context_menu_handler do |ctx|
        model = Sketchup.active_model
        runs = ModelHelpers.selected_runs(model)
        edges = model.selection.grep(Sketchup::Edge)
        next if runs.empty? && edges.empty?

        sub = ctx.add_submenu('Plant Piping')
        sub.add_item(cmds[:convert]) unless edges.empty?
        unless runs.empty?
          %i[rebuild flow hydraulic bom].each { |k| sub.add_item(cmds[k]) }
        end
      end

      file_loaded(__FILE__)
    end
  end
end
