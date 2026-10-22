# frozen_string_literal: true

require_relative 'steel_helper'
SteelSU.load!

# Steel Supports TH in (stubbed) SketchUp, with Plant Piping's pipes:
# placing each detail from a clicked pipe, the attributes it keeps, the
# link with Plant Piping (Auto Supports, its hangers, redrawn pipes),
# refits, the tool, the BOM and the dialog.
class TestSteelSU < Minitest::Test
  PH = ArtK::PlantPipe::ModelHelpers
  SH = ArtK::SteelSupport::H
  Z = 2400.0
  WALL = -450.0

  def setup
    @model = Sketchup::Model.new
    Sketchup.active_model = @model
    Sketchup::InputPoint.next_vertex = nil
    Sketchup::InputPoint.next_dof = nil
    Sketchup.write_default(SH::PREF, 'settings_b64', nil)
    SH.forget_settings
    PH.save_settings(ArtK::PlantPipe::Settings.sanitize('service' => 'CW', 'catalog' => 'CS_B36_10', 'size' => '2"',
                                                       'lod' => 'light'))
    SS::Builder.forget
    SS::Link.register
  end

  def pipe_run(y, z, size, svc, ins = 0, x0: 0, x1: 6000)
    st = ArtK::PlantPipe::Settings.sanitize('service' => svc, 'catalog' => 'CS_B36_10', 'size' => size,
                                            'lod' => 'light', 'insulation_mm' => ins)
    ArtK::PlantPipe::Builder.create_run(@model, [[[x0, y, z], [x1, y, z]]], st)[0]
  end

  def wall!
    @model.ray_hits = SteelSU.rays(boxes: [[[-1000.0, WALL - 300, 0.0], [9000.0, WALL, 4000.0]]])
  end

  # The drawing: cold water, chilled water + insulation, air; steam above.
  def drawing!
    wall!
    @cw = pipe_run(-250, Z, '2"', 'CW')
    @chw = pipe_run(-30, Z, '3"', 'CHWS', 50)
    @ca = pipe_run(170, Z, '1"', 'CA')
    @stm = pipe_run(-60, Z + 420, '2"', 'STM', 50)
  end

  def hit_at(pt)
    pp = SS::Link.pipe_at(@model, pt)
    { point: pp[:point], dir: pp[:dir], src: 'pp', pipe: SS::Builder.pipe_record(pp) }
  end

  def place(detail, pt, opts = {})
    plan = SS::Planner.plan(@model, detail, hit_at(pt), SH.settings.merge(opts))
    SS::Builder.create(@model, plan)
  end

  def supports
    SH.supports(@model).map(&:first)
  end

  def test_link_is_available
    assert SS::Link.available?
    assert_match(/เชื่อม/, SS::Link.status)
  end

  def test_pick_on_insulation_surface
    chw = pipe_run(0, Z, '3"', 'CHWS', 50)
    hit = SS::Link.pipe_at(@model, [3000, 0, Z + 44.45 + 49])
    assert_equal chw.persistent_id, hit[:pid]
    assert_nil SS::Link.pipe_at(@model, [3000, 0, Z + 44.45 + 50 + 40]), 'clear of the insulation'
    bare = pipe_run(1000, Z, '2"', 'CW')
    assert_equal bare.persistent_id, SS::Link.pipe_at(@model, [3000, 1000, Z + 30.15 + 25])[:pid]
    assert_nil SS::Link.pipe_at(@model, [3000, 1000, Z + 30.15 + 45])
  end

  # ---------- 1.0 details (no longer offered; still refitted in old files) ----------

  def test_wall_frame_from_plant_piping_pipes
    drawing!
    g = place('wf', [3000, -30, Z])
    assert_equal 'WF-01', g.get_attribute(SH::DICT, 'number')
    assert_match(/โครงกล่อง/, g.name)
    pipes = SH.get_json(g, 'pipes')
    assert_equal 4, pipes.size, 'three in the box, steam on top'
    assert_equal [@cw, @chw, @ca, @stm].map(&:persistent_id).sort, pipes.map { |p| p['pid'] }.sort
    assert_equal 'C100', g.get_attribute(SH::DICT, 'section')
    assert_equal '1/2', g.get_attribute(SH::DICT, 'anchor')
    # frame y points away from the wall, which is 420 from the clicked pipe
    assert_in_delta 420.0, SH.get_json(g, 'struct')['wall'], 0.5
    assert_operator SH.get_json(g, 'ydir')[1], :>, 0.9
    # each pipe's support point on its own axis, for Plant Piping
    stm = pipes.find { |p| p['pid'] == @stm.persistent_id }
    assert_in_delta Z + 420, stm['at'][2], 0.5
    assert_in_delta(-60.0, stm['at'][1], 0.5)
    assert_equal [stm['at']], SS::Builder.points_for(@model, @stm.persistent_id)
    assert(SH.get_json(g, 'bom').any? { |b| b['cat'] == 'anchor' && b['qty'] == 3 })
    assert_equal 'WF-02', place('wf', [1000, -30, Z]).get_attribute(SH::DICT, 'number')
  end

  def test_wall_on_the_other_side_flips_the_frame
    @model.ray_hits = SteelSU.rays(boxes: [[[-1000.0, 600.0, 0.0], [9000.0, 900.0, 4000.0]]])
    pipe_run(0, Z, '2"', 'CW')
    pipe_run(250, Z, '2"', 'CW')
    g = place('wb', [3000, 0, Z])
    assert_operator SH.get_json(g, 'ydir')[1], :<, -0.9
    assert_in_delta 600.0, SH.get_json(g, 'struct')['wall'], 0.5
    assert_equal 2, SH.get_json(g, 'pipes').size
    assert_match(/ขาค้ำ/, g.name)
  end

  def test_no_wall_is_an_error
    @model.ray_hits = nil
    pipe_run(0, Z, '2"', 'CW')
    assert_raises(RuntimeError) { SS::Planner.plan(@model, 'wf', hit_at([3000, 0, Z]), SH.settings) }
  end

  def test_truss_hanger_moves_under_the_chord
    chord = { axis: 1, c: [3120.0, 3500.0], r: 24.15, range: [-1500.0, 1500.0] }
    @model.ray_hits = SteelSU.rays(cyls: [chord], boxes: [[[-1000.0, -3000.0, 4500.0], [9000.0, 3000.0, 4700.0]]])
    pipe_run(0, Z, '2"', 'CW')
    pipe_run(200, Z, '3"', 'CHWS', 50)
    g = place('th', [3000, 0, Z])
    o = SH.get_json(g, 'origin')
    assert_in_delta 3120.0, o[0], 1.5, 'the support plane is the chord centre'
    st = SH.get_json(g, 'struct')
    assert_equal 'round', st['kind']
    assert_in_delta 24.15, st['r'], 0.5
    assert_in_delta 3500.0 - Z, st['z'], 1.0
    assert_equal '3/8', g.get_attribute(SH::DICT, 'rod')
    assert_empty SH.get_json(g, 'notes')
    bom = SH.get_json(g, 'bom')
    assert_equal 2, bom.count { |b| b['desc'].include?('รัด truss Ø48') }
  end

  def test_hanger_under_a_flat_soffit_uses_drop_in_anchors
    @model.ray_hits = SteelSU.rays(boxes: [[[-1000.0, -3000.0, 3500.0], [9000.0, 3000.0, 3700.0]]])
    pipe_run(0, Z, '2"', 'CW')
    g = place('th', [3000, 0, Z])
    assert_in_delta 3000.0, SH.get_json(g, 'origin')[0], 0.5
    assert(SH.get_json(g, 'bom').any? { |b| b['desc'].include?('Drop-in') })
  end

  def test_channel_on_truss_chords_below
    chords = [-200.0, 400.0].map { |y| { axis: 0, c: [y, 2200.0], r: 24.15, range: [-1000.0, 9000.0] } }
    @model.ray_hits = SteelSU.rays(cyls: chords, boxes: [[[-1000.0, -3000.0, -200.0], [9000.0, 3000.0, 0.0]]])
    pipe_run(0, Z, '2"', 'CW')
    pipe_run(200, Z, '2"', 'CW')
    g = place('tt', [3000, 0, Z])
    st = SH.get_json(g, 'struct')
    assert_equal 2, st['chords'].size
    assert_in_delta(-200.0, st['chords'][0]['y'], 1.0)
    assert_in_delta 24.15, st['chords'][0]['r'], 0.5
    assert_equal 2, SH.get_json(g, 'pipes').size
    assert_match(/วางบนโครง/, g.name)
  end

  def test_plant_piping_auto_supports_leave_our_supports_out
    drawing!
    place('wf', [3000, -30, Z])
    PH.save_settings(PH.load_settings.merge('support_type' => 'clevis', 'support_group_mm' => 0))
    @model.selection.push(@ca)
    ArtK::PlantPipe::Commands.auto_supports
    xs = PH.get_json(@ca, 'supports', []).map { |r| r['at'][0] }
    refute_empty xs
    assert(xs.none? { |x| (x - 3000).abs < 600 }, "no clevis next to the frame: #{xs.map(&:round)}")
  end

  def test_placing_removes_plant_piping_hanger_there
    drawing!
    ArtK::PlantPipe::SupportBuilder.place(@model, 'clevis', ArtK::PlantPipe::Picker.nearest_pipe(@model, [3050, 170, Z]),
                                          gap: 0)
    assert_equal 1, PH.get_json(@ca, 'supports', []).size
    place('wf', [3000, -30, Z])
    assert_empty PH.get_json(@ca, 'supports', [])
  end

  def test_refit_takes_a_new_pipe_and_plant_piping_redraws_refit
    wall!
    a = pipe_run(-200, Z, '2"', 'CW')
    pipe_run(0, Z, '2"', 'CW')
    g = place('wb', [3000, -200, Z])
    assert_equal 2, SH.get_json(g, 'pipes').size
    assert_equal :same, SS::Builder.refit(@model, g)
    c = pipe_run(250, Z, '2"', 'CW')
    ArtK::PlantPipe::SupportBuilder.notify_changed(@model, [c]) # as after drawing it
    g2 = supports.first
    refute g.valid?
    assert_equal 3, SH.get_json(g2, 'pipes').size
    assert_equal 'WB-01', g2.get_attribute(SH::DICT, 'number'), 'keeps its number'
    assert_equal :same, SS::Builder.refit(@model, g2)
    assert_equal 1, supports.size
    a.erase!
    assert_equal :lost, SS::Builder.refit(@model, g2), 'the clicked pipe is gone'
  end

  # ---------- standard supports A–D ----------

  COLUMN = [[2800.0, -850.0, 0.0], [3200.0, -450.0, 4000.0]].freeze # 400 wide, face at y = −450

  def column!(more = [])
    @model.ray_hits = SteelSU.rays(boxes: [COLUMN] + more)
  end

  def std(t, pt, opts = {})
    plan = SS::Placer.from_pipe(@model, t, hit_at(pt), SH.settings.merge(opts))
    SS::Builder.create(@model, plan)
  end

  def face(y)
    y + 450.0
  end

  def test_d_at_the_column_centre_with_u_bolts_on_the_pipes
    column!
    big = pipe_run(-120, Z, '6"', 'CW')                       # 330 from the face, as drawn
    pipe_run(90, Z - 84.15 + 36.5, '2-1/2"', 'CW')            # 540
    pipe_run(240, Z - 84.15 + 24.15, '1-1/2"', 'CW')          # 690
    g = std('D', [3150, -120, Z])
    o = SH.get_json(g, 'origin')
    assert_in_delta 3000.0, o[0], 1.0, 'centre of the column'
    assert_in_delta(-450.0, o[1], 0.5, 'on the column face')
    assert_in_delta Z - 84.15, o[2], 0.5, 'steel top under the pipes'
    assert_equal 'D-01', g.get_attribute(SH::DICT, 'number')
    assert_match(/ซัพพอร์ต D/, g.name)
    pipes = SH.get_json(g, 'pipes')
    assert_equal [330.0, 540.0, 690.0], pipes.map { |q| q['y'] }
    assert_includes pipes.map { |q| q['pid'] }, big.persistent_id
    assert_equal 400, SH.get_json(g, 'struct')['column']
    assert_equal '1/2', g.get_attribute(SH::DICT, 'anchor')
    assert_equal false, SH.get_json(g, 'info')['nominal']
  end

  def test_c_takes_the_steam_line_on_top
    column!
    pipe_run(-120, Z, '6"', 'CW')
    pipe_run(150, Z - 84.15 + 30.15, '2"', 'CA')
    stm = pipe_run(-15, Z - 84.15 + 420 + 5 + 100 + 57.15, '4"', 'STM')
    g = std('C', [3050, -15, Z - 84.15 + 420 + 105 + 57.15])  # clicking the steam line
    assert_in_delta Z - 84.15, SH.get_json(g, 'origin')[2], 0.5, 'level from the lines inside'
    pipes = SH.get_json(g, 'pipes')
    assert_equal 3, pipes.size
    assert_includes pipes.map { |q| q['pid'] }, stm.persistent_id
  end

  def test_on_a_wall_it_stays_where_clicked_and_reach_is_checked
    wall!
    pipe_run(-450 + 160, Z, '4"', 'CW')
    g = std('A', [3100, -290, Z])
    assert_in_delta 3100.0, SH.get_json(g, 'origin')[0], 1.0
    assert_nil SH.get_json(g, 'struct')['column']
    assert_equal 'C75', g.get_attribute(SH::DICT, 'section')
    pipe_run(0, Z + 1000, '2"', 'CW') # 450 from the wall: beyond A's 310
    err = assert_raises(RuntimeError) { SS::Placer.from_pipe(@model, 'A', hit_at([3000, 0, Z + 1000]), {}) }
    assert_match(/เกินระยะ/, err.message)
  end

  def test_face_click_without_pipes_then_pipes_drawn_refit_it
    column!
    plan = SS::Placer.from_face(@model, 'D', [3150.0, -450.0, 1500.0], [0, 1.0, 0], [3150.0, 5000.0, 1500.0])
    assert_in_delta 3000.0, plan[:origin][0], 1.0
    assert_in_delta 1500.0 - 420.0, plan[:origin][2], 1e-6, 'the picked point is the top of the frame'
    pts = plan[:result].part.solids.select { |r, _| r == :steel }.flat_map { |_, q| q.polys.flatten(1) }
    assert_in_delta 420.0, pts.map { |q| q[2] }.max, 1e-6
    g = SS::Builder.create(@model, plan)
    assert SH.get_json(g, 'info')['nominal']
    assert_equal 3, g.entities.grep(Sketchup::ConstructionPoint).size, 'guide points at the drawn pipe centres'
    assert_equal :same, SS::Builder.refit(@model, g)
    run6 = pipe_run(-120, 1080 + 84.15, '6"', 'CW')
    ArtK::PlantPipe::SupportBuilder.notify_changed(@model, [run6]) # as after drawing it
    g2 = supports.first
    refute g.valid?
    assert_equal 'D-01', g2.get_attribute(SH::DICT, 'number')
    assert_equal [run6.persistent_id], SH.get_json(g2, 'pipes').map { |q| q['pid'] }
    assert_in_delta 3000.0, SH.get_json(g2, 'origin')[0], 1.0, 'the steel stays put'
    assert_equal :same, SS::Builder.refit(@model, g2)
    # the back of the face is its front when the camera looks from there
    back = SS::Placer.from_face(@model, 'A', [3150.0, -450.0, 1500.0], [0, -1.0, 0], [3150.0, 5000.0, 1500.0])
    assert_operator back[:y][1], :>, 0.9
  end

  # The user's case: the cursor snapped onto the column's corner edge.
  def test_click_on_the_column_edge_still_centres
    column!
    face = FakeF.new([0, 1, 0], [[2800, -450, 0], [3200, -450, 0], [3200, -450, 4000], [2800, -450, 4000]])
    pl = SS::Placer.from_face(@model, 'A', [3200.0, -450.0, 2000.0], [0, 1.0, 0], [5000.0, 5000.0, 2000.0],
                              face: [face, Geom::Transformation.new])
    assert_in_delta 3000.0, pl[:origin][0], 1e-6, 'centre of the face outline'
    assert_equal 400, pl[:struct][:column]
    # without the face (rays only), a pick just off the edge still finds it
    ray = SS::Placer.from_face(@model, 'A', [3201.0, -450.0, 2000.0], [0, 1.0, 0], [5000.0, 5000.0, 2000.0])
    assert_in_delta 3000.0, ray[:origin][0], 2.0
  end

  # The user's next case: the point snapped to the column's right edge,
  # where the face seen (front, +y) meets one facing away (+x). The
  # support must stand out of the seen face, centred, never in the column.
  def column_faces
    front = FakeF.new([0, 1, 0], [[2800, -450, 0], [3200, -450, 0], [3200, -450, 4000], [2800, -450, 4000]])
    right = FakeF.new([1, 0, 0], [[3200, -450, 0], [3200, -850, 0], [3200, -850, 4000], [3200, -450, 4000]])
    edge = FakeE.new
    edge.faces << right << front # the hidden one first, as the bug had it
    [front, right, edge]
  end

  def outside_column?(plan)
    pts = plan[:result].part.solids.select { |r, _| r == :steel }.flat_map { |_, q| q.polys.flatten(1) }
    pts.none? do |px, py, pz|
      w = SS::Vec.add(SS::Vec.add(SS::Vec.add(plan[:origin], SS::Vec.scale(plan[:x], px)), SS::Vec.scale(plan[:y], py)),
                      [0, 0, pz])
      w[0] > 2801 && w[0] < 3199 && w[1] > -849 && w[1] < -451
    end
  end

  def test_tool_on_the_column_edge_stands_out_of_the_face_seen
    column!
    front, _right, edge = column_faces
    view = @model.active_view
    # seen from far left: the front face at a grazing angle, the right one
    # facing away (what made 2.0.3 pick it and run the frame through)
    view.camera = Sketchup::Camera.new(PH.to_pt([-5000, 600, 6000]))
    Sketchup::InputPoint.next_position = PH.to_pt([3200, -450, 2000])
    Sketchup::InputPoint.next_edge = edge
    %w[A D].each do |t|
      [[[front]], []].each do |paths| # with the face under the cursor, and without (edge only)
        view.pick_paths = paths
        tool = SS::PlaceTool.new(t)
        tool.onMouseMove(0, 10, 10, view)
        plan = tool.instance_variable_get(:@plan)
        refute plan[:error], plan[:error]
        assert_operator plan[:y][1], :>, 0.99, "#{t}: out of the front face"
        assert_in_delta 3000.0, plan[:origin][0], 1e-6, "#{t}: column centre"
        assert_in_delta(-450.0, plan[:origin][1], 1e-6)
        assert outside_column?(plan), "#{t}: steel inside the column"
      end
    end
  ensure
    Sketchup::InputPoint.next_edge = nil
    view.pick_paths = nil
    view.camera = nil
  end

  # ---------- supports first, pipes after (2.0.5) ----------

  def b_at_1500
    SS::Builder.create(@model, SS::Placer.from_face(@model, 'B', [3150.0, -450.0, 1500.0], [0, 1.0, 0],
                                                    [3150.0, 5000.0, 1500.0]))
  end

  # Guide points of support +g+: [y, z] in its own coordinates.
  def guide_points(g)
    g.entities.grep(Sketchup::ConstructionPoint).map do |c|
      PH.from_pt(c.position).values_at(1, 2).map { |v| v.round(6) }
    end
  end

  # Draw a Plant Piping pipe of +size+ from a point picked on +path+
  # (a support / its guide) along +x.
  def draw_onto(size, path, start)
    PH.save_settings(ArtK::PlantPipe::Settings.sanitize('service' => 'CW', 'catalog' => 'CS_B36_10', 'size' => size,
                                                       'lod' => 'light', 'snap45' => false))
    tool = ArtK::PlantPipe::PipeTool.new
    tool.activate
    view = @model.active_view
    Sketchup::InputPoint.next_path = path
    Sketchup::InputPoint.next_dof = 0
    Sketchup::InputPoint.next_position = PH.to_pt(start)
    tool.onMouseMove(0, 0, 0, view)
    tip = view.tooltip
    tool.onLButtonDown(0, 0, 0, view)
    Sketchup::InputPoint.next_path = nil
    Sketchup::InputPoint.next_dof = nil
    tool.onKeyDown(VK_RIGHT, 0, 0, view)
    Sketchup::InputPoint.next_position = PH.to_pt([start[0] + 4000, start[1] + 300, 0])
    tool.onMouseMove(0, 0, 0, view)
    tool.onLButtonDown(0, 0, 0, view)
    tool.onReturn(view)
    [ArtK::PlantPipe::Collector.all_runs(@model).map(&:first).max_by(&:persistent_id), tip]
  ensure
    Sketchup::InputPoint.next_path = nil
    Sketchup::InputPoint.next_dof = nil
  end

  # The user's case: B placed on the column first at the level wanted, a
  # 6" pipe drawn onto its guide – it lies on the arm, B takes it with a
  # 1/2" U-bolt at once and keeps the other drawn place's guide.
  def test_pipes_drawn_onto_a_support_placed_first
    column!
    g = b_at_1500
    cps = g.entities.grep(Sketchup::ConstructionPoint)
    assert_equal [[200.0, 0.0], [430.0, 0.0]], guide_points(g), 'guide points on the arm where the drawn lines rest'
    run, tip = draw_onto('6"', [g, cps.first], [2600.0, -250.0, 1500.0])
    assert_match(/วางบนซัพพอร์ต B-01/, tip)
    cl = PH.get_json(run, 'cl').flatten(1)
    cl.each { |p| assert_in_delta 1500.0 + 84.15, p[2], 1e-6, 'the 6" lies on the arm' }
    g2 = supports.first
    refute g.valid?
    assert_equal 'B-01', g2.get_attribute(SH::DICT, 'number')
    assert_in_delta 1500.0, SH.get_json(g2, 'origin')[2], 1e-6, 'the steel stays where it was placed'
    pipes = SH.get_json(g2, 'pipes')
    assert_equal [[200.0, run.persistent_id]], pipes.map { |q| [q['y'], q['pid']] }
    assert_in_delta 84.15, pipes[0]['z'], 0.1
    assert(SH.get_json(g2, 'bom').any? { |b| b['key'] == 'ub 1/2 168' }, 'U-bolt 1/2" round the 6"')
    refute(SH.get_json(g2, 'bom').any? { |b| b['cat'] == 'plate' }, 'no packer')
    assert_empty SH.get_json(g2, 'notes')
    left = g2.entities.grep(Sketchup::ConstructionPoint)
    assert_equal [[430.0, 0.0]], guide_points(g2)
    # the second line, 1½", onto the guide left: both carried, each its own U-bolt
    run2, = draw_onto('1-1/2"', [g2, left.first], [2600.0, -20.0, 1500.0])
    PH.get_json(run2, 'cl').flatten(1).each { |p| assert_in_delta 1500.0 + 24.15, p[2], 1e-6 }
    g3 = supports.first
    assert_equal [200.0, 430.0], SH.get_json(g3, 'pipes').map { |q| q['y'] }
    ubolts = SH.get_json(g3, 'bom').select { |b| b['cat'] == 'ubolt' }
    assert_equal ['ub 1/2 168', 'ub 3/8 48'], ubolts.map { |b| b['key'] }
    assert_empty g3.entities.grep(Sketchup::ConstructionPoint)
  end

  # Clicking the arm's top puts the pipe on it too, at the nearest drawn
  # place; with none free near, where picked; a point not on the steel the
  # pipes sit on is left as picked.
  def test_pipe_picked_on_the_arm_top_lies_on_it
    column!
    g = b_at_1500
    run, = draw_onto('4"', [g], [2600.0, -150.0, 1500.0]) # 300 out on the arm
    PH.get_json(run, 'cl').flatten(1).each { |p| assert_in_delta 1500.0 + 57.15, p[2], 1e-6 }
    q = SH.get_json(supports.first, 'pipes')
    assert_equal [200.0], q.map { |p| p['y'] }, 'the nearest drawn place'
    assert_in_delta 57.15, q[0]['z'], 0.1
    draw_onto('1"', [supports.first], [2600.0, -390.0, 1500.0]) # 60 out: 0.20 taken, 0.43 far
    assert_equal [60.0, 200.0], SH.get_json(supports.first, 'pipes').map { |p| p['y'] }
    free, = draw_onto('2"', [], [2600.0, 1000.0, 1500.0])
    PH.get_json(free, 'cl').flatten(1).each { |p| assert_in_delta 1500.0, p[2], 1e-6 }
  end

  # C: the steam line drawn onto the top lies on its shoe as drawn (the
  # shoe welds to the bare pipe – insulation round it); the 6" below on
  # its guide.
  def test_steam_line_drawn_onto_c_lies_on_its_shoe
    column!
    g = SS::Builder.create(@model, SS::Placer.from_face(@model, 'C', [3000.0, -450.0, 1920.0], [0, 1.0, 0],
                                                        [3000.0, 5000.0, 1920.0]))
    assert_equal [[330.0, 0.0], [600.0, 0.0], [435.0, 525.0]], guide_points(g)
    PH.save_settings(ArtK::PlantPipe::Settings.sanitize('service' => 'STM', 'catalog' => 'CS_B36_10', 'size' => '4"',
                                                       'lod' => 'light', 'insulation_mm' => 50))
    tool = ArtK::PlantPipe::PipeTool.new
    tool.activate
    view = @model.active_view
    Sketchup::InputPoint.next_path = [g]
    Sketchup::InputPoint.next_dof = 2
    Sketchup::InputPoint.next_position = PH.to_pt([3010.0, -450.0 + 435.0, 1500.0 + 425.0]) # on the 2" seat
    tool.onMouseMove(0, 0, 0, view)
    tool.onLButtonDown(0, 0, 0, view)
    Sketchup::InputPoint.next_path = nil
    tool.onKeyDown(VK_RIGHT, 0, 0, view)
    Sketchup::InputPoint.next_position = PH.to_pt([7000.0, 0, 0])
    tool.onMouseMove(0, 0, 0, view)
    tool.onLButtonDown(0, 0, 0, view)
    tool.onReturn(view)
    stm = ArtK::PlantPipe::Collector.all_runs(@model).map(&:first).last
    PH.get_json(stm, 'cl').flatten(1).each { |p| assert_in_delta 1500.0 + 525.0 + 57.15, p[2], 1e-6 }
    six, = draw_onto('6"', [supports.first], [2600.0, -450.0 + 330.0, 1500.0])
    c = supports.first
    assert_equal [six.persistent_id, stm.persistent_id].sort, SH.get_json(c, 'pipes').map { |q| q['pid'] }.sort
    assert_in_delta 1500.0, SH.get_json(c, 'origin')[2], 1e-6
    refute(SH.get_json(c, 'bom').any? { |b| b['cat'] == 'plate' }, 'shoe as drawn, no packing')
    assert_equal [[600.0, 0.0]], guide_points(c)
  ensure
    Sketchup::InputPoint.next_path = nil
    Sketchup::InputPoint.next_dof = nil
  end

  # The user's case (2.0.5): the 6" picked on the arm by the column and
  # the 1½" by its end lay where picked – off the drawing's places – and
  # each pipe took B down. They go to the drawn places (0.20, 0.43) and B
  # stays at the level it was placed at.
  def test_pipes_picked_on_the_arm_go_to_the_drawn_places
    column!
    g = b_at_1500
    run, tip = draw_onto('6"', [g], [3010.0, -450.0 + 110.0, 1500.0]) # on the arm, by the column
    assert_match(/B-01 ที่ 0\.20/, tip)
    PH.get_json(run, 'cl').flatten(1).each do |p|
      assert_in_delta(-250.0, p[1], 1e-6, '0.20 from the face')
      assert_in_delta 1584.15, p[2], 1e-6
    end
    run2, = draw_onto('1-1/2"', [supports.first], [2990.0, -450.0 + 465.0, 1500.0]) # by the arm's end
    PH.get_json(run2, 'cl').flatten(1).each { |p| assert_in_delta(-20.0, p[1], 1e-6, '0.43 from the face') }
    s = supports.first
    assert_equal [1500.0, -450.0], SH.get_json(s, 'origin').values_at(2, 1), 'B where it was placed'
    assert_equal [200.0, 430.0], SH.get_json(s, 'pipes').map { |q| q['y'] }
    assert_empty SH.get_json(s, 'notes')
  end

  # A pipe moved after (Plant Piping's stretch / move): up – it rides on a
  # packer; down into the steel – the support stays where it was placed
  # and says so.
  def test_support_stays_when_a_pipe_is_moved
    column!
    g = b_at_1500
    run, = draw_onto('2"', [g, g.entities.grep(Sketchup::ConstructionPoint).first], [2600.0, -250.0, 1500.0])
    up = PH.get_json(run, 'cl').flatten(1).uniq.map { |p| [p, [p[0], p[1], p[2] + 150.0]] }
    ArtK::PlantPipe::RunEditor.apply(@model, run, up)
    s = supports.first
    assert_in_delta 1500.0, SH.get_json(s, 'origin')[2], 1e-6
    assert(SH.get_json(s, 'bom').any? { |b| b['cat'] == 'plate' }, 'on a packer')
    down = PH.get_json(run, 'cl').flatten(1).uniq.map { |p| [p, [p[0], p[1], p[2] - 250.0]] }
    ArtK::PlantPipe::RunEditor.apply(@model, run, down)
    s = supports.first
    assert_in_delta 1500.0, SH.get_json(s, 'origin')[2], 1e-6, 'never moves'
    assert(SH.get_json(s, 'notes').any? { |n| n.include?('จมในเหล็ก') })
  end

  # Drawn some other way into the steel: the support stays and says so.
  def test_a_pipe_drawn_into_the_steel_leaves_the_support_where_it_is
    column!
    b_at_1500
    run = pipe_run(-250, 1530.15, '6"', 'CW')
    ArtK::PlantPipe::SupportBuilder.notify_changed(@model, [run]) # as after drawing it
    g = supports.first
    assert_in_delta 1500.0, SH.get_json(g, 'origin')[2], 1e-6
    assert(SH.get_json(g, 'notes').any? { |n| n.include?('6"') && n.include?('จมในเหล็ก 54 มม.') })
    assert_equal ['ub 3/8 48'], SH.get_json(g, 'bom').select { |b| b['cat'] == 'ubolt' }.map { |b| b['key'] },
                 "no drawing's U-bolt through the 6\""
  end

  # Whatever passes – 1, 2, 3, 4 lines, any size and place – gets a U-bolt.
  def test_any_number_of_pipes_passing
    column!
    top = 2000.0
    lvl = top - 420.0
    [[150, '2"', 30.15], [300, '3"', 44.45], [480, '4"', 57.15], [650, '2"', 30.15]].each do |f, size, r|
      pipe_run(f - 450, lvl + r, size, 'CW')
    end
    d = SS::Placer.from_face(@model, 'D', [3000.0, -450.0, top], [0, 1.0, 0], [3000.0, 5000.0, top])
    assert_equal [150.0, 300.0, 480.0, 650.0], d[:result].carried.map { |q| q[:y] }
    refute d[:result].info[:nominal]
    assert_empty d[:result].notes
    assert_equal 4, d[:result].bom.count { |b| b[:cat] == 'ubolt' }
    one = SS::Placer.from_face(@model, 'A', [3000.0, -450.0, lvl], [0, 1.0, 0], [3000.0, 5000.0, lvl])
    assert_equal [150.0], one[:result].carried.map { |q| q[:y] }, 'A at the pipes: the one within its arm'
  end

  def test_every_column_along_a_run
    column!([[[4800.0, -850.0, 0.0], [5200.0, -450.0, 4000.0]]])
    r = pipe_run(-120, Z, '6"', 'CW', x0: 0, x1: 8000)
    @model.selection.push(r)
    UI.messages.clear
    assert_equal 2, SS::Commands.columns('D')
    xs = supports.map { |g| SH.get_json(g, 'origin')[0] }.sort
    assert_in_delta 3000.0, xs[0], 2.0
    assert_in_delta 5000.0, xs[1], 2.0
    assert_equal 0, SS::Commands.columns('D'), 'not twice'
    rows = SS::Report.rows(supports)
    assert_in_delta 2 * 2.78, rows.find { |q| q[:cat] == 'steel' }[:length_m], 0.01
    assert_match(/พุก Expansion bolt 1\/2"/, SS::Report.csv(supports))
    assert_match(/น้ำหนักเหล็กรวม/, SS::Report.html(supports))
  end

  def test_place_tool
    column!
    pipe_run(-120, Z, '6"', 'CW')
    tool = SS::PlaceTool.new('B')
    tool.activate
    view = @model.active_view
    Sketchup::InputPoint.next_position = PH.to_pt([3100, -120, Z + 90])
    tool.onMouseMove(0, 10, 10, view)
    assert_match(/ซัพพอร์ต B/, view.tooltip)
    assert_match(/กลางเสา/, view.tooltip)
    tool.draw(view)
    refute_empty view.drawn
    tool.onLButtonDown(0, 10, 10, view)
    assert_equal 1, supports.size
    tool.onKeyDown(9, false, 0, view)
    assert_equal 'C', SH.settings['detail']
    Sketchup::InputPoint.next_position = PH.to_pt([3100, 3000, Z])
    tool.onMouseMove(0, 10, 10, view) # nothing there
    tool.onLButtonDown(0, 10, 10, view)
    assert_equal 1, supports.size
  end

  def test_dialog_payload_and_old_settings
    Sketchup.write_default(SH::PREF, 'settings_b64', [JSON.generate('detail' => 'wf')].pack('m0'))
    SH.forget_settings
    assert_equal 'A', SH.settings['detail'], '1.0 types are no longer offered'
    d = SS::Dialog.payload
    assert_equal %w[A B C D], d[:types].map { |t| t[:key] }
    assert_equal true, d[:linked]
    JSON.generate(d)
    SS::Dialog.save(JSON.generate('detail' => 'C', 'spacing_m' => 3))
    assert_equal 'C', SH.settings['detail']
    assert_equal 3, SH.settings['spacing_m']
    # what SketchUp keeps has no double quote in it, and reads back (new session)
    stored = Sketchup.read_default(SH::PREF, 'settings_b64')
    refute_includes stored, '"'
    SH.forget_settings
    assert_equal 'C', SH.settings['detail']
    # the window's place button uses it: the tool is C, not A
    SS::Dialog.command('place')
    assert_equal 'C', @model.tool.instance_variable_get(:@detail)
  end

  # A faceted tube drawn without Plant Piping, as SketchUp faces.
  FakeV = Struct.new(:position)
  class FakeE
    attr_reader :faces

    def initialize
      @faces = []
    end
  end
  class FakeF
    attr_reader :normal, :vertices, :edges

    def initialize(n, pts)
      @normal = Geom::Vector3d.new(*n)
      @vertices = pts.map { |p| FakeV.new(PH.to_pt(p)) }
      @edges = []
    end
  end

  def test_generic_cylinder_from_faces
    n = 24
    r = 57.0
    faces = (0...n).map do |k|
      a0 = 2 * Math::PI * k / n
      a1 = 2 * Math::PI * (k + 1) / n
      am = (a0 + a1) / 2
      pts = [[0, r * Math.cos(a0), 1000 + r * Math.sin(a0)], [3000, r * Math.cos(a0), 1000 + r * Math.sin(a0)],
             [3000, r * Math.cos(a1), 1000 + r * Math.sin(a1)], [0, r * Math.cos(a1), 1000 + r * Math.sin(a1)]]
      FakeF.new([0, Math.cos(am), Math.sin(am)], pts)
    end
    n.times do |k|
      e = FakeE.new
      e.faces << faces[k] << faces[(k + 1) % n]
      faces[k].edges << e
      faces[(k + 1) % n].edges << e
    end
    cyl = SS::Generic.cylinder(faces[3], Geom::Transformation.new)
    assert_in_delta 57.0, cyl[:radius], 0.01
    assert_in_delta 1.0, cyl[:axis][0].abs, 1e-9
    p = SS::Generic.pipe(cyl, [1500, 0, 1000], [1, 0, 0], [0, 1, 0])
    assert_in_delta 0.0, p[:y], 0.01
    assert_in_delta 0.0, p[:z], 0.01
    assert_in_delta 114.0, p[:od], 0.1
    assert_operator p[:kg_m], :>, 20
  end
end
