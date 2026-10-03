# frozen_string_literal: true

module ArtK
  module PlantPipe
    # Components built 1:1 from the reference-model pack (lib/refs.rb).
    #
    # Faces keep their source materials (valve handles, gauges, body paint);
    # unpainted faces are left without material so the instance colour shows
    # through – pipe fittings therefore follow the run's colour scheme, and
    # valves get the body colour of their material (see ROLE_COLORS).
    module RefModels
      H = ModelHelpers

      # Colour of unpainted faces per material (reasoned from what the part
      # is made of, not from the source file's display colour).
      ROLE_COLORS = {
        'galvanized' => ['PP_Ref_Galvanised', [190, 194, 198]],   # hot-dip zinc, dull silver
        'black_steel' => ['PP_Ref_Black_Steel', [74, 78, 84]],    # A105 / A234 black, mill finish
        'valve_cast' => ['PP_Ref_Valve_Cast', [58, 70, 102]],     # cast steel / DI, blue-grey paint
        'valve_green' => ['PP_Ref_Valve_Green', [118, 186, 118]], # JIS 10K DI body, green epoxy
        'bronze' => ['PP_Ref_Bronze', [181, 142, 78]],            # bronze / brass body
        'pvc_blue' => ['PP_Ref_PVC_Blue', [34, 128, 206]],        # TIS 17 blue
        'pvc_white' => ['PP_Ref_PVC_White', [236, 236, 230]],     # Sch40 DWV white
        'pvc_grey' => ['PP_Ref_PVC_Grey', [140, 144, 146]],       # PVC-U RAL 7011 grey
        'pp_black' => ['PP_Ref_PP_Black', [52, 52, 54]],          # PP-H / PE black
        'pvc_clear' => ['PP_Ref_Clear', [214, 228, 236]],         # rotameter tube
        'steel_ss' => ['PP_Ref_Stainless', [205, 207, 210]],
        'chrome' => ['PP_Ref_Chrome', [200, 203, 207]]              # chromed brass (taps)
      }.freeze

      class << self
        def role_material(model, role)
          name, rgb = ROLE_COLORS[role]
          name ? H.material(model, name, rgb) : nil
        end

        # Component definition for a pack item (built once per model).
        # plain: faces left unpainted (decals excepted) so the part takes the
        # instance colour – pipe fittings follow their line's colour.
        def definition(model, item, plain: false)
          name = "PP Ref #{item['key']}#{' (plain)' if plain}"
          defs = model.definitions
          d = defs[name]
          return d if current?(d, item)

          # a definition from an older version is rebuilt in place, so every
          # copy already in the model takes the new geometry
          d ||= defs.add(name)
          d.entities.clear!
          build(model, d, item, plain)
          unless H.faces?(d.entities)
            defs.remove(d) if defs.respond_to?(:remove)
            raise "reference model #{item['key']} produced no faces"
          end
          d
        end

        def current?(d, item)
          d && d.get_attribute(H::DICT, 'type') == 'part' && H.faces?(d.entities) &&
            (d.get_attribute(H::DICT, 'rev') || 1) == Refs.geometry_rev(item)
        end

        def build(model, d, item, plain)
          d.set_attribute(H::DICT, 'type', 'part')
          d.set_attribute(H::DICT, 'ref_key', item['key'])
          d.set_attribute(H::DICT, 'rev', Refs.geometry_rev(item))
          d.description = [item['standard'], item['src_name']].compact.join(' – ')
          fill(model, d.entities, Refs.mesh(item), plain: plain)
        end

        # On opening a model: generated parts drawn by an older version
        # (their size read from a placed copy) and dial images tinted by
        # v1.5–v1.8. Returns [[definition, item]…, [material, image]…].
        def stale(model)
          parts = model.definitions.to_a.filter_map do |d|
            key = d.get_attribute(H::DICT, 'ref_key').to_s
            next unless key.start_with?('gen:')

            inst = d.instances.find { |i| i.valid? && i.get_attribute(H::DICT, 'size') }
            next unless inst

            base = Refs.get(inst.get_attribute(H::DICT, 'model').to_s)
            spec = Catalog.spec(inst.get_attribute(H::DICT, 'catalog'), inst.get_attribute(H::DICT, 'size'))
            item = base && Refs.sized_item(base, spec)
            [d, item] if item && !current?(d, item)
          rescue StandardError
            nil
          end
          mats = Refs.materials.keys.filter_map do |key|
            tex = Refs.texture_path(key)
            mat = model.materials["PP_Src #{key.split(':', 2).last}"]
            [mat, tex] if tex && mat && File.exist?(tex) && !mat.get_attribute(H::DICT, 'clean_texture')
          end
          [parts, mats]
        end

        def refresh(model, parts, mats)
          mats.each { |mat, tex| clean_texture(mat, tex) }
          parts.each do |d, item|
            d.entities.clear!
            build(model, d, item, false)
          end
          parts.size
        end

        # Image without tint; flagged so it is done once per file.
        def clean_texture(mat, tex)
          mat.texture = tex if mat.respond_to?(:texture=)
          mat.set_attribute(H::DICT, 'clean_texture', true)
        end

        def fill(model, ents, mesh, plain: false)
          pts = mesh[:verts].map { |v| H.to_pt(v) }
          mats = {}
          soft = {}
          mesh[:faces].each do |f|
            f[:loops].each_with_index do |lp, li|
              lp.each_with_index do |vi, k|
                soft[edge_key(vi, lp[(k + 1) % lp.size])] = true if f[:soft][li][k]
              end
            end
          end
          faces = if ents.respond_to?(:build)
                    build_fast(ents, mesh, pts)
                  else
                    mesh[:faces].map { |f| add_face_slow(ents, f, pts) }
                  end
          faces.each_with_index do |face, i|
            next unless face

            f = mesh[:faces][i]
            orient(face, f, mesh[:verts])
            next if plain && !f[:pins]

            m = f[:mat] && (mats[f[:mat]] ||= source_material(model, f[:mat]))
            next unless m

            if f[:pins] && m.texture && face.respond_to?(:position_material)
              # decal (e.g. meter dial): place the image exactly as in the source
              pins = f[:pins].flat_map { |pt, (u, v)| [H.to_pt(pt), Geom::Point3d.new(u, v, 1.0)] }
              face.position_material(m, pins, true)
            else
              face.material = m
            end
            face.back_material = m
          end
          smooth_edges(ents, soft, mesh[:verts])
        end

        # SketchUp 2022+: EntitiesBuilder adds faces with holes directly.
        def build_fast(ents, mesh, pts)
          out = []
          ents.build do |b|
            mesh[:faces].each do |f|
              outer = f[:loops][0].map { |i| pts[i] }
              holes = f[:loops][1..].map { |lp| lp.map { |i| pts[i] } }
              out << begin
                holes.empty? ? b.add_face(outer) : b.add_face(outer, holes: holes)
              rescue ArgumentError
                nil # degenerate face in the source – skipped
              end
            end
          end
          out
        end

        # Older SketchUp: add the outer face, then cut each hole.
        def add_face_slow(ents, f, pts)
          face = ents.add_face(f[:loops][0].map { |i| pts[i] })
          f[:loops][1..].each do |lp|
            hole = ents.add_face(lp.map { |i| pts[i] })
            hole&.erase! if hole&.valid?
          end
          face
        rescue ArgumentError
          nil
        end

        # Keep the source orientation (outer loop order = front side).
        def orient(face, f, verts)
          n = newell(f[:loops][0].map { |i| verts[i] })
          face.reverse! if face.normal.dot(H.to_vec(n)) < 0.0
        end

        def smooth_edges(ents, soft, verts)
          return if soft.empty?

          index = {}
          verts.each_with_index { |v, i| index[v.map { |c| (c * 10).round }] = i }
          ents.grep(Sketchup::Edge).each do |e|
            a = index[H.from_pt(e.start.position).map { |c| (c * 10).round }]
            b = index[H.from_pt(e.end.position).map { |c| (c * 10).round }]
            next unless a && b && soft[edge_key(a, b)]

            e.soft = true
            e.smooth = true
          end
        end

        def edge_key(a, b)
          a < b ? [a, b] : [b, a]
        end

        def newell(pts)
          n = [0.0, 0.0, 0.0]
          pts.each_with_index do |a, i|
            b = pts[(i + 1) % pts.size]
            n[0] += (a[1] - b[1]) * (a[2] + b[2])
            n[1] += (a[2] - b[2]) * (a[0] + b[0])
            n[2] += (a[0] - b[0]) * (a[1] + b[1])
          end
          n
        end

        # "piping:Valve Blue" → material "PP_Src Valve Blue" in the source colour.
        # Textured materials (meter dial) never get a colour set: SketchUp
        # would tint the image with it. Re-assigning the image also repairs a
        # dial tinted by v1.5–1.8.
        def source_material(model, key)
          rgb = Refs.materials[key] or return nil
          name = "PP_Src #{key.split(':', 2).last}"
          tex = Refs.texture_path(key)
          if tex && File.exist?(tex)
            mat = model.materials[name] || model.materials.add(name)
            clean_texture(mat, tex) if mat.texture.nil? || !mat.get_attribute(H::DICT, 'clean_texture')
            mat.alpha = rgb[3] if rgb[3] && rgb[3] < 1.0
            return mat
          end
          H.material(model, name, rgb[0, 3], rgb[3] || 1.0)
        end

        # Transformation placing the canonical frame at world frame +f+
        # (Mesh.frame hash, mm).
        def transform(f)
          H.frame_transform(f)
        end
      end
    end
  end
end
