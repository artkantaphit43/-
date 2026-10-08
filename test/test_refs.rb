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
   ref_browser].each do |f|
  require File.expand_path("../src/artk_plant_pipe/su/#{f}", __dir__)
end

# Reference-library placement: parts fit the pipe they are put on.
class TestRefs < Minitest::Test
  H = ModelHelpers

  def setup
    @model = Sketchup::Model.new
    Sketchup.active_model = @model
  end

  def item(type)
    Refs.items.find { |i| i['type'] == type && !i['ports'].empty? }
  end

  def test_new_parts_are_in_the_library_with_their_connections
    meter = item('water_meter')
    tap = item('faucet')
    gauges = Refs.items.select { |i| i['type'] == 'gauge' && i['src'] == 'gauge' }
    assert_equal 2, meter['ports'].size
    assert_equal :inline, Refs.mount(meter)
    assert_equal :end, Refs.mount(tap)
    assert_equal 5, gauges.size
    assert(gauges.all? { |g| Refs.mount(g) == :top })
    # faucet brought to real size from its ½" BSP thread (model was ~12× too big)
    assert_in_delta 20.96, tap['ports'][0]['ri'] * 2, 0.05
    assert_operator tap['bbox'][1][0] - tap['bbox'][0][0], :<, 150
  end

  def test_every_electric_butterfly_has_full_bore_ends
    Refs.items.select { |i| i['operator'] == 'actuator' }.each do |i|
      refute_empty i['ports'], i['key']
      assert_in_delta i['dn'], i['ports'][0]['ri'] * 2, 1.0, i['key']
    end
  end

  def test_variant_of_the_pipe_size_is_used_when_it_exists
    two = Refs.items.find { |i| i['key'] == 'valves:jis10k/butterfly/lever/2"' }
    spec = Catalog.spec('CS_B36_10', '4"')
    v = Refs.variant_for(two, spec)
    assert_equal '4"', v['size']
    assert_equal 'jis10k', v['family']
    assert_equal 1.0, Refs.scale_for(v, spec.od)
  end

  def test_single_size_parts_scale_to_the_pipe
    meter = item('water_meter')
    assert_equal 1.0, Refs.scale_for(meter, 21.4)
    assert_in_delta 60.3 / 21.4, Refs.scale_for(meter, 60.3), 1e-9
  end

  def test_port_frame_puts_the_end_circle_on_the_pipe_end
    tap = item('faucet')
    e = [1000.0, 200.0, 300.0]
    u = [0.0, 1.0, 0.0]
    k = 2.0
    f = Refs.port_frame(tap, 0, e, u, [0.0, 0.0, 1.0], k)
    p = tap['ports'][0]
    world = ->(q) { Vec.add(f[:o], Vec.add(Vec.add(Vec.scale(f[:x], q[0] * k), Vec.scale(f[:y], q[1] * k)), Vec.scale(f[:z], q[2] * k))) }
    assert Vec.near?(world.call(p['p']), e, 1e-6)
    dir = Vec.add(Vec.add(Vec.scale(f[:x], p['d'][0]), Vec.scale(f[:y], p['d'][1])), Vec.scale(f[:z], p['d'][2]))
    assert Vec.near?(dir, [0.0, -1.0, 0.0], 1e-6), 'port faces into the pipe'
  end

  def test_socket_mouth_sits_back_by_the_socket_depth
    el = Refs.items.find { |i| i['family'] == 'pvc_tis' && i['type'] == 'elbow90' && i['size'] == '2"' }
    m = Refs.mouth_point(el, 0, [0.0, 0.0, 0.0], [1.0, 0.0, 0.0])
    assert_in_delta(-el['ports'][0]['depth'], m[0], 1e-9)
  end

  def test_meter_takes_its_iso4064_size_not_a_blown_up_copy
    s = Settings.sanitize('service' => 'CW', 'catalog' => 'PVC_TIS17', 'size' => '2"')
    run, = Builder.create_run(@model, [[[0, 0, 0], [3000, 0, 0]]], s)
    meter = item('water_meter')
    v = Builder.add_valve(@model, run, 'water_meter', [1500.0, 0, 0], [1.0, 0, 0], model_key: meter['key'])
    assert_equal meter['key'], v.get_attribute(H::DICT, 'model'), 'base key stored – rebuilds find it'
    sized = Refs.sized_item(meter, Settings.spec(s))
    assert_equal 50, sized['dn']
    a, b = sized['ports'].map { |p| H.transform_mm(v.transformation, p['p']) }
    # ISO 4064 DN50 L = 300 (the ½" model's 165 → 166.9 incl. tails)
    assert_in_delta 300.0 * 166.88 / 165.0, Vec.dist(a, b), 0.05
    assert Vec.near?(Vec.scale(Vec.add(a, b), 0.5), [1500.0, 0, 0], 0.01), 'ends on the pipe axis'
    # register grows as real meters do (×1.79), not with the pipe (×2.8)
    mn, mx = sized['bbox']
    assert_in_delta 81.8 * 1.79, mx[2] - mn[2], 1.0
    assert_in_delta 60.0 / 21.4 * 12.0, sized['ports'][0]['ri'], 0.01, 'tail fits the pipe'
    assert_includes v.definition.name, '@DN50'
  end

  def test_meter_sizes_follow_the_standard_table
    meter = item('water_meter')
    gap = lambda do |cat, size|
      it = Refs.sized_item(meter, Catalog.spec(cat, size))
      it && Vec.dist(*it['ports'].map { |p| p['p'] })
    end
    assert_in_delta 166.88, gap.call('GSP_BS1387', '1/2"'), 0.01, '½" is the model itself'
    assert_in_delta 190 * 166.88 / 165, gap.call('GSP_BS1387', '3/4"'), 0.01
    assert_in_delta 260 * 166.88 / 165, gap.call('HDPE_PE100', '32 mm'), 0.01, 'metric pipe → DN25'
    assert_equal 225.0, gap.call('CS_B36_10', '3"'), 'DN80 Woltman, ISO 4064'
    assert_nil gap.call('CS_B36_10', '14"'), 'no meter above DN300'
  end

  def test_big_pipe_gets_a_flanged_woltman_meter_that_snaps
    s = Settings.sanitize('service' => 'CW', 'catalog' => 'CS_B36_10', 'size' => '4"')
    run, = Builder.create_run(@model, [[[0, 0, 0], [3000, 0, 0]]], s)
    tool = RefPlaceTool.new(item('water_meter'))
    tool.instance_variable_set(:@model, @model)
    tool.instance_variable_set(:@angle, 0.0)
    pl = tool.placement([1500.0, 0.0, 30.0])
    assert_equal :inline, pl[:mode]
    it = pl[:item]
    assert_equal 'woltman', it['generated']
    assert_equal 250.0, Vec.dist(*it['ports'].map { |p| p['p'] }), 'ISO 4064 DN100 L = 250'
    assert_in_delta 220.0, it['bbox'][1][2] - it['bbox'][0][2], 0.5, 'PN16 DN100 flange Ø220'
    assert_equal 'valve_cast', it['material'], 'same colour as the valves'
    v = Builder.add_valve(@model, run, 'water_meter', pl[:at], [1.0, 0, 0], model_key: item('water_meter')['key'])
    assert_equal item('water_meter')['key'], v.get_attribute(H::DICT, 'model')
    assert_equal 'Flanged PN16', v.get_attribute(H::DICT, 'end_type')
    assert_equal 2, run.entities.count { |e| H.type_of(e) == 'flange' }, 'companion flanges on the pipe'
    Builder.render(@model, run, s)
    assert_equal 1, run.entities.count { |e| H.type_of(e) == 'valve' }
    assert_includes run.entities.find { |e| H.type_of(e) == 'valve' }.definition.name, 'woltman@DN100'
  end

  def test_woltman_meshes_are_closed_and_sized
    MeterModels.sizes.each do |dn|
      m = MeterModels.woltman(dn, 100.0)
      assert m[:faces].all? { |f| f[:loops].all? { |l| l.uniq.size >= 3 } }, "DN#{dn} degenerate face"
      xs = m[:verts].map(&:first)
      assert_operator xs.max - xs.min, :>=, MeterModels.length(dn), "DN#{dn} laying length (+ bolts)"
      assert m[:faces].any? { |f| f[:pins] }, 'dial image'
      assert m[:faces].any? { |f| f[:mat].nil? }, 'body takes the valve colour'
    end
  end

  def test_woltman_bolts_go_through_the_companion_flange_holes
    spec = Catalog.spec('CS_B36_10', '4"')
    it = Refs.sized_item(item('water_meter'), spec)
    fl = Refs.companion_flange(spec, it)
    mate = Refs.flange_bolting(fl)
    assert_equal 8, mate['angles'].size
    assert_in_delta 180.0, mate['pcd'], 0.5, 'PN16 DN100 bolt circle'
    m = Refs.mesh(it)
    half = it['ports'][1]['p'][0]
    # bolt heads sit on the companion flange back, on its hole circle
    heads = m[:verts].select { |x, _y, _z| x > half + mate['thick'] + 1.0 }
    refute_empty heads
    angles = heads.map { |_x, y, z| Math.atan2(z, y) }
    mate['angles'].each do |a|
      assert(angles.any? { |b| ((b - a + Math::PI) % (2 * Math::PI) - Math::PI).abs < 0.05 }, "bolt at #{a}")
    end
    assert(heads.all? { |_x, y, z| (Math.hypot(y, z) - mate['pcd'] / 2.0).abs < 25.0 }, 'heads on the bolt circle')
  end

  def test_meter_on_a_too_big_pipe_is_not_snapped
    s = Settings.sanitize('service' => 'CW', 'catalog' => 'CS_B36_10', 'size' => '14"')
    Builder.create_run(@model, [[[0, 0, 0], [3000, 0, 0]]], s)
    tool = RefPlaceTool.new(item('water_meter'))
    tool.instance_variable_set(:@model, @model)
    tool.instance_variable_set(:@angle, 0.0)
    pl = tool.placement([1500.0, 0.0, 30.0])
    assert_equal :free, pl[:mode]
    assert_includes pl[:tip], 'ขนาดมาตรฐาน'
  end

  def test_old_meter_on_a_too_big_pipe_survives_a_rebuild
    s = Settings.sanitize('service' => 'CW', 'catalog' => 'CS_B36_10', 'size' => '14"')
    run, = Builder.create_run(@model, [[[0, 0, 0], [3000, 0, 0]]], s)
    meter = item('water_meter')
    Builder.add_valve(@model, run, 'water_meter', [1500.0, 0, 0], [1.0, 0, 0], model_key: meter['key'])
    warnings = Builder.render(@model, run, s)
    assert_equal 1, run.entities.count { |e| H.type_of(e) == 'valve' }, 'kept, never dropped'
    assert(warnings.any? { |w| w.include?('ไม่มีขนาดมาตรฐาน') })
  end

  def test_placing_a_faucet_at_a_pipe_end
    s = Settings.sanitize('service' => 'CW', 'catalog' => 'GSP_BS1387', 'size' => '1"')
    Builder.create_run(@model, [[[0, 0, 0], [2000, 0, 0]]], s)
    tool = RefPlaceTool.new(item('faucet'))
    tool.instance_variable_set(:@model, @model)
    tool.instance_variable_set(:@angle, 0.0)
    pl = tool.placement([1990.0, 0.0, 10.0])
    assert_equal :end, pl[:mode]
    assert_equal 1.0, pl[:k]
    assert_equal 25, pl[:item]['dn']
    assert_in_delta 1.3 * 10.48, pl[:item]['ports'][0]['ri'], 1e-6, '1" bib tap'
    p = pl[:item]['ports'][0]['p']
    f = pl[:frame]
    at = Vec.add(f[:o], Vec.add(Vec.add(Vec.scale(f[:x], p[0]), Vec.scale(f[:y], p[1])), Vec.scale(f[:z], p[2])))
    assert Vec.near?(at, [2000.0, 0.0, 0.0], 0.01), at.inspect
    assert Vec.near?(f[:y], [0.0, 0.0, 1.0], 1e-6), 'spout hangs down (canonical +Y up)'
    assert_nil Refs.sized_item(item('faucet'), Catalog.spec('GSP_BS1387', '2"')), 'no 2" bib tap'
  end

  def test_gauge_mounts_on_top_of_the_pipe_at_its_own_size
    s = Settings.sanitize('service' => 'CW', 'catalog' => 'CS_B36_10', 'size' => '4"')
    Builder.create_run(@model, [[[0, 0, 0], [3000, 0, 0]]], s)
    g = Refs.items.find { |i| i['type'] == 'gauge' && i['src'] == 'gauge' }
    tool = RefPlaceTool.new(g)
    tool.instance_variable_set(:@model, @model)
    tool.instance_variable_set(:@angle, 0.0)
    pl = tool.placement([1500.0, 0.0, 60.0])
    assert_equal :top, pl[:mode]
    assert_equal 1.0, pl[:k]
    assert Vec.near?(pl[:frame][:o], [1500.0, 0.0, 114.3 / 2], 0.01), pl[:frame][:o].inspect
    assert Vec.near?(pl[:frame][:x], [0.0, 0.0, 1.0], 1e-6)
  end

  def test_dial_texture_is_positioned_on_its_face
    meter = item('water_meter')
    m = Refs.mesh(meter)
    dial = m[:faces].find { |f| f[:pins] }
    refute_nil dial
    assert File.exist?(Refs.texture_path(dial[:mat]))
    ents = Sketchup::Entities.new
    RefModels.fill(@model, ents, m)
    assert(ents.grep(Sketchup::Face).any?(&:pins), 'position_material called with pins')
    mat = @model.materials.find { |x| x.texture }
    assert_nil mat.color, 'no colour on the dial – SketchUp would tint the image'
  end

  # Library audit (1.11): repaired items, hidden duplicates, size filter.
  def test_repaired_library_items_have_their_ends
    tee = Refs.get('pvc:pvc_tis/tee/-/1-1/4"')
    assert_equal 3, tee['ports'].size
    assert_equal tee['ports'][1]['depth'], tee['ports'][0]['depth'], 'run sockets equally deep'
    assert_equal 2, Refs.get('pvc:pvc_tis_dwv/u_trap/-/2"')['ports'].size
    assert_equal 3, Refs.get('pvc:pvc_tis_dwv/wye/-/2"')['ports'].size, 'run end without its end face found'
    trap = Refs.get('piping:gi_thrd/steam_trap/-/3/4"')
    assert_in_delta 150.0, Vec.dist(*trap['ports'].map { |p| p['p'] }), 0.5, 'ends at the body, as the other sizes'
    assert_equal 2, Refs.geometry_rev(trap)
    refute_nil Refs.fitting_for('tee', Catalog.spec('PVC_TIS17', '1-1/4"')), 'real 1-1/4" tee used in runs'
  end

  def test_browser_hides_spools_and_duplicates_and_offers_gate_6in
    pl = RefBrowser.payload
    keys = pl.map { |i| i[:key] }
    assert(keys.none? { |k| k.start_with?('piping:wafer150/check') }, 'piping-file wafer checks (1 m spools) hidden')
    assert_includes keys, 'valves:wafer150/check/-/6"'
    refute_includes keys, 'piping:cs_bw/hose/-/6"'
    assert(pl.all? { |i| Refs.get(i[:key])['ports'].any? }, 'every part offered snaps to a pipe')
    gate = pl.find { |i| i[:grow] }
    assert_equal 'valves:flg150/gate/wheel/4"', gate[:key]
    assert_equal [4.0, 24.0], gate[:grow], 'offered as 5"–24", scaled to B16.10 / B16.5'
    assert_equal [0.5, 12.0], pl.find { |i| i[:type] == 'water_meter' }[:range]
    assert(pl.select { |i| i[:type] == 'gauge' }.all? { |i| i[:any] })
  end

  def test_library_gate_on_a_6in_pipe_takes_the_standard_length
    s = Settings.sanitize('service' => 'CW', 'catalog' => 'CS_B36_10', 'size' => '6"')
    Builder.create_run(@model, [[[0, 0, 0], [4000, 0, 0]]], s)
    tool = RefPlaceTool.new(Refs.get('valves:flg150/gate/wheel/4"'))
    tool.instance_variable_set(:@model, @model)
    tool.instance_variable_set(:@angle, 0.0)
    pl = tool.placement([2000.0, 0.0, 30.0])
    assert_equal :inline, pl[:mode]
    spec = Catalog.spec('CS_B36_10', '6"')
    kx, = Builder.valve_scale('gate', spec, pl[:item])
    assert_in_delta FittingsData.face_to_face('gate', spec.od, :flanged), Builder.port_gap(pl[:item]) * kx, 0.5
  end
end
