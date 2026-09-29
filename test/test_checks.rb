# frozen_string_literal: true

require_relative 'test_helper'

class TestChecks < Minitest::Test
  def chain(*pts)
    pts.each_cons(2).to_a
  end

  # ---------- Profile ----------

  def test_inverted_u_has_high_point
    # pump (open end) up, across, down to equipment (open end)
    cl = chain([0, 0, 500], [0, 0, 3000], [5000, 0, 3000], [5000, 0, 500])
    prof = Profile.analyse(cl)
    assert_equal 1, prof[:high].size
    assert_empty prof[:low]
    assert_in_delta 3000.0, prof[:high].first[2], 1e-9
  end

  def test_u_trap_has_low_point
    cl = chain([0, 0, 3000], [1000, 0, 3000], [1000, 0, 500], [4000, 0, 500], [4000, 0, 3000], [6000, 0, 3000])
    prof = Profile.analyse(cl)
    assert_equal 1, prof[:low].size
    assert_empty prof[:high]
  end

  def test_level_run_ending_at_open_end_is_not_a_high_point
    cl = chain([0, 0, 500], [0, 0, 3000], [5000, 0, 3000])
    prof = Profile.analyse(cl)
    assert_empty prof[:high]
  end

  def test_direction_independent
    cl = chain([0, 0, 3000], [1000, 0, 3000], [1000, 0, 500], [4000, 0, 500], [4000, 0, 3000], [6000, 0, 3000])
    flipped = cl.map(&:reverse).reverse
    assert_equal Profile.analyse(cl)[:low], Profile.analyse(flipped)[:low]
  end

  # ---------- RunCheck ----------

  def spec(cat = 'CS_B36_10', size = '3"', rating = 'SCH40')
    Catalog.spec(cat, size, rating)
  end

  def test_pressure_run_totals
    cl = chain([0, 0, 0], [10_000, 0, 0], [10_000, 0, 5000])
    run = { spec: spec, service: 'CHWS', flow_m3h: 28.0, cl: cl,
            pipes: [{ from: [0, 0, 0], to: [9886, 0, 0], length_mm: 9886.0 },
                    { from: [10_000, 0, 114], to: [10_000, 0, 5000], length_mm: 4886.0 }],
            elbows: [{ angle_deg: 90.0, radius_type: 'lr', radius_mm: 114.3 }],
            valves: %w[gate check] }
    r = RunCheck.check(run)
    assert_in_delta 5.0, r[:dz], 1e-9
    assert_in_delta 0.3 + 0.15 + 2.0, r[:k_sum], 1e-9
    assert r[:total_head] > r[:dz]
    assert_in_delta r[:hf_friction] + r[:hf_minor] + r[:dz], r[:total_head], 0.002
    assert r[:ok]
  end

  def test_velocity_too_high_fails
    run = { spec: spec('CS_B36_10', '1"'), service: 'CW', flow_m3h: 10.0,
            cl: chain([0, 0, 0], [5000, 0, 0]),
            pipes: [{ from: [0, 0, 0], to: [5000, 0, 0], length_mm: 5000.0 }] }
    r = RunCheck.check(run)
    refute r[:ok]
    assert r[:velocity] > 2.0
  end

  def test_gravity_drain_slope_and_capacity
    sp = spec('PVC_TIS17', '4"', 'Class 8.5')
    cl = chain([0, 0, 1000], [10_000, 0, 1000 - 104]) # 1.04 %
    run = { spec: sp, service: 'SAN', flow_m3h: 10.0, cl: cl,
            pipes: [{ from: cl[0][0], to: cl[0][1], length_mm: 10_000.0 }] }
    r = RunCheck.check(run)
    assert_in_delta 1.04, r[:min_slope_pct], 0.01
    assert r[:capacity_m3h] > 10.0
    assert r[:ok], r[:messages].inspect

    flat = { spec: sp, service: 'SAN', flow_m3h: 10.0, cl: chain([0, 0, 0], [5000, 0, 0]), pipes: [] }
    refute RunCheck.check(flat)[:ok]
  end

  def test_gravity_sag_detected
    sp = spec('PVC_TIS17', '4"', 'Class 8.5')
    cl = chain([0, 0, 1000], [5000, 0, 900], [10_000, 0, 950])
    r = RunCheck.check({ spec: sp, service: 'SAN', flow_m3h: 5.0, cl: cl, pipes: [] })
    refute r[:ok]
    assert_equal 1, r[:low_points].size
  end

  def test_steam_low_point_advice
    cl = chain([0, 0, 3000], [1000, 0, 3000], [1000, 0, 500], [4000, 0, 500], [4000, 0, 3000], [6000, 0, 3000])
    r = RunCheck.check({ spec: spec, service: 'STM', flow_m3h: 500.0, cl: cl, pipes: [] })
    assert(r[:messages].any? { |m| m.include?('steam trap') })
  end

  def test_no_flow
    r = RunCheck.check({ spec: spec, service: 'CW', flow_m3h: 0, cl: [], pipes: [] })
    refute r[:ok]
  end

  # ---------- Clash ----------

  def test_segment_distance_parallel_and_crossing
    d, = Clash.segment_distance([0, 0, 0], [1000, 0, 0], [0, 100, 0], [1000, 100, 0])
    assert_in_delta 100.0, d, 1e-9
    d, = Clash.segment_distance([0, 0, 0], [1000, 0, 0], [500, -500, 300], [500, 500, 300])
    assert_in_delta 300.0, d, 1e-9
    d, = Clash.segment_distance([0, 0, 0], [1000, 0, 0], [1500, 0, 0], [2000, 0, 0])
    assert_in_delta 500.0, d, 1e-9
  end

  def test_find_clashes_between_runs_only
    items = [
      Clash::Item.new(owner: 'A', label: 'A1', a: [0, 0, 0], b: [5000, 0, 0], r: 57.0),
      Clash::Item.new(owner: 'A', label: 'A2', a: [0, 50, 0], b: [5000, 50, 0], r: 57.0),     # same run: ignored
      Clash::Item.new(owner: 'B', label: 'B1', a: [2500, -1000, 100], b: [2500, 1000, 100], r: 30.0),
      Clash::Item.new(owner: 'C', label: 'C1', a: [0, 0, 2000], b: [5000, 0, 2000], r: 30.0) # far away
    ]
    res = Clash.find(items, clearance: 25.0)
    assert_equal 1, res.size
    assert_equal %w[A B], res.first[:owners]
    assert_in_delta 100.0 - 57.0 - 30.0, res.first[:gap], 0.1
  end

  def test_arc_chords_end_on_arc
    ch = Clash.arc_chords([0, 0, 0], [1, 0, 0], [0, 0, 1], 100.0, Math::PI / 2)
    assert_equal 3, ch.size
    assert Vec.near?(ch.last[1], [0, 100, 0], 1e-9)
  end
end
