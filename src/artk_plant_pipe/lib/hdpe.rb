# frozen_string_literal: true

require_relative 'vec'
require_relative 'mesh'
require_relative 'fittings_data'
require_relative 'valve_models'

module ArtK
  module PlantPipe
    # HDPE (PE100) fitting systems – each joins the pipe differently and so
    # looks different:
    #   :fusion        – butt fusion spigot fittings (EN 12201-3 / ISO 4427-3):
    #                    body = pipe OD, straight legs long enough to clamp in
    #                    the fusion machine, a double roll-back bead at every
    #                    joint; from d315 elbows are fabricated from mitred
    #                    segments (one bead per weld).
    #   :electrofusion – EF sockets larger than the pipe (heating wire inside),
    #                    two terminal pins in shrouds and fusion indicators;
    #                    socket length / body OD from GF ELGEF Plus SDR11
    #                    (d20 L70 D31, d63 L96 D81, d110 L145 D138, d160 L180
    #                    D196), larger sizes extrapolated.
    #   :compression   – PP compression fittings (ISO 14236 type, 20–110 mm
    #                    in Thai water supply): black body, blue nut at every
    #                    end, pipe pushed in to the socket bottom.
    # Flanged connections use a PE stub end (collar ≈ raised-face diameter)
    # and a loose steel backing ring drilled like the valve flange.
    #
    # Joint choice ('hdpe_joint' setting): auto = by size, as usually built –
    # ≤ 63 mm compression, 75–110 mm electrofusion, ≥ 125 mm butt fusion.
    module Hdpe
      M = Mesh
      F = FittingsData
      JOINTS = %w[auto butt ef comp].freeze
      STYLES = { 'butt' => :fusion, 'ef' => :electrofusion, 'comp' => :compression }.freeze
      NAMES = {
        fusion: ['ชนหลอม (Butt fusion)', 'Butt fusion spigot'],
        electrofusion: ['หลอมไฟฟ้า (Electrofusion)', 'Electrofusion'],
        compression: ['สวมอัด PP (Compression)', 'Compression (PP)']
      }.freeze
      SEGMENTED_FROM = 315.0 # fabricated (mitred) elbows from this OD
      SEGMENT_DEG = 22.5     # largest turn per mitre weld

      # [d, coupler length L, body OD D] – GF ELGEF Plus SDR11; last two rows
      # extrapolated.
      EF = [[20.0, 70.0, 31.0], [63.0, 96.0, 81.0], [110.0, 145.0, 138.0], [160.0, 180.0, 196.0],
            [315.0, 290.0, 375.0], [630.0, 480.0, 730.0]].freeze
      # [d, equal coupler length, nut OD] – PP compression couplers.
      COMP = [[20.0, 115.0, 48.0], [25.0, 128.0, 55.0], [32.0, 148.0, 66.0], [40.0, 170.0, 80.0],
              [50.0, 198.0, 95.0], [63.0, 232.0, 115.0], [75.0, 280.0, 135.0], [90.0, 320.0, 160.0],
              [110.0, 378.0, 190.0], [160.0, 520.0, 262.0]].freeze
      # PE stub ends pair with the flange of this DN (d110/125 → DN100 …).
      DN = { 20 => 15, 25 => 20, 32 => 25, 40 => 32, 50 => 40, 63 => 50, 75 => 65, 90 => 80, 110 => 100,
             125 => 100, 140 => 125, 160 => 150, 180 => 150, 200 => 200, 225 => 200, 250 => 250, 280 => 250,
             315 => 300, 355 => 350, 400 => 400, 450 => 450, 500 => 500, 560 => 500, 630 => 600 }.freeze
      DN_OD = { 15 => 21.3, 20 => 26.7, 25 => 33.4, 32 => 42.2, 40 => 48.3, 50 => 60.3, 65 => 73.0, 80 => 88.9,
                100 => 114.3, 125 => 141.3, 150 => 168.3, 200 => 219.1, 250 => 273.0, 300 => 323.8,
                350 => 355.6, 400 => 406.4, 450 => 457.0, 500 => 508.0, 600 => 610.0 }.freeze

      module_function

      def joint(value)
        JOINTS.include?(value.to_s) ? value.to_s : 'auto'
      end

      def style(od, value = 'auto')
        STYLES.fetch(joint(value)) do
          if od <= 63.5 then :compression
          elsif od <= 110.5 then :electrofusion
          else :fusion
          end
        end
      end

      # Opts of an HDPE line (only HDPE catalogues use these styles).
      def style?(o)
        %i[fusion electrofusion compression].include?(o.style)
      end

      def name(style, lang = 0)
        NAMES.fetch(style, NAMES[:fusion])[lang]
      end

      def lerp(table, x, col)
        rows = table.map { |r| [r[0], r[col]] }
        return rows.first[1] * x / rows.first[0] if x <= rows.first[0]
        return rows.last[1] * x / rows.last[0] if x >= rows.last[0]

        rows.each_cons(2) do |(x0, y0), (x1, y1)|
          return y0 + (y1 - y0) * (x - x0) / (x1 - x0) if x.between?(x0, x1)
        end
      end

      # ---- dimensions (mm) ----

      # Straight spigot leg of a butt fusion fitting (clamping length).
      def leg(od)
        (0.6 * od + 25.0).round
      end

      def ef_length(od)
        lerp(EF, od, 1).round
      end

      def ef_body(od)
        lerp(EF, od, 2).round
      end

      # Socket depth to the centre stop.
      def ef_socket(od)
        ef_length(od) / 2.0 - 3.0
      end

      def comp_length(od)
        lerp(COMP, od, 1).round
      end

      def comp_nut(od)
        lerp(COMP, od, 2).round
      end

      def comp_socket(od)
        (0.45 * comp_length(od)).round
      end

      def comp_body_r(od)
        0.42 * comp_nut(od)
      end

      def dn(od)
        DN.min_by { |d, _| (d - od).abs }[1]
      end

      # Flange table entry of the DN this stub end belongs to.
      def flange(od)
        F.flange(DN_OD.fetch(dn(od)))
      end

      def stub_collar(od)
        (0.12 * od + 5.0).round
      end

      def stub_length(od)
        [0.6 * od + 20.0, 50.0].max.round
      end

      def segmented?(o)
        o.style == :fusion && o.od >= SEGMENTED_FROM
      end

      # Centre-to-end (to the socket bottom / spigot end) of an elbow.
      def elbow_take(o, deg, radius)
        th = deg * Math::PI / 180.0
        case o.style
        when :electrofusion, :compression
          (0.12 * o.od + 0.25 * o.od * Math.sin(th / 2.0) / Math.sin(Math::PI / 4.0) + 8.0).round(1)
        else
          (leg(o.od) + radius * Math.tan(th / 2.0)).round(1)
        end
      end

      def tee_c(o)
        case o.style
        when :electrofusion then (0.5 * o.od + 8.0).round(1)
        when :compression then (0.5 * o.od + 10.0).round(1)
        else (0.5 * o.od + leg(o.od)).round(1)
        end
      end

      # End-to-end of a reducer between the end points (spigot ends or
      # socket bottoms) – sockets reach past them.
      # Each end contributes half of its system's length: EF / compression
      # reducing couplers are a short core between two sockets, a butt
      # fusion reducer is a cone between two clamping legs.
      def reducer_length(big, small)
        return stepped_length(big, small) if big.style == :fusion && small.style == :fusion

        [big, small].sum do |o|
          case o.style
          when :electrofusion then 0.25 * big.od + 10.0
          when :compression then 0.2 * big.od + 12.0
          else (leg(big.od) + leg(small.od) + [1.2 * (big.od - small.od), 20.0].max) / 2.0
          end
        end.round(1)
      end

      # Standard PE pipe ODs (ISO 4427) – the steps of a stepped reducer.
      ODS = [20, 25, 32, 40, 50, 63, 75, 90, 110, 125, 140, 160, 180, 200, 225, 250, 280, 315, 355, 400, 450,
             500, 560, 630].freeze

      # Outer radii from a to b (either order): the standard sizes in
      # between, at most three, evenly picked.
      def step_ods(a_od, b_od)
        lo, hi = [a_od, b_od].minmax
        mid = ODS.select { |d| d > lo + 0.5 && d < hi - 0.5 }
        mid = (1..3).map { |k| mid[(k * mid.size / 4.0).floor] }.uniq if mid.size > 3
        a_od > b_od ? mid.reverse : mid
      end

      # Stepped butt fusion reducer (as moulded / machined on site): a leg
      # at each end and a short shoulder + collar for every size between.
      def step_profile(a, b, lead: nil, tail: nil)
        targets = step_ods(a.od, b.od).map { |d| d / 2.0 } + [b.ro]
        pts = [[0.0, a.ro]]
        x = lead || 0.6 * leg(a.od)
        r = a.ro
        targets.each_with_index do |r2, i|
          pts << [x, r]                       # end of the collar / leg
          x += (r - r2).abs * 0.6             # shoulder
          pts << [x, r2]
          x += i == targets.size - 1 ? (tail || 0.6 * leg(b.od)) : [0.5 * r2, 12.0].max
          r = r2
        end
        pts << [x, r]
      end

      def stepped_length(a, b, lead: nil, tail: nil)
        step_profile(a, b, lead: lead, tail: tail).last[0].round(1)
      end

      # The reducer solid from a (x = 0) to b; the bore follows the outside
      # at the SDR of each end (a's wall ratio up to the last step).
      def stepped_reducer(a, b, lead: nil, tail: nil, ends: true)
        prof = step_profile(a, b, lead: lead, tail: tail)
        ka = a.ri / a.ro
        inner = prof.each_with_index.map do |(x, r), i|
          [x, i == prof.size - 1 || (r - b.ro).abs < 1e-6 ? b.ri : r * ka]
        end
        loop2d = prof + inner.reverse
        part = Mesh::Part.new
        part.add(:fitting, M.revolve([loop2d], axis_o: [0.0, 0.0, 0.0], axis: [1.0, 0.0, 0.0], steps: [a.steps, b.steps].max))
        len = prof.last[0]
        if ends
          joint_end(part, [0.0, 0.0, 0.0], [-1.0, 0.0, 0.0], a)
          joint_end(part, [len, 0.0, 0.0], [1.0, 0.0, 0.0], b)
        end
        part
      end

      # Radius of the fitting body (insulation, clash).
      def body_radius(o)
        case o.style
        when :electrofusion then ef_body(o.od) / 2.0
        when :compression then comp_body_r(o.od)
        else o.ro
        end
      end

      def ext_radius(o)
        o.style == :compression ? comp_nut(o.od) / 2.0 : body_radius(o)
      end

      # ---- geometry ----

      # Terminals and fusion indicators go on +Z of the part frame (the
      # fitting's own plane normal); flip(-1) builds them on −Z, for parts
      # whose frame has Z pointing down in the model, so they face up.
      def flip(sign)
        old = @up
        @up = sign.negative? ? -1.0 : 1.0
        yield
      ensure
        @up = old
      end

      def up_for(d)
        z = [0.0, 0.0, @up || 1.0]
        u = Vec.sub(z, Vec.scale(d, Vec.dot(d, z)))
        Vec.length(u) < 0.2 ? Vec.unit(Vec.cross(d, [0.0, 1.0, 0.0])) : Vec.unit(u)
      end

      # Joint at end point p, the pipe on the side of direction d.
      def joint_end(part, p, d, o)
        case o.style
        when :electrofusion then ef_socket_end(part, p, d, o)
        when :compression then comp_end(part, p, d, o)
        else bead(part, p, d, o)
        end
        part
      end

      # Double roll-back bead of a butt fusion joint.
      def bead(part, p, d, o)
        return part unless o.detailed?

        r = [o.wall * 0.35, 1.2].max
        [-0.8, 0.8].each do |k|
          part.add(:weld, M.torus(Vec.add(p, Vec.scale(d, k * r)), d, o.ro + r * 0.3, r, steps: o.steps, sec_steps: 6))
        end
        part
      end

      def ef_socket_end(part, p, d, o)
        s = ef_socket(o.od)
        rd = ef_body(o.od) / 2.0
        mouth = Vec.add(p, Vec.scale(d, s))
        part.add(:fitting, M.cylinder(p, mouth, rd, ri: o.ro, steps: o.steps))
        up = up_for(d)
        rt = [[0.05 * rd * 2 + 6.0, 8.0].max, 16.0].min
        ht = [[0.12 * rd * 2 + 8.0, 12.0].max, 30.0].min
        q = Vec.add(Vec.sub(mouth, Vec.scale(d, rt + [0.08 * s, 4.0].max)), Vec.scale(up, rd - 1.0))
        top = Vec.add(q, Vec.scale(up, ht))
        if o.detailed?
          part.add(:fitting, M.cylinder(q, top, rt, ri: rt - 2.5, steps: 12))
          part.add(:fitting, M.cylinder(q, Vec.add(q, Vec.scale(up, ht - 4.0)), rt - 2.5, steps: 12))
          part.add(:brass, M.cylinder(Vec.add(q, Vec.scale(up, ht - 4.0)), Vec.add(q, Vec.scale(up, ht - 1.0)),
                                      od_pin(o.od) / 2.0, steps: 8))
          ind = Vec.sub(q, Vec.scale(d, rt + 6.0))
          part.add(:indicator, M.cylinder(ind, Vec.add(ind, Vec.scale(up, 4.0)), 2.0, steps: 6))
        else
          part.add(:fitting, M.cylinder(q, top, rt, steps: 8))
        end
        part
      end

      # Terminal pin: 4.0 mm on small fittings, 4.7 mm from d63.
      def od_pin(od)
        od < 63.0 ? 4.0 : 4.7
      end

      def comp_end(part, p, d, o)
        sc = comp_socket(o.od)
        rn = comp_nut(o.od) / 2.0
        rb = comp_body_r(o.od)
        b = 0.5 * sc
        nut0 = Vec.add(p, Vec.scale(d, b))
        mouth = Vec.add(p, Vec.scale(d, sc))
        part.add(:fitting, M.cylinder(p, Vec.add(nut0, Vec.scale(d, 2.0)), rb, ri: o.ro, steps: o.steps))
        part.add(:comp_nut, M.cylinder(nut0, mouth, rn, ri: o.ro + 0.6, steps: [o.steps, 24].max))
        return part unless o.detailed?

        # grip ribs round the nut and a lip where the pipe enters
        ref = Vec.perpendicular(d)
        bin = Vec.cross(d, ref)
        w = [0.07 * rn, 2.0].max
        a0 = Vec.add(nut0, Vec.scale(d, 0.12 * (sc - b)))
        a1 = Vec.sub(mouth, Vec.scale(d, 0.12 * (sc - b)))
        8.times do |k|
          t = 2 * Math::PI * k / 8
          off = Vec.add(Vec.scale(ref, rn * Math.cos(t)), Vec.scale(bin, rn * Math.sin(t)))
          part.add(:comp_nut, M.bar(Vec.add(a0, off), Vec.add(a1, off), w, w, off))
        end
        lip = Vec.sub(mouth, Vec.scale(d, [0.06 * sc, 3.0].max))
        part.add(:comp_nut, M.cylinder(lip, mouth, rn * 1.04, ri: o.ro + 0.6, steps: [o.steps, 24].max))
        part
      end

      # Elbow starting at the origin heading +X, turning towards +Y about +Z,
      # ending at T·(1 + d_out) – T = the take the network trimmed to.
      def elbow(angle, take, o, radius)
        part = Mesh::Part.new
        d_out = [Math.cos(angle), Math.sin(angle), 0.0]
        v = [take, 0.0, 0.0]
        e = Vec.add(v, Vec.scale(d_out, take))
        case o.style
        when :electrofusion, :compression
          r = (o.style == :electrofusion ? ef_body(o.od) / 2.0 : comp_body_r(o.od)) * 0.94
          part.add(:fitting, M.cylinder([0, 0, 0], v, r, ri: o.ri, steps: o.steps))
          part.add(:fitting, M.cylinder(v, e, r, ri: o.ri, steps: o.steps))
          part.add(:fitting, M.sphere(v, r, steps: o.steps))
        else
          lg = [leg(o.od), take * 0.9].min
          r = (take - lg) / Math.tan(angle / 2.0)
          r = radius if r <= 0.0
          if segmented?(o)
            M.sweep(segment_points(angle, take, lg, r), o.ro, o.ri, steps: o.steps).first.tap { |s| part.add(:fitting, s) }
            mitres(angle, take, lg, r).each { |pt, n| bead(part, pt, n, o) }
          else
            t1 = [lg, 0.0, 0.0]
            part.add(:fitting, M.cylinder([0, 0, 0], t1, o.ro, ri: o.ri, steps: o.steps)) if lg > 0.5
            arc_steps = [(angle / (Math::PI / 2) * (o.steps / 2)).ceil, 2].max
            part.add(:fitting, M.bend([lg, r, 0], [0, -1, 0], [0, 0, 1], r, angle, o.ro, o.ri,
                                      steps: o.steps, arc_steps: arc_steps))
            t2 = [lg + r * Math.sin(angle), r * (1 - Math.cos(angle)), 0.0]
            part.add(:fitting, M.cylinder(t2, e, o.ro, ri: o.ri, steps: o.steps)) if lg > 0.5
          end
        end
        joint_end(part, [0.0, 0.0, 0.0], [-1.0, 0.0, 0.0], o)
        joint_end(part, e, d_out, o)
      end

      def welds(angle)
        [(angle * 180.0 / Math::PI / SEGMENT_DEG - 1e-6).ceil, 1].max
      end

      # Centre line of a segmented bend: legs, then n mitres on the polyline
      # circumscribing the arc of radius r.
      def segment_points(angle, take, lg, r)
        n = welds(angle)
        phi = angle / n
        half = r * Math.tan(phi / 2.0)
        pts = [[0.0, 0.0, 0.0]]
        p = [lg + half, 0.0, 0.0]
        n.times do |k|
          pts << p
          dir = [Math.cos(phi * (k + 1)), Math.sin(phi * (k + 1)), 0.0]
          p = Vec.add(p, Vec.scale(dir, 2.0 * half))
        end
        d_out = [Math.cos(angle), Math.sin(angle), 0.0]
        pts << Vec.add([take, 0.0, 0.0], Vec.scale(d_out, take))
      end

      # [point, mitre-plane normal] of each weld of a segmented bend.
      def mitres(angle, take, lg, r)
        pts = segment_points(angle, take, lg, r)
        pts[1..-2].each_with_index.map do |p, i|
          a = Vec.unit(Vec.sub(p, pts[i]))
          b = Vec.unit(Vec.sub(pts[i + 2], p))
          [p, Vec.unit(Vec.add(a, b))]
        end
      end

      # In-line coupler at a stick joint, centred on the origin along +X:
      # EF / compression coupler, or the bead of a butt fusion joint.
      def coupler(o)
        part = Mesh::Part.new
        case o.style
        when :electrofusion, :compression
          r = o.style == :electrofusion ? ef_body(o.od) / 2.0 : comp_body_r(o.od)
          part.add(:fitting, M.cylinder([-1.5, 0, 0], [1.5, 0, 0], r, ri: o.ri, steps: o.steps))
          joint_end(part, [1.5, 0.0, 0.0], [1.0, 0.0, 0.0], o)
          joint_end(part, [-1.5, 0.0, 0.0], [-1.0, 0.0, 0.0], o)
        else
          bead(part, [0.0, 0.0, 0.0], [1.0, 0.0, 0.0], o)
        end
        part
      end

      # PE stub end + loose steel backing ring. Mating (collar) face at
      # x = 0 facing −X, spigot towards +X, joined to the pipe at its end.
      def stub_flange(o, part = Mesh::Part.new, frame = nil)
        fl = flange(o.od)
        h = stub_collar(o.od)
        ls = stub_length(o.od)
        rc = fl.raised_face / 2.0
        sub = Mesh::Part.new
        sub.add(:fitting, M.cylinder([0, 0, 0], [h, 0, 0], rc, ri: o.ri, steps: o.steps))
        fil = [0.12 * o.od, 8.0].max
        sub.add(:fitting, M.frustum([h, 0, 0], [h + fil, 0, 0], o.ro + 0.05 * o.od, o.ro, ri1: o.ri, ri2: o.ri,
                                    steps: o.steps))
        sub.add(:fitting, M.cylinder([h + fil, 0, 0], [ls, 0, 0], o.ro, ri: o.ri, steps: o.steps))
        ring_ri = o.ro + 0.06 * o.od + 1.0
        x0 = h + 0.5
        if o.detailed?
          sub.add(:galv, M.holed_disc([x0, 0, 0], [1.0, 0, 0], fl.od / 2.0, ring_ri, fl.thickness, fl.bolt_circle / 2.0,
                                      fl.bolts, fl.hole / 2.0, steps: [o.steps, 24].max, hole_steps: 8))
        else
          sub.add(:galv, M.cylinder([x0, 0, 0], [x0 + fl.thickness, 0, 0], fl.od / 2.0, ri: ring_ri, steps: o.steps))
        end
        stub_joint(sub, ls, o)
        frame ? part.merge(sub, frame) : part.merge(sub)
        part
      end

      # Stub spigot to pipe: bead (butt), EF coupler, or the adaptor's own
      # compression end.
      def stub_joint(part, ls, o)
        case o.style
        when :electrofusion
          s = ef_socket(o.od)
          c = Mesh::Part.new
          c.add(:fitting, M.cylinder([-1.5, 0, 0], [1.5, 0, 0], ef_body(o.od) / 2.0, ri: o.ro, steps: o.steps))
          joint_end(c, [1.5, 0.0, 0.0], [1.0, 0.0, 0.0], o)
          joint_end(c, [-1.5, 0.0, 0.0], [-1.0, 0.0, 0.0], o)
          part.merge(c, M.frame([ls, 0, 0], [1, 0, 0], [0, 1, 0])) if s.positive?
        else
          joint_end(part, [ls, 0.0, 0.0], [1.0, 0.0, 0.0], o)
        end
      end

      # Length a stub assembly adds beyond the face it bolts to.
      def stub_reach(o)
        stub_length(o.od) + (o.style == :electrofusion ? ef_socket(o.od) + 1.5 : 0.0)
      end

      # Two stub ends face to face (gasket between) bolted through the rings.
      def flange_pair(o)
        part = Mesh::Part.new
        g = 3.0
        stub_flange(o, part, M.frame([g / 2.0, 0, 0], [1, 0, 0], [0, 1, 0]))
        stub_flange(o, part, M.frame([-g / 2.0, 0, 0], [-1, 0, 0], [0, -1, 0])) # keeps +Z up
        fl = flange(o.od)
        part.add(:gasket, M.cylinder([-g / 2.0, 0, 0], [g / 2.0, 0, 0], fl.raised_face / 2.0, ri: o.ri, steps: o.steps))
        x = g / 2.0 + stub_collar(o.od) + 0.5 + fl.thickness
        bolts(part, fl, -x, x) if o.detailed?
        part
      end

      # Flanged valve (cast body, Class 150 – the DN of the stub ends) with a
      # stub end + backing ring bolted to each face.
      def flanged_valve(type, o, vo)
        part = ValveModels.build(type, vo, :flanged)
        len = F.face_to_face(type, vo.od, :flanged)
        g = 3.0
        fl = F.flange(vo.od)
        [1.0, -1.0].each do |s|
          face = s * (len / 2.0 + g)
          stub_flange(o, part, M.frame([face, 0, 0], [s, 0, 0], [0, s, 0])) # +Z stays up
          part.add(:gasket, M.cylinder([s * len / 2.0, 0, 0], [face, 0, 0], fl.raised_face / 2.0, ri: o.ri, steps: o.steps))
          next unless o.detailed?

          x0 = s * (len / 2.0 - 1.6 - fl.thickness)
          x1 = s * (len / 2.0 + g + stub_collar(o.od) + 0.5 + fl.thickness)
          bolts(part, fl, *[x0, x1].sort)
        end
        part
      end

      def valve_length(type, o, vo)
        F.face_to_face(type, vo.od, :flanged) + 2.0 * (3.0 + stub_reach(o))
      end

      def bolts(part, fl, x0, x1)
        r = fl.hole / 2.0 * 0.85
        nut = r * 1.7
        fl.bolts.times do |k|
          t = 2 * Math::PI * (k + 0.5) / fl.bolts
          y = fl.bolt_circle / 2.0 * Math.cos(t)
          z = fl.bolt_circle / 2.0 * Math.sin(t)
          part.add(:bolt, M.cylinder([x0 - r * 1.6, y, z], [x1 + r * 1.6, y, z], r, steps: 6))
          [[x0 - r * 1.2, x0], [x1, x1 + r * 1.2]].each do |a, b|
            part.add(:bolt, M.ngon_prism([a, y, z], [b, y, z], nut, 6))
          end
        end
        part
      end
    end
  end
end
