# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'su_stub'

module ArtK
  module PlantPipe
    PLUGIN_ROOT = File.expand_path('../src/artk_plant_pipe', __dir__) unless defined?(PLUGIN_ROOT)
    VERSION = 'test' unless defined?(VERSION)
  end
end
%w[model_helpers builder support_builder collector picker reports commands support_tool].each do |f|
  require File.expand_path("../src/artk_plant_pipe/su/#{f}", __dir__)
end

class TestSuV2 < Minitest::Test
  H = ModelHelpers

  def setup
    @model = Sketchup::Model.new
    Sketchup.active_model = @model
    @fp = Settings.sanitize('service' => 'FP', 'catalog' => 'CS_B36_10', 'size' => '4"')
    # A slab soffit at z = 4000 mm and a floor at z = 0 everywhere; the ray
    # first meets our own pipe, which the plugin must skip.
    own_pipe = Sketchup::Group.new
    own_pipe.set_attribute(H::DICT, 'type', 'pipe')
    @model.ray_hits = lambda do |pt, dir|
      if dir[2] > 0.5
        pt[2] < 3000 + 57 ? [[pt[0], pt[1], 3000 + 57], [own_pipe]] : [[pt[0], pt[1], 4000.0], []]
      elsif dir[2] < -0.5
        [[pt[0], pt[1], 0.0], []]
      end
    end
  end

  def children(run, type)
    run.entities.select { |e| H.instance?(e) && H.type_of(e) == type }
  end

  def l_run
    [[[0, 0, 3000], [8000, 0, 3000]], [[8000, 0, 3000], [8000, 6000, 3000]]]
  end

  def test_fittings_are_shared_component_instances
    r1, = Builder.create_run(@model, l_run, @fp)
    r2, = Builder.create_run(@model, l_run.map { |a, b| [a.map { |c| c + 20_000 }, b.map { |c| c + 20_000 }] }, @fp)
    e1 = children(r1, 'elbow').first
    e2 = children(r2, 'elbow').first
    assert_kind_of Sketchup::ComponentInstance, e1
    assert_same e1.definition, e2.definition
    assert_equal 2, e1.definition.count_instances
    assert_kind_of Sketchup::Group, children(r1, 'pipe').first
    assert $mesh_polys.to_i.positive?
  end

  def test_socket_pipe_cut_length_includes_insertion
    pvc = Settings.sanitize('service' => 'CW', 'catalog' => 'PVC_TIS17', 'size' => '2"')
    run, = Builder.create_run(@model, [[[0, 0, 0], [3000, 0, 0]], [[3000, 0, 0], [3000, 2000, 0]]], pvc)
    lens = children(run, 'pipe').map { |p| p.get_attribute(H::DICT, 'length_mm') }.sort
    r = Catalog.spec('PVC_TIS17', '2"').elbow_radius_lr
    ins = FittingsData.socket_depth(60.0)
    # open end: no insertion; elbow end: + socket depth
    assert_in_delta 2000 - r + ins, lens[0], 0.2
    assert_in_delta 3000 - r + ins, lens[1], 0.2
  end

  def test_auto_supports_hang_from_structure_and_count_in_bom
    run, = Builder.create_run(@model, l_run, @fp)
    @model.selection.push(run)
    H.save_settings(@fp.merge('support_type' => 'clevis'))
    Commands.auto_supports
    sup = children(run, 'support')
    refute_empty sup
    recs = H.get_json(run, 'supports')
    assert_equal sup.size, recs.size
    assert(recs.all? { |r| (r['target'][2] - 4000.0).abs < 1e-6 }, 'hangers must reach the slab, not our own pipe')
    # 4" steel: span 14 ft = 4.27 m → 8 m leg needs ≥ 3 supports
    assert sup.size >= 5
    rows = Bom.aggregate(Collector.records(@model))
    assert(rows.any? { |r| r.category == 'support' && r.qty == sup.size })
    rod = rows.find { |r| r.category == 'rod' }
    assert_equal 'Threaded rod 5/8" (M16)', rod.description
  end

  def test_supports_follow_resize
    run, = Builder.create_run(@model, l_run, @fp)
    rec, = SupportBuilder.record_for(@model, run, Geom::Transformation.new, 'clevis', [4000, 0, 3000], [1, 0, 0])
    H.set_json(run, 'supports', [rec])
    Builder.rebuild(@model, [run], @fp.merge('size' => '8"'))
    s = children(run, 'support').first
    assert_equal '8"', s.get_attribute(H::DICT, 'pipe_size')
    assert_equal '7/8" (M22)', s.get_attribute(H::DICT, 'rod_label')
  end

  def test_floor_stand_and_bracket_records
    run, = Builder.create_run(@model, l_run, @fp)
    rec, = SupportBuilder.record_for(@model, run, Geom::Transformation.new, 'stand', [4000, 0, 3000], [1, 0, 0])
    assert_in_delta 0.0, rec['target'][2], 1e-6
    rec2, note = SupportBuilder.record_for(@model, run, Geom::Transformation.new, 'bracket', [4000, 0, 3000], [1, 0, 0])
    assert_nil rec2 # no wall within 3 m in this model
    assert_match(/wall/, note)
  end

  def test_trapeze_spans_parallel_runs
    Builder.create_run(@model, [[[0, 0, 3000], [6000, 0, 3000]]], @fp)
    Builder.create_run(@model, [[[0, 400, 3000], [6000, 400, 3000]]], @fp.merge('size' => '2"'))
    Builder.create_run(@model, [[[0, 5000, 3000], [6000, 5000, 3000]]], @fp) # too far away
    g, = SupportBuilder.create_multi(@model, 'trapeze', [3000, 0, 3000], [1, 0, 0])
    assert_equal '2 pipes', g.get_attribute(H::DICT, 'pipe_size')
    assert g.get_attribute(H::DICT, 'member_length_mm').positive?
  end

  def test_colour_scheme_recolours_materials
    Builder.create_run(@model, l_run, @fp)
    Builder.create_run(@model, l_run, @fp.merge('service' => 'CHWS'))
    assert_equal [200, 30, 36], @model.materials['PP_FP_CS'].color.rgb   # fire red even in material scheme
    assert_equal Services::MATERIAL_COLORS['CS'], @model.materials['PP_CHWS_CS'].color.rgb
    H.apply_color_scheme(@model, 'distinct')
    assert_equal Services.get('CHWS')[:rgb], @model.materials['PP_CHWS_CS'].color.rgb
  end

  def test_rebuild_purges_unused_definitions
    run, = Builder.create_run(@model, l_run, @fp)
    before = @model.definitions.map(&:name)
    Builder.rebuild(@model, [run], @fp.merge('size' => '6"'))
    after = @model.definitions.map(&:name)
    assert(before.any? { |n| n.include?('4"') })
    assert(after.none? { |n| n.include?('4"') })
  end

  def test_light_lod_uses_fewer_polygons
    $mesh_polys = 0
    run, = Builder.create_run(@model, [[[0, 0, 0], [5000, 0, 0]]], @fp.merge('lod' => 'light'))
    Builder.add_valve(@model, run, 'gate', [2500, 0, 0], [1, 0, 0])
    light = $mesh_polys
    m2 = Sketchup::Model.new
    Sketchup.active_model = m2
    $mesh_polys = 0
    run2, = Builder.create_run(m2, [[[0, 0, 0], [5000, 0, 0]]], @fp.merge('lod' => 'detailed'))
    Builder.add_valve(m2, run2, 'gate', [2500, 0, 0], [1, 0, 0])
    assert $mesh_polys > 1.5 * light
  end

  def test_failed_component_falls_back_to_group_not_a_gap
    H.singleton_class.send(:alias_method, :orig_part_definition, :part_definition)
    H.define_singleton_method(:part_definition) { |*_a, **_k| raise 'simulated SketchUp failure' }
    run, warnings = Builder.create_run(@model, l_run, @fp)
    elbow = children(run, 'elbow').first
    refute_nil elbow, 'elbow must still exist'
    assert_kind_of Sketchup::Group, elbow
    assert(warnings.any? { |w| w.include?('simulated SketchUp failure') })
    assert(H.get_json(run, 'warnings').any? { |w| w.include?('drawn as group') })
  ensure
    H.singleton_class.send(:alias_method, :part_definition, :orig_part_definition)
  end
end

class TestDiagnostics < Minitest::Test
  def test_diagnostics_runs_and_undoes
    model = Sketchup::Model.new
    Sketchup.active_active = nil if Sketchup.respond_to?(:active_active=)
    Sketchup.active_model = model
    def Sketchup.version = '26.0'
    ArtK::PlantPipe::ModelHelpers.save_settings(Settings.sanitize('service' => 'FP', 'catalog' => 'CS_B36_10', 'size' => '4"'))
    ArtK::PlantPipe::Commands.diagnostics
    html = UI.last_html
    assert_includes html, 'Self-test'
    %w[pipe elbow tee valve].each { |t| assert_includes html, "<td>#{t}</td>" }
    refute_includes html, 'NO FACES'
    assert_equal [:abort], model.ops.last
  end
end

class TestSettingsPersistence < Minitest::Test
  H = ArtK::PlantPipe::ModelHelpers

  # Simulate SketchUp mangling quotes in stored strings.
  def test_settings_survive_quote_mangling_storage
    orig = Sketchup.method(:write_default)
    Sketchup.define_singleton_method(:write_default) { |sec, key, val| orig.call(sec, key, val.to_s.delete('"\\')) }
    H.save_settings(Settings.sanitize('service' => 'FP', 'catalog' => 'CS_B36_10', 'size' => '6"', 'valve_type' => 'butterfly'))
    H.reset_settings_cache! # as after restarting SketchUp
    s = H.load_settings
    assert_equal %w[FP 6" CS_B36_10 butterfly], s.values_at('service', 'size', 'catalog', 'valve_type')
  ensure
    Sketchup.define_singleton_method(:write_default, orig)
  end

  def test_each_new_run_uses_the_size_chosen_at_that_time
    model = Sketchup::Model.new
    Sketchup.active_model = model
    runs = %w[1" 2" 4" 8"].each_with_index.map do |size, i|
      H.save_settings(Settings.sanitize('service' => 'FP', 'catalog' => 'CS_B36_10', 'size' => size))
      H.reset_settings_cache!
      ArtK::PlantPipe::Builder.create_run(model, [[[0, i * 1000, 0], [2000, i * 1000, 0]]], H.load_settings).first
    end
    assert_equal ['1"-FP-001', '2"-FP-002', '4"-FP-003', '8"-FP-004'], runs.map(&:name)
  end
end
