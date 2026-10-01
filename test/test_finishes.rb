# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'su_stub'

module ArtK
  module PlantPipe
    PLUGIN_ROOT = File.expand_path('../src/artk_plant_pipe', __dir__) unless defined?(PLUGIN_ROOT)
    VERSION = 'test' unless defined?(VERSION)
  end
end
%w[model_helpers builder ref_models ref_builder support_builder collector picker reports library commands
   ref_browser].each do |f|
  require File.expand_path("../src/artk_plant_pipe/su/#{f}", __dir__)
end

# v1.7 realistic finishes: one palette, colours only.
class TestFinishes < Minitest::Test
  H = ModelHelpers

  def setup
    @model = Sketchup::Model.new
    Sketchup.active_model = @model
  end

  def test_every_mapping_points_to_a_defined_finish
    used = Finishes::PIPE.values + Finishes::PAINTED.values + Finishes::ROLE.values + Finishes::FIXED.values +
           Finishes::SOURCE.values.flat_map { |v| v.is_a?(Hash) ? v.values : [v] }
    used.uniq.each { |f| assert Finishes::LIST.key?(f), "unknown finish #{f}" }
    Finishes::LIST.each_value do |rgb, metal, rough|
      assert(rgb.all? { |c| c.between?(0, 255) })
      assert metal.between?(0.0, 1.0)
      assert rough.between?(0.0, 1.0)
    end
  end

  def test_every_part_material_and_source_material_is_covered
    (Refs.items.map { |i| i['material'] }.uniq - ['pvc_clear']).each do |m|
      refute_nil Finishes.role(m), "no finish for #{m}"
    end
    Finishes::SOURCE.each_key { |k| assert Refs.materials.key?(k), "#{k} not in the reference pack" }
    H::FIXED_ROLES.each_key { |r| assert Finishes::FIXED.key?(r), "no finish for role #{r}" }
  end

  def test_pipe_colours_come_from_the_palette
    assert_equal Finishes.rgb('pvc_blue'), Services.color('CW', 'material', 'PVC')
    assert_equal Finishes.rgb('stainless'), Services.color('CW', 'material', 'SS')
    assert_equal Finishes.rgb('fire_red'), Services.color('FP', 'material', 'CS')
  end

  def test_valve_body_paint_follows_what_the_valve_is_made_of
    assert_equal 'brass', Finishes.source('piping:Valve Metal', 'bronze')
    assert_equal 'epoxy_blue', Finishes.source('piping:Valve Metal', 'valve_cast')
    assert_equal 'handle_blue', Finishes.source('piping:Valve Blue', 'bronze')
    assert_nil Finishes.source('gauge:[Translucent Glass Gray]', 'steel_ss') # glass keeps its source look

    bronze = Refs.items.find { |i| i['family'] == 'gi_thrd' && i['type'] == 'globe' }
    ents = Sketchup::Entities.new
    RefModels.fill(@model, ents, Refs.mesh(bronze), item_mat: bronze['material'])
    names = ents.grep(Sketchup::Face).map { |f| f.material&.name }.compact.uniq
    assert_includes names, 'PP_Fin brass'
    refute_includes names, 'PP_Src Valve Metal'
    assert_equal Finishes.rgb('brass'), @model.materials['PP_Fin brass'].color.rgb
  end

  def test_role_materials_keep_their_names_with_new_colours
    m = RefModels.role_material(@model, 'valve_cast')
    assert_equal 'PP_Ref_Valve_Cast', m.name
    assert_equal Finishes.rgb('epoxy_blue'), m.color.rgb
    assert_equal Finishes.rgb('zinc_bolt'), H.role_material(@model, :bolt).color.rgb
    assert_equal 'PP_Bolt', H.role_material(@model, :bolt).name
  end

  def test_old_reference_definitions_are_repainted_in_place
    it = Refs.items.find { |i| i['family'] == 'flg150' && i['type'] == 'globe' }
    d = RefModels.definition(@model, it)
    d.set_attribute(H::DICT, 'finish', nil) # as built by v1.6
    d.entities.grep(Sketchup::Face).each { |f| f.material = nil }
    assert_equal 1, H.apply_finishes(@model)
    assert_equal Finishes::VERSION, d.get_attribute(H::DICT, 'finish')
    assert(d.entities.grep(Sketchup::Face).any? { |f| f.material&.name == 'PP_Fin epoxy_blue' })
    assert_same d, RefModels.definition(@model, it)
    assert_equal 0, H.apply_finishes(@model)
  end

  # SketchUp 2025+ material with PBR settings.
  class PbrMaterial < Sketchup::Material
    attr_accessor :metalness_enabled, :metallic_factor, :roughness_enabled, :roughness_factor
  end

  def test_metallic_sheen_only_where_sketchup_supports_it
    old = Sketchup::Material.new('old')
    H.apply_pbr(old, 1.0, 0.3) # SketchUp 2024 and older: nothing to set, no error
    m = PbrMaterial.new('new')
    H.apply_pbr(m, *Finishes.pbr('stainless'))
    assert m.metalness_enabled
    assert_in_delta 1.0, m.metallic_factor
    assert_in_delta 0.28, m.roughness_factor
    H.apply_pbr(m, *Finishes.pbr('epoxy_blue'))
    refute m.metalness_enabled
    assert_equal H::PAINT, H.pipe_pbr('CHWS', 'distinct', 'SS')
    assert_equal Finishes.pbr('stainless'), H.pipe_pbr('CHWS', 'material', 'SS')
    assert_equal Finishes.pbr('fire_red'), H.pipe_pbr('FP', 'material', 'SS')
  end
end
