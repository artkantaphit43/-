# frozen_string_literal: true

require_relative 'test_helper'

class TestNetwork < Minitest::Test
  SPEC = { od: 114.3, elbow_radius_lr: 152.4, elbow_radius_sr: 101.6, tee_c: 105.0 }.freeze

  def solve(segs, **opts)
    Network.new(segs, SPEC, **opts).solve
  end

  def test_straight_line_split_in_clicks_is_one_pipe
    n = solve([[[0, 0, 0], [1000, 0, 0]], [[1000, 0, 0], [3000, 0, 0]]])
    assert_equal 1, n.pipes.size
    assert_in_delta 3000.0, n.pipes.first.data[:length], 1e-6
    assert_empty n.fittings
    assert_empty n.warnings
  end

  def test_90_degree_elbow_geometry
    n = solve([[[0, 0, 0], [2000, 0, 0]], [[2000, 0, 0], [2000, 1500, 0]]])
    elbows = n.pieces.select { |p| p.type == :elbow }
    assert_equal 1, elbows.size
    e = elbows.first.data
    assert_in_delta 90.0, e[:angle_deg], 1e-6
    assert_equal 90.0, e[:nominal_angle]
    # Tangent length for 90° = R
    assert_in_delta 2000.0 - 152.4, e[:start][0], 1e-6
    assert_in_delta 152.4, e[:end][1], 1e-6
    # Both tangent points are exactly R from the centre
    assert_in_delta 152.4, Vec.dist(e[:center], e[:start]), 1e-6
    assert_in_delta 152.4, Vec.dist(e[:center], e[:end]), 1e-6
    # Pipes are trimmed by the tangent length
    lens = n.pipes.map { |p| p.data[:length] }.sort
    assert_in_delta 1500.0 - 152.4, lens[0], 1e-6
    assert_in_delta 2000.0 - 152.4, lens[1], 1e-6
  end

  def test_arc_sweep_ends_on_outgoing_tangent
    # Rotating xaxis about normal by the elbow angle must land on the end point
    [[[0, 0, 0], [1000, 0, 0], [1000 + 700, 700, 0]],     # 45° in plan
     [[0, 0, 0], [0, 0, 1000], [800, 300, 1500]],          # skewed 3D bend
     [[0, 0, 3000], [0, 0, 0], [0, 2000, 0]]].each do |a, b, c|
      n = solve([[a, b], [b, c]])
      e = n.pieces.find { |p| p.type == :elbow }.data
      rotated = Vec.add(e[:center], Vec.scale(Vec.rotate(e[:xaxis], e[:normal], e[:angle]), e[:radius]))
      assert Vec.near?(rotated, e[:end], 1e-6), "arc does not end at tangent point for #{[a, b, c]}"
      # tangent at the start of the arc equals incoming direction
      tangent = Vec.cross(e[:normal], e[:xaxis])
      assert Vec.near?(tangent, e[:dir_in], 1e-9)
    end
  end

  def test_45_degree_elbow_is_nominal
    n = solve([[[0, 0, 0], [1000, 0, 0]], [[1000, 0, 0], [2000, 1000, 0]]])
    e = n.pieces.find { |p| p.type == :elbow }.data
    assert_equal 45.0, e[:nominal_angle]
    assert_in_delta 152.4 * Math.tan(Math::PI / 8), Vec.dist(e[:vertex], e[:start]), 1e-6
  end

  def test_short_run_downgrades_to_sr_then_mitre
    # 250 mm between two 90° bends: LR needs 304.8, SR needs 203.2 → SR fits
    n = solve([[[0, 0, 0], [1000, 0, 0]], [[1000, 0, 0], [1000, 250, 0]], [[1000, 250, 0], [2000, 250, 0]]])
    types = n.pieces.select { |p| p.type == :elbow }.map { |p| p.data[:radius_type] }
    assert_equal %i[sr sr], types.sort
    refute_empty n.warnings

    # 150 mm: even SR (203.2) does not fit → at least one mitre
    n = solve([[[0, 0, 0], [1000, 0, 0]], [[1000, 0, 0], [1000, 150, 0]], [[1000, 150, 0], [2000, 150, 0]]])
    assert n.pieces.any? { |p| p.type == :mitre }
    # Remaining geometry still consistent: no negative pipe
    n.pipes.each { |p| assert p.data[:length].positive? }
  end

  def test_tee_detection_and_trim
    segs = [[[0, 0, 0], [2000, 0, 0]], [[2000, 0, 0], [4000, 0, 0]], [[2000, 0, 0], [2000, 1000, 0]]]
    n = solve(segs)
    tee = n.pieces.find { |p| p.type == :tee }
    refute_nil tee
    assert_in_delta 90.0, tee.data[:branch_angle], 1e-6
    assert Vec.near?(tee.data[:branch], [0, 1, 0], 1e-9)
    lens = n.pipes.map { |p| p.data[:length] }.sort
    assert_in_delta 1000.0 - 105.0, lens[0], 1e-6
    assert_in_delta 2000.0 - 105.0, lens[1], 1e-6
    assert_in_delta 2000.0 - 105.0, lens[2], 1e-6
  end

  def test_lateral_45
    segs = [[[0, 0, 0], [2000, 0, 0]], [[2000, 0, 0], [4000, 0, 0]], [[2000, 0, 0], [3000, 1000, 0]]]
    n = solve(segs)
    lat = n.pieces.find { |p| p.type == :lateral }
    refute_nil lat
    assert_in_delta 45.0, lat.data[:branch_angle], 1e-6
  end

  def test_cross
    segs = [[[-1000, 0, 0], [0, 0, 0]], [[0, 0, 0], [1000, 0, 0]],
            [[0, -1000, 0], [0, 0, 0]], [[0, 0, 0], [0, 1000, 0]]]
    n = solve(segs)
    assert_equal 1, n.pieces.count { |p| p.type == :cross }
    assert_equal 4, n.pipes.size
  end

  def test_nearby_points_merge_within_tolerance
    n = solve([[[0, 0, 0], [1000, 0, 0]], [[1000.4, 0.3, 0], [1000, 1000, 0]]], tol: 1.0)
    assert_equal 1, n.pieces.count { |p| p.type == :elbow }
  end

  def test_closed_rectangle_loop
    pts = [[0, 0, 0], [3000, 0, 0], [3000, 2000, 0], [0, 2000, 0]]
    segs = pts.each_with_index.map { |p, i| [p, pts[(i + 1) % 4]] }
    n = solve(segs)
    assert_equal 4, n.pieces.count { |p| p.type == :elbow }
    assert_equal 4, n.pipes.size
  end

  def test_fold_back_is_warned
    n = solve([[[0, 0, 0], [1000, 0, 0]], [[1000, 0, 0], [500, 0, 0]]])
    refute_empty n.warnings
  end

  def test_three_d_offset_with_riser
    pts = [[0, 0, 3000], [2000, 0, 3000], [2000, 0, 500], [2000, 1500, 500]]
    segs = pts.each_cons(2).to_a
    n = solve(segs)
    assert_equal 2, n.pieces.count { |p| p.type == :elbow }
    total = n.pipes.sum { |p| p.data[:length] }
    # centreline length minus 2·R per 90° elbow + arc lengths ≈ total CL
    arc = n.pieces.select { |p| p.type == :elbow }.sum { |p| p.data[:radius] * p.data[:angle] }
    assert_in_delta 2000 + 2500 + 1500 - 4 * 152.4 + 0, total, 1e-6
    assert_in_delta Math::PI * 152.4, arc, 1e-6
  end
end

class TestNetworkComponents < Minitest::Test
  def test_components
    segs = [[[0, 0, 0], [1000, 0, 0]], [[1000, 0, 0], [1000, 1000, 0]],
            [[5000, 0, 0], [6000, 0, 0]]]
    comps = Network.components(segs)
    assert_equal [2, 1], comps.map(&:size).sort.reverse
  end
end
