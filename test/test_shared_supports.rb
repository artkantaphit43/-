# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'su_stub'

module ArtK
  module PlantPipe
    PLUGIN_ROOT = File.expand_path('../src/artk_plant_pipe', __dir__) unless defined?(PLUGIN_ROOT)
    VERSION = 'test' unless defined?(VERSION)
  end
end
%w[model_helpers migrate builder ref_models ref_builder support_builder collector picker reports commands pipe_tool
   support_tool].each do |f|
  require File.expand_path("../src/artk_plant_pipe/su/#{f}", __dir__)
end

# Neighbouring parallel pipes share one support (H-frame, trapeze,
# sleeper, column bracket), also when a pipe is drawn next to existing
# supports later.
class TestSharedSupports < Minitest::Test
  H = ModelHelpers

  def setup
    @model = Sketchup::Model.new
    Sketchup.active_model = @model
    Sketchup::InputPoint.next_vertex = nil
    Sketchup::InputPoint.next_dof = nil
    @s = Settings.sanitize('service' => 'CW', 'catalog' => 'CS_B36_10', 'size' => '2"', 'lod' => 'light')
    # slab soffit at 4 m, floor at 0, a column face at y = −600
    @model.ray_hits = lambda do |pt, dir|
      if dir[2] > 0.5 then [[pt[0], pt[1], 4000.0], []]
      elsif dir[2] < -0.5 then [[pt[0], pt[1], 0.0], []]
      elsif dir[1] < -0.5 && pt[1] > -600 then [[pt[0], -600.0, pt[2]], []]
      end
    end
    H.save_settings(@s)
  end

  def run_at(y, z = 1000, size: '2"')
    Builder.create_run(@model, [[[0, y, z], [6000, y, z]]], @s.merge('size' => size))[0]
  end

  def shared
    SupportBuilder.shared_supports(@model)
  end

  def hit_on(run, x)
    Picker.nearest_pipe(@model, [x, H.get_json(run, 'cl')[0][0][1], H.get_json(run, 'cl')[0][0][2]])
  end

  def test_grouping_rules
    c = [[0.0, 30, 0.0, 'a'], [250.0, 30, 0.0, 'b'], [1200.0, 30, 0.0, 'c'], [-200.0, 20, -100.0, 'd'],
         [-400.0, 20, 800.0, 'e'], [-600.0, 20, 0.0, 'f']]
    ids = Supports.group(c).map { |o| o[3] }.sort
    # c: 890 mm clear gap – too far; e: 800 mm higher – own support (but
    # not a barrier: f beyond it is still in)
    assert_equal %w[a b d f], ids
    assert_equal ['a'], Supports.group(c, gap: 0).map { |o| o[3] }
  end

  def test_fill_keeps_shared_supports_and_span
    xs = Supports.fill(10_000.0, 3000.0, 600.0, [5000.0])
    all = (xs + [5000.0]).sort
    assert_in_delta 600.0, all.first, 1e-6
    assert_in_delta 9400.0, all.last, 1e-6
    assert(all.each_cons(2).all? { |a, b| b - a <= 3000.0 + 1e-6 })
    refute_includes xs, 5000.0
  end

  def test_stand_on_a_pipe_with_a_neighbour_becomes_an_h_frame_for_both
    a = run_at(0)
    run_at(350)
    run_at(2500) # far away – not included
    note = SupportBuilder.place(@model, 'stand', hit_on(a, 3000))
    assert_nil note
    assert_equal 1, shared.size
    g = shared.first
    assert_equal 'hframe', g.get_attribute(H::DICT, 'support_type')
    assert_equal 'stand', g.get_attribute(H::DICT, 'base_type')
    assert_equal 2, H.get_json(g, 'members').size
    assert_empty H.get_json(a, 'supports', []), 'no single stand as well'
  end

  def test_single_pipe_keeps_its_own_support
    a = run_at(0)
    SupportBuilder.place(@model, 'clevis', hit_on(a, 3000))
    assert_empty shared
    assert_equal 1, H.get_json(a, 'supports').size
  end

  def test_pipe_drawn_next_to_supports_is_taken_in
    a = run_at(0)
    SupportBuilder.place(@model, 'hframe', hit_on(a, 2000)) # frame for one pipe
    SupportBuilder.place(@model, 'clevis', hit_on(a, 4500)) # single hanger
    assert_equal 1, shared.size
    # draw a second pipe beside them with the pipe tool
    t = PipeTool.new
    t.activate
    [[0, 300, 1000], [6000, 300, 1000]].each do |p|
      Sketchup::InputPoint.next_position = H.to_pt(p)
      t.onMouseMove(0, 0, 0, @model.active_view)
      t.onLButtonDown(0, 0, 0, @model.active_view)
    end
    t.onReturn(@model.active_view)
    assert_equal 2, shared.size, 'H-frame widened, hanger became a trapeze'
    assert(shared.all? { |g| H.get_json(g, 'members').size == 2 })
    assert_equal %w[hframe trapeze], shared.map { |g| g.get_attribute(H::DICT, 'support_type') }.sort
    assert_empty H.get_json(a, 'supports', []), 'the single hanger was replaced'
  end

  # A hanger beside a second pipe became a trapeze whose rods had no
  # length – the search for the structure started at the pipe bottom and
  # stopped on what the pipes rest on there.
  def test_trapeze_rods_reach_the_structure_even_when_the_pipes_touch_something
    @model.ray_hits = lambda do |pt, dir|
      next nil unless dir[2] > 0.5
      next [pt, []] if (pt[2] - (1000 - 30.15)).abs < 1.0 # a face touching the pipe bottoms

      [[pt[0], pt[1], 4000.0], []]
    end
    a = run_at(0)
    run_at(250)
    assert_nil SupportBuilder.place(@model, 'clevis', hit_on(a, 3000))
    g = shared.first
    assert_equal 'trapeze', g.get_attribute(H::DICT, 'support_type')
    assert_in_delta 2 * (3000 + 30.15), g.get_attribute(H::DICT, 'rod_length_mm'), 1.0
  end

  def beams(run)
    H.get_json(run, 'supports', []).select { |r| r['type'] == 'beam' }
  end

  # Beam clamps are hung one per pipe: clicking one of two pipes side by
  # side hangs both, each from its own clamp and sized for its own pipe.
  def test_beam_clamp_hangs_each_neighbour_separately
    a = run_at(0, size: '4"')
    b = run_at(250)
    assert_nil SupportBuilder.place(@model, 'beam', hit_on(a, 3000))
    assert_empty shared, 'no trapeze'
    assert_equal 1, beams(a).size
    assert_equal 1, beams(b).size
    assert_in_delta 3000.0, beams(b).first['at'][0], 1.0
    assert_in_delta 250.0, beams(b).first['at'][1], 1.0
    assert_in_delta 4000.0, beams(b).first['target'][2], 1.0, 'its own rod up to the slab'
    # each rendered for its own size (4" and 2" rods / clamps)
    sizes = [a, b].map { |r| r.entities.select { |e| H.type_of(e) == 'support' }.map { |e| e.get_attribute(H::DICT, 'pipe_size') } }
    assert_equal [['4"'], ['2"']], sizes
    # clicking the same place again adds nothing
    SupportBuilder.place(@model, 'beam', hit_on(b, 3100))
    assert_equal [1, 1], [beams(a).size, beams(b).size]
  end

  def test_auto_beam_clamps_pair_up_along_two_pipes
    a = run_at(0, size: '4"')
    b = run_at(250)
    c = run_at(1500) # too far – on its own
    @model.selection.push(a)
    @model.selection.push(b)
    H.save_settings(@s.merge('support_type' => 'beam'))
    Commands.auto_supports
    assert_empty shared
    xa = beams(a).map { |r| r['at'][0].round }.sort
    xb = beams(b).map { |r| r['at'][0].round }.sort
    refute_empty xa
    xa.each { |x| assert(xb.any? { |y| (y - x).abs <= 1 }, "pipe b hung at #{x} too") }
    [xa, xb].each { |xs| xs.each_cons(2) { |p, q| assert_operator q - p, :>, SupportBuilder::COVER, 'no doubles' } }
    span_b = Supports.max_span_m(Catalog.spec('CS_B36_10', '2"')) * 1000
    xb.each_cons(2) { |p, q| assert_operator q - p, :<=, span_b + 1.0 }
    assert_empty beams(c)
  end

  def test_pipe_drawn_beside_beam_clamps_gets_its_own
    a = run_at(0)
    SupportBuilder.place(@model, 'beam', hit_on(a, 2000))
    t = PipeTool.new
    t.activate
    [[0, 300, 1000], [6000, 300, 1000]].each do |p|
      Sketchup::InputPoint.next_position = H.to_pt(p)
      t.onMouseMove(0, 0, 0, @model.active_view)
      t.onLButtonDown(0, 0, 0, @model.active_view)
    end
    t.onReturn(@model.active_view)
    b = Collector.all_runs(@model).map(&:first).find { |r| r != a }
    assert_equal 1, beams(b).size
    assert_in_delta 2000.0, beams(b).first['at'][0], 1.0
    assert_empty shared
  end

  def test_no_beam_clamp_under_a_pipe_above
    a = run_at(0, 1000)
    b = run_at(0, 1200) # right above a
    SupportBuilder.place(@model, 'beam', hit_on(b, 3000))
    assert_equal 1, beams(b).size
    assert_empty beams(a), 'its rod would pass through the pipe above'
  end

  def test_column_bracket_carries_the_pipes_beside_it
    a = run_at(0)
    run_at(300)
    SupportBuilder.place(@model, 'bracket', hit_on(a, 3000))
    g = shared.first
    assert_equal 'bracket', g.get_attribute(H::DICT, 'support_type')
    assert_equal 2, H.get_json(g, 'members').size
    # arm from the column (y = −600) past the far pipe (y = 300 + r + 60)
    assert_operator g.get_attribute(H::DICT, 'member_length_mm'), :>, (600 + 300 + 30 + 60) * 1.7 - 1
  end

  def test_higher_neighbour_is_shared_lower_than_limit_only
    a = run_at(0)
    run_at(300, 1150)   # 150 mm higher – on a packer
    run_at(-300, 1800)  # 800 mm higher – its own support
    SupportBuilder.place(@model, 'stand', hit_on(a, 3000))
    assert_equal 2, H.get_json(shared.first, 'members').size
  end

  def test_auto_supports_share_and_do_not_double_up
    a = run_at(0)
    b = run_at(300)
    @model.selection.push(a)
    @model.selection.push(b)
    H.save_settings(@s.merge('support_type' => 'stand'))
    Commands.auto_supports
    refute_empty shared
    assert(shared.all? { |g| H.get_json(g, 'members').size == 2 })
    assert_empty H.get_json(a, 'supports', [])
    assert_empty H.get_json(b, 'supports', []), 'b is already carried by the shared frames'
    xs = shared.map { |g| JSON.parse(g.get_attribute(H::DICT, 'at'))[0] }.sort
    span = Supports.max_span_m(Catalog.spec('CS_B36_10', '2"')) * 1000
    assert(xs.each_cons(2).all? { |p, q| q - p <= span + 1e-6 })
  end

  def test_clear_removes_shared_supports_of_the_selection
    a = run_at(0)
    b = run_at(300)
    SupportBuilder.place(@model, 'stand', hit_on(a, 3000))
    @model.selection.push(a)
    @model.selection.push(b)
    Commands.clear_supports
    assert_empty shared
  end

  # Ray against axis-aligned boxes [min, max] (mm): nearest exit/entry.
  def box_rays(boxes)
    lambda do |pt, dir|
      best = nil
      boxes.each do |mn, mx|
        t0 = -Float::INFINITY
        t1 = Float::INFINITY
        ok = (0..2).all? do |i|
          if dir[i].abs < 1e-9
            pt[i].between?(mn[i], mx[i])
          else
            a = (mn[i] - pt[i]) / dir[i]
            b = (mx[i] - pt[i]) / dir[i]
            a, b = b, a if a > b
            t0 = [t0, a].max
            t1 = [t1, b].min
            t0 <= t1
          end
        end
        next unless ok

        t = t0 > 1e-6 ? t0 : t1
        next unless t > 1e-6

        best = t if best.nil? || t < best
      end
      best && [pt.each_with_index.map { |c, i| c + dir[i] * best }, []]
    end
  end

  # The user's case: a pipe pair along a wall passing a column; the
  # bracket is bolted to the column's side face and its arm runs past the
  # column under both pipes.
  def test_column_side_bracket_carries_both_pipes_from_the_column_face
    column = [[2900.0, -900.0, -2000.0], [3100.0, -500.0, 3000.0]] # 200 along the pipes, 400 deep
    wall = [[-5000.0, 400.0, -2000.0], [9000.0, 500.0, 3000.0]]     # wall on the other side
    @model.ray_hits = box_rays([column, wall])
    a = run_at(0)
    run_at(250)
    note = SupportBuilder.place(@model, 'column', hit_on(a, 3080))
    assert_nil note
    g = shared.first
    assert_equal 'column', g.get_attribute(H::DICT, 'support_type')
    assert_equal 2, H.get_json(g, 'members').size, 'both pipes on the arm'
    at = JSON.parse(g.get_attribute(H::DICT, 'at'))
    # just outside the column face nearer the click (x = 3100), plate + half arm
    assert_in_delta 3100 + Supports::COLUMN_PLATE + Supports::COLUMN_ARM / 2, at[0], 0.5
    assert_operator g.get_attribute(H::DICT, 'member_length_mm'), :>, 500 + 250 + 30 + 60
    # the column side is found even though the wall is nearer on the other side
    col = SupportBuilder.find_column(@model, [3080.0, 0.0, 1000.0], [1.0, 0, 0])
    assert_in_delta 500.0, col[:wall], 0.5
    assert_in_delta 400.0, col[:depth], 0.5
  end

  def test_column_bracket_needs_a_column
    @model.ray_hits = box_rays([[[-5000.0, 400.0, -2000.0], [9000.0, 500.0, 3000.0]]]) # only a long wall
    a = run_at(0)
    assert_raises(RuntimeError) { SupportBuilder.place(@model, 'column', hit_on(a, 3000)) }
  end
end
