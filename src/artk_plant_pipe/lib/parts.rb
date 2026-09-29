# frozen_string_literal: true

require_relative 'vec'
require_relative 'mesh'
require_relative 'fittings_data'

module ArtK
  module PlantPipe
    # Parametric part library (pure Ruby, millimetres).
    #
    # Each builder returns a Mesh::Part in a canonical frame so SketchUp can
    # store it once as a ComponentDefinition and place instances:
    #   pipe   – from origin along +X
    #   elbow  – starts at origin heading +X, bends towards +Y about +Z
    #   tee    – centre at origin, arms given as unit vectors in the XY plane
    #   flange – mating face at x = 0, hub towards +X
    #   valve  – centre at origin, flow along +X, stem/operator towards +Z
    #
    # Joint styles follow the catalogue: :butt_weld (steel, stainless),
    # :fusion (HDPE butt fusion), :socket (PVC/PP-R solvent/fusion sockets,
    # copper solder cups) and :threaded (galvanised malleable iron, banded).
    # LOD :detailed adds bolt holes, bolts, spokes, beads and hub lips;
    # :light keeps only the silhouette for very large plant models.
    module Parts
      M = Mesh
      F = FittingsData

      Opts = Struct.new(:od, :id, :wall, :style, :lod, :steps, keyword_init: true) do
        def detailed?
          lod == :detailed
        end

        def ro
          od / 2.0
        end

        def ri
          id / 2.0
        end
      end

      module_function

      def opts(spec, lod: :detailed, steps: 16)
        Opts.new(od: spec.od.to_f, id: spec.id.to_f, wall: spec.wall.to_f,
                 style: (spec.respond_to?(:style) && spec.style) || :butt_weld,
                 lod: lod.to_sym, steps: steps)
      end

      # ---------------------------------------------------------------
      # Pipe & insulation
      # ---------------------------------------------------------------

      def pipe(len, o)
        Mesh::Part.new.add(:pipe, M.cylinder([0, 0, 0], [len, 0, 0], o.ro, ri: o.ri, steps: o.steps))
      end

      # Straight insulation shell (a, b in any frame).
      def insulation_tube(a, b, r_in, thickness, steps)
        M.cylinder(a, b, r_in + thickness, ri: r_in + 0.5, steps: steps)
      end

      # ---------------------------------------------------------------
      # Joint ends (hubs, bands, beads) shared by fittings
      # ---------------------------------------------------------------

      def hub_thickness(o)
        [o.wall * 1.3, 0.05 * o.od + 1.5].max
      end

      # Outer radius of a fitting body between its ends.
      def body_radius(o)
        case o.style
        when :socket then o.ro + 0.75 * hub_thickness(o)
        when :threaded then o.ro * 1.12
        else o.ro
        end
      end

      # How far a pipe enters the fitting past the fitting's end point.
      def insertion(o)
        case o.style
        when :socket then F.socket_depth(o.od)
        when :threaded then F.thread_engagement(o.od)
        else 0.0
        end
      end

      # End feature at point p, opening in direction d (pointing away from
      # the fitting body, towards the pipe).
      def joint_end(part, p, d, o)
        case o.style
        when :socket
          s = F.socket_depth(o.od)
          rh = o.ro + hub_thickness(o)
          part.add(:fitting, M.cylinder(p, Vec.add(p, Vec.scale(d, s)), rh, ri: o.ro, steps: o.steps))
          if o.detailed?
            lip = [s * 0.12, 3.0].max
            tip = Vec.add(p, Vec.scale(d, s))
            part.add(:fitting, M.cylinder(Vec.sub(tip, Vec.scale(d, lip)), tip, rh + [0.012 * o.od, 0.6].max,
                                          ri: rh - 0.2, steps: o.steps))
          end
        when :threaded
          band = [0.22 * o.od, 6.0].max
          e = F.thread_engagement(o.od)
          part.add(:fitting, M.cylinder(p, Vec.add(p, Vec.scale(d, e)), o.ro * 1.12, ri: o.ro, steps: o.steps))
          if o.detailed?
            tip = Vec.add(p, Vec.scale(d, e))
            part.add(:fitting, M.cylinder(Vec.sub(tip, Vec.scale(d, band)), tip, o.ro * 1.3, ri: o.ro * 1.12 - 0.3,
                                          steps: o.steps))
          end
        when :butt_weld
          part.add(:weld, M.torus(p, d, o.ro, [o.wall * 0.45, 1.0].max, steps: o.steps, sec_steps: 6)) if o.detailed?
        when :fusion
          if o.detailed? # characteristic double fusion bead
            r = [o.wall * 0.35, 1.2].max
            [-0.8, 0.8].each do |k|
              part.add(:weld, M.torus(Vec.add(p, Vec.scale(d, k * r)), d, o.ro + r * 0.3, r, steps: o.steps, sec_steps: 6))
            end
          end
        end
        part
      end

      # ---------------------------------------------------------------
      # Fittings
      # ---------------------------------------------------------------

      # Elbow of +angle+ (rad) and centreline radius +r+.
      def elbow(angle, r, o)
        part = Mesh::Part.new
        arc_steps = [(angle / (Math::PI / 2) * (o.steps / 2)).ceil, 2].max
        part.add(:fitting, M.bend([0, r, 0], [0, -1, 0], [0, 0, 1], r, angle, body_radius(o), o.ri,
                                  steps: o.steps, arc_steps: arc_steps))
        e = [r * Math.sin(angle), r * (1 - Math.cos(angle)), 0.0]
        d_out = [Math.cos(angle), Math.sin(angle), 0.0]
        joint_end(part, [0.0, 0.0, 0.0], [-1.0, 0.0, 0.0], o)
        joint_end(part, e, d_out, o)
      end

      # Tee / lateral / cross: arms = [[unit dir (XY plane), c, opts], ...].
      # Opposite arms are modelled as one through-bore.
      def branch(arms)
        part = Mesh::Part.new
        used = []
        arms.each_with_index do |(d, c, o), i|
          next if used.include?(i)

          j = arms.each_index.find { |k| k != i && !used.include?(k) && Vec.dot(arms[k][0], d) < -0.999 }
          if j
            d2, c2, o2 = arms[j]
            part.add(:fitting, M.cylinder(Vec.scale(d2, c2), Vec.scale(d, c), body_radius(o), ri: o.ri, steps: o.steps))
            joint_end(part, Vec.scale(d2, c2), d2, o2)
            used << j
          else
            part.add(:fitting, M.cylinder([0, 0, 0], Vec.scale(d, c), body_radius(o), ri: o.ri, steps: o.steps))
          end
          joint_end(part, Vec.scale(d, c), d, o)
          used << i
        end
        part
      end

      # Weld-neck flange (steel) or stub/adaptor flange (plastics):
      # mating face at x = 0 facing −X, hub towards +X.
      def flange(o, holes: true)
        fl = F.flange(o.od)
        part = Mesh::Part.new
        ax = [1.0, 0.0, 0.0]
        rf = o.detailed? ? 1.6 : 0.0
        if o.detailed? && holes
          part.add(:flange, M.holed_disc([rf, 0, 0], ax, fl.od / 2.0, o.ri, fl.thickness, fl.bolt_circle / 2.0,
                                         fl.bolts, fl.hole / 2.0, steps: [o.steps, 24].max, hole_steps: 8))
          part.add(:flange, M.cylinder([0, 0, 0], [rf, 0, 0], fl.raised_face / 2.0, ri: o.ri, steps: o.steps))
        else
          part.add(:flange, M.cylinder([0, 0, 0], [fl.thickness, 0, 0], fl.od / 2.0, ri: o.ri, steps: o.steps))
        end
        t = fl.thickness + rf
        if %i[butt_weld fusion].include?(o.style)
          hub = [fl.hub_length - fl.thickness, 10.0].max
          part.add(:flange, M.frustum([t, 0, 0], [t + hub, 0, 0], fl.hub_base / 2.0, o.ro, ri1: o.ri, ri2: o.ri,
                                      steps: o.steps))
        else
          hub = F.socket_depth(o.od)
          part.add(:flange, M.cylinder([t, 0, 0], [t + hub, 0, 0], o.ro + hub_thickness(o), ri: o.ro, steps: o.steps))
        end
        part
      end

      # Studs + nuts through a flange pair whose faces are at x0 and x1.
      def bolts(part, o, x0, x1)
        fl = F.flange(o.od)
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

      # ---------------------------------------------------------------
      # Valves
      # ---------------------------------------------------------------

      # type: gate, globe, ball, butterfly, check, strainer, prv, flange
      def valve(type, o, metallic: true)
        len = F.face_to_face(type, o.od)
        d = o.od
        part = Mesh::Part.new
        fl = F.flange(d)
        tf = fl.thickness

        ends = lambda do
          if metallic
            [[-len / 2.0, 1.0], [len / 2.0, -1.0]].each do |x, s|
              # flange mating face at the valve end, body side inwards
              f = M.frame([x, 0, 0], [s, 0, 0], [0, 1, 0])
              part.merge(flange_disc(o, holes: true), f)
            end
          else
            union_ends(part, o, len)
          end
        end

        case type
        when 'flange' then return flange_pair(o)
        when 'gate' then ends.call
                         gate_body(part, o, len, tf)
        when 'globe' then ends.call
                          globe_body(part, o, len, tf)
        when 'ball'
          if metallic
            ends.call
            ball_body(part, o, len, tf)
          else
            true_union_ball(part, o, len)
          end
        when 'butterfly' then butterfly_body(part, o, len, metallic)
        when 'check' then ends.call
                          check_body(part, o, len, tf)
        when 'strainer' then ends.call
                             strainer_body(part, o, len, tf)
        when 'prv' then ends.call
                        prv_body(part, o, len, tf)
        else raise ArgumentError, "unknown valve #{type}"
        end
        part
      end

      # Flange disc without hub (valve end flanges).
      def flange_disc(o, holes: true)
        fl = F.flange(o.od)
        part = Mesh::Part.new
        if o.detailed? && holes
          part.add(:valve, M.holed_disc([0, 0, 0], [1, 0, 0], fl.od / 2.0, o.ri, fl.thickness, fl.bolt_circle / 2.0,
                                        fl.bolts, fl.hole / 2.0, steps: [o.steps, 24].max, hole_steps: 8))
        else
          part.add(:valve, M.cylinder([0, 0, 0], [fl.thickness, 0, 0], fl.od / 2.0, ri: o.ri, steps: o.steps))
        end
        part
      end

      def flange_pair(o)
        part = Mesh::Part.new
        gasket = 3.0
        part.merge(flange(o), M.frame([gasket / 2.0, 0, 0], [1, 0, 0], [0, 1, 0]))
        part.merge(flange(o), M.frame([-gasket / 2.0, 0, 0], [-1, 0, 0], [0, 1, 0]))
        fl = F.flange(o.od)
        part.add(:gasket, M.cylinder([-gasket / 2.0, 0, 0], [gasket / 2.0, 0, 0], fl.raised_face / 2.0, ri: o.ri,
                                     steps: o.steps))
        bolts(part, o, -gasket / 2.0 - fl.thickness - 1.6, gasket / 2.0 + fl.thickness + 1.6) if o.detailed?
        part
      end

      # Plastic valves: socket union ends with polygonal union nuts.
      def union_ends(part, o, len)
        s = F.socket_depth(o.od)
        nut_r = o.ro * 1.55
        [[-1.0], [1.0]].each do |(sg)|
          tip = [sg * len / 2.0, 0, 0]
          root = [sg * (len / 2.0 - s), 0, 0]
          part.add(:valve, M.cylinder(root, tip, o.ro + hub_thickness(o), ri: o.ro, steps: o.steps))
          n0 = [sg * (len / 2.0 - s * 0.9), 0, 0]
          n1 = [sg * (len / 2.0 - s * 0.9 - 0.3 * o.od - 6), 0, 0]
          part.add(:valve, o.detailed? ? M.ngon_prism(n1, n0, nut_r, 12) : M.cylinder(n1, n0, nut_r, steps: o.steps))
        end
      end

      def stem_and_wheel(part, o, z0, z1, wheel_r, spokes)
        part.add(:valve, M.cylinder([0, 0, z0], [0, 0, z1 + 0.15 * o.od], [0.05 * o.od, 3.0].max, steps: 8))
        rim = [0.06 * wheel_r, 3.0].max
        part.add(:handle, M.torus([0, 0, z1], [0, 0, 1], wheel_r, rim, steps: [o.steps, 20].max, sec_steps: 6))
        hub_r = [0.12 * wheel_r, 6.0].max
        part.add(:handle, M.cylinder([0, 0, z1 - rim], [0, 0, z1 + rim], hub_r, steps: 12))
        if o.detailed?
          spokes.times do |k|
            t = 2 * Math::PI * k / spokes
            u = [Math.cos(t), Math.sin(t), 0.0]
            part.add(:handle, M.cylinder(Vec.add([0, 0, z1], Vec.scale(u, hub_r * 0.8)),
                                         Vec.add([0, 0, z1], Vec.scale(u, wheel_r)), rim * 0.8, steps: 6))
          end
        else
          part.add(:handle, M.cylinder([0, 0, z1 - rim * 0.4], [0, 0, z1 + rim * 0.4], wheel_r, steps: [o.steps, 20].max))
        end
      end

      # Gate: tall wedge chamber, bolted bonnet, yoke with rising stem.
      def gate_body(part, o, len, tf)
        d = o.od
        inner = len / 2.0 - tf
        part.add(:valve, M.cylinder([-inner, 0, 0], [inner, 0, 0], d * 0.62, ri: o.ri, steps: o.steps))
        cr = [0.34 * len, 0.62 * d].min
        part.add(:valve, M.cylinder([0, 0, -0.62 * d], [0, 0, 0.95 * d], cr, steps: o.steps))
        part.add(:valve, M.cylinder([0, 0, 0.95 * d], [0, 0, 1.08 * d], cr * 1.3, steps: o.steps)) # bonnet flange
        part.add(:valve, M.frustum([0, 0, 1.08 * d], [0, 0, 1.75 * d], cr * 0.9, cr * 0.45, steps: o.steps))
        # yoke: two posts and a top bridge
        yo = cr * 0.55
        w = [0.09 * d, 5.0].max
        [-1, 1].each do |s|
          part.add(:valve, Mesh.bar([0, s * yo, 1.75 * d], [0, s * yo, 2.55 * d], w, w))
        end
        part.add(:valve, Mesh.bar([0, -yo - w / 2, 2.55 * d], [0, yo + w / 2, 2.55 * d], w * 1.4, w * 1.4))
        wheel = [0.75 * d, 45.0].max
        stem_and_wheel(part, o, 1.08 * d, 2.7 * d, wheel, 3)
        # rising stem above the handwheel
        part.add(:valve, M.cylinder([0, 0, 2.7 * d], [0, 0, 3.3 * d], [0.05 * d, 3.0].max, steps: 8))
        bonnet_bolts(part, o, 1.02 * d, cr * 1.15) if o.detailed?
      end

      # Globe: spherical body, short bonnet, handwheel (non-rising yoke).
      def globe_body(part, o, len, tf)
        d = o.od
        inner = len / 2.0 - tf
        part.add(:valve, M.cylinder([-inner, 0, 0], [inner, 0, 0], d * 0.6, ri: o.ri, steps: o.steps))
        part.add(:valve, M.sphere([0, 0, 0], [0.9 * d, 0.36 * len].min, steps: o.steps))
        part.add(:valve, M.cylinder([0, 0, 0.5 * d], [0, 0, 0.95 * d], 0.55 * d, steps: o.steps))
        part.add(:valve, M.cylinder([0, 0, 0.95 * d], [0, 0, 1.07 * d], 0.72 * d, steps: o.steps))
        part.add(:valve, M.frustum([0, 0, 1.07 * d], [0, 0, 1.6 * d], 0.45 * d, 0.22 * d, steps: o.steps))
        stem_and_wheel(part, o, 1.07 * d, 1.9 * d, [0.6 * d, 40.0].max, 5)
        bonnet_bolts(part, o, 1.01 * d, 0.62 * d) if o.detailed?
      end

      def bonnet_bolts(part, o, z, r, cx = 0.0)
        n = o.od >= 150 ? 8 : 4
        b = [0.035 * o.od, 2.5].max
        n.times do |k|
          t = 2 * Math::PI * (k + 0.5) / n
          x = cx + r * Math.cos(t)
          y = r * Math.sin(t)
          part.add(:bolt, M.ngon_prism([x, y, z + 0.06 * o.od], [x, y, z + 0.06 * o.od + b * 1.4], b * 1.6, 6))
        end
      end

      # Floating ball, flanged: round body, square stem, flat lever along the pipe.
      def ball_body(part, o, len, tf)
        d = o.od
        inner = len / 2.0 - tf
        part.add(:valve, M.cylinder([-inner, 0, 0], [inner, 0, 0], d * 0.62, ri: o.ri, steps: o.steps))
        part.add(:valve, M.sphere([0, 0, 0], [0.85 * d, 0.4 * len].min, steps: o.steps))
        top = [0.85 * d, 0.4 * len].min
        part.add(:valve, M.cylinder([0, 0, top * 0.8], [0, 0, top + 0.35 * d], [0.16 * d, 8.0].max, steps: 12))
        lever(part, o, top + 0.35 * d)
      end

      def lever(part, o, z)
        d = o.od
        l = [2.6 * d, 130.0].max
        w = [0.2 * d, 14.0].max
        t = [0.05 * d, 4.0].max
        part.add(:handle, Mesh.bar([-w * 0.6, 0, z], [l, 0, z], w, t, [0, 0, 1]))
        part.add(:handle, M.cylinder([l * 0.72, 0, z], [l, 0, z], w * 0.55, steps: 10)) if o.detailed?
      end

      # PVC / PP-R true-union ball valve.
      def true_union_ball(part, o, len)
        union_ends(part, o, len)
        d = o.od
        body_l = len - 2 * F.socket_depth(d)
        part.add(:valve, M.cylinder([-body_l / 2.0, 0, 0], [body_l / 2.0, 0, 0], d * 0.8, ri: o.ri, steps: o.steps))
        part.add(:valve, M.sphere([0, 0, 0], d * 0.95, steps: o.steps))
        part.add(:valve, M.cylinder([0, 0, d * 0.8], [0, 0, d * 1.15], d * 0.22, steps: 12))
        # T-handle across the pipe
        w = [0.28 * d, 12.0].max
        part.add(:handle, Mesh.box(M.frame([0, 0, d * 1.25], [1, 0, 0], [0, 1, 0]), [0, 0, 0], [w, [1.9 * d, 70.0].max, w * 0.5]))
      end

      # Wafer butterfly between companion flanges; lever < 6", gearbox ≥ 6".
      def butterfly_body(part, o, len, metallic)
        d = o.od
        fl = F.flange(d)
        body_r = (metallic ? fl.bolt_circle / 2.0 - fl.hole : o.ro * 1.5)
        part.add(:valve, M.cylinder([-len / 2.0, 0, 0], [len / 2.0, 0, 0], body_r, ri: o.ri, steps: o.steps))
        part.add(:handle, M.cylinder([-0.04 * d, 0, 0], [0.04 * d, 0, 0], o.ri * 0.96, steps: o.steps)) # disc
        neck_top = body_r + 0.45 * d
        part.add(:valve, M.cylinder([0, 0, body_r * 0.9], [0, 0, neck_top], [0.12 * d, 10.0].max, steps: 12))
        part.add(:valve, Mesh.box(M.frame([0, 0, neck_top], [1, 0, 0], [0, 1, 0]), [0, 0, 4], [0.5 * d, 0.5 * d, 8]))
        if d >= 168.0
          g = [0.4 * d, 80.0].max
          part.add(:valve, Mesh.box(M.frame([0, 0, neck_top + 8], [1, 0, 0], [0, 1, 0]), [0, 0, g / 2], [g, g * 0.9, g]))
          hw = [0.45 * d, 90.0].max
          part.add(:valve, M.cylinder([0, g * 0.45, neck_top + 8 + g / 2], [0, g * 0.45 + g * 0.6, neck_top + 8 + g / 2],
                                      [0.05 * d, 6.0].max, steps: 8))
          part.add(:handle, M.torus([0, g * 1.05, neck_top + 8 + g / 2], [0, 1, 0], hw, [0.04 * hw, 4.0].max,
                                    steps: 20, sec_steps: 6))
        else
          # notch plate + lever
          part.add(:valve, M.cylinder([0, 0, neck_top + 8], [0, 0, neck_top + 12], 0.55 * d, steps: o.steps))
          lever(part, o, neck_top + 20)
        end
        return unless metallic

        [[-len / 2.0, -1.0], [len / 2.0, 1.0]].each do |x, s|
          part.merge(flange(o), M.frame([x, 0, 0], [s, 0, 0], [0, 1, 0]))
        end
        bolts(part, o, -len / 2.0 - fl.thickness - 1.6, len / 2.0 + fl.thickness + 1.6) if o.detailed?
      end

      # Swing check: horizontal body, inclined bolted cover, flow arrow.
      def check_body(part, o, len, tf)
        d = o.od
        inner = len / 2.0 - tf
        part.add(:valve, M.cylinder([-inner, 0, 0], [inner, 0, 0], d * 0.7, ri: o.ri, steps: o.steps))
        part.add(:valve, M.cylinder([-0.1 * len, 0, 0.3 * d], [-0.1 * len, 0, 0.95 * d], 0.6 * d, steps: o.steps))
        part.add(:valve, M.cylinder([-0.1 * len, 0, 0.95 * d], [-0.1 * len, 0, 1.08 * d], 0.72 * d, steps: o.steps))
        bonnet_bolts(part, o, 1.02 * d, 0.64 * d, -0.1 * len) if o.detailed?
        # flow arrow on the side (+Y)
        y = d * 0.7
        a = 0.28 * len
        arrow = [[-a, y, -0.08 * d], [a * 0.4, y, -0.08 * d], [a * 0.4, y, -0.2 * d], [a, y, 0.0],
                 [a * 0.4, y, 0.2 * d], [a * 0.4, y, 0.08 * d], [-a, y, 0.08 * d]]
        # split into two convex prisms (shaft + head)
        part.add(:handle, M.extrude([arrow[0], arrow[1], arrow[5], arrow[6]], [0, 2.5, 0]))
        part.add(:handle, M.extrude([arrow[2], arrow[3], arrow[4]], [0, 2.5, 0]))
      end

      # Y-strainer: screen leg at 45° downstream-down, cap and drain plug.
      def strainer_body(part, o, len, tf)
        d = o.od
        inner = len / 2.0 - tf
        part.add(:valve, M.cylinder([-inner, 0, 0], [inner, 0, 0], d * 0.62, ri: o.ri, steps: o.steps))
        leg = Vec.unit([1.0, 0.0, -1.0])
        tip = Vec.scale(leg, 0.55 * len)
        part.add(:valve, M.cylinder([0, 0, 0], tip, d * 0.48, steps: o.steps))
        part.add(:valve, M.cylinder(tip, Vec.add(tip, Vec.scale(leg, 0.08 * d + 4)), d * 0.6, steps: o.steps))
        plug_a = Vec.add(tip, Vec.scale(leg, 0.08 * d + 4))
        part.add(:bolt, M.ngon_prism(plug_a, Vec.add(plug_a, Vec.scale(leg, 0.12 * d + 4)), [0.12 * d, 6.0].max, 6))
      end

      # Pressure-reducing valve: globe body, diaphragm housing, spring bonnet.
      def prv_body(part, o, len, tf)
        d = o.od
        inner = len / 2.0 - tf
        part.add(:valve, M.cylinder([-inner, 0, 0], [inner, 0, 0], d * 0.6, ri: o.ri, steps: o.steps))
        part.add(:valve, M.sphere([0, 0, 0], [0.85 * d, 0.36 * len].min, steps: o.steps))
        part.add(:valve, M.cylinder([0, 0, 0.5 * d], [0, 0, 1.0 * d], 0.3 * d, steps: o.steps))
        dia = [1.05 * d, 70.0].max
        part.add(:handle, M.frustum([0, 0, 1.0 * d], [0, 0, 1.18 * d], dia * 0.8, dia, steps: o.steps))
        part.add(:handle, M.frustum([0, 0, 1.18 * d], [0, 0, 1.36 * d], dia, dia * 0.8, steps: o.steps))
        part.add(:valve, M.frustum([0, 0, 1.36 * d], [0, 0, 2.4 * d], 0.42 * d, 0.3 * d, steps: o.steps))
        part.add(:bolt, M.cylinder([0, 0, 2.4 * d], [0, 0, 2.7 * d], [0.06 * d, 4.0].max, steps: 8))
        part.add(:bolt, M.ngon_prism([0, 0, 2.4 * d], [0, 0, 2.48 * d], [0.12 * d, 7.0].max, 6))
      end
    end
  end
end
