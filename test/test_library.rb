# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'su_stub'
require 'tmpdir'

module ArtK
  module PlantPipe
    PLUGIN_ROOT = File.expand_path('../src/artk_plant_pipe', __dir__) unless defined?(PLUGIN_ROOT)
    VERSION = 'test' unless defined?(VERSION)
  end
end
%w[model_helpers builder ref_models ref_builder support_builder collector picker reports library commands valve_tool support_tool
   pipe_tool].each do |f|
  require File.expand_path("../src/artk_plant_pipe/su/#{f}", __dir__)
end

class TestLibrary < Minitest::Test
  H = ModelHelpers

  def setup
    @home = Dir.mktmpdir
    @old_home = ENV['HOME']
    ENV['HOME'] = @home
    @model = Sketchup::Model.new
    Sketchup.active_model = @model
    @fp = Settings.sanitize('service' => 'FP', 'catalog' => 'CS_B36_10', 'size' => '4"')
  end

  def teardown
    ENV['HOME'] = @old_home
    FileUtils.rm_rf(@home)
  end

  def apply(tr, p)
    H.from_pt(H.to_pt(p).transform(tr))
  end

  # A user model whose flow runs along its own Y axis, stem along its X
  # axis, inlet at y=-50, outlet at y=150 (200 mm face-to-face).
  def entry
    { 'inlet' => [10.0, -50.0, 5.0], 'outlet' => [10.0, 150.0, 5.0], 'up' => [1.0, 0.0, 0.0], 'size' => nil }
  end

  def test_transform_maps_inlet_outlet_onto_pipe_and_stem_up
    at = [1000.0, 2000.0, 3000.0]
    dir = [0.0, 1.0, 0.0]
    up = [0.0, 0.0, 1.0]
    tr = Library.transform(entry, at, dir, up, 229.0) # 4" gate F-F
    a = apply(tr, entry['inlet'])
    b = apply(tr, entry['outlet'])
    assert Vec.near?(a, [1000, 2000 - 114.5, 3000], 1e-6), a.inspect
    assert Vec.near?(b, [1000, 2000 + 114.5, 3000], 1e-6), b.inspect
    # the model's up axis (+X) now points world up
    tip = apply(tr, [110.0, 50.0, 5.0]) # 100 mm "above" the axis midpoint in model space
    assert_in_delta 3000 + 100 * 229.0 / 200.0, tip[2], 1e-6
    assert_in_delta 1000, tip[0], 1e-6
  end

  def test_exact_size_model_is_not_scaled
    tr = Library.transform(entry.merge('size' => '4"'), [0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 0.0, 1.0], nil)
    assert_in_delta 200.0, Vec.dist(apply(tr, entry['inlet']), apply(tr, entry['outlet'])), 1e-6
  end

  def test_registered_model_is_used_for_that_valve_type
    defn = @model.definitions.add('Manufacturer Gate Valve PN16')
    e = Library.register(defn, type: 'gate', size: nil, inlet: entry['inlet'], outlet: entry['outlet'], up: [1.0, 0, 0])
    assert File.exist?(File.join(Library.dir, e['file']))
    run, = Builder.create_run(@model, [[[0, 0, 0], [5000, 0, 0]]], @fp)
    v = Builder.add_valve(@model, run, 'gate', [2500.0, 0, 0], [1.0, 0, 0])
    assert_equal e['file'], v.get_attribute(H::DICT, 'model')
    a = apply(v.transformation, entry['inlet'])
    assert Vec.near?(a, [2500 - 114.5, 0, 0], 1e-6), a.inspect
    # other types use the reference library, not the user's gate model
    b = Builder.add_valve(@model, run, 'globe', [1000.0, 0, 0], [1.0, 0, 0])
    refute_equal e['file'], b.get_attribute(H::DICT, 'model')
    assert(Bom.aggregate(Collector.records(@model)).any? { |r| r.description == 'Gate Valve' })
  end

  def test_register_rejects_bad_input
    defn = @model.definitions.add('x')
    assert_raises(RuntimeError) { Library.register(defn, type: 'gate', size: nil, inlet: [0, 0, 0], outlet: [1, 0, 0], up: [0, 0, 1]) }
    assert_raises(RuntimeError) { Library.register(defn, type: 'gate', size: nil, inlet: [0, 0, 0], outlet: [100, 0, 0], up: [1, 0, 0]) }
  end

  def test_tools_follow_dialog_changes
    H.save_settings(@fp.merge('valve_type' => 'gate', 'support_type' => 'clevis'))
    vt = ValveTool.new
    vt.activate
    st = SupportTool.new
    st.activate
    H.save_settings(@fp.merge('valve_type' => 'butterfly', 'support_type' => 'stand'))
    [ValveTool, SupportTool].each { |t| t.active&.reload_settings }
    assert_equal 'butterfly', vt.instance_variable_get(:@type)
    assert_equal 'stand', st.instance_variable_get(:@type)
  end

  def test_plastic_valves_are_grey_not_pipe_blue
    pvc = Settings.sanitize('service' => 'CW', 'catalog' => 'PVC_TIS17', 'size' => '2"', 'lod' => 'light')
    run, = Builder.create_run(@model, [[[0, 0, 0], [3000, 0, 0]]], pvc)
    v = Builder.add_valve(@model, run, 'ball', [1500.0, 0, 0], [1.0, 0, 0])
    mats = v.definition.entities.grep(Sketchup::MeshBlob).map { |m| m.material&.name }.compact
    assert_includes mats, 'PP_Valve_PVC'
  end

  def test_plastic_reference_valve_keeps_its_own_colour
    pvc = Settings.sanitize('service' => 'CW', 'catalog' => 'PVC_TIS17', 'size' => '2"')
    run, = Builder.create_run(@model, [[[0, 0, 0], [3000, 0, 0]]], pvc)
    v = Builder.add_valve(@model, run, 'ball', [1500.0, 0, 0], [1.0, 0, 0])
    assert_match(/pl_union/, v.get_attribute(H::DICT, 'model'))
    refute_match(/\APP_CW_/, v.material.name)
  end
end
