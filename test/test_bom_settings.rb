# frozen_string_literal: true

require_relative 'test_helper'

class TestBomSettings < Minitest::Test
  def pipe(len, size = '2"', svc = 'CW')
    sp = Catalog.spec('CS_B36_10', size, 'SCH40')
    { 'type' => 'pipe', 'service' => svc, 'catalog_name' => sp.catalog_name, 'material' => sp.material,
      'size' => size, 'rating' => 'SCH40', 'length_mm' => len, 'weight_kg_m' => sp.weight_kg_m,
      'stick_m' => 6.0 }
  end

  def test_pipe_lengths_sum_and_sticks
    rows = Bom.aggregate([pipe(4000), pipe(5500), pipe(3000, '4"')], waste: 0.05)
    two = rows.find { |r| r.size == '2"' }
    assert_in_delta 9.5, two.qty, 1e-9
    assert_equal 2, two.sticks # 9.5·1.05 = 9.975 m → 2 × 6 m
    assert_in_delta 9.5 * Catalog.spec('CS_B36_10', '2"').weight_kg_m, two.weight, 0.1
    assert_equal '2"', rows.first.size # sorted by size
  end

  def test_fittings_grouped
    recs = [
      { 'type' => 'elbow', 'service' => 'CW', 'material' => 'CS', 'size' => '2"', 'nominal_angle' => 90.0, 'radius_type' => 'lr' },
      { 'type' => 'elbow', 'service' => 'CW', 'material' => 'CS', 'size' => '2"', 'nominal_angle' => 90.0, 'radius_type' => 'lr' },
      { 'type' => 'elbow', 'service' => 'CW', 'material' => 'CS', 'size' => '2"', 'angle' => 37.5, 'radius_type' => 'lr' },
      { 'type' => 'tee', 'service' => 'CW', 'material' => 'CS', 'size' => '2"', 'kind' => 'tee', 'branch_size' => '1"' },
      { 'type' => 'valve', 'service' => 'CW', 'material' => 'CS', 'size' => '2"', 'valve_type' => 'gate', 'valve_name' => 'Gate Valve' }
    ]
    rows = Bom.aggregate(recs)
    e90 = rows.find { |r| r.description == 'Elbow 90° LR' }
    assert_equal 2, e90.qty
    assert rows.any? { |r| r.description == 'Elbow 37.5° (bend) LR' }
    assert rows.any? { |r| r.description == 'Reducing Tee' && r.size == '2" x 1"' }
    assert_equal 2 + 2 + 2 + 3 + 2, Bom.joint_estimate(recs)
  end

  def test_csv_has_bom_and_escapes
    rows = Bom.aggregate([pipe(1000)])
    csv = Bom.to_csv(rows, title: 'Project "A", Line 1')
    assert csv.start_with?("﻿")
    assert_includes csv, '"Project ""A"", Line 1"'
    assert_includes csv, "\r\n"
  end

  def test_size_sort
    sizes = ['4"', '1/2"', '1-1/4"', '1"', '3/4"', '10"']
    assert_equal ['1/2"', '3/4"', '1"', '1-1/4"', '4"', '10"'], sizes.sort_by { |s| Bom.size_sort_key(s) }
    assert Bom.size_sort_key('20 mm') < Bom.size_sort_key('110 mm')
  end

  def test_settings_sanitize_fixes_inconsistent_size
    s = Settings.sanitize('catalog' => 'PPR_DIN8077', 'size' => '1"', 'rating' => 'SCH40', 'segments' => 5)
    assert_equal '32 mm', s['size'] # closest OD to 1" (33.4) in PP-R
    assert_equal 'PN20', s['rating']
    assert_equal 8, s['segments']
  end

  def test_settings_roundtrip
    s = Settings.load(Settings.dump('service' => 'FP', 'catalog' => 'CS_B36_10', 'size' => '6"', 'snap45' => 'false'))
    assert_equal 'FP', s['service']
    assert_equal '6"', s['size']
    assert_equal false, s['snap45']
    assert_equal Settings::DEFAULTS.keys.sort, s.keys.sort
  end

  def test_settings_bad_json
    assert_equal Settings.sanitize({}), Settings.load('{oops')
  end

  def test_all_service_defaults_resolve
    Services.all.each do |svc|
      sp = Catalog.spec(svc[:catalog], svc[:size], svc[:rating])
      assert_equal svc[:rating], sp.rating, "#{svc[:code]} default rating invalid"
      %w[distinct asme jis].each { |sch| assert_equal 3, Services.color(svc[:code], sch).size }
    end
  end
end

class TestBomSupports < Minitest::Test
  def test_supports_expand_into_rod_and_members
    recs = [
      { 'type' => 'support', 'support_type' => 'clevis', 'support_name' => 'Clevis hanger + threaded rod',
        'pipe_size' => '4"', 'service' => 'FP', 'rod_label' => '5/8" (M16)', 'rod_length_mm' => 800 },
      { 'type' => 'support', 'support_type' => 'clevis', 'support_name' => 'Clevis hanger + threaded rod',
        'pipe_size' => '4"', 'service' => 'FP', 'rod_label' => '5/8" (M16)', 'rod_length_mm' => 700 },
      { 'type' => 'support', 'support_type' => 'trapeze', 'support_name' => 'Trapeze', 'pipe_size' => '3 pipes',
        'service' => 'multi', 'member_name' => 'Strut channel 41×41', 'member_length_mm' => 900,
        'rod_label' => '1/2" (M12)', 'rod_length_mm' => 1400 }
    ]
    rows = Bom.aggregate(recs)
    assert_equal 2, rows.find { |r| r.category == 'support' && r.size == '4"' }.qty
    assert_in_delta 1.5, rows.find { |r| r.description == 'Threaded rod 5/8" (M16)' }.qty, 1e-9
    assert_in_delta 0.9, rows.find { |r| r.category == 'member' }.qty, 1e-9
  end
end
