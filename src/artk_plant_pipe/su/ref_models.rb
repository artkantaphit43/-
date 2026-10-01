# frozen_string_literal: true

module ArtK
  module PlantPipe
    # Components built 1:1 from the reference-model pack (lib/refs.rb).
    #
    # Faces keep their source materials (valve handles, gauges, body paint);
    # unpainted faces are left without material so the instance colour shows
    # through – pipe fittings therefore follow the run's colour scheme, and
    # valves get the body colour of their material (see ROLE_NAMES).
    # Colours are the realistic finishes of lib/finishes.rb (v1.7).
    module RefModels
      H = ModelHelpers

      # Material of unpainted faces per part material (names as in v1.6 so
      # older models pick up the new colours). Colours: lib/finishes.rb.
      ROLE_NAMES = {
        'galvanized' => 'PP_Ref_Galvanised', 'black_steel' => 'PP_Ref_Black_Steel', 'valve_cast' => 'PP_Ref_Valve_Cast',
        'valve_green' => 'PP_Ref_Valve_Green', 'bronze' => 'PP_Ref_Bronze', 'pvc_blue' => 'PP_Ref_PVC_Blue',
        'pvc_white' => 'PP_Ref_PVC_White', 'pvc_grey' => 'PP_Ref_PVC_Grey', 'pp_black' => 'PP_Ref_PP_Black',
        'pvc_clear' => 'PP_Ref_Clear', 'steel_ss' => 'PP_Ref_Stainless', 'chrome' => 'PP_Ref_Chrome'
      }.freeze

      class << self
        def role_material(model, role)
          name = ROLE_NAMES[role] or return nil
          return H.material(model, name, Finishes::CLEAR[0], Finishes::CLEAR[1], pbr: [0.0, 0.1]) if role == 'pvc_clear'

          fin = Finishes.role(role)
          fin ? H.finish_material(model, fin, name: name) : nil
        end

        # Component definition for a pack item (built once per model).
        # plain: faces left unpainted (decals excepted) so the part takes the
        # instance colour – pipe fittings follow their line's colour.
        def definition(model, item, plain: false)
          name = "PP Ref #{item['key']}#{' (plain)' if plain}"
          defs = model.definitions
          d = defs[name]
          if d && d.get_attribute(H::DICT, 'type') == 'part' && H.faces?(d.entities)
            repaint(model, d, item, plain: plain) if d.get_attribute(H::DICT, 'finish').to_i < Finishes::VERSION
            return d
          end

          d = defs.add(name)
          d.set_attribute(H::DICT, 'type', 'part')
          d.set_attribute(H::DICT, 'ref_key', item['key'])
          d.set_attribute(H::DICT, 'finish', Finishes::VERSION)
          d.description = [item['standard'], item['src_name']].compact.join(' – ')
          fill(model, d.entities, Refs.mesh(item), plain: plain, item_mat: item['material'])
          unless H.faces?(d.entities)
            defs.remove(d) if defs.respond_to?(:remove)
            raise "reference model #{item['key']} produced no faces"
          end
          d
        end

        # A definition built by an earlier version: refill it with the
        # current finishes. Instances keep their place (same definition).
        def repaint(model, d, item, plain: false)
          d.entities.clear!
          fill(model, d.entities, Refs.mesh(item), plain: plain, item_mat: item['material'])
          d.set_attribute(H::DICT, 'finish', Finishes::VERSION)
          d
        end

        # Repaint every reference definition of an older palette in +model+.
        def repaint_all(model)
          n = 0
          model.definitions.to_a.each do |d|
            next unless d.get_attribute(H::DICT, 'type') == 'part'
            next if d.get_attribute(H::DICT, 'finish').to_i >= Finishes::VERSION

            item = (key = d.get_attribute(H::DICT, 'ref_key')) && Refs.get(key)
            next unless item

            repaint(model, d, item, plain: d.name.to_s.end_with?('(plain)'))
            n += 1
          end
          n
        end

        def fill(model, ents, mesh, plain: false, item_mat: nil)
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

            m = f[:mat] && (mats[f[:mat]] ||= source_material(model, f[:mat], item_mat))
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

        # Painted source face → its realistic finish (lib/finishes.rb), e.g.
        # "piping:Valve Blue" → "PP_Fin handle_blue". Materials the palette
        # leaves alone (glass, dial print, the meter dial texture) keep the
        # source colour as "PP_Src <name>".
        def source_material(model, key, item_mat = nil)
          fin = Finishes.source(key, item_mat)
          return H.finish_material(model, fin) if fin

          rgb = Refs.materials[key] or return nil
          name = "PP_Src #{key.split(':', 2).last}"
          mat = H.material(model, name, rgb[0, 3], rgb[3] || 1.0)
          tex = Refs.texture_path(key)
          mat.texture = tex if tex && File.exist?(tex) && mat.respond_to?(:texture=) && mat.texture.nil?
          mat
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
