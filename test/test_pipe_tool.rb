# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'su_stub'

module ArtK
  module PlantPipe
    PLUGIN_ROOT = File.expand_path('../src/artk_plant_pipe', __dir__) unless defined?(PLUGIN_ROOT)
    VERSION = 'test' unless defined?(VERSION)
  end
end
%w[model_helpers builder valves collector picker reports commands pipe_tool].each do |f|
  require File.expand_path("../src/artk_plant_pipe/su/#{f}", __dir__)
end

class TestPipeTool < Minitest::Test
  H = ModelHelpers

  def setup
    @model = Sketchup::Model.new
    Sketchup.active_model = @model
    @view = @model.active_view
    Sketchup::InputPoint.next_vertex = nil
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
end
