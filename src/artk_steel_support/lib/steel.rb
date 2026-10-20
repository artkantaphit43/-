# frozen_string_literal: true

require_relative 'mesh'

module ArtK
  module SteelSupport
    # Steel sections with their real dimensions (mm) and kg/m.
    #
    # * Hot-rolled channels "เหล็กรางน้ำ" – JIS G 3192 / มอก. 1227:
    #   H × B × t1 (web) × t2 (flange), r1 root radius, r2 toe radius.
    # * Lip channels "เหล็กตัวซี" – JIS G 3350 / มอก. 1228: H × A × C × t,
    #   cold formed, inside bend radius = t.
    # * Equal angles "เหล็กฉาก" – JIS G 3192 / มอก. 1227: A × A × t, r1, r2.
    # Areas worked out from these profiles match the tabulated masses
    # within 1 % (tested), so lengths × kg/m in the BOM are real weights.
    module Steel
      SECTIONS = {
        # tab: JIS table properties (cm⁴, cm³, cm) – the rolled flanges are
        # tapered, so these (not the parallel-flange model) are used in checks
        'C75' => { type: :channel, h: 75.0, b: 40.0, t1: 5.0, t2: 7.0, r1: 8.0, r2: 4.0, kg: 6.92,
                   inch: '3"', name: 'เหล็กรางน้ำ 3" C75×40×5×7',
                   tab: { area: 8.818, ix: 75.3, iy: 12.2, zx: 20.1, zy: 4.47, cy: 1.28 } },
        'C100' => { type: :channel, h: 100.0, b: 50.0, t1: 5.0, t2: 7.5, r1: 8.0, r2: 4.0, kg: 9.36,
                    inch: '4"', name: 'เหล็กรางน้ำ 4" C100×50×5×7.5',
                    tab: { area: 11.92, ix: 188.0, iy: 26.0, zx: 37.6, zy: 7.52, cy: 1.54 } },
        'C125' => { type: :channel, h: 125.0, b: 65.0, t1: 6.0, t2: 8.0, r1: 8.0, r2: 4.0, kg: 13.4,
                    inch: '5"', name: 'เหล็กรางน้ำ 5" C125×65×6×8',
                    tab: { area: 17.11, ix: 424.0, iy: 61.8, zx: 67.8, zy: 13.4, cy: 1.90 } },
        'C150' => { type: :channel, h: 150.0, b: 75.0, t1: 6.5, t2: 10.0, r1: 10.0, r2: 5.0, kg: 18.6,
                    inch: '6"', name: 'เหล็กรางน้ำ 6" C150×75×6.5×10',
                    tab: { area: 23.71, ix: 861.0, iy: 117.0, zx: 115.0, zy: 22.4, cy: 2.28 } },
        'LC75' => { type: :lip, h: 75.0, b: 45.0, c: 15.0, t: 2.3, kg: 3.25,
                    inch: '3"', name: 'เหล็กตัวซี 3" C75×45×15×2.3' },
        'LC100' => { type: :lip, h: 100.0, b: 50.0, c: 20.0, t: 2.3, kg: 4.06,
                     inch: '4"', name: 'เหล็กตัวซี 4" C100×50×20×2.3' },
        'LC100T' => { type: :lip, h: 100.0, b: 50.0, c: 20.0, t: 3.2, kg: 5.50,
                      inch: '4"', name: 'เหล็กตัวซี 4" C100×50×20×3.2' },
        'LC125' => { type: :lip, h: 125.0, b: 50.0, c: 20.0, t: 3.2, kg: 6.13,
                     inch: '5"', name: 'เหล็กตัวซี 5" C125×50×20×3.2' },
        'LC150' => { type: :lip, h: 150.0, b: 50.0, c: 20.0, t: 3.2, kg: 6.76,
                     inch: '6"', name: 'เหล็กตัวซี 6" C150×50×20×3.2' },
        'L50' => { type: :angle, a: 50.0, t: 5.0, r1: 6.5, r2: 3.0, kg: 3.77, name: 'เหล็กฉาก L50×50×5' },
        'L65' => { type: :angle, a: 65.0, t: 6.0, r1: 8.5, r2: 4.0, kg: 5.91, name: 'เหล็กฉาก L65×65×6' },
        'L75' => { type: :angle, a: 75.0, t: 6.0, r1: 8.5, r2: 4.0, kg: 6.85, name: 'เหล็กฉาก L75×75×6' },
        'L100' => { type: :angle, a: 100.0, t: 7.0, r1: 10.0, r2: 5.0, kg: 10.7, name: 'เหล็กฉาก L100×100×7' }
      }.freeze

      # Channels the automatic choice tries, lightest first.
      AUTO = %w[C75 C100 C125 C150].freeze
      ANGLES = %w[L50 L65 L75 L100].freeze

      FY = 245.0          # MPa, SS400 (มอก. 1227 / JIS G 3101)
      FB = 0.6 * FY       # allowable bending stress (ASD)
      E = 200_000.0       # MPa
      RHO = 7.85e-6       # kg/mm³

      ARC = 4 # segments of a 90° fillet (22.5° each – drawn smooth)

      module_function

      def get(key)
        SECTIONS[key] or raise ArgumentError, "unknown section #{key}"
      end

      def channel?(key)
        %i[channel lip].include?(get(key)[:type])
      end

      # Depth (along the member's depth axis) and leg width of a channel.
      def depth(key)
        get(key)[:h]
      end

      def width(key)
        s = get(key)
        s[:type] == :angle ? s[:a] : s[:b]
      end

      def web(key)
        s = get(key)
        s[:t1] || s[:t]
      end

      # Counter-clockwise outline [[u, v]]: u across the depth (centred),
      # v from the back of the web (0) to the toes (B). Angles: legs along
      # +u and +v from the heel at the origin.
      def profile(key)
        s = get(key)
        case s[:type]
        when :channel then channel_profile(s)
        when :lip then lip_profile(s)
        else angle_profile(s)
        end
      end

      def channel_profile(s)
        h2 = s[:h] / 2.0
        b, t1, t2, r1, r2 = s.values_at(:b, :t1, :t2, :r1, :r2)
        hp = Math::PI / 2.0
        pts = [[-h2, 0.0], [h2, 0.0], [h2, b]]
        pts += Mesh.arc2d([h2 - t2 + r2, b - r2], r2, hp, Math::PI, ARC)
        pts += Mesh.arc2d([h2 - t2 - r1, t1 + r1], r1, 0.0, -hp, ARC)
        pts += Mesh.arc2d([-h2 + t2 + r1, t1 + r1], r1, -hp, -Math::PI, ARC)
        pts += Mesh.arc2d([-h2 + t2 - r2, b - r2], r2, 0.0, hp, ARC)
        pts << [-h2, b]
        pts
      end

      # Thin wall of thickness t around the centre line web → flanges →
      # lips, corners bent at inside radius t.
      def lip_profile(s)
        h, b, c, t = s.values_at(:h, :b, :c, :t)
        h2 = h / 2.0 - t / 2.0
        rc = 1.5 * t # centre-line bend radius
        y1 = b - t / 2.0
        path = []
        hp = Math::PI / 2.0
        path += line_pts([h / 2.0 - c, y1], [h2 - rc, y1])
        path += Mesh.arc2d([h2 - rc, y1 - rc], rc, hp, 0.0, ARC)[1..]
        path += Mesh.arc2d([h2 - rc, t / 2.0 + rc], rc, 0.0, -hp, ARC)
        path += Mesh.arc2d([-h2 + rc, t / 2.0 + rc], rc, -hp, -Math::PI, ARC)
        path += Mesh.arc2d([-h2 + rc, y1 - rc], rc, Math::PI, hp, ARC)
        path << [-h / 2.0 + c, y1]
        offset_strip(path, t)
      end

      def line_pts(a, b)
        [a, b]
      end

      # Closed outline of a strip of width t centred on an open polyline:
      # one side out, the other back (counter-clockwise when the path turns
      # clockwise, as the lip channel does).
      def offset_strip(path, t)
        n = path.size
        normals = path.each_index.map do |i|
          a = path[[i - 1, 0].max]
          b = path[[i + 1, n - 1].min]
          d = [b[0] - a[0], b[1] - a[1]]
          l = Math.hypot(*d)
          [-d[1] / l, d[0] / l]
        end
        left = path.each_with_index.map { |p, i| [p[0] + normals[i][0] * t / 2.0, p[1] + normals[i][1] * t / 2.0] }
        right = path.each_with_index.map { |p, i| [p[0] - normals[i][0] * t / 2.0, p[1] - normals[i][1] * t / 2.0] }
        outline = right + left.reverse
        Mesh.area2d(outline).negative? ? outline.reverse : outline
      end

      def angle_profile(s)
        a, t, r1, r2 = s.values_at(:a, :t, :r1, :r2)
        hp = Math::PI / 2.0
        pts = [[0.0, 0.0], [a, 0.0]]
        pts += Mesh.arc2d([a - r2, t - r2], r2, 0.0, hp, ARC)
        pts += Mesh.arc2d([t + r1, t + r1], r1, -hp, -Math::PI, ARC)
        pts += Mesh.arc2d([t - r2, a - r2], r2, 0.0, hp, ARC)
        pts << [0.0, a]
        pts
      end

      # Section properties from the outline: area mm², centroid v (from
      # the web back), I and Z for bending square to the web (the members
      # here lie web-flat, toes down – the minor axis) and along it.
      def props(key)
        @props ||= {}
        @props[key] ||= begin
          poly = profile(key)
          a = Mesh.area2d(poly)
          cu = cv = iuu = ivv = 0.0
          poly.each_with_index do |p, i|
            q = poly[(i + 1) % poly.size]
            cr = p[0] * q[1] - q[0] * p[1]
            cu += (p[0] + q[0]) * cr
            cv += (p[1] + q[1]) * cr
            iuu += (p[1]**2 + p[1] * q[1] + q[1]**2) * cr # ∫v² dA
            ivv += (p[0]**2 + p[0] * q[0] + q[0]**2) * cr # ∫u² dA
          end
          cu /= 6.0 * a
          cv /= 6.0 * a
          i_flat = iuu / 12.0 - a * cv * cv  # bending with the web flat (load ⟂ web)
          i_edge = ivv / 12.0 - a * cu * cu  # bending with the web upright
          s = get(key)
          far = (s[:type] == :angle ? s[:a] : s[:b]) - cv
          out = { area: a, cv: cv, i_flat: i_flat, z_flat: i_flat / [far, cv].max,
                  i_edge: i_edge, z_edge: i_edge / (s[:type] == :angle ? [s[:a] - cu, cu].max : s[:h] / 2.0),
                  kg: a * RHO * 1000.0 }
          if (t = s[:tab])
            out.merge!(area: t[:area] * 100.0, cv: t[:cy] * 10.0, i_flat: t[:iy] * 1e4, z_flat: t[:zy] * 1e3,
                       i_edge: t[:ix] * 1e4, z_edge: t[:zx] * 1e3)
          end
          out[:r_min] = Math.sqrt([out[:i_flat], out[:i_edge]].min / out[:area])
          out
        end
      end

      def kg_m(key)
        get(key)[:kg]
      end

      # A member of channel / lip channel +key+ whose web back runs along
      # a → b, depth across +depth_dir+ (centred on the line), toes toward
      # +toes+. cut0 / cut1: end planes [point, normal] for sloped ends.
      def member(key, a, b, depth_dir, toes, cut0: nil, cut1: nil)
        ax = Vec.sub(b, a)
        len = Vec.length(ax)
        return nil if len < 0.5

        ax = Vec.scale(ax, 1.0 / len)
        u = Vec.unit(depth_dir)
        v = Vec.unit(toes)
        u = Vec.scale(u, -1.0) if Vec.dot(Vec.cross(u, v), ax).negative?
        Mesh.extrude(profile(key), a, u, v, ax, len, cut0: cut0, cut1: cut1)
      end

      # An angle with its heel on a → b, legs along leg1 / leg2.
      def angle(key, a, b, leg1, leg2)
        ax = Vec.sub(b, a)
        len = Vec.length(ax)
        ax = Vec.scale(ax, 1.0 / len)
        u = Vec.unit(leg1)
        v = Vec.unit(leg2)
        if Vec.dot(Vec.cross(u, v), ax).negative?
          # mirror: swap legs so the profile stays counter-clockwise
          u, v = v, u
        end
        Mesh.extrude(profile(key), a, u, v, ax, len)
      end
    end
  end
end
