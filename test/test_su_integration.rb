# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'su_stub'

module ArtK
  module PlantPipe
    PLUGIN_ROOT = File.expand_path('../src/artk_plant_pipe', __dir__) unless defined?(PLUGIN_ROOT)
    VERSION = 'test' unless defined?(VERSION)
  end
end
%w[model_helpers builder ref_models ref_builder support_builder collector picker reports commands support_tool].each do |f|
  require File.expand_path("../src/artk_plant_pipe/su/#{f}", __dir__)
end

class TestSuIntegration < Minitest::Test
  H = ModelHelpers

  def setup
    @model = Sketchup::Model.new
    Sketchup.active_model = @model
    @settings = Settings.sanitize('service' => 'CHWS', 'catalog' => 'CS_B36_10', 'size' => '4"',
                                  'rating' => 'SCH40', 'insulation_mm' => 50, 'labels' => true)
  end

  def l_run
    [[[0, 0, 3000], [5000, 0, 3000]], [[5000, 0, 3000], [5000, 4000, 3000]]]
  end

  def children(run, type)
    run.entities.select { |e| H.instance?(e) && H.type_of(e) == type }
  end

  def test_create_run_builds_pieces_and_attributes
    run, warnings = Builder.create_run(@model, l_run, @settings)
    assert_empty warnings
    assert_equal '4"-CHWS-001', run.name
    assert_equal 2, children(run, 'pipe').size
    assert_equal 1, children(run, 'elbow').size
    assert_equal 3, children(run, 'insulation').size
    assert_equal 1, children(run, 'centerline').size
    assert_equal [:start, 'Plant Piping: Draw Run'], @model.ops.first
    assert_equal [:commit], @model.ops.last
    len = children(run, 'pipe').sum { |p| p.get_attribute(H::DICT, 'length_mm') }
    assert_in_delta 9000 - 2 * 152.4, len, 0.2
  end

  # Open pipe ends carry a real circle + construction point so SketchUp's
  # own tools snap to "Center"; ends inside fittings get none.
  def test_open_pipe_ends_get_snappable_center
    run, = Builder.create_run(@model, l_run, @settings)
    centers = children(run, 'pipe').flat_map do |p|
      p.entities.select { |e| H.instance?(e) && H.type_of(e) == 'end_center' }
    end
    assert_equal 2, centers.size
    centers.each do |c|
      assert_equal 1, c.entities.count { |e| e.is_a?(Sketchup::ConstructionPoint) }
      assert_operator c.entities.count { |e| e.is_a?(Sketchup::Edge) }, :>=, 12
    end
    assert_empty children(run, 'end_center')
  end

  def test_line_numbers_increment_per_service
    r1, = Builder.create_run(@model, l_run, @settings)
    r2, = Builder.create_run(@model, l_run, @settings)
    r3, = Builder.create_run(@model, l_run, @settings.merge('service' => 'FP'))
    assert_equal ['4"-CHWS-001', '4"-CHWS-002', '4"-FP-001'], [r1.name, r2.name, r3.name]
  end

  def test_bom_from_model
    Builder.create_run(@model, l_run, @settings)
    recs = Collector.records(@model)
    rows = Bom.aggregate(recs)
    pipe = rows.find { |r| r.category == 'pipe' }
    assert_in_delta (9000 - 2 * 152.4) / 1000.0, pipe.qty, 0.005 # BOM rounds to 0.01 m
    assert_equal 2, pipe.sticks
    assert(rows.any? { |r| r.description == 'Elbow 90° LR' && r.qty == 1 })
    assert(rows.any? { |r| r.category == 'insulation' })
  end

  def test_rebuild_resizes_and_keeps_valves
    run, = Builder.create_run(@model, l_run, @settings)
    Builder.add_valve(@model, run, 'gate', [2500, 0, 3000], [1, 0, 0])
    assert_equal 1, children(run, 'valve').size
    Builder.rebuild(@model, [run], @settings.merge('size' => '6"'))
    assert_equal '6"-CHWS-001', run.name
    assert_equal 1, children(run, 'valve').size
    assert_equal '6"', children(run, 'valve').first.get_attribute(H::DICT, 'size')
    assert_in_delta 168.3, children(run, 'pipe').first.get_attribute(H::DICT, 'od'), 1e-9
  end

  def test_extend_run_adds_elbow
    run, = Builder.create_run(@model, l_run, @settings)
    Builder.extend_run(@model, run, [[[5000, 4000, 3000], [5000, 4000, 500]]])
    assert_equal 2, children(run, 'elbow').size
    assert_equal 3, H.get_json(run, 'cl').size
  end

  def test_branch_tee_from_existing_pipe
    main, = Builder.create_run(@model, [[[0, 0, 3000], [10_000, 0, 3000]]], @settings)
    hit = Picker.nearest_pipe(@model, [4000, 40, 3000])
    refute_nil hit
    assert_in_delta 4000, hit[:proj][0], 1e-6
    tee = { 'at' => hit[:proj], 'main_dir' => hit[:dir], 'main_catalog' => 'CS_B36_10',
            'main_size' => '4"', 'main_rating' => 'SCH40', 'main_service' => 'CHWS',
            'main_pid' => main.persistent_id }
    branch_settings = @settings.merge('size' => '2"')
    br, w = Builder.create_run(@model, [[hit[:proj], [4000, 3000, 3000]]], branch_settings, tees: [tee])
    assert_empty w
    t = children(br, 'tee').first
    assert_equal 'branch', t.get_attribute(H::DICT, 'role')
    assert_equal '2"', t.get_attribute(H::DICT, 'branch_size')
    # branch pipe starts at the tee outlet (C = 105 mm for 4")
    assert_in_delta 3000 - 105, children(br, 'pipe').first.get_attribute(H::DICT, 'length_mm'), 0.1
    rows = Bom.aggregate(Collector.records(@model))
    assert(rows.any? { |r| r.description == 'Reducing Tee' && r.size == '4" x 2"' })
    # connected runs are not reported as clashing
    clashes = Clash.find(Collector.clash_items(@model), clearance: 25, connections: Collector.connections(@model))
    assert_empty clashes

    # resizing the main line updates the branch's reducing tee
    Builder.rebuild(@model, [main], @settings.merge('size' => '8"'))
    t = children(br, 'tee').first
    assert_equal '8"', t.get_attribute(H::DICT, 'size')
    assert_in_delta 3000 - 178, children(br, 'pipe').first.get_attribute(H::DICT, 'length_mm'), 0.1
  end

  def test_run_end_detection_and_clash_between_runs
    Builder.create_run(@model, l_run, @settings)
    e = Picker.run_end(@model, [5000, 4000, 3010])
    refute_nil e
    # a second run crossing 100 mm below the first one → hard clash (insulated)
    Builder.create_run(@model, [[[2500, -2000, 2900], [2500, 2000, 2900]]], @settings.merge('service' => 'FP', 'insulation_mm' => 0))
    clashes = Clash.find(Collector.clash_items(@model), clearance: 25, connections: Collector.connections(@model))
    assert_equal 1, clashes.size
    assert clashes.first[:gap].negative?
  end

  def test_hydraulic_data_and_check
    run, = Builder.create_run(@model, l_run, @settings)
    run.set_attribute(H::DICT, 'design_flow_m3h', 60.0)
    res = RunCheck.check(Collector.run_data(run))
    assert res[:ok], res[:messages].inspect
    assert_in_delta 60.0 / 3600 / (Math::PI * 0.10226**2 / 4), res[:velocity], 0.01
  end

  def test_convert_selection_command
    e1 = @model.entities.add_line(Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(100, 0, 0))
    e2 = @model.entities.add_line(Geom::Point3d.new(100, 0, 0), Geom::Point3d.new(100, 100, 0))
    e3 = @model.entities.add_line(Geom::Point3d.new(300, 0, 0), Geom::Point3d.new(400, 0, 0))
    @model.selection.push(e1, e2, e3)
    H.save_settings(@settings)
    Commands.convert_selection
    runs = Collector.all_runs(@model).map(&:first)
    assert_equal 2, runs.size
    refute e1.valid? # source edges deleted after confirmation
  end

  def test_bom_command_renders_report
    Builder.create_run(@model, l_run, @settings)
    Commands.bom
    assert_includes UI.last_html, 'Elbow 90° LR'
  end

  def test_valve_types_all_build
    run, = Builder.create_run(@model, [[[0, 0, 0], [20_000, 0, 0]]], @settings)
    FittingsData.valve_types.each_with_index do |t, i|
      Builder.add_valve(@model, run, t, [1000 + i * 2000, 0, 0], [1, 0, 0])
    end
    assert_equal FittingsData.valve_types.size, children(run, 'valve').size
    run2, = Builder.create_run(@model, [[[0, 5000, 0], [0, 5000, 5000]]], @settings.merge('catalog' => 'PPR_DIN8077'))
    Builder.add_valve(@model, run2, 'ball', [0, 5000, 2500], [0, 0, 1]) # vertical plastic line
    assert_equal 1, children(run2, 'valve').size
  end
end
