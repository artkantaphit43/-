# frozen_string_literal: true

module ArtK
  module PlantPipe
    # Parametric valve models placed on a pipe axis.
    #
    # Dimensions: face-to-face from ASME B16.10 (interpolated), flange OD
    # from ASME B16.5 Class 150. Bodies and operators are simplified shapes
    # sized to the pipe – enough for layout, operator access and clash
    # checks, and light enough to keep large plant models responsive.
    #
    # Operator orientation follows common plant practice: the stem points
    # up on horizontal lines (never down – packing leaks onto the operator
    # and dirt collects in the bonnet), and horizontally on vertical lines.
    # Butterfly valves from 6" use a gear operator, smaller ones a lever.
    module Valves
      H = ModelHelpers

      module_function

      def build(ctx, type, at, dir)
        spec = ctx[:spec]
        info = FittingsData.valve(type)
        od = spec.od
        dir = Vec.unit(dir)
        up = stem_direction(dir)
        len = FittingsData.face_to_face(type, od)
        metallic = spec.density > 5000
        fr = metallic ? FittingsData.flange_od(od) / 2.0 : spec.fitting_od / 2.0 * 1.15
        tf = metallic ? FittingsData.flange_thickness(od) : [0.12 * len, 8.0].max
        segs = ctx[:segs]

        grp = ctx[:ents].add_group
        ents = grp.entities
        body = []   # part groups painted with the valve material
        wheel = []  # part groups painted with the handwheel material
        pt = ->(u, s) { Vec.add(at, Vec.scale(u, s)) }

        if type == 'flange'
          gap = 1.5 # half gasket thickness
          body << H.disc(ents, pt.call(dir, -(tf / 2.0 + gap)), dir, fr, tf, segs)
          body << H.disc(ents, pt.call(dir, tf / 2.0 + gap), dir, fr, tf, segs)
        elsif type == 'butterfly'
          body << H.disc(ents, at, dir, fr * 0.92, len, segs)
          neck_top = fr * 0.92 + 0.35 * od
          body << H.sweep(ents, [0.12 * od, 12.0].max, segs, line: [pt.call(up, fr * 0.8), pt.call(up, neck_top)])
          if od >= 168.0
            gear = [0.35 * od, 40.0].max
            body << H.disc(ents, pt.call(up, neck_top + gear / 2.0), up, gear, gear, segs)
            wheel_c = Vec.add(pt.call(up, neck_top + gear / 2.0), Vec.scale(dir, gear * 0.9))
            wheel << H.disc(ents, wheel_c, dir, [0.45 * od, 80.0].max, 12.0, segs)
          else
            lever(ents, wheel, pt.call(up, neck_top), dir, od, segs)
          end
        else
          # End connections (flanges, or socket/union ends for plastics)
          body << H.disc(ents, pt.call(dir, -(len / 2.0 - tf / 2.0)), dir, fr, tf, segs)
          body << H.disc(ents, pt.call(dir, len / 2.0 - tf / 2.0), dir, fr, tf, segs)
          body_r = od * (type == 'globe' || type == 'prv' ? 0.85 : 0.72)
          body_r = [body_r, fr * 0.95].min
          body << H.sweep(ents, body_r, segs,
                          line: [pt.call(dir, -(len / 2.0 - tf)), pt.call(dir, len / 2.0 - tf)])
          operator(ents, body, wheel, type, info[:operator], at, dir, up, od, body_r, len, segs)
        end

        body.each { |g| g.material = H.valve_material(ctx[:model]) }
        wheel.each { |g| g.material = H.handwheel_material(ctx[:model]) }
        grp.layer = ctx[:tag]
        grp.name = "#{info[:name]} #{spec.size}"
        H.set_attrs(grp, ctx[:common].merge(
          'type' => 'valve', 'valve_type' => type, 'valve_name' => info[:name],
          'valve_rating' => metallic ? 'Class 150' : spec.rating,
          'end_type' => metallic ? 'Flanged' : 'Socket / union',
          'face_to_face' => len, 'at' => JSON.generate(at), 'dir' => JSON.generate(dir),
          'geom' => JSON.generate('a' => pt.call(dir, -len / 2.0), 'b' => pt.call(dir, len / 2.0), 'r' => fr)
        ))
        grp
      end

      def stem_direction(dir)
        z = [0.0, 0.0, 1.0]
        u = Vec.sub(z, Vec.scale(dir, Vec.dot(dir, z)))
        Vec.length(u) < 0.2 ? Vec.perpendicular(dir) : Vec.unit(u)
      end

      def operator(ents, body, wheel, type, kind, at, dir, up, od, body_r, len, segs)
        pt = ->(u, s) { Vec.add(at, Vec.scale(u, s)) }
        case kind
        when :handwheel
          bonnet_h = body_r + (type == 'gate' ? 0.9 : 0.6) * od
          body << H.sweep(ents, 0.45 * od, segs, line: [pt.call(up, body_r * 0.5), pt.call(up, bonnet_h)])
          stem_top = bonnet_h + [(type == 'gate' ? 1.2 : 0.8) * od, 80.0].max
          body << H.sweep(ents, [0.05 * od, 4.0].max, 8, line: [pt.call(up, bonnet_h), pt.call(up, stem_top)])
          wheel << H.disc(ents, pt.call(up, stem_top), up, [0.8 * od, 50.0].max, [0.1 * od, 8.0].max, segs)
        when :lever
          stem_top = body_r + [0.5 * od, 30.0].max
          body << H.sweep(ents, [0.1 * od, 6.0].max, 8, line: [pt.call(up, body_r * 0.5), pt.call(up, stem_top)])
          lever(ents, wheel, pt.call(up, stem_top), dir, od, segs)
        when :none # swing check: bolted cover
          body << H.sweep(ents, 0.5 * od, segs, line: [pt.call(up, body_r * 0.5), pt.call(up, body_r + 0.25 * od)])
        when :basket # Y-strainer: screen leg 45° down-stream
          leg = Vec.unit(Vec.sub(dir, up))
          tip = Vec.add(at, Vec.scale(leg, 0.6 * len))
          body << H.sweep(ents, 0.45 * od, segs, line: [at, tip])
          body << H.disc(ents, tip, leg, 0.55 * od, [0.08 * od, 6.0].max, segs)
        when :pilot # PRV: diaphragm + spring bonnet
          dia = body_r + 0.25 * od
          wheel << H.disc(ents, pt.call(up, dia), up, [0.9 * od, 60.0].max, [0.25 * od, 15.0].max, segs)
          body << H.sweep(ents, 0.35 * od, segs, line: [pt.call(up, dia), pt.call(up, dia + 1.4 * od)])
        end
      end

      def lever(ents, wheel, root, dir, od, segs)
        tip = Vec.add(root, Vec.scale(dir, [2.5 * od, 120.0].max))
        wheel << H.sweep(ents, [0.06 * od, 5.0].max, [segs / 2, 8].max, line: [root, tip])
      end
    end
  end
end
