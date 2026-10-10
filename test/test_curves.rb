# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'su_stub'

module ArtK
  module PlantPipe
    PLUGIN_ROOT = File.expand_path('../src/artk_plant_pipe', __dir__) unless defined?(PLUGIN_ROOT)
    VERSION = 'test' unless defined?(VERSION)
  end
end
%w[model_helpers migrate builder ref_models ref_builder support_builder collector picker reports library commands
   run_editor].each do |f|
  require File.expand_path("../src/artk_plant_pipe/su/#{f}", __dir__)
end

# Pipe bent along a drawn arc / curve (1.13): one continuous pipe, no
# elbow at every facet.
class TestCurves < Minitest::Test
  H = ModelHelpers
  SPEC = { od: 60.3, elbow_radius_lr: 76.2, elbow_radius_sr: 50.8, tee_c: 64.0 }.freeze

  def setup
    @model = Sketchup::Model.new
    Sketchup.active_model = @model
    @settings = Settings.sanitize('service' => 'CW', 'catalog' => 'HDPE_PE100', 'size' => '63 mm', 'insulation_mm' => 0)
  end

  # Quarter arc of radius r (mm) from the origin heading +x, turning to +y.
  def arc_points(r = 20_000.0, n = 12, deg = 90.0)
    (0..n).map { |i| a = deg * Math::PI / 180 * i / n; [r * Math.sin(a), r - r * Math.cos(a), 0.0] }
  end

  def segs(pts)
    pts.each_cons(2).to_a
  end

  def run_pieces(run, type)
    run.entities.select { |e| H.instance?(e) && H.type_of(e) == type }
  end

  def arc_len(r, deg, n)
    n * 2 * r * Math.sin(deg * Math::PI / 180 / n / 2)
  end

  # ---- network ----

  def test_curve_points_become_one_bent_pipe
    pts = arc_points
    net = Network.new(segs(pts), SPEC, smooth: pts).solve
    curves = net.pieces.select { |p| p.type == :curve }
    assert_equal 1, curves.size
    assert_empty net.fittings
    assert_empty net.pipes
    d = curves.first.data
    assert_equal 13, d[:points].size
    assert_in_delta arc_len(20_000, 90, 12), d[:length], 1e-6
    assert_in_delta 20_000, d[:radius], 1.0
    assert_in_delta 82.5, d[:angle_deg], 0.1 # 11 inner vertices × 7.5°
  end

  def test_without_curve_points_every_facet_is_an_elbow
    net = Network.new(segs(arc_points), SPEC).solve
    assert_equal 11, net.pieces.count { |p| p.type == :elbow }
    assert_empty net.pieces.select { |p| p.type == :curve }
  end

  def test_curve_keeps_its_tangent_lines_and_real_corners
    pts = [[-3000.0, 0.0, 0.0]] + arc_points + [[20_000.0, 25_000.0, 0.0], [25_000.0, 25_000.0, 0.0]]
    net = Network.new(segs(pts), SPEC, smooth: arc_points).solve
    curve = net.pieces.find { |p| p.type == :curve }.data
    assert_equal [-3000.0, 0.0, 0.0], curve[:points].first # tangent line joins the bent pipe
    elbows = net.pieces.select { |p| p.type == :elbow }
    assert_equal 1, elbows.size, 'the 90° corner after the curve is still an elbow'
    assert_in_delta 90.0, elbows.first.data[:angle_deg], 1e-6
    # the bent pipe stops where that elbow starts
    assert_in_delta 25_000.0 - 76.2, curve[:points].last[1], 1e-6
  end

  def test_sharp_corner_on_a_curve_is_never_bent
    pts = [[0.0, 0.0, 0.0], [1000.0, 0.0, 0.0], [1000.0, 1000.0, 0.0]]
    net = Network.new(segs(pts), SPEC, smooth: pts).solve
    assert_equal 1, net.pieces.count { |p| p.type == :elbow }
  end

  def test_exploded_arc_is_found_but_a_pair_of_small_elbows_is_not
    pts = arc_points
    found = Network.curve_points(segs(pts))
    assert_equal 11, found.size
    offset = [[0.0, 0.0, 0.0], [2000.0, 0.0, 0.0], [3000.0, 198.9, 0.0], [5000.0, 198.9, 0.0]] # two 11.25° bends
    assert_empty Network.curve_points(segs(offset))
    rolled = [[0.0, 0.0, 0.0], [1000.0, 0.0, 0.0], [1990.0, 140.0, 0.0], [2900.0, 560.0, 0.0], [3600.0, 1260.0, 0.0],
              [9000.0, 1260.0, 0.0]] # uneven chords
    refute_equal 4, Network.curve_points(segs(rolled)).size
  end

  # ---- mesh ----

  def test_sweep_is_a_closed_tube_of_the_right_volume
    pts = [[-2000.0, 0.0, 0.0]] + arc_points(5000.0, 12)
    solid, = Mesh.sweep(pts, 30.0, 27.0, steps: 16)
    assert Mesh.closed?(solid)
    len = pts.each_cons(2).sum { |p, q| Vec.dist(p, q) }
    poly_area = 8 * Math.sin(Math::PI / 8) * (30.0**2 - 27.0**2)
    assert_in_delta poly_area * len, Mesh.volume(solid), poly_area * len * 1e-6
    solid.polys.each do |q|
      n = Vec.unit(Mesh.normal(q))
      q.each { |p| assert_in_delta 0.0, Vec.dot(Vec.sub(p, q[0]), n), 1e-6 }
    end
  end

  # ---- supports ----

  def test_supports_follow_the_curve_at_the_span
    pts = arc_points
    res = Supports.place([{ from: pts.first, to: pts.last, path: pts }], 1500.0)
    at = res[:supports].map { |s| s[:at] }
    len = arc_len(20_000, 90, 12)
    assert_equal ((len - 2 * 375.0) / 1500.0).ceil + 1, at.size
    at.each do |p|
      assert_in_delta 20_000.0, Vec.dist(p, [0.0, 20_000.0, 0.0]), 20_000 * (1 - Math.cos(Math::PI / 48)) + 1e-6
    end
    at.each_cons(2) { |p, q| assert_operator Vec.dist(p, q), :<=, 1500.0 + 1e-6 }
  end

  # ---- in SketchUp ----

  def draw_arc(pts_mm)
    edges = pts_mm.each_cons(2).map do |a, b|
      @model.entities.add_line(H.to_pt(a), H.to_pt(b))
    end
    Sketchup::Curve.new(edges)
    edges
  end

  def convert(edges)
    @model.selection.push(*edges)
    H.save_settings(@settings)
    Commands.convert_selection
    Collector.all_runs(@model).map(&:first)
  end

  def test_convert_arc_draws_one_bent_pipe
    edges = draw_arc(arc_points)
    edges << @model.entities.add_line(H.to_pt([20_000, 20_000, 0]), H.to_pt([20_000, 26_000, 0]))
    runs = convert(edges)
    assert_equal 1, runs.size
    run = runs.first
    refute_empty H.get_json(run, 'smooth', [])
    assert_empty run_pieces(run, 'elbow')
    pipes = run_pieces(run, 'pipe')
    assert_equal 1, pipes.size
    g = H.get_json(pipes.first, 'geom')
    assert_equal 14, g['path'].size
    total = arc_len(20_000, 90, 12) + 6000
    assert_in_delta total, pipes.first.get_attribute(H::DICT, 'length_mm'), 0.5
    assert_in_delta 20_000, pipes.first.get_attribute(H::DICT, 'bend_radius_mm'), 2
    assert_equal 2, pipes.first.entities.count { |e| H.instance?(e) && H.type_of(e) == 'end_center' }
    assert_empty H.get_json(run, 'warnings', [])

    # BOM, clash, picking, supports and the stretch check all follow the curve
    bom = Bom.aggregate(Collector.records(@model))
    pipe_row = bom.find { |r| r.category == 'pipe' }
    assert_in_delta total / 1000.0, pipe_row.qty, 0.01
    assert_equal 13, Collector.clash_items(@model).size
    mid = arc_points[6]
    hit = Picker.nearest_pipe(@model, Vec.add(mid, [0, 0, 20]))
    assert hit
    assert_in_delta 0.0, Vec.dist(hit[:proj], [mid[0], mid[1], 0.0]), 1.0
    assert_nil Picker.run_node(@model, mid), 'curve points are not corners'
    assert_empty RunEditor.inspect(run)[:issues]
    rebuilt = Builder.rebuild(@model, [run], @settings)
    assert_empty rebuilt
    assert_equal 1, run_pieces(run, 'pipe').size, 'a rebuild keeps the curve'
  end

  def test_auto_supports_on_a_curve
    runs = convert(draw_arc(arc_points))
    @model.selection.clear
    @model.selection.push(runs.first)
    H.save_settings(@settings.merge('support_type' => 'clamp'))
    Commands.auto_supports
    sups = H.get_json(runs.first, 'supports', [])
    span = Supports.max_span_m(Catalog.spec('HDPE_PE100', '63 mm')) * 1000
    assert_operator sups.size, :>=, (arc_len(20_000, 90, 12) / span).floor
    sups.each do |s|
      assert_in_delta 20_000.0, Vec.dist(s['at'], [0.0, 20_000.0, 0.0]), 43.0, 'support sits on the drawn curve (chord sag 42.8)'
    end
  end

  def test_tight_curve_warns_with_the_material_minimum
    pvc = @settings.merge('catalog' => 'PVC_TIS17', 'size' => '2"')
    run, w = Builder.create_run(@model, segs(arc_points(3000.0)), pvc, smooth: arc_points(3000.0))
    assert_equal 1, run_pieces(run, 'pipe').size
    assert(w.any? { |x| x.include?('300×OD') }, w.inspect)
    _run, w = Builder.create_run(@model, segs(arc_points(3000.0)), @settings, smooth: arc_points(3000.0))
    assert_empty w, 'HDPE 63 bends to 25×OD = 1.6 m'
  end

  def test_closed_ring_and_sloped_helix
    ring = (0..24).map { |i| a = 2 * Math::PI * i / 24; [3000 * Math.cos(a), 3000 * Math.sin(a), 0.0] }
    ring[-1] = ring[0]
    run, w = Builder.create_run(@model, segs(ring), @settings, smooth: ring)
    assert_empty w
    pipe = run_pieces(run, 'pipe')
    assert_equal 1, pipe.size
    assert_in_delta 24 * 2 * 3000 * Math.sin(Math::PI / 24), pipe.first.get_attribute(H::DICT, 'length_mm'), 0.5
    helix = (0..36).map { |i| a = 3 * Math::PI * i / 36; [3000 * Math.cos(a), 3000 * Math.sin(a), 50.0 * i] }
    run, w = Builder.create_run(@model, segs(helix), @settings, smooth: helix)
    assert_empty w
    assert_equal 1, run_pieces(run, 'pipe').size
  end

  def test_runs_without_curve_points_draw_as_before
    run, = Builder.create_run(@model, segs(arc_points), @settings)
    assert_nil run.get_attribute(H::DICT, 'smooth')
    assert_equal 11, run_pieces(run, 'elbow').size
  end
end
