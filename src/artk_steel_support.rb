# frozen_string_literal: true
#
# Steel Supports TH – SketchUp extension loader.
#
# Registers the extension only; the code lives in artk_steel_support/ and
# loads when the extension is enabled. Works on its own with any round
# pipe, and together with Plant Piping TH (its pipes, BOM and Auto
# Supports) when that is installed.

require 'sketchup.rb'
require 'extensions.rb'

module ArtK
  module SteelSupport
    PLUGIN_ID   = File.basename(__FILE__, '.rb')
    PLUGIN_ROOT = File.join(File.dirname(__FILE__), PLUGIN_ID)

    require File.join(PLUGIN_ROOT, 'version')

    unless file_loaded?(__FILE__)
      ext = SketchupExtension.new('Steel Supports TH', File.join(PLUGIN_ROOT, 'main'))
      ext.description = 'ซัพพอร์ตท่อเหล็กรางน้ำ / ตัวซี ตามแบบ: โครงกล่องยึดผนัง, ขาค้ำสามเหลี่ยม, ' \
                        'แขวนใต้ truss, วางบน truss – ขนาดเหล็กจริง U-bolt พุก ตรวจกำลัง ถอดวัสดุ ' \
                        '(ใช้ร่วมกับ Plant Piping TH ได้)'
      ext.version     = VERSION
      ext.creator     = 'ArtK'
      ext.copyright   = "#{Time.now.year} ArtK"
      Sketchup.register_extension(ext, true)
      file_loaded(__FILE__)
    end
  end
end
