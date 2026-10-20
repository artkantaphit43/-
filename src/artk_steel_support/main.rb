# frozen_string_literal: true

require 'sketchup.rb'
require 'json'

module ArtK
  module SteelSupport
    PLUGIN_ROOT = File.dirname(__FILE__) unless defined?(PLUGIN_ROOT)

    # Engineering core (no SketchUp API – unit tested outside SketchUp)
    %w[vec mesh steel hardware beam pipes details].each { |f| require File.join(PLUGIN_ROOT, 'lib', f) }
    # SketchUp layer
    %w[helpers link probe generic planner builder place_tool report commands dialog].each do |f|
      require File.join(PLUGIN_ROOT, 'su', f)
    end

    def self.icon(name)
      dir = File.join(PLUGIN_ROOT, 'icons')
      return [File.join(dir, "#{name}.svg")] * 2 if Sketchup.platform == :platform_win

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
        settings: command('Steel Supports / ซัพพอร์ตเหล็ก', 'เลือกแบบ เหล็ก พุก และคำสั่งทั้งหมด', 'settings') { Commands.settings },
        wf: command('Wall Box Frame / โครงกล่องยึดผนัง', 'ชี้ที่ท่อข้างผนัง/เสา แล้วคลิก', 'wf') { Commands.place('wf') },
        wb: command('Wall Bracket / ขาค้ำสามเหลี่ยม', 'ชี้ที่ท่อข้างผนัง/เสา แล้วคลิก', 'wb') { Commands.place('wb') },
        th: command('Hang from Truss / แขวนใต้ Truss', 'ชี้ที่ท่อใต้ truss แล้วคลิก', 'th') { Commands.place('th') },
        tt: command('On Truss / วางบน Truss', 'ชี้ที่ท่อเหนือ truss แล้วคลิก', 'tt') { Commands.place('tt') },
        auto: command('Along Selected Runs / วางตามแนวท่อ', 'วางแบบที่เลือกตามแนวท่อ Plant Piping ที่เลือก', 'auto') { Commands.auto },
        refit: command('Refit / ปรับตามท่อ', 'สร้างซัพพอร์ตที่เลือก (หรือทั้งหมด) ใหม่ตามท่อปัจจุบัน', 'refit') { Commands.refit },
        report: command('BOM & Checks / รายการวัสดุ', 'สรุปเหล็ก U-bolt พุก น็อต และผลตรวจกำลัง', 'report') { Commands.report }
      }
      menu = UI.menu('Extensions').add_submenu('Steel Supports TH')
      %i[settings wf wb th tt auto refit report].each { |k| menu.add_item(cmds[k]) }
      tb = UI::Toolbar.new('Steel Supports TH')
      %i[settings wf wb th tt auto refit report].each { |k| tb.add_item(cmds[k]) }
      tb.restore
      # Plant Piping loads first (file order); register now and once more
      # when SketchUp is up, in case it came later.
      Link.register
      UI.start_timer(2.0, false) { Link.register }
      file_loaded(__FILE__)
    end
  end
end
