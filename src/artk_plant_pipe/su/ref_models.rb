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
        'steel_ss' => ['PP_Ref_Stainless', [205, 207, 210]]
      }.freeze

      class << self
        def role_material(model, role)
          name, rgb = ROLE_COLORS[role]
          name ? H.material(model, name, rgb) : nil
        end

        # Component definition for a pack item (built once per model).
        def definition(model, item)
          name = "PP Ref #{item['key']}"
          defs = model.definitions
          d = defs[name]
          return d if d && d.get_attribute(H::DICT, 'type') == 'part' && H.faces?(d.entities)

          d = defs.add(name)
          d.set_attribute(H::DICT, 'type', 'part')
          d.set_attribute(H::DICT, 'ref_key', item['key'])
          d.description = [item['standard'], item['src_name']].compact.join(' – ')
          fill(model, d.entities, Refs.mesh(item))
          unless H.faces?(d.entities)
            defs.remove(d) if defs.respond_to?(:remove)
            raise "reference model #{item['key']} produced no faces"
          end
          d
        end

        def fill(model, ents, mesh)
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
            m = f[:mat] && (mats[f[:mat]] ||= source_material(model, f[:mat]))
            face.material = m if m
            face.back_material = m if m
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
        def source_material(model, key)
          rgb = Refs.materials[key] or return nil
          name = "PP_Src #{key.split(':', 2).last}"
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
