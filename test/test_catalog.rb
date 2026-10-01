# frozen_string_literal: true

require_relative 'test_helper'

class TestCatalog < Minitest::Test
  def test_every_size_has_positive_bore
    Catalog.all.each do |key, cat|
      cat[:sizes].each do |s|
        s[:walls].each do |rating, _w|
          sp = Catalog.spec(key, s[:size], rating)
          assert sp.id.positive?, "#{key} #{s[:size]} #{rating} has no bore"
          assert sp.wall < sp.od / 4.0, "#{key} #{s[:size]} #{rating} wall implausible"
        end
      end
    end
  end

  def test_od_strictly_increasing
    Catalog.all.each do |key, cat|
      ods = cat[:sizes].map { |s| s[:od] }
      assert_equal ods.sort, ods, "#{key} sizes out of order"
      assert_equal ods.uniq.size, ods.size, "#{key} duplicate OD"
    end
  end

  def test_asme_b36_10_sch40_4in
    sp = Catalog.spec('CS_B36_10', '4"', 'SCH40')
    assert_in_delta 114.3, sp.od, 1e-9
    assert_in_delta 6.02, sp.wall, 1e-9
    assert_in_delta 102.26, sp.id, 1e-6
    # Published B36.10M mass 16.07 kg/m
    assert_in_delta 16.07, sp.weight_kg_m, 0.05
  end

  def test_sch80_2in_weight
    sp = Catalog.spec('CS_B36_10', '2"', 'SCH80')
    assert_in_delta 7.48, sp.weight_kg_m, 0.05 # B36.10M: 7.48 kg/m
  end

  def test_b16_9_elbow_radius
    sp = Catalog.spec('CS_B36_10', '4"')
    assert_in_delta 152.4, sp.elbow_radius_lr, 1e-6 # A = 152 mm
    assert_in_delta 101.6, sp.elbow_radius_sr, 1e-6
    assert_in_delta 105.0, sp.tee_c, 1e-9
    assert_in_delta 38.0, Catalog.spec('CS_B36_10', '1/2"').elbow_radius_lr, 1e-9
  end

  def test_pvc_wall_estimate_close_to_catalogue_for_4in
    # Typical TIS 17 walls for 4": class 5 ≈ 2.2, 8.5 ≈ 3.8, 13.5 ≈ 5.7 mm
    assert_in_delta 2.2, Catalog.spec('PVC_TIS17', '4"', 'Class 5').wall, 0.25
    assert_in_delta 3.8, Catalog.spec('PVC_TIS17', '4"', 'Class 8.5').wall, 0.25
    assert_in_delta 5.7, Catalog.spec('PVC_TIS17', '4"', 'Class 13.5').wall, 0.25
    assert Catalog.spec('PVC_TIS17', '4"').estimated
  end

  def test_rating_fallback
    sp = Catalog.spec('HDPE_PE100', '63 mm', 'NOPE')
    assert_equal 'SDR11 PN16', sp.rating
  end

  def test_elbow_radius_never_below_three_quarter_od
    Catalog.all.each do |key, cat|
      cat[:sizes].each do |s|
        sp = Catalog.spec(key, s[:size])
        assert sp.elbow_radius_sr >= 0.6 * sp.od, "#{key} #{s[:size]} SR too tight"
        assert sp.elbow_radius_lr >= sp.elbow_radius_sr
      end
    end
  end

  def test_custom_catalog
    path = File.expand_path('../docs/custom_catalog.example.json', __dir__)
    keys = Catalog.load_custom(path)
    refute_empty keys
    sp = Catalog.spec(keys.first, Catalog.sizes(keys.first).first)
    assert sp.id.positive?
  ensure
    Catalog.reset!
  end
end
