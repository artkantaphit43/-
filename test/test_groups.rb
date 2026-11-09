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
   library commands pipe_tool stretch_tool support_tool color_pick_tool api].each do |f|
  require File.expand_path("../src/artk_plant_pipe/su/#{f}", __dir__)
end

# Pipes inside other groups / components (1.21.4): the tools see them – a
# pipe drawn onto one joins it, as in the open context. Before, only runs
# directly in the open context counted: drawing onto a pipe in another
# group gave a loose pipe beside it (the user's "different groups").
class TestGroups < Minitest::Test
  H = ModelHelpers
  IP = Sketchup::InputPoint
  S2 = { 'service' => 'CW', 'catalog' => 'PVC_TIS17', 'size' => '2"' }.freeze

  def setup
    @model = Sketchup::Model.new
    Sketchup.active_model = @model
    @view = @model.active_view
    clear_pick
    H.save_settings(Settings.sanitize(S2))
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

  # A group moved to +at+ (world mm) holding a 2" run along its own x,
  # 0 → 5000 (inside +parent+ entities, root by default).
  def run_in_group(at, parent: @model.entities, settings: S2)
    g = parent.add_group
    g.transformation = Geom::Transformation.new(H.to_pt(at).to_a)
    run = nil
    inside(g.entities) { run, = Builder.create_run(@model, [[[0.0, 0, 0], [5000.0, 0, 0]]], Settings.sanitize(settings)) }
    [g, run]
  end

  # Builder adds runs to the open context: make +ents+ that for a moment.
  def inside(ents)
    @model.define_singleton_method(:active_entities) { ents }
    yield
  ensure
    @model.singleton_class.send(:remove_method, :active_entities)
  end

  def pick(tool, mm, path: nil, dof: 3)
    clear_pick
    IP.next_position = H.to_pt(mm)
    IP.next_path = path
    IP.next_dof = dof
    tool.onMouseMove(0, 0, 0, @view)
    tool.onLButtonDown(0, 0, 0, @view)
  end

  def tool(settings = {})
    H.save_settings(Settings.sanitize(S2.merge(settings)))
    t = PipeTool.new
    t.activate
    t
  end

  def roots
    @model.entities.select { |e| H.run?(e) }
  end

  def world_cl(run, tr)
    H.get_json(run, 'cl').flatten(1).uniq.map { |p| H.transform_mm(tr, p).map { |c| c.round(3) } }
  end

  def test_runs_in_other_groups_are_seen_with_their_place
    g, run = run_in_group([1000, 2000, 500])
    _, deep = run_in_group([0, 0, 100], parent: g.entities)
    list = H.active_runs(@model)
    found = list.to_h { |r, t| [r, t] }
    assert_equal [[1000.0, 2000.0, 500.0], [6000.0, 2000.0, 500.0]], world_cl(run, found[run])
    assert_equal [[1000.0, 2000.0, 600.0], [6000.0, 2000.0, 600.0]], world_cl(deep, found[deep])
  end

  # the user's case: a branch drawn from outside onto a pipe in a group
  def test_branch_onto_a_pipe_in_another_group_is_a_tee
    g, main = run_in_group([1000, 2000, 500])
    piece = main.entities.find { |e| H.type_of(e) == 'pipe' }
    t = tool
    pick(t, [3500, 2000, 500 + 30], path: [g, main, piece], dof: 2) # on the pipe's top
    pick(t, [3500, 4000, 500], dof: 1)
    t.onReturn(@view)
    b = roots.first
    assert b, 'a branch run'
    assert_equal [[3500.0, 2000.0, 500.0], [3500.0, 4000.0, 500.0]], world_cl(b, Geom::Transformation.new)
    tee = H.get_json(b, 'tees').first
    assert_equal main.persistent_id, tee['main_pid']
  end

  # starting on its open end continues it – inside its own group, in that
  # group's coordinates
  def test_continuing_a_pipe_in_another_group_extends_it_there
    g, main = run_in_group([1000, 2000, 500])
    piece = main.entities.find { |e| H.type_of(e) == 'pipe' }
    t = tool
    pick(t, [6000, 2000, 500], path: [g, main, piece], dof: 2) # its end
    pick(t, [6000, 5000, 500], dof: 1)
    t.onReturn(@view)
    assert_empty roots, 'no loose run outside'
    assert_equal [[0.0, 0.0, 0.0], [5000.0, 0.0, 0.0], [5000.0, 3000.0, 0.0]],
                 H.get_json(main, "cl").flatten(1).map { |p| p.map { |c| c.to_f.round(3) } }.uniq
    assert_equal 1, main.entities.count { |e| H.type_of(e) == 'elbow' }
  end

  # a line from outside ending on the pipe's open end: one line, joined
  def test_line_ending_on_the_end_of_a_pipe_in_another_group_joins_it
    g, main = run_in_group([1000, 2000, 500])
    piece = main.entities.find { |e| H.type_of(e) == 'pipe' }
    t = tool
    pick(t, [9000, 2000, 500])
    pick(t, [6000, 2000, 500], path: [g, main, piece], dof: 2) # onto its end → Center
    assert_empty roots
    assert_equal [[0.0, 0.0, 0.0], [5000.0, 0.0, 0.0], [8000.0, 0.0, 0.0]],
                 H.get_json(main, "cl").flatten(1).map { |p| p.map { |c| c.to_f.round(3) } }.uniq.sort
  end

  # another size onto the end in a group: reducer + new run, joined
  def test_other_size_onto_a_pipe_in_another_group_gets_a_reducer
    g, main = run_in_group([1000, 2000, 500])
    piece = main.entities.find { |e| H.type_of(e) == 'pipe' }
    t = tool('size' => '3"')
    pick(t, [6000, 2000, 500], path: [g, main, piece], dof: 2)
    pick(t, [9000, 2000, 500], dof: 1)
    t.onReturn(@view)
    n = roots.first
    assert n
    assert_equal main.persistent_id, H.get_json(n, 'joins').first['main_pid']
    assert_equal [6000.0, 2000.0, 500.0], world_cl(n, Geom::Transformation.new).first
  end

  # a component placed twice: each copy is a pipe to join
  def test_each_copy_of_a_component_is_joined
    g, main = run_in_group([0, 0, 0])
    defn = g.definition
    a = @model.entities.add_instance(defn, Geom::Transformation.new(H.to_pt([0, 3000, 0]).to_a))
    piece = main.entities.find { |e| H.type_of(e) == 'pipe' }
    t = tool
    pick(t, [2500, 3000, 30], path: [a, main, piece], dof: 2) # on the second copy
    pick(t, [2500, 6000, 0], dof: 1)
    t.onReturn(@view)
    b = roots.first
    assert_equal [2500.0, 3000.0, 0.0], world_cl(b, Geom::Transformation.new).first
    assert_equal 1, H.get_json(b, 'tees').size
  end

  # hidden groups are not drawn onto
  def test_pipes_in_hidden_groups_are_left_alone
    g, main = run_in_group([1000, 2000, 500])
    g.define_singleton_method(:hidden?) { true }
    refute(H.active_runs(@model).any? { |r, _| r == main })
  end

  # Steel Supports TH finds the pipe through the API
  def test_steel_supports_see_pipes_in_groups
    _, main = run_in_group([1000, 2000, 500])
    hit = API.pipe_at(@model, [3000.0, 2000.0, 500.0])
    assert hit, 'pipe_at finds it'
    assert_equal main.persistent_id, hit[:pid] || hit[:run]&.persistent_id
  end

  # the Stretch tool edits it in its group
  def test_stretch_tool_moves_the_end_of_a_pipe_in_a_group
    g, main = run_in_group([1000, 2000, 500])
    s = StretchTool.new
    s.activate
    pick(s, [6000, 2000, 500]) # grab the open end
    pick(s, [7000, 2000, 500]) # +1 m along it
    assert_equal [6000.0, 0.0, 0.0], H.get_json(main, 'cl').last.last.map { |c| c.round(3) }
    refute_nil g
  end
end
