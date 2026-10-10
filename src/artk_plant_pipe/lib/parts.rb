# frozen_string_literal: true

require_relative 'vec'
require_relative 'mesh'
require_relative 'fittings_data'
require_relative 'valve_models'
require_relative 'hdpe'

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
    # :socket (PVC/PP-R solvent/fusion sockets, copper solder cups) and
    # :threaded (galvanised malleable iron, banded). HDPE lines use :fusion,
    # :electrofusion or :compression (see Hdpe – chosen by the 'hdpe_joint'
    # setting and the size).
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

      def opts(spec, lod: :detailed, steps: 16, joint: nil)
        style = (spec.respond_to?(:style) && spec.style) || :butt_weld
        # Small-bore steel (< 2") is socket-welded with forged fittings in
        # practice (ASME B16.11), not butt-welded.
        style = :socket_weld if style == :butt_weld && spec.od < 60.0
        style = Hdpe.style(spec.od.to_f, joint) if spec.respond_to?(:family) && spec.family == 'HDPE'
        Opts.new(od: spec.od.to_f, id: spec.id.to_f, wall: spec.wall.to_f, style: style,
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
        return [0.26 * o.od, 5.0].max if o.style == :socket_weld # forged Class 3000

        [o.wall * 1.3, 0.05 * o.od + 1.5].max
      end

      # Outer radius of a fitting body between its ends.
      def body_radius(o)
        case o.style
        when :socket then o.ro + 0.75 * hub_thickness(o)
        when :socket_weld then o.ro + 0.85 * hub_thickness(o)
        when :threaded then o.ro * 1.12
        when :electrofusion, :compression then Hdpe.body_radius(o)
        else o.ro
        end
      end

      # How far a pipe enters the fitting past the fitting's end point.
      def insertion(o)
        case o.style
        when :socket then F.socket_depth(o.od)
        when :socket_weld then [0.38 * o.od, 10.0].max.round(1) # ≈ B16.11 socket depth
        when :threaded then F.thread_engagement(o.od)
        else 0.0
        end
      end

      # End feature at point p, opening in direction d (pointing away from
      # the fitting body, towards the pipe).
      def joint_end(part, p, d, o)
        return Hdpe.joint_end(part, p, d, o) if Hdpe.style?(o)

        case o.style
        when :socket_weld
          s = insertion(o) + 2.0
          part.add(:fitting, M.cylinder(p, Vec.add(p, Vec.scale(d, s)), o.ro + hub_thickness(o), ri: o.ro, steps: o.steps))
          if o.detailed? # weld fillet at the socket mouth
            tip = Vec.add(p, Vec.scale(d, s))
            part.add(:weld, M.torus(tip, d, o.ro + 0.5, [0.06 * o.od, 1.5].max, steps: o.steps, sec_steps: 6))
          end
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
        return forged_elbow(angle, r, o) if o.style == :socket_weld
        return Hdpe.elbow(angle, r * Math.tan(angle / 2.0), o, r) if Hdpe.style?(o)

        part = Mesh::Part.new
        arc_steps = [(angle / (Math::PI / 2) * (o.steps / 2)).ceil, 2].max
        part.add(:fitting, M.bend([0, r, 0], [0, -1, 0], [0, 0, 1], r, angle, body_radius(o), o.ri,
                                  steps: o.steps, arc_steps: arc_steps))
        e = [r * Math.sin(angle), r * (1 - Math.cos(angle)), 0.0]
        d_out = [Math.cos(angle), Math.sin(angle), 0.0]
        joint_end(part, [0.0, 0.0, 0.0], [-1.0, 0.0, 0.0], o)
        joint_end(part, e, d_out, o)
      end

      # Forged socket-weld elbow (ASME B16.11): two socket arms meeting in a
      # rounded corner block at the vertex – not a swept bend. The arms end
      # at the same tangent points the network trims the pipes to.
      def forged_elbow(angle, r, o)
        part = Mesh::Part.new
        t = r * Math.tan(angle / 2.0)
        v = [t, 0.0, 0.0]
        d_out = [Math.cos(angle), Math.sin(angle), 0.0]
        e = Vec.add(v, Vec.scale(d_out, t))
        br = body_radius(o)
        part.add(:fitting, M.cylinder([0, 0, 0], v, br, ri: o.ri, steps: o.steps))
        part.add(:fitting, M.cylinder(v, e, br, ri: o.ri, steps: o.steps))
        part.add(:fitting, M.sphere(v, br, steps: o.steps))
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

      # Concentric reducer / expander / adaptor from pipe +a+ (at x = 0) to
      # pipe +b+ (at x = len) along +X. Transition cone in the middle third.
      def reducer(len, a, b)
        return Hdpe.stepped_reducer(a, b) if a.style == :fusion && b.style == :fusion

        part = Mesh::Part.new
        ra = body_radius(a)
        rb = body_radius(b)
        x1 = len / 3.0
        x2 = 2.0 * len / 3.0
        steps = [a.steps, b.steps].max
        part.add(:fitting, M.cylinder([0, 0, 0], [x1, 0, 0], ra, ri: a.ri, steps: steps))
        part.add(:fitting, M.frustum([x1, 0, 0], [x2, 0, 0], ra, rb, ri1: a.ri, ri2: b.ri, steps: steps))
        part.add(:fitting, M.cylinder([x2, 0, 0], [len, 0, 0], rb, ri: b.ri, steps: steps))
        joint_end(part, [0.0, 0.0, 0.0], [-1.0, 0.0, 0.0], a)
        joint_end(part, [len, 0.0, 0.0], [1.0, 0.0, 0.0], b)
      end

      # Weld-neck flange (steel) or stub/adaptor flange (plastics):
      # mating face at x = 0 facing −X, hub towards +X.
      def flange(o, holes: true)
        return Hdpe.stub_flange(o) if Hdpe.style?(o)

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

      # type: gate, globe, ball, butterfly, check, strainer, prv, flange.
      # The construction family (flanged cast / forged socket-weld / brass
      # threaded / plastic true-union) follows the pipe – see ValveModels.
      def valve(type, o, metallic: true)
        if Hdpe.style?(o) && o.style != :compression
          return Hdpe.flange_pair(o) if type == 'flange'

          return Hdpe.flanged_valve(type, o, hdpe_valve_opts(o))
        end
        ValveModels.build(type, o, ValveModels.family(o, metallic))
      end

      def valve_length(type, o, metallic: true)
        if Hdpe.style?(o) && o.style != :compression
          return Hdpe.valve_length(type, o, hdpe_valve_opts(o)) unless type == 'flange'

          return 2.0 * Hdpe.stub_reach(o) + 3.0
        end
        FittingsData.face_to_face(type, o.od, ValveModels.family(o, metallic))
      end

      # HDPE fusion lines take flanged valves of the stub ends' DN (cast,
      # Class 150 drilling); compression lines keep PP valves.
      def hdpe_valve_opts(o)
        Opts.new(od: Hdpe::DN_OD.fetch(Hdpe.dn(o.od)), id: o.id, wall: o.wall, style: :butt_weld,
                 lod: o.lod, steps: o.steps)
      end

      def coupler(o)
        Hdpe.coupler(o)
      end

      def flange_pair(o)
        return Hdpe.flange_pair(o) if Hdpe.style?(o)

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
    end
  end
end
