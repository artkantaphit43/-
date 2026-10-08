# frozen_string_literal: true

require 'minitest/autorun'

LIB = File.expand_path('../src/artk_plant_pipe/lib', __dir__)
%w[vec catalog services fittings_data hydraulics network bom settings profile run_check clash mesh parts supports valve_models meter_models refs data_format run_edit].each do |f|
  require File.join(LIB, f)
end

include ArtK::PlantPipe # rubocop:disable Style/MixinUsage
