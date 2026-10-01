# frozen_string_literal: true
#
# Plant Piping TH – SketchUp extension loader.
#
# This file only registers the extension. Everything else lives in the
# artk_plant_pipe/ folder and is loaded lazily when the extension is enabled
# (SketchUp Extension Warehouse guideline: keep the root .rb tiny).

require 'sketchup.rb'
require 'extensions.rb'

module ArtK
  module PlantPipe
    PLUGIN_ID   = File.basename(__FILE__, '.rb')
    PLUGIN_ROOT = File.join(File.dirname(__FILE__), PLUGIN_ID)

    require File.join(PLUGIN_ROOT, 'version')

    unless file_loaded?(__FILE__)
      ext = SketchupExtension.new('Plant Piping TH', File.join(PLUGIN_ROOT, 'main'))
      ext.description = 'วาดระบบท่อน้ำ ประปา สุขาภิบาล และท่อในโรงงานอุตสาหกรรม ' \
                        '(Water, plumbing & industrial process piping) พร้อมข้อต่อ วาล์ว ' \
                        'ถอดปริมาณวัสดุ (BOM) และตรวจสอบไฮดรอลิก'
      ext.version     = VERSION
      ext.creator     = 'ArtK'
      ext.copyright   = "#{Time.now.year} ArtK"
      Sketchup.register_extension(ext, true)
      file_loaded(__FILE__)
    end
  end
end
