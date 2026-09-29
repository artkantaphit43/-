# frozen_string_literal: true

require_relative 'test_helper'

class TestHydraulics < Minitest::Test
  def test_velocity
    # 36 m³/h through 100 mm bore: Q = 0.01 m³/s, A = 7.854e-3 m² → 1.273 m/s
    assert_in_delta 1.2732, Hydraulics.velocity(36.0, 100.0), 1e-4
  end

  def test_friction_factor_against_colebrook
    # Colebrook solved iteratively for comparison
    re = 1.0e5
    eps_d = 0.045 / 100.0
    f = 0.02
    50.times { f = (-2.0 * Math.log10(eps_d / 3.7 + 2.51 / (re * Math.sqrt(f))))**-2 }
    assert_in_delta f, Hydraulics.friction_factor(re, 0.045, 100.0), f * 0.02
  end

  def test_laminar
    assert_in_delta 64.0 / 1000, Hydraulics.friction_factor(1000, 0.045, 50), 1e-12
  end

  def test_hazen_williams_reference_case
    # 4" Sch40 steel (ID 102.26), C=120, 20 L/s, 100 m.
    # Hand calc: 10.67·100·0.02^1.852 / (120^1.852 · 0.10226^4.8704)
    #          = 10.67·100·7.13e-4 / (7086 · 1.50e-5) ≈ 7.15 m
    hf = Hydraulics.hazen_williams_hf(72.0, 102.26, 120, 100.0)
    assert_in_delta 7.15, hf, 0.05
  end

  def test_darcy_and_hw_agree_roughly_for_cold_water_steel
    hw = Hydraulics.hazen_williams_hf(72.0, 102.26, 120, 100.0)
    dw = Hydraulics.darcy_hf(72.0, 102.26, 0.045, 100.0, :water)
    assert_in_delta hw, dw, hw * 0.25
  end

  def test_size_table_recommends_smallest_passing
    specs = Catalog.sizes('CS_B36_10').map { |s| Catalog.spec('CS_B36_10', s, 'SCH40') }
    # 28 m³/h: 2-1/2" → 2.5 m/s (fails vmax); 3" → 1.63 m/s, ≈3.6 m/100 m (passes)
    rows, idx = Hydraulics.size_table(specs, 28.0, fluid: :water, vmax: 2.0, hf_max: 4.0)
    refute_nil idx
    assert rows[idx][:ok]
    assert(rows[0...idx].none? { |r| r[:ok] })
    assert_equal '3"', rows[idx][:size]
  end

  def test_manning_full_and_half_full
    full = Hydraulics.manning_capacity(100.0, 1.0, fill: 1.0, n: 0.011)
    half = Hydraulics.manning_capacity(100.0, 1.0, fill: 0.5, n: 0.011)
    # Half-full: same hydraulic radius as full (D/4) → same velocity, half flow
    assert_in_delta full[:v], half[:v], 1e-9
    assert_in_delta full[:q_m3h] / 2.0, half[:q_m3h], 1e-6
    # Full flow: v = (1/n)(D/4)^(2/3) S^0.5 = 90.9 · 0.0855 · 0.1 = 0.777 m/s
    assert_in_delta 0.777, full[:v], 0.002
  end

  def test_min_drain_slope
    assert_in_delta 2.08, Services.min_drain_slope_pct(60.0), 1e-9
    assert_in_delta 2.08, Services.min_drain_slope_pct(76.0), 1e-9
    assert_in_delta 1.04, Services.min_drain_slope_pct(89.0), 1e-9
    assert_in_delta 0.52, Services.min_drain_slope_pct(216.0), 1e-9
  end

  def test_valve_face_to_face_interpolation
    assert_in_delta 229.0, FittingsData.face_to_face('gate', 114.3), 1e-9
    v = FittingsData.face_to_face('gate', 110.0) # HDPE 110 mm between 3" and 4"
    assert v > 203.0 && v < 229.0
    assert FittingsData.face_to_face('flange', 60.3).positive?
  end
end
