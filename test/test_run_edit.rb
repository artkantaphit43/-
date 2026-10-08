# frozen_string_literal: true

require_relative 'test_helper'
require File.join(LIB, 'run_edit')

# Editing a drawn run: moving centreline points carries what sits on it.
class TestRunEdit < Minitest::Test
  def l_data
    {
      'cl' => [[[0.0, 0, 0], [4000.0, 0, 0]], [[4000.0, 0, 0], [4000.0, 3000, 0]]],
      'tees' => [], 'joins' => [],
      'valves' => [{ 'at' => [1000.0, 0, 0], 'dir' => [1.0, 0, 0] }, { 'at' => [4000.0, 2000, 0], 'dir' => [0, 1.0, 0] }],
      'supports' => [{ 'type' => 'clevis', 'at' => [4000.0, 2500, 0], 'dir' => [0, 1.0, 0], 'target' => [4000.0, 2500, 900] }],
      'end_parts' => [{ 'key' => 'x', 'at' => [4000.0, 3000, 0], 'angle' => 0.0 }]
    }
  end

  def test_stretching_an_open_end_carries_the_end_fitting_and_keeps_valves
    out, w = RunEdit.move_points(l_data, [[[4000.0, 3000, 0], [4000.0, 3800, 0]]])
    assert_empty w
    assert_equal [4000.0, 3800, 0], out['cl'][1][1]
    assert_equal [4000.0, 3800, 0], out['end_parts'][0]['at']
    assert Vec.near?(out['valves'][1]['at'], [4000.0, 2000, 0], 1e-9), 'valve keeps its distance from the elbow'
    assert Vec.near?(out['supports'][0]['target'], [4000.0, 2500, 900], 1e-9)
  end

  def test_moving_the_start_keeps_records_measured_from_the_far_end
    out, = RunEdit.move_points(l_data, [[[0.0, 0, 0], [-500.0, 0, 0]]])
    assert Vec.near?(out['valves'][0]['at'], [1000.0, 0, 0], 1e-9), 'valve stays 3000 mm from the elbow'
  end

  def test_moving_a_corner_slides_records_on_both_legs
    out, = RunEdit.move_points(l_data, [[[4000.0, 0, 0], [5000.0, 0, 0]]])
    assert_equal [5000.0, 0, 0], out['cl'][0][1]
    assert_equal [5000.0, 0, 0], out['cl'][1][0]
    assert Vec.near?(out['valves'][0]['at'], [1000.0, 0, 0], 1e-9)
    # second leg now runs from (5000,0) to (4000,3000): valve stays 1000 mm from the far end
    v = out['valves'][1]['at']
    assert_in_delta 1000.0, Vec.dist(v, [4000.0, 3000, 0]), 1e-6
    assert_in_delta 0.0, Vec.dot(Vec.unit(out['valves'][1]['dir']), Vec.unit([-1000.0, 3000, 0])) - 1.0, 1e-9
  end

  def test_shortening_past_a_valve_clamps_it_and_warns
    out, w = RunEdit.move_points(l_data, [[[0.0, 0, 0], [3500.0, 0, 0]]])
    refute_empty w
    assert Vec.near?(out['valves'][0]['at'], [3500.0, 0, 0], 1e-9)
  end

  def test_branch_connection_points_are_locked
    d = l_data.merge('tees' => [{ 'at' => [0.0, 0, 0] }])
    out, w = RunEdit.move_points(d, [[[0.0, 0, 0], [-100.0, 0, 0]]])
    assert_nil out
    refute_empty w
  end

  def ring(c, u, r, n = 8)
    v = Vec.perpendicular(u)
    w = Vec.cross(u, v)
    (0...n).map do |i|
      a = 2 * Math::PI * i / n
      Vec.add(c, Vec.add(Vec.scale(v, r * Math.cos(a)), Vec.scale(w, r * Math.sin(a))))
    end
  end

  def test_measure_reads_a_pushed_open_end
    a = [0.0, 0, 0]
    b = [2000.0, 0, 0]
    pts = ring([-20.0, 0, 0], [1, 0, 0], 30) + ring([2600.0, 0, 0], [1, 0, 0], 30)
    m = RunEdit.measure_pipe(a, b, 20.0, 0.0, 30.0, pts)
    assert_in_delta 0.0, m[:da], 1e-6
    assert_in_delta 600.0, m[:db], 1e-6
    assert Vec.near?(m[:b], [2600.0, 0, 0], 1e-6)
    refute m[:radial]
    assert_in_delta 0.0, m[:lateral], 1e-6
  end

  def test_measure_flags_sideways_move_and_scaled_diameter
    pts = ring([0.0, 100, 0], [1, 0, 0], 45) + ring([2000.0, 100, 0], [1, 0, 0], 45)
    m = RunEdit.measure_pipe([0.0, 0, 0], [2000.0, 0, 0], 0.0, 0.0, 30.0, pts)
    assert_in_delta 100.0, m[:lateral], 1e-6
    assert m[:radial]
  end
end
