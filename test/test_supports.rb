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
