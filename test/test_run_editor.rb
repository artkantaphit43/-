# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'su_stub'

module ArtK
  module PlantPipe
    PLUGIN_ROOT = File.expand_path('../src/artk_plant_pipe', __dir__) unless defined?(PLUGIN_ROOT)
    VERSION = 'test' unless defined?(VERSION)
  end
end
require File.join(LIB, 'run_edit')
%w[model_helpers migrate builder ref_models ref_builder support_builder collector run_editor picker reports library commands
   ref_browser stretch_tool].each do |f|
  require File.expand_path("../src/artk_plant_pipe/su/#{f}", __dir__)
end

# Pipes stay editable: stretch tool, reading SketchUp edits back, fittings
# fixed to pipe ends.
class TestRunEditor < Minitest::Test
  H = ModelHelpers

  def setup
    @model = Sketchup::Model.new
    Sketchup.active_model = @model
    @view = @model.active_view
    @s = Settings.sanitize('service' => 'CW', 'catalog' => 'GSP_BS1387', 'size' => '1"')
  end

  def pipes(run)
    Collector.pieces(run, 'pipe')
  end

  def pipe_at(run, pt)
    pipes(run).find { |p| g = H.get_json(p, 'geom'); Vec.dist(g['a'], pt) <= 1 || Vec.dist(g['b'], pt) <= 1 }
  end

  # Replace a pipe group's mesh with rings at pa / pb (what SketchUp would
  # hold after Push/Pull or Scale), in the group's own coordinates.
  def fake_mesh(pipe, pa, pb, r)
    pipe.entities.clear!
    u = Vec.unit(Vec.sub(pb, pa))
    v = Vec.perpendicular(u)
    w = Vec.cross(u, v)
    [pa, pb].each do |c|
      pts = (0...12).map do |i|
        a = 2 * Math::PI * i / 12
        H.to_pt(Vec.add(c, Vec.add(Vec.scale(v, r * Math.cos(a)), Vec.scale(w, r * Math.sin(a)))))
      end
      pts.each_cons(2) { |p, q| pipe.entities.add_line(p, q) }
    end
  end

  def mesh_as_built(pipe)
    g = H.get_json(pipe, 'geom')
    u = Vec.unit(Vec.sub(g['b'], g['a']))
    [Vec.sub(g['a'], Vec.scale(u, g['ea'])), Vec.add(g['b'], Vec.scale(u, g['eb']))]
  end

  def l_run
    [[[0.0, 0, 0], [3000.0, 0, 0]], [[3000.0, 0, 0], [3000.0, 2000, 0]]]
  end

  def test_untouched_pipes_read_back_unchanged
    run, = Builder.create_run(@model, l_run, @s)
    od = run.get_attribute(H::DICT, 'od').to_f
    pipes(run).each { |p| fake_mesh(p, *mesh_as_built(p), od / 2) }
    r = RunEditor.inspect(run)
    assert_empty r[:moves]
    assert_empty r[:issues]
  end

  def test_open_end_pushed_with_sketchup_is_taken_into_the_run
    run, = Builder.create_run(@model, l_run, @s)
    od = run.get_attribute(H::DICT, 'od').to_f
    pipes(run).each { |p| fake_mesh(p, *mesh_as_built(p), od / 2) }
    p = pipe_at(run, [3000.0, 2000, 0])
    pa, = mesh_as_built(p)
    fake_mesh(p, pa, [3000.0, 2700, 0], od / 2) # Push/Pull the open end 700 mm
    res = RunEditor.sync(@model, [run])
    assert_equal [run], res[:synced]
    assert_equal [3000.0, 2700, 0], H.get_json(run, 'cl').last.last.map { |c| c.round(3) }
    g = H.get_json(pipe_at(run, [3000.0, 2700, 0]), 'geom')
    assert_in_delta 2700.0, g['b'][1], 1e-6
    # a rebuild keeps the new length
    Builder.rebuild(@model, [run], {})
    assert_equal 2700.0, H.get_json(run, 'cl').last.last[1].round(3)
  end

  def test_scaled_pipe_group_is_read_through_its_transformation
    run, = Builder.create_run(@model, [[[0.0, 0, 0], [2000.0, 0, 0]]], @s)
    p = pipes(run).first
    fake_mesh(p, [0.0, 0, 0], [2000.0, 0, 0], run.get_attribute(H::DICT, 'od').to_f / 2)
    p.transformation = Geom::Transformation.scaling(1.25, 1.0, 1.0) # Scale tool, red handle
    r = RunEditor.inspect(run)
    assert_equal 1, r[:moves].size
    assert Vec.near?(r[:moves].first[1], [2500.0, 0, 0], 1e-6), r[:moves].inspect
  end

  def test_sideways_move_and_joined_end_are_reported_not_guessed
    run, = Builder.create_run(@model, l_run, @s)
    od = run.get_attribute(H::DICT, 'od').to_f
    p = pipe_at(run, [0.0, 0, 0])
    pa, pb = mesh_as_built(p)
    fake_mesh(p, Vec.add(pa, [0, 150, 0]), Vec.add(pb, [0, 150, 0]), od / 2)
    r = RunEditor.inspect(run)
    assert_empty r[:moves]
    refute_empty r[:issues]
  end

  def test_stretch_tool_extends_an_end_by_a_typed_distance_and_valves_stay
    run, = Builder.create_run(@model, l_run, @s)
    Builder.add_valve(@model, run, 'gate', [1000.0, 0, 0], [1.0, 0, 0])
    t = StretchTool.new
    t.activate
    Sketchup::InputPoint.next_position = H.to_pt([10.0, 5, 0])
    t.onMouseMove(0, 0, 0, @view)
    t.onLButtonDown(0, 0, 0, @view) # grab the open start
    Sketchup::InputPoint.next_position = H.to_pt([-300.0, 40, 0])
    t.onMouseMove(0, 0, 0, @view)
    t.onUserText('500', @view)
    assert_equal [-500.0, 0, 0], H.get_json(run, 'cl').first.first.map { |c| c.round(3) }
    v = Collector.pieces(run, 'valve').first
    assert_equal [1000.0, 0, 0], JSON.parse(v.get_attribute(H::DICT, 'at')).map { |c| c.round(3) }
  end

  def test_stretch_tool_moves_a_corner
    run, = Builder.create_run(@model, l_run, @s)
    t = StretchTool.new
    t.activate
    Sketchup::InputPoint.next_position = H.to_pt([3000.0, 0, 0])
    t.onMouseMove(0, 0, 0, @view)
    t.onLButtonDown(0, 0, 0, @view)
    t.onKeyDown(VK_RIGHT, 0, 0, @view)
    Sketchup::InputPoint.next_position = H.to_pt([3600.0, 80, 0])
    t.onMouseMove(0, 0, 0, @view)
    t.onLButtonDown(0, 0, 0, @view)
    cl = H.get_json(run, 'cl')
    assert_equal [3600.0, 0, 0], cl[0][1].map { |c| c.round(3) }
    assert_equal [3600.0, 0, 0], cl[1][0].map { |c| c.round(3) }
  end

  def faucet
    Refs.items.find { |i| i['type'] == 'faucet' && !i['ports'].empty? }
  end

  def end_parts(run)
    run.entities.select { |e| H.instance?(e) && e.get_attribute(H::DICT, 'end_part') }
  end

  def port_world(inst, item)
    H.transform_mm(inst.transformation, item['ports'][0]['p'])
  end

  def test_library_fitting_on_an_end_follows_the_stretched_pipe
    run, = Builder.create_run(@model, [[[0.0, 0, 0], [2000.0, 0, 0]]], @s)
    Builder.add_end_part(@model, run, faucet['key'], [2000.0, 0, 0], 0.0)
    assert_equal 1, end_parts(run).size
    RunEditor.apply(@model, run, [[[2000.0, 0, 0], [2600.0, 0, 0]]])
    parts = end_parts(run)
    assert_equal 1, parts.size
    rec = JSON.parse(parts.first.get_attribute(H::DICT, 'end_part'))
    assert_equal [2600.0, 0, 0], rec['at']
    assert_equal 'component', H.type_of(parts.first), 'still counted in the BOM'
    # mouth of the part sits on the new end (socket swallows the pipe)
    # a 1" bib tap (standard size), not the ½" one blown up
    item = Refs.sized_item(faucet, Catalog.spec('GSP_BS1387', '1"'))
    assert_includes parts.first.definition.name, '@DN25'
    m = Refs.mouth_point(item, 0, [2600.0, 0, 0], [1.0, 0, 0])
    tr = parts.first.transformation
    assert Vec.near?(H.transform_mm(tr, item['ports'][0]['p']), m, 0.01)
  end

  def test_end_fitting_survives_rebuild_and_is_dropped_when_the_end_is_continued
    run, = Builder.create_run(@model, [[[0.0, 0, 0], [2000.0, 0, 0]]], @s)
    Builder.add_end_part(@model, run, faucet['key'], [2000.0, 0, 0], 0.0)
    Builder.rebuild(@model, [run], {})
    assert_equal 1, end_parts(run).size
    w = Builder.extend_run(@model, run, [[[2000.0, 0, 0], [2000.0, 1000, 0]]])
    assert_empty end_parts(run)
    assert(w.any? { |x| x.include?('removed') })
  end

  def test_placing_on_an_end_with_the_library_tool_attaches_to_the_run
    run, = Builder.create_run(@model, [[[0.0, 0, 0], [2000.0, 0, 0]]], @s)
    tool = RefPlaceTool.new(faucet)
    tool.activate
    pl = tool.placement([1990.0, 0.0, 10.0])
    tool.send(:commit, pl)
    assert_equal 1, end_parts(run).size
  end

  def test_auto_sync_reads_a_scaled_pipe_after_the_edit
    run, = Builder.create_run(@model, [[[0.0, 0, 0], [2000.0, 0, 0]]], @s)
    p = pipes(run).first
    fake_mesh(p, [0.0, 0, 0], [2000.0, 0, 0], run.get_attribute(H::DICT, 'od').to_f / 2)
    p.transformation = Geom::Transformation.scaling(1.5, 1.0, 1.0)
    @model.selection.clear
    @model.selection << p
    p.parent = run.definition # SketchUp: a piece's parent is its run's definition
    AutoSync.check(@model)
    assert_in_delta 3000.0, H.get_json(run, 'cl').first.last[0], 1e-6
  end

  # The user's case: pipe stretched with Push/Pull, then a fitting from the
  # library – it must land on the end you see, not the old one.
  def test_fitting_tool_snaps_to_the_stretched_end
    run, = Builder.create_run(@model, [[[0.0, 0, 0], [2000.0, 0, 0]]], @s)
    fake_mesh(pipes(run).first, [0.0, 0, 0], [2800.0, 0, 0], run.get_attribute(H::DICT, 'od').to_f / 2)
    tool = RefPlaceTool.new(faucet)
    tool.activate
    pl = tool.placement([2790.0, 0.0, 10.0])
    assert_equal :end, pl[:mode]
    assert_equal [2800.0, 0, 0], pl[:local].map { |c| c.round(3) }
  end
end
