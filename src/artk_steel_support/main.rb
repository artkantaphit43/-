# frozen_string_literal: true

require 'sketchup.rb'
require 'json'

module ArtK
  module SteelSupport
    PLUGIN_ROOT = File.dirname(__FILE__) unless defined?(PLUGIN_ROOT)

    # Engineering core (no SketchUp API – unit tested outside SketchUp)
    %w[vec mesh steel hardware beam pipes details std].each { |f| require File.join(PLUGIN_ROOT, 'lib', f) }
    # SketchUp layer
    %w[helpers link probe generic planner placer builder place_tool report commands dialog].each do |f|
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
        settings: command('Steel Supports / ซัพพอร์ตเหล็ก', 'เลือกแบบ A–D และคำสั่งทั้งหมด', 'settings') { Commands.settings },
        a: command('Support A / ซัพพอร์ต A', 'ขาค้ำ C 3" 0.31×0.30 – ชี้ท่อข้างเสา หรือหน้าเสา แล้วคลิก', 'a') { Commands.place('A') },
        b: command('Support B / ซัพพอร์ต B', 'ขาค้ำ C 4" 0.48×0.40 – ชี้ท่อข้างเสา หรือหน้าเสา แล้วคลิก', 'b') { Commands.place('B') },
        c: command('Support C / ซัพพอร์ต C', 'โครงกล่อง C 4" 0.87×0.52 + สตีมด้านบน', 'c') { Commands.place('C') },
        d: command('Support D / ซัพพอร์ต D', 'โครงกล่อง C 4" 0.87×0.52 ท่อ 3 เส้น', 'd') { Commands.place('D') },
        columns: command('At Every Column / ทุกเสาตามแนวท่อ', 'วางแบบที่เลือกทุกเสาที่แนวท่อ Plant Piping ที่เลือกผ่าน',
                         'auto') { Commands.columns },
        refit: command('Refit / ปรับตามท่อ', 'สร้างซัพพอร์ตที่เลือก (หรือทั้งหมด) ใหม่ตามท่อปัจจุบัน', 'refit') { Commands.refit },
        report: command('BOM & Checks / รายการวัสดุ', 'สรุปเหล็ก U-bolt พุก น็อต และผลตรวจกำลัง', 'report') { Commands.report }
      }
      menu = UI.menu('Extensions').add_submenu('Steel Supports TH')
      %i[settings a b c d columns refit report].each { |k| menu.add_item(cmds[k]) }
      tb = UI::Toolbar.new('Steel Supports TH')
      %i[settings a b c d columns refit report].each { |k| tb.add_item(cmds[k]) }
      tb.restore
      # Plant Piping loads first (file order); register now and once more
      # when SketchUp is up, in case it came later.
      Link.register
      UI.start_timer(2.0, false) { Link.register }
      file_loaded(__FILE__)
    end
  end
end
