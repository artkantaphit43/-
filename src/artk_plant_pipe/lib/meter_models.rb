# frozen_string_literal: true

module ArtK
  module PlantPipe
    # Flanged Woltman water meters (DN65–DN300), modelled from the standard
    # dimensions because no reference model exists for them:
    #   laying length L – ISO 4064 (short series)
    #   flanges – EN 1092-2 PN16 (outside diameter D, bolt circle K); the
    #     bolt pattern follows the companion flange the meter is bolted to,
    #     so every bolt passes through both flanges
    #   bolting – hex bolts ISO 4014, nuts ISO 4032, washers ISO 7089
    #   register – the same sealed dry dial on every size (as on real
    #     meters), lid left off
    # Body and bolting are left unpainted so they take the valve body colour
    # of the instance, like the neighbouring valves; only the register is
    # painted.
    # Canonical frame as the reference pack's in-line items: origin midway
    # between the flange faces, +X along the flow, +Y up (register).
    # Returns { verts: [[x,y,z] mm], faces: [{ mat:, loops:, soft:, pins: }] }
    # in the format of Refs.mesh.
    module MeterModels
      # DN => [L, D, K, bolts, bolt dia, flange thickness]
      WOLTMAN = {
        65 => [200, 185, 145, 4, 16, 19], 80 => [225, 200, 160, 8, 16, 19], 100 => [250, 220, 180, 8, 16, 19],
        125 => [250, 250, 210, 8, 16, 19], 150 => [300, 285, 240, 8, 20, 19], 200 => [350, 340, 295, 12, 20, 20],
        250 => [450, 405, 355, 12, 24, 22], 300 => [500, 460, 410, 12, 24, 24.5]
      }.freeze

      # bolt dia => [nut across flats s, nut height m, head height k,
      #              washer outside dia, washer thickness, clearance hole]
      BOLTING = {
        16 => [24.0, 14.8, 10.0, 30.0, 3.0, 18.0], 20 => [30.0, 18.0, 12.5, 37.0, 3.0, 22.0],
        24 => [36.0, 21.5, 15.0, 44.0, 4.0, 26.0]
      }.freeze

      BODY = nil # unpainted – instance colour (valve body)
      GREY = 'gen:Register Grey'
      GLASS = 'gen:Register Glass'
      DARK = 'gen:Register Socket'
      DIAL = 'meter:водяной счетчик' # the reference meter's dial image
      MATERIALS = {
        GREY => [206, 208, 206, 1.0], GLASS => [214, 228, 236, 0.35], DARK => [40, 42, 46, 1.0]
      }.freeze

      # Geometry revision: raise on every change of the model so definitions
      # already in users' files are rebuilt (RefModels.definition).
      #   1 – v1.8  2 – v1.9 full bolting, valve colours
      REV = 2

      REGISTER_R = 58.0 # mm – dry register head, same on all sizes
      GAP = 0.3         # mm between parts that only touch (no shared faces)

      # Minimal mesh builder: shared vertices, faces with outward loops.
      class Builder
        attr_reader :verts, :faces

        def initialize
          @verts = []
          @index = {}
          @faces = []
        end

        def v(p)
          k = p.map { |c| (c * 100).round }
          @index[k] ||= (@verts << p.map(&:to_f)).size - 1
        end

        # loops: outer first, holes after; soft: per loop, per edge.
        def face(mat, loops, soft: nil, pins: nil)
          idx = loops.map { |lp| lp.map { |p| v(p) } }
          soft ||= idx.map { |lp| Array.new(lp.size, false) }
          @faces << { mat: mat, loops: idx, soft: soft, pins: pins }
        end

        def mesh
          { verts: @verts, faces: @faces }
        end
      end

      module_function

      def sizes
        WOLTMAN.keys
      end

      def length(dn)
        WOLTMAN.fetch(dn)[0].to_f
      end

      def flange_od(dn)
        WOLTMAN.fetch(dn)[1].to_f
      end

      # Bolt pattern of the meter flanges: from the companion flange when
      # given ({ 'pcd', 'angles', 'hole', 'thick' }), else the PN16 table.
      def bolting(dn, mate = nil)
        _l, _d, k, nb, md, = WOLTMAN.fetch(dn)
        if mate
          bd = BOLTING.keys.min_by { |b| (BOLTING[b][5] - mate['hole']).abs }
          return { pcd: mate['pcd'], angles: mate['angles'], bolt: bd, mate_t: mate['thick'] }
        end
        { pcd: k.to_f, angles: Array.new(nb) { |i| Math::PI / nb + 2.0 * Math::PI * i / nb }, bolt: md, mate_t: nil }
      end

      # Point in the YZ plane (axis :x) or XZ plane (axis :y).
      def pt(axis, c, u, w)
        axis == :x ? [c, u, w] : [u, c, w]
      end

      # Points of a regular polygon of radius r around an axis.
      def ring(axis, c, r, n, phase = 0.0, off: [0.0, 0.0])
        Array.new(n) do |i|
          a = phase + 2.0 * Math::PI * i / n
          pt(axis, c, off[0] + r * Math.cos(a), off[1] + r * Math.sin(a))
        end
      end

      # Frustum / prism along an axis from c0 (radius r0) to c1 (radius r1),
      # c0 < c1. Optional bore rb, end caps. soft: smooth side edges.
      def frustum(b, mat, axis, c0, c1, r0, r1, n, rb: nil, ends: [true, true], soft: true, phase: 0.0,
                  off: [0.0, 0.0])
        a = ring(axis, c0, r0, n, phase, off: off)
        z = ring(axis, c1, r1, n, phase, off: off)
        side(b, mat, axis, a, z, soft, outward: true)
        if rb
          side(b, mat, axis, ring(axis, c0, rb, n, phase, off: off), ring(axis, c1, rb, n, phase, off: off), soft,
               outward: false)
        end
        hole = ->(c) { rb ? [ring(axis, c, rb, n, phase, off: off)] : [] }
        cap(b, mat, axis, a, hole.call(c0), -1) if ends[0]
        cap(b, mat, axis, z, hole.call(c1), 1) if ends[1]
      end

      def tube(b, mat, axis, c0, c1, r, n, **opts)
        frustum(b, mat, axis, c0, c1, r, r, n, **opts)
      end

      # Side quads between two rings of equal point count. Edges along the
      # axis are smooth when soft; the ring edges stay hard.
      def side(b, mat, axis, a, z, soft, outward:)
        n = a.size
        n.times do |i|
          j = (i + 1) % n
          lp = axis == :x ? [a[i], a[j], z[j], z[i]] : [a[i], z[i], z[j], a[j]]
          lp = lp.reverse unless outward
          # :x loops start with a ring edge, :y loops with an axial edge
          b.face(mat, [lp], soft: [axis == :x ? [false, soft, false, soft] : [soft, false, soft, false]])
        end
      end

      # End cap facing +axis (dir 1) or −axis (dir −1), with hole loops.
      # ring() runs counter-clockwise about +X for :x and about −Y for :y.
      def cap(b, mat, axis, outer, holes, dir)
        flip = axis == :x ? dir.negative? : dir.positive?
        b.face(mat, [flip ? outer.reverse : outer] + holes.map { |h| flip ? h : h.reverse })
      end

      # Rounded rectangle (corner radius cr) lying in XZ between y0 < y1.
      def plate(b, mat, y0, y1, hx, hz, cr)
        pts = []
        [[1, 1], [-1, 1], [-1, -1], [1, -1]].each_with_index do |(sx, sz), q|
          cx = sx * (hx - cr)
          cz = sz * (hz - cr)
          5.times do |i|
            a = (q * 90 + i * 22.5) * Math::PI / 180.0
            pts << [cx + cr * Math.cos(a), cz + cr * Math.sin(a)]
          end
        end
        bot = pts.map { |x, z| [x, y0, z] }
        top = pts.map { |x, z| [x, y1, z] }
        n = pts.size
        arc = ->(m) { (1..3).cover?(m % 5) } # edges inside a corner arc are smooth
        n.times do |i|
          j = (i + 1) % n
          b.face(mat, [[bot[i], top[i], top[j], bot[j]]], soft: [[arc.call(i), false, arc.call(j), false]])
        end
        b.face(mat, [bot])
        b.face(mat, [top.reverse])
      end

      # Hex (nut or bolt head) along X from x0 to x1 with 30° chamfers on
      # the ends listed in +bevel+ (:lo / :hi).
      def hex(b, x0, x1, s, off, bevel)
        rc = s / Math.sqrt(3.0) # across corners / 2
        rb = s / 2.0            # chamfer down to the across-flats circle
        c = (rc - rb) * Math.tan(Math::PI / 3)
        lo = bevel.include?(:lo) ? x0 + c : x0
        hi = bevel.include?(:hi) ? x1 - c : x1
        ph = Math::PI / 6
        frustum(b, BODY, :x, lo, hi, rc, rc, 6, phase: ph, off: off, soft: false, ends: [false, false])
        if lo > x0
          frustum(b, BODY, :x, x0, lo, rb, rc, 6, phase: ph, off: off, soft: false, ends: [true, false])
        else
          cap(b, BODY, :x, ring(:x, x0, rc, 6, ph, off: off), [], -1)
        end
        if hi < x1
          frustum(b, BODY, :x, hi, x1, rc, rb, 6, phase: ph, off: off, soft: false, ends: [false, true])
        else
          cap(b, BODY, :x, ring(:x, x1, rc, 6, ph, off: off), [], 1)
        end
      end

      # One through-bolt at +off+ for the flange joint at x = sgn·face:
      # head + washer on the companion flange's back, washer + nut + thread
      # end on the meter flange's back.
      def bolt(b, sgn, face, t, mate_t, d, off)
        s, m, k, dw, hw, = BOLTING.fetch(d)
        r = d / 2.0
        inner = face - t          # meter flange back (body side)
        outer = face + mate_t.to_f # companion flange back
        # x range of the distances u0..u1 from the centre, on this side
        span = lambda do |u0, u1|
          a, z = [sgn * u0, sgn * u1].sort
          [a, z]
        end
        outer = face unless mate_t # no companion flange: nut side only
        # head side (outside, on the companion flange)
        g = GAP
        if mate_t
          w0, w1 = span.call(outer + g, outer + g + hw)
          tube(b, BODY, :x, w0, w1, dw / 2.0, 16, off: off, ends: [true, true])
          h0, h1 = span.call(outer + 2 * g + hw, outer + 2 * g + hw + k)
          hex(b, h0, h1, s, off, [sgn.positive? ? :hi : :lo])
        end
        # nut side (between the flanges and the meter body)
        n0, n1 = span.call(inner - g - hw, inner - g)
        tube(b, BODY, :x, n0, n1, dw / 2.0, 16, off: off, ends: [true, true])
        m0, m1 = span.call(inner - 2 * g - hw - m, inner - 2 * g - hw)
        hex(b, m0, m1, s, off, [:lo, :hi])
        # shank through both flanges and the thread end past the nut
        e = inner - 2 * g - hw - m - 0.25 * d
        s0, s1 = span.call(e, outer)
        tube(b, BODY, :x, s0, s1, r, 12, off: off, ends: [false, false])
        c0, c1 = span.call(e - 0.12 * d, e)
        if sgn.positive?
          frustum(b, BODY, :x, c0, c1, r * 0.8, r, 12, off: off, ends: [true, false])
        else
          frustum(b, BODY, :x, c0, c1, r, r * 0.8, 12, off: off, ends: [false, true])
        end
      end

      # Socket head cap screw on the cover (axis :y, head from y0 up).
      def cap_screw(b, y0, d, off)
        rh = 0.75 * d
        h = d
        y1 = y0 + h
        sk = 0.43 * d # socket across corners / 2
        tube(b, BODY, :y, y0, y1 - 0.08 * d, rh, 16, off: off, ends: [false, false])
        frustum(b, BODY, :y, y1 - 0.08 * d, y1, rh, rh * 0.92, 16, off: off, ends: [false, false])
        top = ring(:y, y1, rh * 0.92, 16, off: off)
        sock = ring(:y, y1, sk, 6, off: off)
        cap(b, BODY, :y, top, [sock], 1)
        side(b, DARK, :y, ring(:y, y1 - 0.5 * d, sk, 6, off: off), sock, false, outward: false)
        cap(b, DARK, :y, ring(:y, y1 - 0.5 * d, sk, 6, off: off), [], 1)
      end

      def woltman(dn, od, mate = nil)
        len, d, _k, _nb, _md, t = WOLTMAN.fetch(dn)
        bolt_set = bolting(dn, mate)
        md = bolt_set[:bolt]
        hole = BOLTING.fetch(md)[5]
        half = len / 2.0
        b = Builder.new
        bore = [od / 2.0 - 2.0, 10.0].max
        pcd = bolt_set[:pcd]
        rb = [0.34 * d, pcd / 2.0 - 1.2 * md].min # neck, inside the nuts
        seg = 32

        # flanges with bolt holes
        [-1, 1].each do |s|
          x0, x1 = [s * half, s * (half - t)].sort
          offs = bolt_set[:angles].map { |a| [pcd / 2.0 * Math.cos(a), pcd / 2.0 * Math.sin(a)] }
          side(b, BODY, :x, ring(:x, x0, d / 2.0, seg), ring(:x, x1, d / 2.0, seg), true, outward: true)
          side(b, BODY, :x, ring(:x, x0, bore, seg), ring(:x, x1, bore, seg), true, outward: false)
          offs.each do |o|
            side(b, BODY, :x, ring(:x, x0, hole / 2.0, 12, off: o), ring(:x, x1, hole / 2.0, 12, off: o), true,
                 outward: false)
          end
          [[x0, -1], [x1, 1]].each do |x, dir|
            holes = [ring(:x, x, bore, seg)] + offs.map { |o| ring(:x, x, hole / 2.0, 12, off: o) }
            cap(b, BODY, :x, ring(:x, x, d / 2.0, seg), holes, dir)
          end
        end
        # necks, then the measuring chamber barrel
        tube(b, BODY, :x, -half + t, half - t, rb, seg, rb: bore, ends: [false, false])
        xm = half - t - 1.7 * md
        tube(b, BODY, :x, -xm, xm, 0.38 * d, seg, rb: rb)
        # through-bolts: both flange joints
        mate_t = bolt_set[:mate_t]
        [-1, 1].each do |s|
          bolt_set[:angles].each do |a|
            # the companion flange at −X is mirrored about the stem plane
            aa = s.positive? ? -a : a
            off = [pcd / 2.0 * Math.cos(aa), pcd / 2.0 * Math.sin(aa)]
            bolt(b, s, half, t, mate_t, md, off)
          end
        end

        # upright housing carrying the register (rounded rectangle) + cover
        hx = half - t - 0.05 * len
        hz = 0.4 * d
        ytop = 0.5 * d
        plate(b, BODY, 0.25 * rb, ytop - 0.07 * d, hx * 0.88, hz * 0.62, 0.3 * hz)
        plate(b, BODY, ytop - 0.07 * d, ytop, hx, hz, 0.35 * hz)
        cs = [[0.07 * d, 8.0].max, 16.0].min
        [[1, 1], [1, -1], [-1, 1], [-1, -1]].each do |sx, sz|
          cap_screw(b, ytop + GAP, cs, [sx * (hx - 0.12 * hz), sz * (hz - 0.12 * hz)])
        end

        # register: grey ring, glass, dial
        r = [REGISTER_R, 0.9 * hz].min
        y0 = ytop + GAP
        y1 = y0 + 0.62 * r
        tube(b, GREY, :y, y0, y1, r, seg, rb: r * 0.82, ends: [false, true])
        frustum(b, GREY, :y, y0 + 0.08 * r, y0 + 0.2 * r, r * 1.04, r * 1.04, seg, ends: [true, true])
        tube(b, GREY, :y, y0, y1 - 0.12 * r, r * 0.82, seg, ends: [false, false])
        yd = y1 - 0.12 * r
        dial(b, yd, r * 0.82)
        b.face(GLASS, [ring(:y, y1 - 0.04 * r, r * 0.82, seg).reverse])
        b.mesh
      end

      # Dial image fitted to a disc of radius r at height y.
      def dial(b, y, r)
        pins = [[-1.0, -0.2], [1.0, 0.2], [0.2, -1.0]].map do |x, z|
          [[x * r, y, z * r], [0.5 + x / 2.0, 0.5 - z / 2.0]]
        end
        b.face(DIAL, [ring(:y, y, r, 32).reverse], pins: pins)
      end
    end
  end
end
