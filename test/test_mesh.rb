# frozen_string_literal: true

require_relative 'test_helper'

class TestMesh < Minitest::Test
  PI = Math::PI

  def assert_solid(s, vol = nil, rel = 0.03, msg = nil)
    assert Mesh.closed?(s), "#{msg} not closed/consistently oriented"
    v = Mesh.volume(s)
    assert v.positive?, "#{msg} inside-out (volume #{v})"
    assert_in_delta vol, v, vol * rel, "#{msg} volume" if vol
  end

  def test_hollow_pipe
    s = Mesh.cylinder([0, 0, 0], [1000, 0, 0], 57.15, ri: 51.13, steps: 32)
    # polygonal section: area factor (n/2π)·sin(2π/n) ≈ 0.9936 for n=32
    assert_solid(s, PI * (57.15**2 - 51.13**2) * 1000 * 0.9936, 0.01, 'pipe')
  end

  def test_solid_rod_and_skew_axis
    assert_solid(Mesh.cylinder([10, 20, 30], [300, -200, 900], 8, steps: 12), nil, 0, 'rod')
  end

  def test_frustum_and_sphere
    assert_solid(Mesh.frustum([0, 0, 0], [0, 0, 100], 50, 20, steps: 32), PI * 100 / 3 * (50**2 + 50 * 20 + 20**2), 0.02, 'cone')
    assert_solid(Mesh.sphere([5, 5, 5], 40, steps: 32), 4.0 / 3 * PI * 40**3, 0.04, 'sphere')
  end

  def test_bend_hollow_90
    s = Mesh.bend([0, 152.4, 0], [0, -1, 0], [0, 0, 1], 152.4, PI / 2, 57.15, 51.13, steps: 24, arc_steps: 12)
    # Pappus: area × path length
    assert_solid(s, PI * (57.15**2 - 51.13**2) * 152.4 * PI / 2, 0.03, 'bend')
  end

  def test_small_angle_bend_is_still_valid
    s = Mesh.bend([0, 100, 0], [0, -1, 0], [0, 0, 1], 100, 0.02, 30, 25, steps: 16, arc_steps: 2)
    assert_solid(s, nil, 0, 'tiny bend')
  end

  def test_torus
    assert_solid(Mesh.torus([0, 0, 0], [0, 0, 1], 100, 8, steps: 32, sec_steps: 12), 2 * PI**2 * 100 * 64, 0.07, 'torus')
  end

  def test_holed_flange
    ro = 114.3
    ri = 60.3
    s = Mesh.holed_disc([0, 0, 0], [1, 0, 0], ro, ri, 22.3, 95.25, 8, 9.55, steps: 32, hole_steps: 12)
    area = PI * (ro**2 - ri**2) - 8 * PI * 9.55**2
    assert_solid(s, area * 22.3, 0.03, 'flange')
  end

  def test_holed_flange_four_holes
    assert_solid(Mesh.holed_disc([0, 0, 0], [0, 0, 1], 75, 30.5, 17.5, 60.35, 4, 9.5), nil, 0, 'flange 4 holes')
  end

  def test_box_bar_ngon
    f = Mesh.frame([0, 0, 0], [1, 1, 0])
    assert_solid(Mesh.box(f, [0, 0, 0], [100, 40, 20]), 80_000, 1e-9, 'box')
    assert_solid(Mesh.bar([0, 0, 0], [0, 300, 400], 41, 41), 500 * 41 * 41, 1e-9, 'bar')
    assert_solid(Mesh.ngon_prism([0, 0, 0], [0, 0, 10], 10, 6), 6 * (Math.sqrt(3) / 4 * 100) * 10, 1e-6, 'hex')
  end
end

class TestHoledDiscRobust < Minitest::Test
  # Every flange-like combination must be a closed solid with the right volume.
  def test_holed_disc_grid
    count = 0
    [3, 4, 5, 6, 8, 12, 16, 20].each do |n|
      [6, 8, 10, 12, 16].each do |hs|
        [16, 24, 32, 48].each do |st|
          [[40.0, 8.0, 22.0, 5.0], [114.3, 51.1, 95.25, 9.55], [28.9, 6.4, 17.66, 6.42],
           [407.5, 161.5, 374.65, 15.9], [60.0, 0.0, 40.0, 6.0]].each do |ro, ri, bc, hr|
            next if hr >= bc * Math.sin(Math::PI / n) * 0.95

            s = Mesh.holed_disc([0, 0, 0], [0, 0, 1], ro, ri, 3.0, bc, n, hr, steps: st, hole_steps: hs)
            assert Mesh.closed?(s), "n=#{n} hs=#{hs} st=#{st} #{[ro, ri, bc, hr]}"
            ideal = (Math::PI * (ro**2 - ri**2) - n * Math::PI * hr**2) * 3.0
            assert_in_delta ideal, Mesh.volume(s), ideal * 0.08, "volume n=#{n} hs=#{hs}"
            count += 1
          end
        end
      end
    end
    assert count > 500
  end
end
