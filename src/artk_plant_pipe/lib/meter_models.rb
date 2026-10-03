# frozen_string_literal: true

module ArtK
  module PlantPipe
    # Flanged Woltman water meters (DN65–DN300), modelled from the standard
    # dimensions because no reference model exists for them:
    #   laying length L – ISO 4064 (short series)
    #   flanges – EN 1092-2 PN16: outside diameter D, bolt circle K, bolts
    #   register – the same sealed dry dial on every size (as on real
    #   meters), lid left off
    # Canonical frame as the reference pack's in-line items: origin midway
    # between the flange faces, +X along the flow, +Y up (register).
    # Returns { verts: [[x,y,z] mm], faces: [{ mat:, loops:, soft:, pins: }] }
    # in the format of Refs.mesh.
    module MeterModels
      # DN => [L, D, K, bolts, bolt dia, flange thickness]
      WOLTMAN = {
        65 => [200, 185, 145, 8, 16, 19], 80 => [225, 200, 160, 8, 16, 19], 100 => [250, 220, 180, 8, 16, 19],
        125 => [250, 250, 210, 8, 16, 19], 150 => [300, 285, 240, 8, 20, 19], 200 => [350, 340, 295, 12, 20, 20],
        250 => [450, 405, 355, 12, 24, 22], 300 => [500, 460, 410, 12, 24, 24.5]
      }.freeze

      BLUE = 'gen:Woltman Body Blue'
      GREY = 'gen:Register Grey'
      STEEL = 'gen:Bolt Steel'
      GLASS = 'gen:Register Glass'
      DIAL = 'meter:водяной счетчик' # the reference meter's dial image
      MATERIALS = {
        BLUE => [36, 104, 186, 1.0], GREY => [206, 208, 206, 1.0],
        STEEL => [176, 179, 183, 1.0], GLASS => [214, 228, 236, 0.35]
      }.freeze

      REGISTER_R = 58.0 # mm – dry register head, same on all sizes

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

        # loops: outer first (counter-clockwise seen from outside), holes
        # after; soft: per loop, per edge.
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

      # Points of a circle of radius r around an axis, n segments.
      #   axis :x – circle in the YZ plane at x = c; :y – XZ plane at y = c
      def ring(axis, c, r, n, phase = 0.0, off: [0.0, 0.0])
        Array.new(n) do |i|
          a = phase + 2.0 * Math::PI * i / n
          u = r * Math.cos(a)
          w = r * Math.sin(a)
          axis == :x ? [c, off[0] + u, off[1] + w] : [off[0] + u, c, off[1] + w]
        end
      end

      # Closed prism along an axis between c0 < c1 of a circle / polygon
      # with outer radius r (and optional bore rb). Ends optional.
      def tube(b, mat, axis, c0, c1, r, n, rb: nil, ends: [true, true], soft: true, phase: 0.0, off: [0.0, 0.0])
        a = ring(axis, c0, r, n, phase, off: off)
        z = ring(axis, c1, r, n, phase, off: off)
        n.times do |i|
          j = (i + 1) % n
          lp = axis == :x ? [a[i], a[j], z[j], z[i]] : [a[i], z[i], z[j], a[j]]
          b.face(mat, [lp], soft: [[false, soft, false, soft]])
        end
        if rb
          ia = ring(axis, c0, rb, n, phase, off: off)
          iz = ring(axis, c1, rb, n, phase, off: off)
          n.times do |i|
            j = (i + 1) % n
            lp = axis == :x ? [ia[j], ia[i], iz[i], iz[j]] : [ia[j], iz[j], iz[i], ia[i]]
            b.face(mat, [lp], soft: [[false, soft, false, soft]])
          end
        end
        lo = axis == :x ? a.reverse : a
        hi = axis == :x ? z : z.reverse
        holes = ->(c) { rb ? [ring(axis, c, rb, n, phase, off: off)] : [] }
        if ends[0]
          h = holes.call(c0)
          b.face(mat, [lo] + h.map { |l| axis == :x ? l : l.reverse })
        end
        return unless ends[1]

        h = holes.call(c1)
        b.face(mat, [hi] + h.map { |l| axis == :x ? l.reverse : l })
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
        n.times do |i|
          j = (i + 1) % n
          arc = ->(m) { (1..3).cover?(m % 5) } # edges inside a corner arc are smooth
          b.face(mat, [[bot[i], top[i], top[j], bot[j]]], soft: [[arc.call(i), false, arc.call(j), false]])
        end
        b.face(mat, [bot])
        b.face(mat, [top.reverse])
      end

      def woltman(dn, od)
        len, d, k, nb, md, t = WOLTMAN.fetch(dn)
        half = len / 2.0
        b = Builder.new
        bore = [od / 2.0 - 2.0, 10.0].max
        rb = [0.34 * d, k / 2.0 - 1.2 * md].min # barrel, inside the bolt heads
        seg = 32

        # flanges with the raised face toward the pipe
        [-1, 1].each do |s|
          x0, x1 = [s * half, s * (half - t)].sort
          tube(b, BLUE, :x, x0, x1, d / 2.0, seg, rb: bore)
        end
        # necks inside the bolt heads, then the measuring chamber barrel
        tube(b, BLUE, :x, -half + t, half - t, rb, seg, rb: bore, ends: [false, false])
        xm = half - t - 1.3 * md
        tube(b, BLUE, :x, -xm, xm, 0.38 * d, seg, rb: rb)
        # flange bolts: hex heads + nuts on the body side, studs between
        [-1, 1].each do |s|
          xf = s * (half - t)
          hh = 0.65 * md
          nb.times do |i|
            a = Math::PI / nb + 2.0 * Math::PI * i / nb
            off = [k / 2.0 * Math.cos(a), k / 2.0 * Math.sin(a)]
            x0, x1 = [xf, xf - s * hh].sort
            tube(b, STEEL, :x, x0, x1, 0.92 * md, 6, phase: a, soft: false, off: off)
            sx0, sx1 = [xf - s * hh, xf - s * (hh + 0.5 * md)].sort
            tube(b, STEEL, :x, sx0, sx1, md / 2.0, 12, ends: [s.positive?, s.negative?], off: off)
          end
        end

        # upright housing carrying the register (rounded square)
        hx = half - t - 0.05 * len
        hz = 0.4 * d
        ytop = 0.5 * d
        plate(b, BLUE, 0.25 * rb, ytop - 0.07 * d, hx * 0.88, hz * 0.62, 0.3 * hz)
        plate(b, BLUE, ytop - 0.07 * d, ytop, hx, hz, 0.35 * hz)
        # cover bolts (socket heads) at the plate corners
        [[1, 1], [1, -1], [-1, 1], [-1, -1]].each do |sx, sz|
          off = [sx * (hx - 0.12 * hz), sz * (hz - 0.12 * hz)]
          tube(b, STEEL, :y, ytop, ytop + [0.05 * d, 12.0].min, [0.055 * d, 11.0].min, 12, ends: [false, true], off: off)
        end

        # register: grey ring, glass, dial
        r = [REGISTER_R, 0.9 * hz].min
        y0 = ytop
        y1 = y0 + 0.62 * r
        tube(b, GREY, :y, y0, y1, r, seg, rb: r * 0.82, ends: [false, true])
        tube(b, GREY, :y, y0, y1 - 0.12 * r, r * 0.82, seg, ends: [false, false])
        tube(b, GREY, :y, y1 - 0.12 * r, y1 - 0.02 * r, r * 0.86, 16, rb: r * 0.82, ends: [false, false])
        yd = y1 - 0.12 * r
        dial(b, yd, r * 0.82)
        glass = ring(:y, y1 - 0.04 * r, r * 0.82, seg)
        b.face(GLASS, [glass.reverse])
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
