# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'su_stub'

module ArtK
  module PlantPipe
    PLUGIN_ROOT = File.expand_path('../src/artk_plant_pipe', __dir__) unless defined?(PLUGIN_ROOT)
    VERSION = 'test' unless defined?(VERSION)
  end
end
%w[model_helpers migrate builder ref_models ref_builder support_builder collector picker reports commands pipe_tool support_tool].each do |f|
  require File.expand_path("../src/artk_plant_pipe/su/#{f}", __dir__)
end

class TestPipeTool < Minitest::Test
  H = ModelHelpers

  def setup
    @model = Sketchup::Model.new
    Sketchup.active_model = @model
    @view = @model.active_view
    Sketchup::InputPoint.next_vertex = nil
    Sketchup::InputPoint.next_dof = nil
  end

  def tool_with(settings)
    H.save_settings(Settings.sanitize(settings))
    t = PipeTool.new
    t.activate
    t
  end

  def click(tool, mm)
    Sketchup::InputPoint.next_position = H.to_pt(mm)
    tool.onMouseMove(0, 0, 0, @view)
    tool.onLButtonDown(0, 0, 0, @view)
  end

  def runs
    Collector.all_runs(@model).map(&:first)
  end

  def cl_points(run)
    H.get_json(run, 'cl').flatten(1)
  end

  def test_draw_with_45_snap
    t = tool_with('service' => 'CW', 'snap45' => true)
    click(t, [0, 0, 0])
    click(t, [3000, 130, 40]) # slightly off-axis → snapped to +X, level
    click(t, [5000, 2100, 0]) # ≈ 45°
    t.onReturn(@view)
    assert_equal 1, runs.size
    pts = cl_points(runs.first)
    assert_in_delta 0.0, pts[1][1], 1e-6
    assert_in_delta 0.0, pts[1][2], 1e-6
    d = Vec.sub(pts[3], pts[2])
    assert_in_delta d[0], d[1], 1e-6 # exactly 45°
    assert_equal 1, runs.first.entities.count { |e| H.type_of(e) == 'elbow' }
  end

  def test_gravity_drain_gets_fall
    t = tool_with('service' => 'SAN', 'catalog' => 'PVC_TIS17', 'size' => '4"', 'slope_pct' => 1.0)
    click(t, [0, 0, 1000])
    click(t, [10_000, 0, 1000])
    t.onReturn(@view)
    pts = cl_points(runs.first)
    assert_in_delta 1000 - 100, pts[1][2], 1e-6
  end

  def test_typed_length
    t = tool_with('service' => 'CW')
    click(t, [0, 0, 0])
    Sketchup::InputPoint.next_position = H.to_pt([500, 0, 0])
    t.onMouseMove(0, 0, 0, @view)
    t.onUserText('2500', @view)
    t.onReturn(@view)
    pts = cl_points(runs.first)
    assert_in_delta 2500.0, pts[1][0], 1e-6
  end

  def test_axis_lock
    t = tool_with('service' => 'CW', 'snap45' => false)
    click(t, [0, 0, 0])
    t.onKeyDown(VK_UP, 0, 0, @view)
    click(t, [300, 200, 2000])
    t.onReturn(@view)
    pts = cl_points(runs.first)
    assert_equal [0.0, 0.0, 2000.0], pts[1].map { |v| v.round(6) }
  end

  def test_branch_and_continue
    t = tool_with('service' => 'FP', 'catalog' => 'CS_B36_10', 'size' => '6"')
    click(t, [0, 0, 3000])
    click(t, [10_000, 0, 3000])
    t.onReturn(@view)
    main = runs.first

    # start on the existing pipe → branch tee
    H.save_settings(Settings.sanitize('service' => 'FP', 'catalog' => 'CS_B36_10', 'size' => '2"'))
    t.resume(@view)
    click(t, [4000, 60, 3000])
    click(t, [4000, 3000, 3000])
    t.onReturn(@view)
    branch = runs.find { |r| r != main }
    tee = branch.entities.find { |e| H.type_of(e) == 'tee' }
    refute_nil tee
    assert_equal '6"', tee.get_attribute(H::DICT, 'size')

    # start at the branch's open end → continue the same run with an elbow
    click(t, [4000, 3000, 3000])
    click(t, [6000, 3000, 3000])
    t.onReturn(@view)
    assert_equal 2, runs.size
    assert_equal 1, branch.entities.count { |e| H.type_of(e) == 'elbow' }
  end

  def test_new_size_from_run_end_adds_reducer_and_new_run
    t = tool_with('service' => 'CW', 'catalog' => 'CS_B36_10', 'size' => '4"')
    click(t, [0, 0, 0])
    click(t, [3000, 0, 0])
    t.onReturn(@view)
    first = runs.first
    # the user now picks 2" and starts at the end of the 4" pipe
    H.save_settings(Settings.sanitize('service' => 'CW', 'catalog' => 'CS_B36_10', 'size' => '2"'))
    t.resume(@view)
    click(t, [3000, 0, 0])
    click(t, [6000, 0, 0])
    t.onReturn(@view)
    assert_equal 2, runs.size
    second = runs.find { |r| r != first }
    assert_equal '2"', second.get_attribute(H::DICT, 'size')
    red = second.entities.find { |e| H.type_of(e) == 'reducer' }
    refute_nil red
    assert_equal '4" x 2"', red.get_attribute(H::DICT, 'size')
    pipe = second.entities.find { |e| H.type_of(e) == 'pipe' }
    assert_in_delta 3000 - 102, pipe.get_attribute(H::DICT, 'length_mm'), 0.5 # B16.9 4"x2" H = 102
  end

  def test_new_size_with_turn_gives_old_run_an_elbow
    t = tool_with('service' => 'CW', 'catalog' => 'CS_B36_10', 'size' => '4"')
    click(t, [0, 0, 0])
    click(t, [3000, 0, 0])
    t.onReturn(@view)
    first = runs.first
    H.save_settings(Settings.sanitize('service' => 'CW', 'catalog' => 'CS_B36_10', 'size' => '2"'))
    t.resume(@view)
    click(t, [3000, 0, 0])
    click(t, [3000, 3000, 0])
    t.onReturn(@view)
    assert_equal 1, first.entities.count { |e| H.type_of(e) == 'elbow' }
    second = runs.find { |r| r != first }
    refute_nil second.entities.find { |e| H.type_of(e) == 'reducer' }
  end

  def test_same_size_from_run_end_continues_run
    t = tool_with('service' => 'CW', 'catalog' => 'CS_B36_10', 'size' => '4"')
    click(t, [0, 0, 0])
    click(t, [3000, 0, 0])
    t.onReturn(@view)
    click(t, [3000, 0, 0])
    click(t, [6000, 0, 0])
    t.onReturn(@view)
    assert_equal 1, runs.size
    assert_equal 1, runs.first.entities.count { |e| H.type_of(e) == 'pipe' } # merged, no gap
  end

  def test_point_snapped_on_a_guide_line_is_kept_exactly
    t = tool_with('service' => 'CW', 'snap45' => true)
    click(t, [0, 0, 0])
    Sketchup::InputPoint.next_dof = 1 # on a guide line / edge
    click(t, [3000, 700, 0])          # not a 45° direction
    Sketchup::InputPoint.next_dof = nil
    t.onReturn(@view)
    assert_equal [3000.0, 700.0, 0.0], cl_points(runs.first)[1].map { |v| v.round(6) }
  end

  def test_drawing_from_an_elbow_makes_a_tee_in_the_same_run
    t = tool_with('service' => 'CW', 'catalog' => 'CS_B36_10', 'size' => '4"')
    click(t, [0, 0, 0])
    click(t, [3000, 0, 0])
    click(t, [3000, 3000, 0])
    t.onReturn(@view)
    run = runs.first
    assert_equal 1, run.entities.count { |e| H.type_of(e) == 'elbow' }
    # start near the elbow (anywhere on the fitting) and carry straight on
    click(t, [3040, -30, 0])
    click(t, [6000, 0, 0])
    t.onReturn(@view)
    assert_equal 1, runs.size
    assert_equal 0, run.entities.count { |e| H.type_of(e) == 'elbow' }
    assert_equal 1, run.entities.count { |e| H.type_of(e) == 'tee' }
  end

  def test_ending_on_an_elbow_joins_that_run
    t = tool_with('service' => 'CW', 'catalog' => 'CS_B36_10', 'size' => '4"')
    click(t, [0, 0, 0])
    click(t, [3000, 0, 0])
    click(t, [3000, 3000, 0])
    t.onReturn(@view)
    click(t, [3000, -3000, 0])
    click(t, [3000, 0, 0]) # ends on the elbow corner
    assert_equal 1, runs.size
    assert_equal 1, runs.first.entities.count { |e| H.type_of(e) == 'tee' }
  end

  def test_smaller_branch_from_an_elbow_gets_stub_and_reducer
    t = tool_with('service' => 'CW', 'catalog' => 'CS_B36_10', 'size' => '4"')
    click(t, [0, 0, 0])
    click(t, [3000, 0, 0])
    click(t, [3000, 3000, 0])
    t.onReturn(@view)
    first = runs.first
    H.save_settings(Settings.sanitize('service' => 'CW', 'catalog' => 'CS_B36_10', 'size' => '2"'))
    t.resume(@view)
    click(t, [3000, 0, 0])
    click(t, [6000, 0, 0])
    t.onReturn(@view)
    assert_equal 1, first.entities.count { |e| H.type_of(e) == 'tee' }
    second = runs.find { |r| r != first }
    assert_equal '2"', second.get_attribute(H::DICT, 'size')
    refute_nil second.entities.find { |e| H.type_of(e) == 'reducer' }
  end

  def test_own_pipe_colour
    t = tool_with('service' => 'CW', 'pipe_color' => '#FF8800')
    click(t, [0, 0, 0])
    click(t, [2000, 0, 0])
    t.onReturn(@view)
    pipe = runs.first.entities.find { |e| H.type_of(e) == 'pipe' }
    assert_equal 'PP_Custom_ff8800', pipe.material.name
    assert_equal [255, 136, 0], pipe.material.color.rgb
  end

  def test_coiled_hdpe_bends_instead_of_elbows
    t = tool_with('service' => 'CW', 'catalog' => 'HDPEC_PE100', 'size' => '63 mm')
    click(t, [0, 0, 0])
    click(t, [20_000, 0, 0])
    click(t, [20_000, 20_000, 0])
    click(t, [20_500, 20_000, 0]) # too close for a 25×OD bend
    t.onReturn(@view)
    run = runs.first
    bends = run.entities.select { |e| e.get_attribute(H::DICT, 'bend_radius_mm') }
    assert_equal 1, bends.size
    assert_equal 63 * 25, bends.first.get_attribute(H::DICT, 'bend_radius_mm')
    assert_equal 1, run.entities.count { |e| H.type_of(e) == 'elbow' } # electrofusion elbow where no room
    assert(H.get_json(run, 'warnings').any? { |w| w.include?('ข้องอหลอมไฟฟ้า') })
    total = run.entities.select { |e| H.type_of(e) == 'pipe' }.sum { |e| e.get_attribute(H::DICT, 'length_mm') }
    assert_operator total, :>, 39_000 # bend arc counted as pipe
  end

  def test_clicking_the_rim_of_a_big_pipe_end_snaps_to_its_center
    t = tool_with('service' => 'CW', 'catalog' => 'CS_B36_10', 'size' => '8"')
    click(t, [0, 0, 0])
    click(t, [3000, 0, 0])
    t.onReturn(@view)
    click(t, [3000, 0, 109.5]) # top of the end ring (OD 219.1)
    click(t, [3000, 3000, 0])
    t.onReturn(@view)
    assert_equal 1, runs.size
    assert_includes cl_points(runs.first).map { |p| p.map { |v| v.round(3) } }, [3000.0, 0.0, 0.0]
    assert_equal 1, runs.first.entities.count { |e| H.type_of(e) == 'elbow' }
  end

  def test_drawing_onto_an_open_end_snaps_to_center_and_continues_that_run
    t = tool_with('service' => 'CW', 'catalog' => 'CS_B36_10', 'size' => '4"')
    click(t, [0, 0, 0])
    click(t, [3000, 0, 0])
    t.onReturn(@view)
    click(t, [3000, 3000, 0])
    Sketchup::InputPoint.next_position = H.to_pt([3000, 40, 45]) # on the end ring
    t.onMouseMove(0, 0, 0, @view)
    assert_includes @view.tooltip, 'Center'
    t.onLButtonDown(0, 0, 0, @view)
    assert_equal 1, runs.size, 'joined the run, no second run'
    assert_equal 1, runs.first.entities.count { |e| H.type_of(e) == 'elbow' }
    assert_equal [3000.0, 3000.0, 0.0], cl_points(runs.first).max_by { |p| p[1] }.map { |v| v.round(3) }
  end

  def test_other_size_onto_an_open_end_gets_a_reducer
    t = tool_with('service' => 'CW', 'catalog' => 'CS_B36_10', 'size' => '4"')
    click(t, [0, 0, 0])
    click(t, [3000, 0, 0])
    t.onReturn(@view)
    H.save_settings(Settings.sanitize('service' => 'CW', 'catalog' => 'CS_B36_10', 'size' => '2"'))
    t.resume(@view)
    click(t, [8000, 0, 0])
    click(t, [3000, 20, 30])
    assert_equal 2, runs.size
    second = runs.find { |r| r.get_attribute(H::DICT, 'size') == '2"' }
    refute_nil second.entities.find { |e| H.type_of(e) == 'reducer' }
  end
end
