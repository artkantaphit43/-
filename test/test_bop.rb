# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'su_stub'

module ArtK
  module PlantPipe
    PLUGIN_ROOT = File.expand_path('../src/artk_plant_pipe', __dir__) unless defined?(PLUGIN_ROOT)
    VERSION = 'test' unless defined?(VERSION)
  end
end
%w[model_helpers bop_pick migrate builder ref_models ref_builder support_builder collector run_editor picker reports
   library commands pipe_tool stretch_tool support_tool color_pick_tool].each do |f|
  require File.expand_path("../src/artk_plant_pipe/su/#{f}", __dir__)
end

# Elevation reference BOP (ท้องท่อ) – 1.21.2: what you pick on the model is
# the pipe's underside (its insulation's), for every pipe kind, in every
# tool that places pipe points; nothing else is lifted.
class TestBop < Minitest::Test
  H = ModelHelpers
  IP = Sketchup::InputPoint
  TOP = 3000.0 # beam top, world

  def setup
    @model = Sketchup::Model.new
    Sketchup.active_model = @model
    @view = @model.active_view
    clear_pick
    beam
  end

  def teardown
    clear_pick
  end

  def clear_pick
    IP.next_vertex = nil
    IP.next_edge = nil
    IP.next_face = nil
    IP.next_path = nil
    IP.next_dof = nil
    @view&.pick_paths = nil
  end

  def pt(*mm)
    H.to_pt(mm)
  end

  # A rack beam: a group lifted to z 2900, 100 deep (top at 3000), its
  # flange 100 wide along y = -50..50, 6 m along x. Its faces / edges are
  # in its own coordinates, as SketchUp keeps them.
  def beam
    @beam = Sketchup::Group.new
    @beam.transformation = Geom::Transformation.new([0, 0, H.mm(2900.0)])
    @top = Sketchup::Face.with([pt(0, -50, 100), pt(6000, -50, 100), pt(6000, 50, 100), pt(0, 50, 100)])
    @side = Sketchup::Face.with([pt(0, 50, 0), pt(6000, 50, 0), pt(6000, 50, 100), pt(0, 50, 100)])
    @edge = Sketchup::Edge.new(pt(0, 50, 100), pt(6000, 50, 100))
    @post = Sketchup::Edge.new(pt(0, 50, 0), pt(0, 50, 100)) # vertical
    @corner = Sketchup::Vertex.new(pt(0, 50, 100))
    # a slab top level with the beam top, all round
    @slab = Sketchup::Face.with([pt(-9000, -9000, 100), pt(9000, -9000, 100), pt(9000, 9000, 100), pt(-9000, 9000, 100)])
  end

  def pick(tool, mm, vertex: nil, edge: nil, face: nil, path: nil, dof: nil, under: nil)
    clear_pick
    IP.next_position = H.to_pt(mm)
    IP.next_vertex = vertex
    IP.next_edge = edge
    IP.next_face = face
    IP.next_path = path
    IP.next_dof = dof || (vertex ? 0 : edge ? 1 : face ? 2 : 3)
    @view.pick_paths = under
    tool.onMouseMove(0, 0, 0, @view)
    tool.onLButtonDown(0, 0, 0, @view)
  end

  def tool(settings)
    H.save_settings(Settings.sanitize({ 'service' => 'CW', 'catalog' => 'GSP_BS1387', 'size' => '2"',
                                        'elevation_ref' => 'bop', 'snap45' => true }.merge(settings)))
    t = PipeTool.new
    t.activate
    t
  end

  def lift(t = nil)
    s = H.load_settings
    t ||= s
    Settings.spec(t).od / 2.0 + t['insulation_mm'].to_f
  end

  def runs
    Collector.all_runs(@model).map(&:first)
  end

  def cl(run)
    H.get_json(run, 'cl').flatten(1).uniq
  end

  def zs(run)
    cl(run).map { |p| p[2].round(3) }.uniq
  end

  # --- what is lifted and what is not ---

  # SketchUp still reports the beam's face under the cursor while the point
  # is inferred along the red axis from the last (lifted) point: that point
  # is in the air, not on the beam – before, it went up another OD/2.
  def test_point_inferred_above_a_beam_is_not_lifted_twice
    t = tool('insulation_mm' => 38.1)
    h = lift
    pick(t, [500, 0, TOP], face: @top, path: [@beam, @top])
    pick(t, [5500, 0, TOP + h], face: @top, path: [@beam, @top], dof: 1)
    t.onReturn(@view)
    assert_equal [(TOP + h).round(3)], zs(runs.first)
  end

  def test_corner_edge_and_face_of_a_beam_are_the_underside
    t = tool('insulation_mm' => 25.4)
    h = lift
    pick(t, [0, 50, TOP], vertex: @corner, path: [@beam, @edge])
    pick(t, [4000, 50, TOP], edge: @edge, path: [@beam, @edge])
    t.onReturn(@view)
    assert_equal [(TOP + h).round(3)], zs(runs.first)

    t = tool('insulation_mm' => 0.0)
    pick(t, [1000, -20, TOP], face: @top, path: [@beam, @top])
    pick(t, [1000, -2000, TOP + lift], dof: 1) # on the green axis from there
    t.onReturn(@view)
    assert_equal [(TOP + lift).round(3)], zs(runs.last)
  end

  # Guides: a guide line / guide point the user put at the underside level.
  def test_guide_line_and_guide_point_are_the_underside
    g = Sketchup::ConstructionLine.new
    g.position = pt(0, 0, 2500)
    g.direction = Geom::Vector3d.new(1, 0, 0)
    t = tool({})
    pick(t, [700, 0, 2500], path: [g], dof: 1)
    c = Sketchup::ConstructionPoint.new
    c.position = pt(4000, 0, 2500)
    pick(t, [4000, 0, 2500], path: [c], dof: 0)
    t.onReturn(@view)
    assert_equal [(2500 + lift).round(3)], zs(runs.first)
  end

  def test_the_ground_is_the_underside
    t = tool({})
    pick(t, [0, 0, 0])
    pick(t, [3000, 0, 0]) # the ground again
    t.onReturn(@view)
    assert_equal [lift.round(3)], zs(runs.first)
  end

  # Walls and columns give no level: the point is the centre, as picked.
  def test_vertical_faces_and_edges_are_not_lifted
    t = tool({})
    pick(t, [2000, 50, 2950], face: @side, path: [@beam, @side])
    pick(t, [2000, 50, 2950 - 1500], dof: 1)
    t.onReturn(@view)
    assert_equal [2950.0, 1450.0], zs(runs.first)

    t = tool({})
    pick(t, [0, 50, 2960], edge: @post, path: [@beam, @post])
    pick(t, [0, 3050, 2960], dof: 1)
    t.onReturn(@view)
    assert_equal [2960.0], zs(runs.last)
  end

  # SketchUp gives only the point; what is under the cursor (PickHelper)
  # says it is on the beam.
  def test_pick_on_a_beam_found_under_the_cursor
    t = tool({})
    pick(t, [1200, 10, TOP], under: [[@beam, @top]], dof: 2)
    pick(t, [4200, 10, TOP], under: [[@beam, @top]], dof: 2)
    t.onReturn(@view)
    assert_equal [(TOP + lift).round(3)], zs(runs.first)
  end

  def test_picks_inside_an_open_group_report_world_positions
    @model.active_path = [@beam]
    t = tool({})
    # open for editing: SketchUp reports the beam's own geometry in world
    # coordinates (its group transformation already applied)
    top = Sketchup::Face.with([pt(0, -50, TOP), pt(6000, -50, TOP), pt(6000, 50, TOP), pt(0, 50, TOP)])
    pick(t, [300, 0, TOP], face: top, path: [@beam, top])
    pick(t, [2300, 0, TOP + lift], dof: 1)
    t.onReturn(@view)
    pts = cl(runs.first).map { |p| H.transform_mm(H.edit_transform(@model), p) }
    assert_equal [(TOP + lift).round(3)], pts.map { |p| p[2].round(3) }.uniq
  ensure
    @model.active_path = nil
  end

  # Every pipe kind the plugin draws, bare and insulated.
  def test_every_pipe_kind_sits_on_the_beam
    Catalog::SHOWN.each do |cat|
      sizes = Catalog.sizes(cat)
      size = sizes.min_by { |z| (Catalog.spec(cat, z).od - 60.0).abs }
      [0.0, 38.1].each do |ins|
        @model = Sketchup::Model.new
        Sketchup.active_model = @model
        @view = @model.active_view
        t = tool('catalog' => cat, 'size' => size, 'rating' => nil, 'insulation_mm' => ins)
        s = H.load_settings
        want = TOP + Settings.spec(s).od / 2.0 + ins
        pick(t, [0, 50, TOP], vertex: @corner, path: [@beam, @edge])
        pick(t, [5000, 0, TOP], face: @top, path: [@beam, @top])
        t.onReturn(@view)
        assert_equal [want.round(3)], zs(runs.first), "#{cat} #{size} ins #{ins}"
      end
    end
  end

  def test_draft_lines_sit_on_the_beam_too
    t = tool('draft' => true, 'insulation_mm' => 38.1)
    h = lift
    pick(t, [0, 50, TOP], vertex: @corner, path: [@beam, @edge])
    pick(t, [4000, 50, TOP], edge: @edge, path: [@beam, @edge])
    t.onReturn(@view)
    assert_equal [(TOP + h).round(3)], zs(runs.first)
  end

  # A pick on the beam next to a pipe already lying there starts a new
  # pipe there – not a branch off its neighbour.
  def test_pick_beside_a_pipe_on_the_rack_is_not_a_branch
    t = tool('size' => '1"')
    pick(t, [0, 0, TOP], face: @top, path: [@beam, @top])
    pick(t, [5000, 0, TOP], face: @top, path: [@beam, @top])
    t.onReturn(@view)
    t = tool('size' => '1"')
    pick(t, [1000, 40, TOP], face: @top, path: [@beam, @top])
    pick(t, [1000, 2000, TOP + lift], dof: 1)
    t.onReturn(@view)
    assert_equal 2, runs.size
    assert_equal [1000.0, 40.0, (TOP + lift).round(3)], cl(runs.last).first.map { |c| c.round(3) }
    assert_empty H.get_json(runs.last, 'tees', [])
  end

  # Our own pipes are joined at their centre (a tee), never lifted.
  def test_pick_on_our_pipe_branches_at_its_centre
    run, = Builder.create_run(@model, [[[0.0, 0, 1000], [6000.0, 0, 1000]]], Settings.sanitize('size' => '4"'))
    piece = run.entities.find { |e| H.type_of(e) == 'pipe' }
    t = tool('size' => '2"')
    r = Settings.spec(Builder.run_settings(run)).od / 2.0
    pick(t, [3000, 0, 1000 + r], face: Sketchup::Face.new, path: [run, piece], dof: 2)
    pick(t, [3000, 2000, 1000], dof: 1)
    t.onReturn(@view)
    branch = runs.find { |x| x != run }
    assert_equal [1000.0], zs(branch)
    assert_equal 1, H.get_json(branch, 'tees', []).size
  end

  def test_centreline_reference_lifts_nothing
    t = tool('elevation_ref' => 'cl', 'insulation_mm' => 38.1)
    pick(t, [0, 50, TOP], vertex: @corner, path: [@beam, @edge])
    pick(t, [4000, 50, TOP], edge: @edge, path: [@beam, @edge])
    t.onReturn(@view)
    assert_equal [TOP], zs(runs.first)
  end

  # --- the other tools ---

  # Lines drawn on the beam tops, converted: they are the underside.
  def test_convert_edges_lifts_the_lines_to_the_pipe_centre
    s = Settings.sanitize('service' => 'CW', 'catalog' => 'HDPE_PE100', 'size' => '63 mm',
                          'elevation_ref' => 'bop', 'insulation_mm' => 25.4)
    edges = [[[0, 0, TOP], [4000, 0, TOP]], [[4000, 0, TOP], [4000, 0, 0]]].map do |a, b|
      @model.entities.add_line(H.to_pt(a), H.to_pt(b))
    end
    @model.selection.push(*edges)
    H.save_settings(s)
    UI.answer = IDNO
    Commands.convert_selection
    h = Settings.spec(s).od / 2.0 + 25.4
    assert_equal [(TOP + h).round(3), h.round(3)], zs(runs.first)
  ensure
    UI.answer = nil
  end

  def test_convert_edges_in_centreline_mode_keeps_the_lines
    s = Settings.sanitize('service' => 'CW', 'catalog' => 'PVC_TIS17', 'size' => '2"', 'elevation_ref' => 'cl')
    e = @model.entities.add_line(pt(0, 0, TOP), pt(4000, 0, TOP))
    @model.selection.push(e)
    H.save_settings(s)
    UI.answer = IDNO
    Commands.convert_selection
    assert_equal [TOP], zs(runs.first)
  ensure
    UI.answer = nil
  end

  # A corner moved onto a beam with the Stretch tool rests on it.
  def test_stretch_tool_puts_a_moved_corner_on_the_beam
    s = Settings.sanitize('service' => 'CW', 'catalog' => 'PVCS40_ASTM', 'size' => '3"', 'insulation_mm' => 25.4)
    run, = Builder.create_run(@model, [[[0.0, 0, 1000], [3000.0, 0, 1000]], [[3000.0, 0, 1000], [3000.0, 2000, 1000]]], s)
    H.save_settings(s.merge('elevation_ref' => 'bop'))
    t = StretchTool.new
    t.activate
    pick(t, [3000, 0, 1000]) # grab the corner
    pick(t, [3000, 0, TOP], face: @top, path: [@beam, @top])
    h = Settings.spec(s).od / 2.0 + 25.4
    assert_equal [3000.0, 0.0, (TOP + h).round(3)], H.get_json(run, 'cl')[0][1].map { |c| c.round(3) }
  end

  # A pipe drawn on the rack keeps its underside on the beam when its size
  # or insulation changes (Rebuild with new settings).
  def test_resize_keeps_the_underside_of_a_bop_pipe
    t = tool('size' => '2"', 'insulation_mm' => 0.0)
    pick(t, [0, 0, TOP], face: @top, path: [@beam, @top])
    pick(t, [5000, 0, TOP], face: @top, path: [@beam, @top])
    t.onReturn(@view)
    run = runs.first
    s = H.load_settings.merge('size' => '4"', 'insulation_mm' => 38.1)
    Builder.rebuild(@model, [run], s)
    want = TOP + Settings.spec(s).od / 2.0 + 38.1
    assert_equal [want.round(3)], zs(run)
  end

  def test_resize_of_a_branched_bop_pipe_keeps_its_centre_and_says_so
    t = tool('size' => '2"')
    pick(t, [0, 0, TOP], face: @top, path: [@beam, @top])
    pick(t, [5000, 0, TOP], face: @top, path: [@beam, @top])
    t.onReturn(@view)
    main = runs.first
    z = zs(main)
    piece = main.entities.find { |e| H.type_of(e) == 'pipe' }
    t = tool('size' => '1"')
    pick(t, [2500, 0, z.first], face: Sketchup::Face.new, path: [main, piece], dof: 2)
    pick(t, [2500, 2000, z.first], dof: 1)
    t.onReturn(@view)
    warnings = Builder.rebuild(@model, [main], H.load_settings.merge('size' => '4"'))
    assert_equal z, zs(main)
    assert(warnings.any? { |w| w.include?('ท้องท่อ') }, warnings.inspect)
  end

  # --- a pipe of another size off a pipe on the beam (1.21.2 screenshot:
  # the new pipe stepped a few cm at the joint – two elbows / a slope) ---

  def main_on_beam(size)
    t = tool('catalog' => 'PVC_TIS17', 'size' => size)
    pick(t, [0, 0, TOP], face: @top, path: [@beam, @top])
    pick(t, [5000, 0, TOP], face: @top, path: [@beam, @top])
    t.onReturn(@view)
    m = runs.first
    [m, m.entities.find { |e| H.type_of(e) == 'pipe' }, cl(m).first[2]]
  end

  def bends(run)
    run.entities.count { |e| H.type_of(e) == 'elbow' }
  end

  def lift_of(size)
    Settings.spec(Settings.sanitize('catalog' => 'PVC_TIS17', 'size' => size)).od / 2.0
  end

  def beam_edge_at(y)
    Sketchup::Edge.new(pt(-9000, y, 100), pt(9000, y, 100))
  end

  # continuing the 2" line at 3" along the beam: straight on, the 3" pipe
  # on the beam too – an eccentric expander, flat on the bottom
  def test_continuing_at_another_size_stays_on_the_beam_with_an_eccentric_reducer
    { face: ->(x) { { face: @top, path: [@beam, @top] } },
      edge: ->(_x) { e = beam_edge_at(0); { edge: e, path: [@beam, e] } } }.each do |how, opts|
      setup
      m, piece, z = main_on_beam('2"')
      t = tool('catalog' => 'PVC_TIS17', 'size' => '3"')
      pick(t, [5000, 0, z], face: Sketchup::Face.new, path: [m, piece], dof: 2) # the 2" open end
      pick(t, [9000, 0, TOP], **(how == :face ? { face: @slab, path: [@beam, @slab] } : opts.call(9000)))
      t.onReturn(@view)
      assert_equal 2, runs.size, how
      n = runs.find { |r| r != m }
      assert_equal [(TOP + lift_of('3"')).round(3)], zs(n), how
      assert_equal [z.round(3)], zs(m), how
      assert_equal 0, bends(m) + bends(n), "#{how}: no elbows at the joint"
      j = H.get_json(n, 'joins').first
      assert_in_delta(lift_of('2"') - lift_of('3"'), j['main_off'][2], 1e-6)
      red = n.entities.find { |e| H.type_of(e) == 'reducer' }
      assert_equal 'Eccentric Expander', red.get_attribute(H::DICT, 'kind')
    end
  end

  # the same, drawn the other way: from the beam to the 2" end
  def test_drawing_to_the_end_of_another_size_makes_the_same_eccentric_joint
    m, piece, z = main_on_beam('2"')
    t = tool('catalog' => 'PVC_TIS17', 'size' => '3"')
    pick(t, [9000, 0, TOP], face: @slab, path: [@beam, @slab])
    pick(t, [5000, 0, z], face: Sketchup::Face.new, path: [m, piece], dof: 2) # onto the 2" end
    n = runs.find { |r| r != m }
    assert n, 'a new run'
    assert_equal [(TOP + lift_of('3"')).round(3)], zs(n)
    assert_equal 0, bends(m) + bends(n)
    assert H.get_json(n, 'joins').first['main_off']
  end

  # branching a 3" (or 1") pipe off the 2" main along the beam: level with
  # the main (a reducing tee), no step
  def test_branch_of_another_size_runs_level_with_its_main
    %w[3" 1"].each do |size|
      { face: { face: @top, path: [@beam, @top] }, edge: :edge }.each do |how, opts|
        setup
        m, piece, z = main_on_beam('2"')
        t = tool('catalog' => 'PVC_TIS17', 'size' => size)
        pick(t, [2500, 0, z + 30], face: Sketchup::Face.new, path: [m, piece], dof: 2)
        o = opts == :edge ? (e = Sketchup::Edge.new(pt(2500, -50, 100), pt(2500, 50, 100)); { edge: e, path: [@beam, e] }) : opts
        pick(t, [2500, 45, TOP], **o)
        pick(t, [2500, 3000, z], dof: 1) # on along the green axis
        t.onReturn(@view)
        b = runs.find { |r| r != m }
        assert_equal [z.round(3)], zs(b), "#{size} #{how}"
        assert_equal 0, bends(b), "#{size} #{how}: no step elbows"
      end
    end
  end

  # a 3" line drawn on the beam ending on the side of the 2" main: it meets
  # the main level, not with a slope on its last metre
  def test_line_ending_on_a_main_of_another_size_meets_it_level
    m, piece, z = main_on_beam('2"')
    t = tool('catalog' => 'PVC_TIS17', 'size' => '3"')
    pick(t, [2500, 3000, TOP], face: @slab, path: [@beam, @slab])
    pick(t, [2500, 0, z + 30], face: Sketchup::Face.new, path: [m, piece], dof: 2) # on the main
    b = runs.find { |r| r != m }
    assert b, 'a branch'
    assert_equal [z.round(3)], zs(b)
    assert_equal 1, H.get_json(b, 'tees').size
  end

  # going straight up from the 2" end at 3": no eccentric step there
  def test_riser_after_a_size_change_is_concentric
    m, piece, z = main_on_beam('2"')
    t = tool('catalog' => 'PVC_TIS17', 'size' => '3"')
    pick(t, [5000, 0, z], face: Sketchup::Face.new, path: [m, piece], dof: 2)
    t.onKeyDown(VK_UP, 0, 0, @view)
    pick(t, [5000, 0, TOP + 1500])
    t.onReturn(@view)
    n = runs.find { |r| r != m }
    a, b = H.get_json(n, 'cl').first
    assert_equal [5000.0, 0.0], a[0, 2].map { |c| c.round(3) }
    assert_in_delta 0.0, Math.hypot(b[0] - a[0], b[1] - a[1]), 1e-6
    refute H.get_json(n, 'joins').first['main_off']
  end
end
