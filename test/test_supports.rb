# frozen_string_literal: true

require_relative 'test_helper'

class TestSupports < Minitest::Test
  def check(part, label)
    part.solids.each_with_index do |(role, s), i|
      assert Mesh.closed?(s), "#{label}: solid #{i} (#{role}) not closed"
      assert Mesh.volume(s).positive?, "#{label}: solid #{i} (#{role}) inside-out"
    end
  end

  def test_span_table_values
    assert_in_delta 14 * 0.3048, Supports.max_span_m(Catalog.spec('CS_B36_10', '4"')), 0.01 # 4.27 m
    assert_in_delta 7 * 0.3048, Supports.max_span_m(Catalog.spec('CS_B36_10', '1"')), 0.01
    assert_in_delta 1.8, Supports.max_span_m(Catalog.spec('PVC_TIS17', '2"')), 0.01
    cold = Supports.max_span_m(Catalog.spec('PPR_DIN8077', '32 mm'))
    hot = Supports.max_span_m(Catalog.spec('PPR_DIN8077', '32 mm'), hot: true)
    assert_in_delta cold * 0.6, hot, 0.01
    assert_equal '3/8" (M10)', Supports.rod(Catalog.spec('CS_B36_10', '2"'))[:label]
    assert_equal '5/8" (M16)', Supports.rod(Catalog.spec('CS_B36_10', '4"'))[:label]
  end

  def test_placement_respects_span_and_end_distance
    pipes = [{ from: [0, 0, 3000], to: [10_000, 0, 3000] }, { from: [10_000, 0, 3000], to: [10_000, 0, 0] }]
    res = Supports.place(pipes, 3000.0)
    xs = res[:supports].map { |s| s[:at][0] }.sort
    assert_equal 1, res[:risers]
    assert_in_delta 600.0, xs.first, 1e-6
    assert_in_delta 9400.0, xs.last, 1e-6
    xs.each_cons(2) { |a, b| assert b - a <= 3000.0 + 1e-6 }
  end

  def test_short_pipe_gets_one_support_and_loads_get_support
    res = Supports.place([{ from: [0, 0, 0], to: [800, 0, 0] }], 3000.0)
    assert_equal 1, res[:supports].size
    assert_in_delta 400.0, res[:supports].first[:at][0], 1e-6
    res = Supports.place([{ from: [0, 0, 0], to: [12_000, 0, 0] }], 12_000.0, loads: [[6000, 0, 0]])
    assert(res[:supports].any? { |s| (s[:at][0] - 6000).abs <= 600 })
  end

  def test_all_models_are_closed
    [30.0, 57.15, 110.0].each do |r|
      check(Supports.clevis(r, 800, 9.5), "clevis #{r}")
      check(Supports.clevis(r, 800, 9.5, kind: :beam), "beam #{r}")
      check(Supports.pipe_hanger(r, 150, 600, 9.5), "pipe hanger #{r}")
      check(Supports.trapeze([[-300, r], [0, r], [250, 40]], 900, 12.7), "trapeze #{r}")
      check(Supports.stand(r, 900), "stand #{r}")
      check(Supports.hframe([[-300, r], [200, r]], 1200), "hframe #{r}")
      check(Supports.shoe(r, 50, 600), "shoe #{r}")
      check(Supports.bracket(r, 250), "bracket #{r}")
      check(Supports.clevis(r, 800, 9.5, detailed: false), "clevis light #{r}")
    end
  end
end

class TestSupportsLevels < Minitest::Test
  def test_trapeze_with_pipes_at_different_levels
    part = Supports.trapeze([[-200, 57, 0], [100, 30, 120]], 900, 12.7)
    part.solids.each { |_, s| assert Mesh.closed?(s) }
    zs = part.solids.flat_map { |_, s| s.polys.flatten(1).map { |p| p[2] } }
    # channel top at the lowest pipe bottom (-57); rods run 60 mm below it for the nut
    assert_in_delta(-57 - 60, zs.min, 1.0)
  end
end

# The user's wall box frame: C4 channel box bolted to a wall, cold lines
# U-bolted on the bottom member, a hot line on a T-shoe on top.
class TestWallFrame < Minitest::Test
  # cold water 2", chilled water 3" + 50 insulation, air 1", steam 2" + 50 on top
  SET = [[0, 30.2, 0, 0], [180, 94.5, 64.3, 50], [360, 16.7, -13.5, 0], [180, 80.2, 420, 50]].freeze

  def zs(part, role = nil)
    part.solids.select { |r, _| role.nil? || r == role }.flat_map { |_, s| s.polys.flatten(1).map { |p| p[2] } }
  end

  def test_solids_closed_in_both_levels_of_detail
    [SET, SET.first(3), [[0, 10.7, 0, 0]], [[0, 30, 0, 0], [150, 30, 500, 0], [350, 60, 650, 25]]].each do |set|
      [true, false].each do |det|
        part, = Supports.wall_frame(set, 400, detailed: det)
        part.solids.each_with_index do |(role, s), i|
          assert Mesh.closed?(s), "#{set.size} pipes det=#{det}: solid #{i} (#{role}) not closed"
          assert Mesh.volume(s).positive?, "#{set.size} pipes det=#{det}: solid #{i} (#{role}) inside-out"
        end
      end
    end
  end

  def test_levels_box_and_shoe
    part, info = Supports.wall_frame(SET, 400)
    assert_equal 1, info[:upper]
    assert_equal 0, info[:skipped]
    assert_equal 4, info[:carried].size
    steel = zs(part, :steel)
    # box bottom: bottom member web at the lowest pipe bottom (−30.2), toes 40.1 below
    assert_in_delta(-30.2 - Supports::C4[:bf], steel.min, 0.01)
    # top: the shoe web reaches the bare steam pipe (420 − 30.2)
    assert_in_delta 420 - 30.2, steel.max, 0.01
    ys = part.solids.select { |r, _| r == :steel }.flat_map { |_, s| s.polys.flatten(1).map { |p| p[1] } }
    assert_in_delta(-400, ys.min, 0.01) # back post web on the wall face
    assert_in_delta 360 + 16.7 + 60 + Supports::C4[:bf], ys.max, 0.01
    # three expansion bolts into the wall
    assert_equal 3, part.solids.count { |r, s| r == :galv && s.polys.flatten(1).map { |p| p[1] }.min < -450 }
    # bare box (no hot line): top member clears the highest pipe by 80 mm
    part, info = Supports.wall_frame(SET.first(3), 400, detailed: false)
    assert_equal 0, info[:upper]
    assert_in_delta 64.3 + 94.5 + 80 + Supports::C4[:bf], zs(part).max, 0.01
  end

  def test_pipe_too_high_or_in_between_is_left_out
    _part, info = Supports.wall_frame([[0, 30, 0, 0], [200, 30, 1100, 0], [400, 30, 500, 0]], 400)
    assert_equal 1, info[:upper]
    assert_equal 1, info[:skipped] # 600 mm above the shoe level of the other hot line
    _part, info = Supports.wall_frame([[0, 30, 0, 0], [200, 30, 120, 0]], 400)
    assert_equal 0, info[:skipped] # within the box level: on a packer
    _part, info = Supports.wall_frame([[0, 30, 0, 0], [200, 30, 330, 0]], 400)
    assert_equal 1, info[:upper], 'clears the lower lines: on top'
    _part, info = Supports.wall_frame([[0, 110, 0, 0], [300, 30, 200, 0], [500, 30, 230, 0]], 400)
    assert_equal 1, info[:skipped], 'too high for a packer, too low to clear the top member'
  end

  def test_fit_beside_the_wall
    assert Supports.in_frame?(0, 30, 400)
    refute Supports.in_frame?(-380, 30, 400), 'U-bolt nut into the back post'
    refute Supports.in_frame?(1200, 30, 400), 'beyond 1.5 m from the wall'
  end
end

