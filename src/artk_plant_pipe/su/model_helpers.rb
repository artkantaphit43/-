# frozen_string_literal: true

require 'json'

module ArtK
  module PlantPipe
    # Thin wrappers around the SketchUp API used by the builder and tools.
    #
    # Conventions
    # * The engineering core works in millimetres; SketchUp works in inches.
    #   Conversion happens only here (to_pt / to_vec / from_pt).
    # * Every object the extension creates carries an attribute dictionary
    #   DICT with at least 'type' – that is what the BOM, rebuild, valve and
    #   clash tools look for, so user geometry is never touched.
    module ModelHelpers
      DICT = 'ArtK_PlantPipe'
      PREF = 'ArtK_PlantPipe'
      TAG_FOLDER = 'Plant Piping'
      TAG_INSULATION = 'PP-Insulation'
      TAG_CENTERLINE = 'PP-Centerline'
      TAG_LABELS = 'PP-Labels'
      TAG_CLASH = 'PP-Clash'
      MM_PER_INCH = 25.4

      module_function

      # ---------- units ----------

      def mm(v)
        v.to_f / MM_PER_INCH
      end

      def to_pt(a)
        Geom::Point3d.new(mm(a[0]), mm(a[1]), mm(a[2]))
      end

      def to_vec(a)
        Geom::Vector3d.new(a[0].to_f, a[1].to_f, a[2].to_f)
      end

      def from_pt(pt)
        [pt.x.to_f * MM_PER_INCH, pt.y.to_f * MM_PER_INCH, pt.z.to_f * MM_PER_INCH]
      end

      def from_vec(v)
        [v.x.to_f, v.y.to_f, v.z.to_f]
      end

      # Apply a Geom::Transformation to an [x, y, z] mm point.
      def transform_mm(tr, a)
        from_pt(to_pt(a).transform(tr))
      end

      # ---------- attributes ----------

      def set_attrs(entity, hash)
        hash.each { |k, v| entity.set_attribute(DICT, k.to_s, v.is_a?(Symbol) ? v.to_s : v) }
      end

      def attrs(entity)
        d = entity.attribute_dictionary(DICT)
        return nil unless d

        h = {}
        d.each_pair { |k, v| h[k] = v }
        h
      end

      def type_of(entity)
        entity.get_attribute(DICT, 'type')
      end

      def instance?(entity)
        entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
      end

      def run?(entity)
        instance?(entity) && type_of(entity) == 'run'
      end

      def get_json(entity, key, default = nil)
        s = entity.get_attribute(DICT, key)
        s ? JSON.parse(s) : default
      rescue JSON::ParserError
        default
      end

      def set_json(entity, key, value)
        entity.set_attribute(DICT, key, JSON.generate(value))
      end

      # ---------- settings persistence ----------

      def load_settings
        Settings.load(Sketchup.read_default(PREF, 'settings', ''))
      end

      def save_settings(settings)
        Sketchup.write_default(PREF, 'settings', Settings.dump(settings))
      end

      # ---------- tags & materials ----------

      def tag(model, name)
        layers = model.layers
        layer = layers[name]
        return layer if layer

        layer = layers.add(name)
        # Group our tags in a folder (SketchUp 2021+).
        if layers.respond_to?(:add_folder)
          folder = nil
          layers.each_folder { |f| folder = f if f.name == TAG_FOLDER }
          folder ||= layers.add_folder(TAG_FOLDER)
          folder.add_layer(layer)
        end
        layer
      rescue StandardError
        layer
      end

      def service_tag(model, code)
        s = Services.get(code)
        tag(model, "PP-#{code} #{s[:en]}")
      end

      def material(model, name, rgb, alpha = 1.0)
        mat = model.materials[name] || model.materials.add(name)
        mat.color = Sketchup::Color.new(*rgb)
        mat.alpha = alpha if alpha < 1.0
        mat
      end

      def service_material(model, code, scheme, fitting: false)
        rgb = Services.color(code, scheme)
        if fitting
          rgb = rgb.map { |c| (c * 0.75).round }
          material(model, "PP_#{code}_Fitting", rgb)
        else
          material(model, "PP_#{code}", rgb)
        end
      end

      def insulation_material(model)
        material(model, 'PP_Insulation', [225, 225, 215], 0.35)
      end

      def valve_material(model)
        material(model, 'PP_Valve', [70, 74, 84])
      end

      def handwheel_material(model)
        material(model, 'PP_Handwheel', [200, 35, 35])
      end

      # Re-colour every service material for a colour scheme. Because all
      # piping geometry references these materials, this is instant even on
      # large models – no entity traversal needed.
      def apply_color_scheme(model, scheme)
        Services.codes.each do |code|
          next unless model.materials["PP_#{code}"] || model.materials["PP_#{code}_Fitting"]

          service_material(model, code, scheme)
          service_material(model, code, scheme, fitting: true)
        end
      end

      # ---------- geometry primitives ----------

      # Sweep a circular section of +radius_mm+ along a straight line or an
      # arc (Network elbow data). Each sweep lives in its own group so
      # overlapping solids (tee arms, valve parts) never merge geometry.
      def sweep(parent_ents, radius_mm, segs, line: nil, arc: nil, arc_segs: nil)
        grp = parent_ents.add_group
        ents = grp.entities
        if arc
          path = ents.add_arc(to_pt(arc[:center]), to_vec(arc[:xaxis]), to_vec(arc[:normal]),
                              mm(arc[:radius]), 0.0, arc[:angle], arc_segs || 8)
          start = to_pt(arc[:start])
          dir = to_vec(arc[:dir_in])
        else
          a, b = line
          start = to_pt(a)
          edge = ents.add_line(start, to_pt(b))
          raise 'segment too short to model' unless edge

          path = [edge]
          dir = to_vec(Vec.sub(b, a))
        end
        circle = ents.add_circle(start, dir, mm(radius_mm), segs)
        face = ents.add_face(circle)
        raise 'could not create pipe section face' unless face
        raise 'Follow Me failed' unless face.followme(path)

        # Make the solid face outward: the profile face stays as the start
        # cap, whose outward normal must point against the sweep direction.
        if face.valid?
          face.reverse! if face.normal.dot(dir) > 0
          face.orient_connected_faces
        end
        leftovers = path.select { |e| e.valid? && e.faces.empty? }
        ents.erase_entities(leftovers) unless leftovers.empty?
        soften(ents)
        grp
      end

      # Solid disc (flanges, handwheels, butterfly discs).
      def disc(parent_ents, center, dir, radius_mm, thickness_mm, segs)
        a = Vec.sub(center, Vec.scale(dir, thickness_mm / 2.0))
        b = Vec.add(center, Vec.scale(dir, thickness_mm / 2.0))
        sweep(parent_ents, radius_mm, segs, line: [a, b])
      end

      def soften(ents)
        limit = 50.0 * Math::PI / 180.0
        ents.grep(Sketchup::Edge).each do |e|
          next unless e.faces.size == 2

          n1, n2 = e.faces.map(&:normal)
          next unless n1.angle_between(n2) < limit

          e.soft = true
          e.smooth = true
        end
      end

      # World transformation of the active editing context (identity at
      # model root). Geometry built from InputPoint world positions must be
      # mapped by its inverse into active_entities.
      def edit_transform(model)
        model.active_path ? model.edit_transform : Geom::Transformation.new
      end

      # ---------- line numbers ----------

      # Next per-service sequence number, stored in the model so it survives
      # save/reopen and stays unique per service.
      def next_seq(model, code)
        key = "seq_#{code}"
        n = (model.get_attribute(DICT, key) || 0).to_i + 1
        model.set_attribute(DICT, key, n)
        n
      end

      # Line number in the common P&ID form SIZE-SERVICE-SEQ, e.g. 2"-CW-003.
      def line_number(size, code, seq)
        format('%<size>s-%<code>s-%<n>03d', size: size.delete(' '), code: code, n: seq.to_i)
      end

      # ---------- traversal ----------

      # Yields [entity, world_transformation] for every instance in the
      # model tree (groups & components, recursively; component definitions
      # are visited once per instance, so copies are counted correctly).
      def each_instance(entities, tr = Geom::Transformation.new, &block)
        entities.each do |e|
          next unless instance?(e)

          t = tr * e.transformation
          yield e, t
          each_instance(e.definition.entities, t, &block)
        end
      end

      # Runs in the active context with their world transformations.
      def active_runs(model)
        tr = edit_transform(model)
        model.active_entities.select { |e| run?(e) }.map { |r| [r, tr * r.transformation] }
      end

      def selected_runs(model)
        runs = []
        model.selection.each do |e|
          if run?(e)
            runs << e
          elsif instance?(e) && e.respond_to?(:parent)
            # A piece inside a run was selected (user is editing the run).
            parent = e.parent
            owner = parent.respond_to?(:instances) ? parent.instances.first : nil
            runs << owner if owner && run?(owner)
          end
        end
        # When editing inside a run, the run itself is the context.
        if runs.empty? && model.active_path
          owner = model.active_path.reverse.find { |e| run?(e) }
          runs << owner if owner
        end
        runs.uniq
      end
    end
  end
end
