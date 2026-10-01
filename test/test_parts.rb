# frozen_string_literal: true

require_relative 'test_helper'

class TestParts < Minitest::Test
  SAMPLES = [
    ['CS_B36_10', '4"', 'SCH40'], ['CS_B36_10', '1/2"', 'SCH80'], ['SS_B36_19', '2"', '10S'],
    ['GSP_BS1387', '1"', 'Medium'], ['PVC_TIS17', '2"', 'Class 13.5'], ['PPR_DIN8077', '25 mm', 'PN20'],
    ['HDPE_PE100', '110 mm', 'SDR11 PN16'], ['CU_B88_L', '3/4"', 'Type L'], ['CS_B36_10', '8"', 'SCH40']
  ].freeze

  def check(part, label)
    refute_empty part.solids, "#{label}: empty"
    part.solids.each_with_index do |(role, s), i|
      assert Mesh.closed?(s), "#{label}: solid #{i} (#{role}) not closed"
      assert Mesh.volume(s).positive?, "#{label}: solid #{i} (#{role}) inside-out"
    end
  end

  def each_opts
    SAMPLES.each do |cat, size, rating|
      spec = Catalog.spec(cat, size, rating)
      %i[detailed light].each do |lod|
        yield spec, Parts.opts(spec, lod: lod, steps: 16), "#{cat} #{size} #{lod}"
      end
    end
  end

  def test_pipes_and_elbows
    each_opts do |spec, o, label|
      check(Parts.pipe(1000, o), "#{label} pipe")
      [Math::PI / 2, Math::PI / 4, 0.05].each do |a|
        check(Parts.elbow(a, spec.elbow_radius_lr, o), "#{label} elbow #{a}")
      end
    end
  end

  def test_tees_laterals_crosses
    each_opts do |spec, o, label|
      c = spec.tee_c
      x = [1.0, 0.0, 0.0]
      nx = [-1.0, 0.0, 0.0]
      check(Parts.branch([[nx, c, o], [x, c, o], [[0.0, 1.0, 0.0], c, o]]), "#{label} tee")
      check(Parts.branch([[nx, c, o], [x, c, o], [Vec.unit([1, 1, 0]), c, o]]), "#{label} lateral")
      check(Parts.branch([[nx, c, o], [x, c, o], [[0.0, 1.0, 0.0], c, o], [[0.0, -1.0, 0.0], c, o]]), "#{label} cross")
    end
  end

  def test_flanges_and_all_valves
    each_opts do |spec, o, label|
      check(Parts.flange(o), "#{label} flange")
      metallic = spec.density > 5000
      FittingsData.valve_types.each do |t|
        check(Parts.valve(t, o, metallic: metallic), "#{label} #{t}")
      end
    end
  end

  def test_valves_are_visually_distinct
    spec = Catalog.spec('CS_B36_10', '4"')
    o = Parts.opts(spec)
    sigs = FittingsData.valve_types.map do |t|
      part = Parts.valve(t, o)
      pts = part.solids.flat_map { |_, s| s.polys.flatten(1) }
      zmax = pts.map { |p| p[2] }.max.round
      [part.poly_count, zmax, part.solids.map(&:first).uniq.sort]
    end
    assert_equal sigs.size, sigs.uniq.size, 'two valve types produce the same model'
  end

  def test_detailed_flange_has_bolt_holes_light_does_not
    spec = Catalog.spec('CS_B36_10', '4"')
    d = Parts.flange(Parts.opts(spec, lod: :detailed))
    l = Parts.flange(Parts.opts(spec, lod: :light))
    assert d.poly_count > 2 * l.poly_count
    fl = FittingsData.flange(114.3)
    assert_equal 8, fl.bolts
    assert_in_delta 190.5, fl.bolt_circle, 1e-9
  end

  def test_socket_insertion_depth
    o = Parts.opts(Catalog.spec('PVC_TIS17', '2"'))
    assert_in_delta 36.0, Parts.insertion(o), 1e-9 # 0.5·60 + 6
    assert_equal 0.0, Parts.insertion(Parts.opts(Catalog.spec('CS_B36_10', '2"')))
  end
end

class TestReducer < Minitest::Test
  def test_reducers_closed_and_b16_9_length
    [%w[CS_B36_10 4" 2"], %w[PVC_TIS17 2" 1"], ['PPR_DIN8077', '63 mm', '32 mm'], %w[GSP_BS1387 2" 1"]].each do |cat, big, small|
      a = Catalog.spec(cat, big)
      b = Catalog.spec(cat, small)
      len = FittingsData.reducer_length(a.od, b.od, a.style)
      [[a, b], [b, a]].each do |x, y|
        part = Parts.reducer(len, Parts.opts(x), Parts.opts(y))
        part.solids.each { |role, s| assert Mesh.closed?(s), "#{cat} #{role}" }
      end
    end
    assert_in_delta 102.0, FittingsData.reducer_length(114.3, 60.3), 1e-9 # 4"x2" H = 102 mm
  end
end
