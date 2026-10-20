# frozen_string_literal: true

require_relative 'mesh'

module ArtK
  module SteelSupport
    # Threaded hardware in the inch sizes the drawings call for.
    #
    # * Nuts: ASME B18.2.2 hex (across flats f, height m)
    # * Washers: SAE flat (od, t)
    # * Rod load: MSS SP-58 allowable load of carbon steel hanger rod
    #   (650 °F rating), kN
    # * Anchors: typical allowable tension / shear of a wedge / sleeve
    #   expansion anchor in 21 MPa concrete with safety factor 4 (kN) –
    #   indicative: use the manufacturer's values for the final design.
    module Hardware
      SIZES = {
        '3/8' => { d: 9.525, f: 14.29, m: 8.33, wod: 20.6, wt: 1.65, rod_kn: 2.71, anc_t: 3.1, anc_v: 3.9,
                   embed: 64.0, label: '3/8"', metric: 'M10' },
        '1/2' => { d: 12.7, f: 19.05, m: 11.11, wod: 27.0, wt: 2.41, rod_kn: 5.03, anc_t: 5.6, anc_v: 7.8,
                   embed: 83.0, label: '1/2"', metric: 'M12' },
        '5/8' => { d: 15.875, f: 23.81, m: 13.89, wod: 33.3, wt: 2.41, rod_kn: 8.05, anc_t: 8.7, anc_v: 11.1,
                   embed: 102.0, label: '5/8"', metric: 'M16' },
        '3/4' => { d: 19.05, f: 28.58, m: 16.27, wod: 37.3, wt: 3.4, rod_kn: 12.05, anc_t: 12.0, anc_v: 16.0,
                   embed: 114.0, label: '3/4"', metric: 'M20' }
      }.freeze
      ORDER = %w[3/8 1/2 5/8 3/4].freeze

      module_function

      def get(size)
        SIZES[size] or raise ArgumentError, "unknown thread size #{size}"
      end

      def label(size)
        s = get(size)
        "#{s[:label]} (#{s[:metric]})"
      end

      # U-bolt rod for a pipe of bare outside diameter od (MSS SP-58 /
      # common U-bolt tables: ½"–2" 3/8", 2½"–6" 1/2", 8"–10" 5/8").
      def u_bolt_size(od)
        if od <= 61.0 then '3/8'
        elsif od <= 170.0 then '1/2'
        elsif od <= 275.0 then '5/8'
        else '3/4'
        end
      end

      # Smallest size at least +min+ whose allowable (key) carries kn.
      def size_for(kn, key, min: '3/8')
        list = ORDER.drop(ORDER.index(min))
        list.find { |s| get(s)[key] >= kn } || list.last
      end

      def bigger(size)
        ORDER[[ORDER.index(size) + 1, ORDER.size - 1].min]
      end

      # ---------- geometry (all in support coordinates) ----------

      # Nut seated on a face at +at+ with its axis +dir+ (away from the face).
      def nut(part, at, dir, size)
        s = get(size)
        part.add(:galv, Mesh.hex(at, Vec.along(at, dir, s[:m]), s[:f]))
      end

      def washer(part, at, dir, size)
        s = get(size)
        part.add(:galv, Mesh.cylinder(at, Vec.along(at, dir, s[:wt]), s[:wod] / 2.0))
      end

      # Washer + nut on a face (at, facing dir); returns the far end.
      def fastening(part, at, dir, size)
        s = get(size)
        washer(part, at, dir, size)
        nut(part, Vec.along(at, dir, s[:wt]), dir, size)
        Vec.along(at, dir, s[:wt] + s[:m])
      end

      def stack_height(size)
        s = get(size)
        s[:wt] + s[:m]
      end

      def rod(part, a, b, size)
        part.add(:galv, Mesh.cylinder(a, b, get(size)[:d] / 2.0))
      end

      # U-bolt round a pipe / tube of radius +r_in+ centred at c: the bend
      # over the +up+ side, legs at ±(r_in + d/2) along +lat+, running
      # back (−up) for +leg+ from the centre line. One closed tube.
      def u_bolt(part, c, lat, up, r_in, size, leg)
        d = get(size)[:d]
        rc = r_in + d / 2.0
        lat = Vec.unit(lat)
        up = Vec.unit(up)
        pts = [Vec.add(Vec.scale(lat, rc), Vec.scale(up, -leg))]
        (0..12).each do |i|
          t = Math::PI * i / 12.0
          pts << Vec.add(Vec.scale(lat, rc * Math.cos(t)), Vec.scale(up, rc * Math.sin(t)))
        end
        pts << Vec.add(Vec.scale(lat, -rc), Vec.scale(up, -leg))
        pts = pts.map { |p| Vec.add(c, p) }
        part.add(:galv, Mesh.tube(pts, Vec.cross(lat, up), d / 2.0))
      end

      # Expansion anchor through a plate of thickness t whose face against
      # the concrete is at +face+; +out+ points out of the concrete.
      # Sleeve + stud in the hole, washer + nut on the plate.
      def anchor(part, face, out, t, size)
        s = get(size)
        back = Vec.along(face, out, -s[:embed])
        part.add(:galv, Mesh.cylinder(back, Vec.along(face, out, -3.0), s[:d] / 2.0 + 1.5)) # sleeve
        top = fastening(part, Vec.along(face, out, t), out, size)
        rod(part, Vec.along(back, out, -10.0), Vec.along(top, out, 0.6 * s[:d]), size)
      end
    end
  end
end
