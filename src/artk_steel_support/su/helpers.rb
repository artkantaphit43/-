# frozen_string_literal: true

require 'json'

module ArtK
  module SteelSupport
    # SketchUp plumbing: units, attributes, materials, meshes.
    module H
      DICT = 'ArtK_SteelSupport'
      PREF = 'ArtK_SteelSupport'
      TAG = 'ซัพพอร์ตเหล็ก (Steel supports)'
      COLORS = {
        steel: ['SS เหล็กทาสี (painted steel)', [92, 98, 110]],
        galv: ['SS ชุบซิงค์ (zinc plated)', [196, 200, 206]]
      }.freeze
      DEFAULTS = {
        'detail' => 'wf', 'section' => 'auto', 'anchor' => 'auto', 'anchors' => 3, 'rod' => 'auto',
        'spacing_m' => 0, 'gap' => 600, 'drop_hangers' => true
      }.freeze

      module_function

      MM = 25.4 # SketchUp's internal unit is the inch

      def to_pt(a)
        Geom::Point3d.new(a[0].to_f / MM, a[1].to_f / MM, a[2].to_f / MM)
      end

      def from_pt(pt)
        [pt.x.to_f * MM, pt.y.to_f * MM, pt.z.to_f * MM]
      end

      def to_vec(a)
        Geom::Vector3d.new(a[0].to_f, a[1].to_f, a[2].to_f)
      end

      def from_vec(v)
        [v.x.to_f, v.y.to_f, v.z.to_f]
      end

      def transform_mm(tr, a)
        from_pt(to_pt(a).transform(tr))
      end

      def frame_transform(o, x, y)
        z = Vec.cross(x, y)
        Geom::Transformation.axes(to_pt(o), to_vec(x), to_vec(y), to_vec(z))
      end

      def edit_transform(model)
        model.active_path ? model.edit_transform : Geom::Transformation.new
      end

      def get_json(e, key, default = nil)
        v = e.get_attribute(DICT, key)
        v ? JSON.parse(v) : default
      rescue JSON::ParserError
        default
      end

      def set_json(e, key, value)
        e.set_attribute(DICT, key, JSON.generate(value))
      end

      def ours?(e)
        e.respond_to?(:get_attribute) && e.get_attribute(DICT, 'kind') == 'support'
      end

      def instance?(e)
        e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      end

      # [entity, world transformation] for our supports in the active context.
      def supports(model)
        tr = edit_transform(model)
        model.active_entities.select { |e| instance?(e) && ours?(e) }.map { |e| [e, tr * e.transformation] }
      end

      def tag(model, name = TAG)
        layers = model.layers
        layers[name] || layers.add(name)
      end

      def material(model, role)
        name, rgb = COLORS[role] || COLORS[:steel]
        mats = model.materials
        mats[name] || mats.add(name).tap { |m| m.color = Sketchup::Color.new(*rgb) }
      end

      # The part's solids into +ents+, one mesh per material; edges between
      # faces < ~28° apart softened (round rods, fillets, triangulated ends).
      def add_part(model, ents, part)
        part.bodies.each do |role, polys|
          next if polys.empty?

          mesh = Geom::PolygonMesh.new(polys.size * 4, polys.size)
          polys.each { |poly| mesh.add_polygon(*poly.map { |p| to_pt(p) }) }
          mat = material(model, role)
          ents.add_faces_from_mesh(mesh, 0, mat, mat)
        end
        limit = 28.5 * Math::PI / 180.0
        ents.grep(Sketchup::Edge).each do |e|
          f = e.faces
          next unless f.size == 2 && f[0].normal.angle_between(f[1].normal) < limit

          e.soft = true
          e.smooth = true
        end
      end

      def settings
        raw = Sketchup.read_default(PREF, 'settings', '{}')
        DEFAULTS.merge(JSON.parse(raw.to_s))
      rescue JSON::ParserError
        DEFAULTS.dup
      end

      def save_settings(s)
        Sketchup.write_default(PREF, 'settings', JSON.generate(DEFAULTS.merge(s.slice(*DEFAULTS.keys))))
      end
    end
  end
end
