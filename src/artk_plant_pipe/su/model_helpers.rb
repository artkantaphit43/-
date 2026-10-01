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

      # Settings are stored base64-encoded. Pipe sizes contain a double
      # quote (4"), and SketchUp's read/write_default does not round-trip
      # quotes reliably – in v1.0/v1.1 the stored JSON came back broken and
      # every new pipe silently fell back to the defaults (CW, PVC 1").
      # Base64 is only letters/digits, so nothing can be mangled. The
      # current session also keeps an in-memory copy.
      def load_settings
        @settings_cache ||= read_stored_settings
        @settings_cache.dup
      end

      def save_settings(settings)
        @settings_cache = Settings.sanitize(settings)
        Sketchup.write_default(PREF, 'settings_b64', [JSON.generate(@settings_cache)].pack('m0'))
        @settings_cache.dup
      end

      def read_stored_settings
        raw = Sketchup.read_default(PREF, 'settings_b64', nil)
        return Settings.sanitize({}) if raw.nil? || raw.to_s.empty?

        json = raw.to_s.unpack1('m0').force_encoding('UTF-8')
        Settings.sanitize(JSON.parse(json))
      rescue StandardError => e
        puts "Plant Piping: stored settings unreadable (#{e.message}) – using defaults"
        Settings.sanitize({})
      end

      def reset_settings_cache!
        @settings_cache = nil
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

      # +pbr+: [metalness, roughness] – metallic sheen on SketchUp 2025+
      # (PBR materials); ignored by older versions. nil leaves PBR as is.
      def material(model, name, rgb, alpha = 1.0, pbr: nil)
        mat = model.materials[name] || model.materials.add(name)
        mat.color = Sketchup::Color.new(*rgb)
        mat.alpha = alpha if alpha < 1.0
        apply_pbr(mat, *pbr) if pbr
        mat
      end

      # Material of a realistic finish (lib/finishes.rb) – colour + sheen.
      def finish_material(model, finish, name: nil)
        material(model, name || Finishes.material_name(finish), Finishes.rgb(finish), pbr: Finishes.pbr(finish))
      end

      # SketchUp 2025+ PBR: metalness 0 = paint / plastic (roughness still
      # gives the gloss), > 0 = metal. Every call is guarded so older
      # SketchUp versions simply keep the plain colour.
      def apply_pbr(mat, metal, rough)
        return mat unless mat.respond_to?(:roughness_factor=)

        if mat.respond_to?(:metalness_enabled=)
          mat.metalness_enabled = metal.to_f.positive?
          mat.metallic_factor = metal.to_f if metal.to_f.positive? && mat.respond_to?(:metallic_factor=)
        end
        mat.roughness_enabled = true if mat.respond_to?(:roughness_enabled=)
        mat.roughness_factor = rough.to_f
        mat
      rescue StandardError
        mat
      end

      # Pipe/fitting colour: one material per service + material family, so
      # a scheme change is just a recolour of these few materials.
      # The run's own colour when the user picked one (fixed – colour schemes
      # leave it alone), otherwise the service/material colour of the scheme.
      def pipe_material(model, code, family, scheme, custom = nil)
        rgb = Settings.rgb(custom)
        return material(model, "PP_Custom_#{custom.delete('#')}", rgb, pbr: PAINT) if rgb

        material(model, "PP_#{code}_#{family}", Services.color(code, scheme, family), pbr: pipe_pbr(code, scheme, family))
      end

      # Gloss of a painted surface (own colour, identification schemes).
      PAINT = [0.0, 0.4].freeze

      # Sheen of a pipe: the real material's in the "material" scheme
      # (painted services – fire, gas – are paint), otherwise paint.
      def pipe_pbr(code, scheme, family)
        fin = scheme == 'material' && (Finishes::PAINTED[code] || Finishes.pipe(family))
        fin ? Finishes.pbr(fin) : PAINT
      end

      def insulation_material(model)
        material(model, 'PP_Insulation', Finishes.rgb('insulation'), 0.35)
      end

      # Fixed-colour material roles used inside part definitions. Roles not
      # listed (:pipe, :fitting, :flange) are left unpainted so they take the
      # colour of the instance – one definition serves every service colour.
      # Material names stay as in v1.6 so models drawn before pick up the
      # realistic colours (lib/finishes.rb) on the next rebuild.
      FIXED_ROLES = {
        valve: 'PP_Valve_Body', valve_plastic: 'PP_Valve_PVC', cast: 'PP_Cast_Iron', forged: 'PP_Forged_Steel',
        brass: 'PP_Brass', chrome: 'PP_Chrome', iron: 'PP_Iron_Black', grip: 'PP_Vinyl_Grip',
        gauge: 'PP_Gauge_Face', handle: 'PP_Handwheel', bolt: 'PP_Bolt', galv: 'PP_Galvanised',
        steel: 'PP_Support_Steel', concrete: 'PP_Concrete', weld: 'PP_Weld', gasket: 'PP_Gasket'
      }.freeze

      def role_material(model, role)
        name = FIXED_ROLES[role]
        name ? finish_material(model, Finishes::FIXED.fetch(role), name: name) : nil
      end

      # Re-colour every pipe material for a colour scheme (instant – no
      # entity traversal).
      def apply_color_scheme(model, scheme)
        model.materials.to_a.each do |m|
          next unless m.name =~ /\APP_([A-Z]+)_([A-Z]+)\z/ && Services.codes.include?(Regexp.last_match(1))

          code = Regexp.last_match(1)
          family = Regexp.last_match(2)
          m.color = Sketchup::Color.new(*Services.color(code, scheme, family))
          apply_pbr(m, *pipe_pbr(code, scheme, family))
        end
      end

      # Repaint a model drawn with an earlier version in the realistic
      # finishes: pipe colours, generated-part roles, and the copied
      # reference parts (their component definitions are refilled in place,
      # so placed instances keep their position). Returns the number of
      # reference definitions repainted.
      def apply_finishes(model)
        apply_color_scheme(model, load_settings['color_scheme'])
        FIXED_ROLES.each_key { |role| role_material(model, role) if model.materials[FIXED_ROLES[role]] }
        RefModels.repaint_all(model)
      end

      # ---------- geometry output ----------

      # Write a Mesh::Part into +ents+ as faces (one PolygonMesh per role).
      # +recolor+ maps roles to other roles (e.g. plastic valve bodies take
      # the pipe colour: { valve: :fitting }).
      def add_part(model, ents, part, steps: 16, recolor: {})
        part.bodies.each do |role, solid|
          next if solid.polys.empty?

          mesh = Geom::PolygonMesh.new(solid.polys.size * 4, solid.polys.size)
          solid.polys.each { |poly| mesh.add_polygon(*poly.map { |p| to_pt(p) }) }
          mat = role_material(model, recolor.fetch(role, role))
          ents.add_faces_from_mesh(mesh, 0, mat, mat)
        end
        soften(ents, steps)
        ents
      end

      # Unique geometry (pipes, insulation, supports) as a group.
      def add_part_group(model, ents, part, steps: 16, recolor: {})
        g = ents.add_group
        add_part(model, g.entities, part, steps: steps, recolor: recolor)
        g
      end

      # Reusable geometry (fittings, valves, flanges) as a component: built
      # once per name, then instanced – keeps detailed models light.
      def part_definition(model, name, steps: 16, recolor: {})
        defs = model.definitions
        d = defs[name]
        return d if d && d.get_attribute(DICT, 'type') == 'part'

        d = defs.add(name)
        d.set_attribute(DICT, 'type', 'part')
        add_part(model, d.entities, yield, steps: steps, recolor: recolor)
        unless faces?(d.entities)
          defs.remove(d) if defs.respond_to?(:remove)
          raise 'component has no faces'
        end
        d
      end

      def faces?(ents)
        ents.any? { |e| e.is_a?(Sketchup::Face) }
      end

      def frame_transform(f)
        Geom::Transformation.axes(to_pt(f[:o]), to_vec(f[:x]), to_vec(f[:y]), to_vec(f[:z]))
      end

      # Remove our part definitions no longer used (after a rebuild).
      def purge_parts(model)
        defs = model.definitions
        return unless defs.respond_to?(:remove)

        defs.to_a.each do |d|
          defs.remove(d) if d.get_attribute(DICT, 'type') == 'part' && d.count_instances.zero?
        end
      end

      # Soften edges between faces meeting at less than one facet angle
      # (round surfaces look smooth, real corners keep their black line –
      # the technical look of the reference drawings).
      def soften(ents, steps = 16)
        limit = [(360.0 / steps) + 6.0, 26.0].max * Math::PI / 180.0
        ents.grep(Sketchup::Edge).each do |e|
          faces = e.faces
          next unless faces.size == 2
          next unless faces[0].normal.angle_between(faces[1].normal) < limit

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
