# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'su_stub'

module ArtK
  module PlantPipe
    PLUGIN_ROOT = File.expand_path('../src/artk_plant_pipe', __dir__) unless defined?(PLUGIN_ROOT)
    VERSION = 'test' unless defined?(VERSION)
  end
end
%w[model_helpers migrate builder ref_models ref_builder support_builder collector picker reports commands pipe_tool support_tool run_editor].each do |f|
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

  # v1.8 left its own meter geometry in the file under the same name;
  # opening the file must replace it (it was reused unchanged in v1.9).
  def test_v1_8_meter_in_the_file_is_rebuilt_on_open
    s = Settings.sanitize('service' => 'CW', 'catalog' => 'CS_B36_10', 'size' => '4"', 'lod' => 'detailed')
    run, = Builder.create_run(@model, [[[0, 0, 0], [3000, 0, 0]]], s)
    base = Refs.items.find { |i| i['type'] == 'water_meter' }
    v = Builder.add_valve(@model, run, 'water_meter', [1500.0, 0, 0], [1.0, 0, 0], model_key: base['key'])
    d = v.definition
    # turn it into what v1.8 stored: no revision, painted blue body
    d.entities.clear!
    d.dicts[H::DICT].delete('rev')
    old = @model.materials.add('PP_Src Woltman Body Blue')
    d.entities.add_face([H.to_pt([0, 0, 0]), H.to_pt([10, 0, 0]), H.to_pt([0, 10, 0])]).material = old
    dial = @model.materials.add('PP_Src водяной счетчик')
    dial.color = Sketchup::Color.new(223, 224, 223) # tinted by v1.8

    res = Migrate.model(@model)
    assert_equal 1, res[:parts]
    assert_equal MeterModels::REV, d.get_attribute(H::DICT, 'rev')
    faces = d.entities.grep(Sketchup::Face)
    assert_operator faces.size, :>, 500, 'full bolting geometry'
    assert(faces.none? { |f| f.material == old }, 'old blue paint gone – valve colour')
    assert dial.get_attribute(H::DICT, 'clean_texture')
    refute_nil dial.texture
    assert_equal 0, Migrate.model(@model)[:parts], 'nothing left to do on the next open'
  end

  def test_corrected_library_part_is_rebuilt_on_open
    item = Refs.get('piping:gi_thrd/steam_trap/-/3/4"')
    d = RefModels.definition(@model, item)
    d.set_attribute(H::DICT, 'rev', 1) # as built before the correction
    assert_equal 1, Migrate.model(@model)[:parts]
    assert_equal 2, d.get_attribute(H::DICT, 'rev')
    assert_equal 0, Migrate.model(@model)[:parts]
  end

  # The user (1.17.0): steam / hot water drawn with 100 insulation (read as
  # 2" × 2 layers) – the BOQ says 1-1/2" (38.1) one layer. A file from
  # before, opened once and asked once: those runs take 38.1 and drop by
  # the difference so the insulation's underside stays on the supports; a
  # run tied to another keeps its centre line; other runs are left alone.
  def test_old_100_insulation_becomes_one_and_a_half_inch_on_open
    s = Settings.sanitize('service' => 'HW', 'catalog' => 'CS_B36_10', 'size' => '4"', 'insulation_mm' => 100)
    run, = Builder.create_run(@model, [[[0, 0, 3000], [5000, 0, 3000]], [[5000, 0, 3000], [5000, 0, 1000]]], s)
    main, = Builder.create_run(@model, [[[0, 3000, 3000], [8000, 3000, 3000]]], s.merge('insulation_mm' => 101.6))
    tee = { 'at' => [4000.0, 3000.0, 3000.0], 'main_dir' => [1.0, 0, 0], 'main_catalog' => 'CS_B36_10',
            'main_size' => '4"', 'main_rating' => 'SCH40', 'main_service' => 'HW', 'main_pid' => main.persistent_id }
    branch, = Builder.create_run(@model, [[[4000.0, 3000.0, 3000.0], [4000, 6000, 3000]]], s.merge('size' => '2"'), tees: [tee])
    thin, = Builder.create_run(@model, [[[0, 9000, 3000], [4000, 9000, 3000]]], s.merge('insulation_mm' => 25))
    @model.delete_attribute(H::DICT, Migrate::SPEC_KEY) # a file from before 1.17
    keep = H.get_json(thin, 'cl')
    UI.messages.clear
    res = Migrate.model(@model)
    assert_equal 3, res[:respec]
    assert_equal 1, UI.messages.size, 'asked once'
    assert_match(%r{1-1/2"}, UI.messages.first)
    [run, main, branch].each { |r| assert_in_delta 38.1, Builder.run_settings(r)['insulation_mm'], 1e-6 }
    zs = H.get_json(run, 'cl').flatten(1).map { |p| p[2].to_f.round(1) }.uniq.sort
    assert_equal [1000.0 - 61.9, 3000.0 - 61.9], zs, 'lowered: the insulation underside where it was'
    assert_equal [3000.0], H.get_json(main, 'cl').flatten(1).map { |p| p[2].to_f.round(1) }.uniq, 'branched: centre line kept'
    assert_equal [3000.0], H.get_json(branch, 'cl').flatten(1).map { |p| p[2].to_f.round(1) }.uniq, 'on its main: kept'
    assert_equal keep, H.get_json(thin, 'cl')
    assert_in_delta 25, Builder.run_settings(thin)['insulation_mm'], 1e-6
    UI.messages.clear
    assert_equal 0, Migrate.model(@model)[:respec]
    assert_empty UI.messages, 'not asked again'
  end

  # The user's stored setting (100 – 2" × 2 read wrong) becomes 1-1/2"
  # once; hot services start at 1-1/2" (the BOQ's fiberglass, 1.17.0).
  def test_stored_100_insulation_setting_becomes_one_and_a_half_inch
    stored = Settings.sanitize('service' => 'HW', 'catalog' => 'CS_B36_10', 'size' => '4"', 'insulation_mm' => 100)
    Sketchup.write_default(H::PREF, 'settings_b64', [JSON.generate(stored)].pack('m0'))
    Sketchup.write_default(H::PREF, H::SPEC_PREF, nil)
    H.reset_settings_cache!
    assert_in_delta 38.1, H.load_settings['insulation_mm'], 1e-6
    H.save_settings(H.load_settings.merge('insulation_mm' => 100))
    H.reset_settings_cache!
    assert_in_delta 100, H.load_settings['insulation_mm'], 1e-6, 'set again on purpose: kept'
    %w[STM HW HWR CON].each { |c| assert_in_delta 38.1, Services.get(c)[:insulation], 1e-6, c }
  ensure
    Sketchup.write_default(H::PREF, 'settings_b64', nil)
    H.reset_settings_cache!
  end

  # Drafts drawn by 1.20.0 as coloured rods become the isometric single
  # line on open (1.20.1, "เส้นแบบที่ทำมาให้ดูไม่มืออาชีพ").
  def test_rod_drafts_redrawn_as_lines_on_open
    s = Settings.sanitize('service' => 'CW', 'catalog' => 'CS_B36_10', 'size' => '1"', 'draft' => true)
    run, = Builder.create_run(@model, [[[0, 0, 3000], [5000, 0, 3000]], [[5000, 0, 3000], [5000, 3000, 3000]]], s)
    knuckle = run.entities.add_group
    H.set_attrs(knuckle, 'type' => 'draft_node') # as 1.20.0 left it
    assert_equal 1, Migrate.model(@model)[:insulated]
    assert(run.entities.none? { |e| e.valid? && H.type_of(e) == 'draft_node' })
    assert_equal 2, count(run, 'draft_pipe')
    assert_equal 0, Migrate.model(@model)[:insulated], 'once'
  end

  # Drawn with 1.17 on purpose: 100 stays 100.
  def test_new_100_insulation_is_left_alone
    s = Settings.sanitize('service' => 'HW', 'catalog' => 'CS_B36_10', 'size' => '4"', 'insulation_mm' => 100)
    run, = Builder.create_run(@model, [[[0, 0, 3000], [5000, 0, 3000]]], s)
    UI.messages.clear
    assert_equal 0, Migrate.model(@model)[:respec]
    assert_empty UI.messages
    assert_in_delta 100, Builder.run_settings(run)['insulation_mm'], 1e-6
  end

  # Answered no: nothing changes, not asked again.
  def test_old_100_insulation_kept_when_declined
    s = Settings.sanitize('service' => 'HW', 'catalog' => 'CS_B36_10', 'size' => '4"', 'insulation_mm' => 100)
    run, = Builder.create_run(@model, [[[0, 0, 3000], [5000, 0, 3000]]], s)
    @model.delete_attribute(H::DICT, Migrate::SPEC_KEY)
    UI.answer = 7 # IDNO
    assert_equal 0, Migrate.model(@model)[:respec]
    assert_in_delta 100, Builder.run_settings(run)['insulation_mm'], 1e-6
    UI.messages.clear
    Migrate.model(@model)
    assert_empty UI.messages
  ensure
    UI.answer = nil
  end

  # The user (1.16.5): runs drawn with 1.16.4 and before left thick
  # insulation off their elbows (a BOM record instead); installing the
  # update covers them on open – no redrawing.
  def test_bare_elbows_of_old_runs_insulated_on_open
    s = Settings.sanitize('service' => 'HW', 'catalog' => 'CS_B36_10', 'size' => '4"', 'insulation_mm' => 100)
    run, = Builder.create_run(@model, [[[0, 0, 3000], [5000, 0, 3000]], [[5000, 0, 3000], [5000, 4000, 3000]]], s)
    other, = Builder.create_run(@model, [[[0, 900, 0], [3000, 900, 0]]], s.merge('insulation_mm' => 0))
    # as 1.16.4 left it: the elbow's insulation a BOM record, not drawn
    cover = run.entities.find { |e| H.type_of(e) == 'insulation' && e.get_attribute(H::DICT, 'length_mm') < 300 }
    run.entities.erase_entities(cover)
    H.set_json(run, 'extras', [H.attrs(cover).merge('type' => 'insulation', 'thickness' => 100, 'length_mm' => 239.4)])
    pid = run.persistent_id
    before = other.entities.to_a
    res = Migrate.model(@model)
    assert_equal 1, res[:insulated]
    assert_equal 3, count(run, 'insulation'), 'the elbow covered'
    assert_empty H.get_json(run, 'extras', []).select { |x| x['type'] == 'insulation' }
    assert_equal pid, run.persistent_id, 'the same run (supports keep their link)'
    assert_equal before, other.entities.to_a, 'other runs untouched'
    assert_equal 0, Migrate.model(@model)[:insulated], 'nothing left to do on the next open'
  end
end
