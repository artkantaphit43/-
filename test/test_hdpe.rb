# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'su_stub'

module ArtK
  module PlantPipe
    PLUGIN_ROOT = File.expand_path('../src/artk_plant_pipe', __dir__) unless defined?(PLUGIN_ROOT)
    VERSION = 'test' unless defined?(VERSION)
  end
end
%w[model_helpers migrate builder ref_models ref_builder support_builder collector picker reports library commands
   run_editor].each do |f|
  require File.expand_path("../src/artk_plant_pipe/su/#{f}", __dir__)
end

# HDPE fitting systems (1.14): butt fusion spigot, electrofusion,
# compression and stub-end flanges, chosen by size or by the user.
class TestHdpe < Minitest::Test
  H = ModelHelpers

  def setup
    @model = Sketchup::Model.new
    Sketchup.active_model = @model
  end

  def settings(size, joint = 'auto', cat = 'HDPE_PE100')
    Settings.sanitize('service' => 'CW', 'catalog' => cat, 'size' => size, 'hdpe_joint' => joint)
  end

  def opts(size, joint = 'auto', lod = :detailed)
    Parts.opts(Catalog.spec('HDPE_PE100', size), lod: lod, joint: joint)
  end

  def children(run, type)
    run.entities.select { |e| H.instance?(e) && H.type_of(e) == type }
  end

  def l_run(len = 20_000)
    [[[0, 0, 1000], [len, 0, 1000]], [[len, 0, 1000], [len, 4000, 1000]]]
  end

  def bom
    Bom.aggregate(Collector.records(@model))
  end

  def test_joint_system_by_size_or_choice
    assert_equal :compression, opts('63 mm').style
    assert_equal :electrofusion, opts('75 mm').style
    assert_equal :electrofusion, opts('110 mm').style
    assert_equal :fusion, opts('125 mm').style
    assert_equal :electrofusion, opts('63 mm', 'ef').style
    assert_equal :fusion, opts('63 mm', 'butt').style
    assert_equal :compression, opts('160 mm', 'comp').style
    assert_equal 'auto', Settings.sanitize('hdpe_joint' => 'weld')['hdpe_joint']
    assert_equal 'auto', Settings.sanitize({})['hdpe_joint']
    refute Hdpe.style?(Parts.opts(Catalog.spec('CS_B36_10', '4"'))), 'steel keeps its own fittings'
  end

  def test_dimensions_follow_the_tables
    assert_equal 145, Hdpe.ef_length(110)
    assert_equal 138, Hdpe.ef_body(110)
    assert_equal 96, Hdpe.ef_length(63)
    assert_equal 100, Hdpe.dn(110)
    assert_equal 100, Hdpe.dn(125)
    assert_equal 150, Hdpe.dn(160)
    assert_equal 157.2, Hdpe.flange(110).raised_face # DN100 raised face
    o = opts('160 mm')
    assert_in_delta Hdpe.leg(160) + 1.5 * 160, Hdpe.elbow_take(o, 90.0, 1.5 * 160), 1e-6
    assert Hdpe.segmented?(opts('400 mm'))
    refute Hdpe.segmented?(opts('250 mm'))
    assert_equal 4, Hdpe.welds(Math::PI / 2)
    assert_equal 2, Hdpe.welds(Math::PI / 4)
  end

  def test_elbows_end_where_the_network_trimmed
    [['63 mm', 'auto'], ['110 mm', 'auto'], ['160 mm', 'auto'], ['400 mm', 'auto']].each do |size, j|
      o = opts(size, j)
      th = Math::PI / 2
      take = Hdpe.elbow_take(o, 90.0, 1.5 * o.od)
      part = Parts.elbow(th, take / Math.tan(th / 2), o)
      pts = part.solids.flat_map { |_, s| s.polys.flatten(1) }
      far = pts.max_by { |p| p[1] }
      reach = o.style == :fusion ? take : take + Hdpe.ef_socket(o.od)
      reach = take + Hdpe.comp_socket(o.od) if o.style == :compression
      assert_operator far[1], :>=, reach - 1.0, "#{size}: the fitting reaches its end"
      part.solids.each { |_, s| assert Mesh.closed?(s), "#{size} #{o.style}" }
    end
  end

  def test_electrofusion_line_with_couplers_and_bom
    run, w = Builder.create_run(@model, l_run, settings('110 mm'))
    assert_empty w
    elbow = children(run, 'elbow').first
    assert_equal 'EF elbow 90°', elbow.get_attribute(H::DICT, 'fitting_desc')
    assert_equal 'Electrofusion', elbow.get_attribute(H::DICT, 'joint_desc')
    assert_includes elbow.definition.name, 'electrofusion'
    couplers = children(run, 'coupling')
    assert_equal 3, couplers.size, '20 m of 6 m sticks → joints at 6, 12, 18 m'
    rows = bom
    assert_equal 3, rows.find { |r| r.description == 'EF coupler' }.qty
    assert_equal 1, rows.find { |r| r.description == 'EF elbow 90°' }.qty
    # the pipe stops at the socket bottom: take = 0.37·d + 8
    take = Hdpe.elbow_take(opts('110 mm'), 90.0, 165.0)
    lens = children(run, 'pipe').map { |p| p.get_attribute(H::DICT, 'length_mm') }.sort
    assert_in_delta 4000 - take, lens.first, 0.1
  end

  def test_butt_fusion_line_has_legs_beads_and_no_couplers
    run, w = Builder.create_run(@model, l_run, settings('160 mm'))
    assert_empty w
    elbow = children(run, 'elbow').first
    assert_equal 'Elbow 90° R=1.5D, spigot (butt fusion)', elbow.get_attribute(H::DICT, 'fitting_desc')
    assert_empty children(run, 'coupling')
    assert_equal 3, children(run, 'bead').size, 'a fusion bead at every stick joint'
    take = Hdpe.leg(160) + 240.0
    lens = children(run, 'pipe').map { |p| p.get_attribute(H::DICT, 'length_mm') }.sort
    assert_in_delta 4000 - take, lens.first, 0.1
    refute(bom.any? { |r| r.description.to_s.include?('coupler') })
  end

  def test_large_bends_are_segmented
    run, = Builder.create_run(@model, l_run, settings('400 mm'))
    d = children(run, 'elbow').first.get_attribute(H::DICT, 'fitting_desc')
    assert_equal 'Segmented bend 90° R=1.5D, 4 welds (fabricated)', d
  end

  def test_compression_line
    run, w = Builder.create_run(@model, l_run, settings('63 mm'))
    assert_empty w
    assert_equal 'Compression elbow 90° (PP)', children(run, 'elbow').first.get_attribute(H::DICT, 'fitting_desc')
    assert_equal 3, children(run, 'coupling').size
    assert(bom.any? { |r| r.description == 'Compression coupler (PP)' && r.qty == 3 })
    nut = @model.materials.to_a.find { |m| m.name == 'PP_Compression_Nut' }
    assert nut, 'blue compression nuts'
  end

  def test_valves_bolt_on_with_stub_ends
    run, = Builder.create_run(@model, [[[0, 0, 0], [5000, 0, 0]]], settings('110 mm'))
    Builder.add_valve(@model, run, 'gate', [2500, 0, 0], [1, 0, 0])
    v = children(run, 'valve').first
    assert_includes v.get_attribute(H::DICT, 'end_type'), 'stub ends'
    assert_equal 2, v.get_attribute(H::DICT, 'stub_ends')
    rows = bom
    assert_equal 2, rows.find { |r| r.description == 'PE stub end + backing ring DN100' }.qty
    assert(rows.any? { |r| r.category == 'valve' && r.description.include?('Gate') })
    o = opts('110 mm')
    assert_operator Parts.valve_length('gate', o), :>, FittingsData.face_to_face('gate', 114.3, :flanged) + 2 * 90

    run2, = Builder.create_run(@model, [[[0, 3000, 0], [5000, 3000, 0]]], settings('50 mm'))
    Builder.add_valve(@model, run2, 'ball', [2500, 3000, 0], [1, 0, 0])
    assert_equal 'Compression (PP)', children(run2, 'valve').first.get_attribute(H::DICT, 'end_type')
  end

  def test_branch_and_reducer_follow_the_main_line_system
    main, = Builder.create_run(@model, [[[0, 0, 0], [10_000, 0, 0]]], settings('160 mm'))
    tee = { 'at' => [4000.0, 0.0, 0.0], 'main_dir' => [1.0, 0.0, 0.0], 'main_catalog' => 'HDPE_PE100',
            'main_size' => '160 mm', 'main_rating' => 'SDR11 PN16', 'main_service' => 'CW',
            'main_pid' => main.persistent_id, 'main_joint' => 'ef' }
    br, w = Builder.create_run(@model, [[[4000, 0, 0], [4000, 3000, 0]]], settings('160 mm'), tees: [tee])
    assert_empty w
    c = Hdpe.tee_c(opts('160 mm', 'ef'))
    assert_in_delta 3000 - c, children(br, 'pipe').first.get_attribute(H::DICT, 'length_mm'), 0.1
    assert_equal 'Electrofusion', children(br, 'tee').first.get_attribute(H::DICT, 'joint_desc')

    len = Builder.join_length(Catalog.spec('HDPE_PE100', '110 mm'), Catalog.spec('HDPE_PE100', '63 mm'))
    assert_in_delta (0.25 * 110 + 10) + (0.2 * 110 + 12), len, 0.1
  end

  def test_old_hdpe_runs_rebuild_with_the_new_fittings
    run, = Builder.create_run(@model, l_run, settings('110 mm'))
    s = H.get_json(run, 'settings')
    s.delete('hdpe_joint') # drawn before 1.14
    H.set_json(run, 'settings', s)
    Builder.rebuild(@model, [run], Builder.run_settings(run))
    assert_equal 'EF elbow 90°', children(run, 'elbow').first.get_attribute(H::DICT, 'fitting_desc')
  end
end
