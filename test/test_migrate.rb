# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'su_stub'

module ArtK
  module PlantPipe
    PLUGIN_ROOT = File.expand_path('../src/artk_plant_pipe', __dir__) unless defined?(PLUGIN_ROOT)
    VERSION = 'test' unless defined?(VERSION)
  end
end
%w[model_helpers migrate builder ref_models ref_builder support_builder collector picker reports commands pipe_tool support_tool].each do |f|
  require File.expand_path("../src/artk_plant_pipe/su/#{f}", __dir__)
end

# Drawings made with older versions must keep working after an update.
# fixtures/v1_6_0_model.json holds exactly what v1.6.0 stored for two runs
# (2" GI with a water meter, a gate valve and an elbow; a 1" branch).
class TestMigrate < Minitest::Test
  H = ModelHelpers
  FIXTURE = File.expand_path('fixtures/v1_6_0_model.json', __dir__)

  def setup
    @model = Sketchup::Model.new
    Sketchup.active_model = @model
    Sketchup::InputPoint.next_vertex = nil
    Sketchup::InputPoint.next_dof = nil
  end

  # The model as it is reopened: groups carrying the old attributes.
  def load_old_model
    JSON.parse(File.read(FIXTURE))['runs'].map do |r|
      g = @model.active_entities.add_group
      H.set_attrs(g, r['run'])
      r['pieces'].each { |a| H.set_attrs(g.entities.add_group, a) }
      g
    end
  end

  def runs
    Collector.all_runs(@model).map(&:first)
  end

  def count(run, type)
    run.entities.count { |e| H.instance?(e) && H.type_of(e) == type }
  end

  def test_upgrade_steps_exist_for_every_old_format
    (1...DataFormat::CURRENT).each { |v| assert DataFormat::STEPS.key?(v), "no step from format #{v}" }
    out, st = DataFormat.upgrade('type' => 'run', 'cl' => '[]')
    assert_equal :upgraded, st
    assert_equal DataFormat::CURRENT, out['fmt']
    assert_equal '[]', out['cl'], 'data kept'
    assert_equal :newer, DataFormat.upgrade('fmt' => DataFormat::CURRENT + 1)[1]
  end

  def test_v1_6_model_opens_rebuilds_and_keeps_everything
    main, branch = load_old_model
    res = Migrate.model(@model)
    assert_equal 2, res[:upgraded]
    assert_equal DataFormat::CURRENT, main.get_attribute(H::DICT, 'fmt')
    assert_equal DataFormat::CURRENT, @model.get_attribute(H::DICT, 'fmt')
    runs.each { |r| Builder.render(@model, r, Builder.run_settings(r)) }
    assert_equal 2, count(main, 'valve'), 'meter and gate valve kept'
    assert_equal 1, count(main, 'elbow')
    assert_equal 1, count(branch, 'tee')
    meter = main.entities.find { |e| e.get_attribute(H::DICT, 'valve_type') == 'water_meter' }
    assert_includes meter.definition.name, '@DN50', 'old meter now in its standard size'
    assert_equal 'PP_Custom_00aa00', main.entities.find { |e| H.type_of(e) == 'pipe' }.material.name, 'own colour kept'
    assert_equal 0, Migrate.model(@model)[:upgraded], 'second open: nothing to do'
  end

  def test_new_version_draws_onto_old_runs
    main, branch = load_old_model
    Migrate.model(@model)
    t = PipeTool.new
    view = @model.active_view
    click = lambda do |p|
      Sketchup::InputPoint.next_position = H.to_pt(p)
      t.onMouseMove(0, 0, 0, view)
      t.onLButtonDown(0, 0, 0, view)
    end
    # same size from the old run's open end → that run continues
    H.save_settings(Builder.run_settings(main))
    t.activate
    click.call([4000, 3000, 0])
    click.call([6000, 3000, 0])
    t.onReturn(view)
    assert_equal 2, runs.size
    assert_equal 2, count(main, 'elbow')
    # from the middle of the old 2" pipe → tee onto it
    H.save_settings(Builder.run_settings(branch))
    t.resume(view)
    click.call([1000, 40, 0])
    click.call([1000, -2000, 0])
    t.onReturn(view)
    assert_equal 3, runs.size
    assert_equal 1, count(runs.last, 'tee')
  end

  def test_runs_from_a_newer_version_are_left_alone
    main, = load_old_model
    main.set_attribute(H::DICT, 'fmt', DataFormat::CURRENT + 1)
    before = main.entities.to_a.size
    assert_equal 1, Migrate.model(@model)[:newer]
    w = Builder.render(@model, main, Builder.run_settings(main))
    assert_includes w.first, 'เวอร์ชันใหม่กว่า'
    assert_equal before, main.entities.to_a.size, 'not cleared'
    assert_equal DataFormat::CURRENT + 1, main.get_attribute(H::DICT, 'fmt')
  end
end
