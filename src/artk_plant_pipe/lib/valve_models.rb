# frozen_string_literal: true

require_relative 'vec'
require_relative 'mesh'
require_relative 'fittings_data'

module ArtK
  module PlantPipe
    # Detailed valve models by construction family (canonical frame: centre
    # at origin, flow +X, stem +Z, ends at x = ±L/2).
    #
    # The family follows how that valve is really made for the line it sits on:
    #   :flanged     – cast iron / cast steel, flanged Class 150 (steel ≥ 2")
    #   :socket_weld – forged steel Class 800, socket-weld ends, yoke frame
    #                  (steel/stainless < 2", small-bore industrial)
    #   :threaded    – brass / bronze, hex threaded ends (GSP, copper)
    #   :plastic     – PVC-U / PP true-union valves (plastic lines)
    # Each family has its own proportions and face-to-face length
    # (FittingsData.face_to_face with family).
    module ValveModels
      M = Mesh
      SQ3 = Math.sqrt(3.0)
      BODY = { flanged: :cast, socket_weld: :forged, threaded: :brass, plastic: :valve_plastic }.freeze

      module_function

      def family(o, metallic)
        return :plastic unless metallic
        return :threaded if %i[threaded socket].include?(o.style)

        o.od < 60.0 ? :socket_weld : :flanged
      end

      def build(type, o, fam)
        d = o.od
        c = { d: d, len: FittingsData.face_to_face(type, d, fam), o: o, fam: fam, body: BODY[fam],
              st: [o.steps, 16].max, det: o.detailed? }
        part = Mesh::Part.new
        return Parts.flange_pair(o) if type == 'flange'

        ends(part, c) unless type == 'butterfly'
        send("#{type}_valve", part, c)
        part
      end

      # ---------------------------------------------------------------
      # helpers
      # ---------------------------------------------------------------

      def hex(part, role, a, b, af)
        part.add(role, M.ngon_prism(a, b, af / SQ3, 6))
      end

      def tube(part, role, a, b, ro, ri, c)
        part.add(role, M.cylinder(a, b, ro, ri: ri, steps: c[:st]))
      end

      def lathe_x(part, role, prof, c)
        part.add(role, M.lathe([0, 0, 0], [1, 0, 0], prof, steps: c[:st]))
      end

      # Vertical lathe, optionally flattened across the pipe (oval castings).
      def lathe_z(part, role, prof, c, flat: 1.0, x: 0.0)
        s = M.lathe([x, 0, 0], [0, 0, 1], prof, steps: c[:st])
        s = M.scale(s, [x, 0, 0], 1.0, flat, 1.0) if flat != 1.0
        part.add(role, s)
      end

      def bolt_ring(part, role, z, radius, n, af, h, c, cx: 0.0, flat: 1.0)
        return unless c[:det]

        n.times do |k|
          t = 2 * Math::PI * (k + 0.5) / n
          x = cx + radius * Math.cos(t)
          y = radius * Math.sin(t) * flat
          hex(part, role, [x, y, z], [x, y, z + h], af)
        end
      end

      # Spoked handwheel in the plane normal to +axis+ at +center+.
      def spoked_wheel(part, role, center, axis, big_r, spokes, c)
        rim = [0.06 * big_r, 3.0].max
        part.add(role, M.torus(center, axis, big_r, rim, steps: [c[:st] + 8, 24].max, sec_steps: 8))
        hub = [0.16 * big_r, 7.0].max
        ax = Vec.unit(axis)
        part.add(role, M.cylinder(Vec.sub(center, Vec.scale(ax, rim * 1.6)), Vec.add(center, Vec.scale(ax, rim * 1.6)),
                                  hub, steps: 12))
        ref = Vec.perpendicular(ax)
        bin = Vec.cross(ax, ref)
        n = c[:det] ? spokes : 2
        n.times do |k|
          t = 2 * Math::PI * k / n
          u = Vec.add(Vec.scale(ref, Math.cos(t)), Vec.scale(bin, Math.sin(t)))
          part.add(role, M.cylinder(Vec.add(center, Vec.scale(u, hub * 0.8)), Vec.add(center, Vec.scale(u, big_r)),
                                    rim * 0.75, steps: 8))
        end
      end

      # Pressed/cast handwheel disc with holes (small brass & PVC valves).
      def holed_wheel(part, role, z, big_r, thick, c)
        if c[:det]
          part.add(role, M.holed_disc([0, 0, z], [0, 0, 1], big_r * 0.9, big_r * 0.2, thick, big_r * 0.55, 5,
                                      big_r * 0.2, steps: 30, hole_steps: 10))
        else
          part.add(role, M.cylinder([0, 0, z], [0, 0, z + thick], big_r * 0.9, steps: c[:st]))
        end
        part.add(role, M.torus([0, 0, z + thick / 2.0], [0, 0, 1], big_r * 0.92, thick * 0.75, steps: 30, sec_steps: 8))
        part.add(role, M.cylinder([0, 0, z - thick * 0.4], [0, 0, z + thick * 1.4], big_r * 0.24, steps: 12))
      end

      # Flat lever handle with vinyl grip, from the stem along +X.
      def lever(part, z, len, c, width: nil)
        d = c[:d]
        w = width || [0.22 * d, 14.0].max
        t = [0.06 * d, 3.5].max
        part.add(:iron, M.bar([-w * 0.5, 0, z], [len * 0.62, 0, z], w, t, [0, 0, 1]))
        part.add(:grip, M.cylinder([len * 0.6, 0, z], [len, 0, z], [w * 0.62, t * 1.6].max, steps: 12))
        part.add(:grip, M.sphere([len, 0, z], [w * 0.62, t * 1.6].max, steps: 12))
        hex(part, :iron, [0, 0, z + t / 2.0], [0, 0, z + t / 2.0 + [0.12 * d, 5.0].max], [0.3 * d, 10.0].max)
      end

      # ---------------------------------------------------------------
      # end connections
      # ---------------------------------------------------------------

      def ends(part, c)
        d = c[:d]
        l2 = c[:len] / 2.0
        o = c[:o]
        role = c[:body]
        [-1.0, 1.0].each do |s|
          case c[:fam]
          when :flanged
            fl = FittingsData.flange(d)
            rf = 1.6
            face = s * l2
            back = s * (l2 - rf - fl.thickness)
            if c[:det]
              part.add(role, M.holed_disc([s * (l2 - rf), 0, 0], [-s, 0, 0], fl.od / 2.0, o.ri, fl.thickness,
                                          fl.bolt_circle / 2.0, fl.bolts, fl.hole / 2.0, steps: [c[:st], 24].max))
            else
              tube(part, role, [back, 0, 0], [s * (l2 - rf), 0, 0], fl.od / 2.0, o.ri, c)
            end
            tube(part, role, [s * (l2 - rf), 0, 0], [face, 0, 0], fl.raised_face / 2.0, o.ri, c)
            tube(part, role, [s * 0.26 * c[:len], 0, 0], [back, 0, 0], 0.58 * d, o.ri, c) # neck
          when :socket_weld
            hub = 0.5 * d + [0.2 * d, 6.0].max
            tube(part, role, [s * l2, 0, 0], [s * (l2 - 0.22 * c[:len]), 0, 0], hub, o.ro, c)
            tube(part, role, [s * (l2 - 0.22 * c[:len]), 0, 0], [s * 0.2 * c[:len], 0, 0], hub * 0.92, o.ri, c)
          when :threaded
            af = 1.45 * d + 4.0
            e = 0.25 * c[:len]
            part.add(role, M.ngon_prism([s * l2, 0, 0], [s * (l2 - e), 0, 0], af / SQ3, 6))
            tube(part, role, [s * (l2 - e), 0, 0], [s * 0.18 * c[:len], 0, 0], 0.62 * d, o.ri, c)
          when :plastic
            hub_r = o.ro + [0.08 * d, 3.0].max
            tail = 0.3 * c[:len]
            tube(part, role, [s * l2, 0, 0], [s * (l2 - tail), 0, 0], hub_r, o.ro, c)
            nut_r = hub_r * 1.42
            n0 = s * (l2 - 0.06 * c[:len])
            n1 = s * (l2 - tail - 0.02 * c[:len])
            part.add(role, M.ngon_prism([n0, 0, 0], [n1, 0, 0], nut_r, 24))
            if c[:det]
              8.times do |k|
                t = 2 * Math::PI * k / 8
                y = nut_r * Math.cos(t)
                z = nut_r * Math.sin(t)
                part.add(role, M.bar([n0, y, z], [n1, y, z], [0.06 * d, 2.5].max, [0.06 * d, 2.5].max, [0, y, z]))
              end
            end
            tube(part, role, [s * (l2 - tail), 0, 0], [s * 0.16 * c[:len], 0, 0], hub_r * 1.05, o.ri, c)
          end
        end
      end

      # ---------------------------------------------------------------
      # rising-stem assemblies shared by gate / globe
      # ---------------------------------------------------------------

      def bonnet_bolted(part, c, z0, radius, flat, cx: 0.0)
        d = c[:d]
        t = [0.12 * d, 6.0].max
        s = M.cylinder([cx, 0, z0], [cx, 0, z0 + t], radius, steps: c[:st])
        part.add(c[:body], M.scale(s, [cx, 0, 0], 1.0, flat, 1.0))
        bolt_ring(part, :bolt, z0 + t, radius * 0.86, 8, [0.14 * d, 7.0].max, [0.1 * d, 5.0].max, c, cx: cx, flat: flat)
        z0 + t
      end

      def yoke(part, c, z0, z1, half_span, role)
        d = c[:d]
        w = [0.14 * d, 8.0].max
        t = [0.08 * d, 5.0].max
        [-1, 1].each do |s|
          part.add(role, M.bar([s * half_span, 0, z0], [s * half_span * 0.62, 0, z1], t, w, [1, 0, 0]))
        end
        tube(part, role, [0, 0, z1 - t], [0, 0, z1 + 0.14 * d], [0.24 * d, 10.0].max, nil, c)
        hex(part, :bolt, [0, 0, z1 + 0.14 * d], [0, 0, z1 + 0.24 * d], [0.32 * d, 12.0].max)
      end

      def stem(part, z0, z1, c)
        part.add(:chrome, M.cylinder([0, 0, z0], [0, 0, z1], [0.055 * c[:d], 3.0].max, steps: 10))
      end

      # ---------------------------------------------------------------
      # valve types
      # ---------------------------------------------------------------

      def gate_valve(part, c)
        d = c[:d]
        b = c[:body]
        case c[:fam]
        when :flanged
          tube(part, b, [-0.27 * c[:len], 0, 0], [0.27 * c[:len], 0, 0], 0.56 * d, c[:o].ri, c)
          lathe_z(part, b, [[-0.55 * d, 0], [-0.55 * d, 0.24 * d], [-0.46 * d, 0.44 * d], [-0.28 * d, 0.57 * d],
                            [0.0, 0.61 * d], [0.5 * d, 0.58 * d], [0.9 * d, 0.5 * d], [0.9 * d, 0]], c, flat: 0.62)
          top = bonnet_bolted(part, c, 0.9 * d, 0.74 * d, 0.7)
          lathe_z(part, b, [[top, 0], [top, 0.46 * d], [top + 0.22 * d, 0.4 * d], [top + 0.5 * d, 0.3 * d],
                            [top + 0.6 * d, 0.28 * d], [top + 0.6 * d, 0]], c)
          gl = top + 0.6 * d
          tube(part, b, [0, 0, gl], [0, 0, gl + 0.1 * d], 0.2 * d, nil, c)
          part.add(b, M.box(M.frame([0, 0, gl + 0.1 * d], [1, 0, 0], [0, 1, 0]), [0, 0, 0.025 * d], [0.62 * d, 0.2 * d, 0.05 * d]))
          yoke(part, c, gl, gl + 0.85 * d, 0.3 * d, b)
          stem(part, 1.0 * d, gl + 1.55 * d, c)
          spoked_wheel(part, :iron, [0, 0, gl + 1.2 * d], [0, 0, 1], [0.72 * d, 55.0].max, 5, c)
        when :socket_weld
          tube(part, b, [-0.3 * c[:len], 0, 0], [0.3 * c[:len], 0, 0], 0.6 * d, c[:o].ri, c)
          lathe_z(part, b, [[-0.6 * d, 0], [-0.6 * d, 0.3 * d], [-0.4 * d, 0.62 * d], [0.72 * d, 0.62 * d], [0.72 * d, 0]],
                  c, flat: 0.8)
          plate = M.box(M.frame([0, 0, 0.72 * d], [1, 0, 0], [0, 1, 0]), [0, 0, 0.07 * d], [1.3 * d, 1.1 * d, 0.14 * d])
          part.add(b, plate)
          [[-1, -1], [1, -1], [1, 1], [-1, 1]].each do |sx, sy|
            hex(part, :bolt, [sx * 0.5 * d, sy * 0.4 * d, 0.86 * d], [sx * 0.5 * d, sy * 0.4 * d, 0.98 * d], [0.2 * d, 7.0].max)
          end
          lathe_z(part, b, [[0.86 * d, 0], [0.86 * d, 0.42 * d], [1.3 * d, 0.3 * d], [1.3 * d, 0]], c)
          frame_posts(part, c, 1.3 * d, 2.2 * d, 0.42 * d, b)
          stem(part, 0.9 * d, 2.75 * d, c)
          spoked_wheel(part, :iron, [0, 0, 2.45 * d], [0, 0, 1], [0.95 * d, 42.0].max, 3, c)
        when :threaded
          small_body(part, c, 0.76, 0.62)
          hex(part, b, [0, 0, 0.8 * d], [0, 0, 1.05 * d], 1.15 * d)
          lathe_z(part, b, [[1.05 * d, 0], [1.05 * d, 0.34 * d], [1.35 * d, 0.24 * d], [1.35 * d, 0]], c)
          hex(part, b, [0, 0, 1.35 * d], [0, 0, 1.5 * d], [0.48 * d, 12.0].max)
          stem(part, 1.0 * d, 1.95 * d, c)
          holed_wheel(part, b, 1.72 * d, [0.95 * d, 26.0].max, [0.1 * d, 3.5].max, c)
          hex(part, b, [0, 0, 1.9 * d], [0, 0, 2.02 * d], [0.3 * d, 8.0].max)
        else
          plastic_bonnet_valve(part, c, sphere: false)
        end
      end

      def globe_valve(part, c)
        d = c[:d]
        b = c[:body]
        case c[:fam]
        when :flanged
          tube(part, b, [-0.3 * c[:len], 0, 0], [0.3 * c[:len], 0, 0], 0.56 * d, c[:o].ri, c)
          lathe_z(part, b, [[-0.72 * d, 0], [-0.72 * d, 0.3 * d], [-0.56 * d, 0.62 * d], [-0.2 * d, 0.84 * d],
                            [0.22 * d, 0.84 * d], [0.56 * d, 0.62 * d], [0.76 * d, 0.46 * d], [0.76 * d, 0]], c, flat: 0.86)
          top = bonnet_bolted(part, c, 0.76 * d, 0.62 * d, 0.9)
          lathe_z(part, b, [[top, 0], [top, 0.42 * d], [top + 0.45 * d, 0.28 * d], [top + 0.45 * d, 0]], c)
          yoke(part, c, top + 0.45 * d, top + 1.05 * d, 0.24 * d, b)
          stem(part, 0.9 * d, top + 1.6 * d, c)
          spoked_wheel(part, :iron, [0, 0, top + 1.3 * d], [0, 0, 1], [0.58 * d, 50.0].max, 5, c)
        when :socket_weld
          tube(part, b, [-0.3 * c[:len], 0, 0], [0.3 * c[:len], 0, 0], 0.6 * d, c[:o].ri, c)
          part.add(b, M.scale(M.sphere([0, 0, 0], 0.85 * d, steps: c[:st]), [0, 0, 0], 1.0, 0.85, 1.0))
          plate = M.box(M.frame([0, 0, 0.72 * d], [1, 0, 0], [0, 1, 0]), [0, 0, 0.07 * d], [1.2 * d, 1.0 * d, 0.14 * d])
          part.add(b, plate)
          [[-1, -1], [1, -1], [1, 1], [-1, 1]].each do |sx, sy|
            hex(part, :bolt, [sx * 0.46 * d, sy * 0.36 * d, 0.86 * d], [sx * 0.46 * d, sy * 0.36 * d, 0.98 * d], [0.2 * d, 7.0].max)
          end
          lathe_z(part, b, [[0.86 * d, 0], [0.86 * d, 0.4 * d], [1.25 * d, 0.3 * d], [1.25 * d, 0]], c)
          frame_posts(part, c, 1.25 * d, 2.05 * d, 0.4 * d, b)
          stem(part, 0.9 * d, 2.6 * d, c)
          spoked_wheel(part, :iron, [0, 0, 2.3 * d], [0, 0, 1], [0.85 * d, 40.0].max, 3, c)
        when :threaded
          small_body(part, c, 0.92, 0.58)
          hex(part, b, [0, 0, 0.8 * d], [0, 0, 1.02 * d], 1.1 * d)
          lathe_z(part, b, [[1.02 * d, 0], [1.02 * d, 0.32 * d], [1.28 * d, 0.24 * d], [1.28 * d, 0]], c)
          hex(part, b, [0, 0, 1.28 * d], [0, 0, 1.42 * d], [0.46 * d, 12.0].max)
          stem(part, 1.0 * d, 1.85 * d, c)
          holed_wheel(part, b, 1.62 * d, [0.85 * d, 24.0].max, [0.1 * d, 3.5].max, c)
          hex(part, b, [0, 0, 1.8 * d], [0, 0, 1.92 * d], [0.3 * d, 8.0].max)
        else
          plastic_bonnet_valve(part, c, sphere: true)
        end
      end

      def ball_valve(part, c)
        d = c[:d]
        b = c[:body]
        l = c[:len]
        case c[:fam]
        when :flanged
          lathe_x(part, b, [[-0.3 * l, 0], [-0.3 * l, 0.6 * d], [-0.2 * l, 0.86 * d], [0.2 * l, 0.86 * d],
                            [0.3 * l, 0.6 * d], [0.3 * l, 0]], c)
          tube(part, b, [0.06 * l, 0, 0], [0.12 * l, 0, 0], 0.98 * d, nil, c) # body joint flange
          if c[:det]
            6.times do |k|
              t = 2 * Math::PI * (k + 0.5) / 6
              y = 0.9 * d * Math.cos(t)
              z = 0.9 * d * Math.sin(t)
              hex(part, :bolt, [0.12 * l, y, z], [0.12 * l + 0.08 * d, y, z], [0.12 * d, 6.0].max)
            end
          end
          tube(part, b, [0, 0, 0.8 * d], [0, 0, 1.08 * d], [0.2 * d, 10.0].max, nil, c)
          part.add(b, M.box(M.frame([0, 0, 1.08 * d], [1, 0, 0], [0, 1, 0]), [0, 0, 0.03 * d], [0.55 * d, 0.55 * d, 0.06 * d]))
          lever(part, 1.2 * d, [2.6 * d, 160.0].max, c)
        when :socket_weld
          lathe_x(part, b, [[-0.3 * l, 0], [-0.3 * l, 0.62 * d], [-0.18 * l, 0.8 * d], [0.18 * l, 0.8 * d],
                            [0.3 * l, 0.62 * d], [0.3 * l, 0]], c)
          tube(part, b, [0, 0, 0.7 * d], [0, 0, 0.98 * d], [0.2 * d, 7.0].max, nil, c)
          lever(part, 1.05 * d, [3.0 * d, 110.0].max, c)
        when :threaded
          lathe_x(part, :chrome, [[-0.2 * l, 0], [-0.2 * l, 0.6 * d], [-0.12 * l, 0.74 * d], [0.12 * l, 0.74 * d],
                                  [0.2 * l, 0.6 * d], [0.2 * l, 0]], c)
          tube(part, :chrome, [0, 0, 0.62 * d], [0, 0, 0.9 * d], [0.2 * d, 6.0].max, nil, c)
          hex(part, :chrome, [0, 0, 0.9 * d], [0, 0, 1.0 * d], [0.4 * d, 10.0].max)
          lever(part, 1.06 * d, [3.2 * d, 100.0].max, c, width: [0.2 * d, 10.0].max)
        else
          part.add(b, M.sphere([0, 0, 0], 0.98 * d, steps: c[:st]))
          tube(part, b, [-0.2 * l, 0, 0], [0.2 * l, 0, 0], 0.82 * d, c[:o].ri, c)
          tube(part, b, [0, 0, 0.8 * d], [0, 0, 1.12 * d], 0.26 * d, nil, c)
          w = [0.3 * d, 14.0].max
          part.add(:handle, M.box(M.frame([0, 0, 1.12 * d], [1, 0, 0], [0, 1, 0]), [0, 0, w * 0.35],
                                  [w, [2.0 * d, 80.0].max, w * 0.7]))
          part.add(:handle, M.cylinder([0, 0, 1.12 * d], [0, 0, 1.12 * d + w * 0.9], w * 0.7, steps: 12))
        end
      end

      def butterfly_valve(part, c)
        d = c[:d]
        l = c[:len]
        o = c[:o]
        metallic = c[:fam] != :plastic
        fl = FittingsData.flange(d)
        body_r = metallic ? fl.bolt_circle / 2.0 - fl.hole * 0.9 : o.ro * 1.55
        b = metallic ? :cast : :valve_plastic
        tube(part, b, [-l / 2.0, 0, 0], [l / 2.0, 0, 0], body_r, o.ri, c)
        if metallic && c[:det]
          fl.bolts.times do |k|
            t = 2 * Math::PI * (k + 0.5) / fl.bolts
            u = [0.0, Math.cos(t), Math.sin(t)]
            a = Vec.scale(u, body_r * 0.95)
            e = Vec.scale(u, fl.bolt_circle / 2.0 + fl.hole * 0.9)
            part.add(b, M.bar(a, e, fl.hole * 2.2, l * 0.96, [1, 0, 0]))
          end
        end
        part.add(:chrome, M.cylinder([-0.035 * d, 0, 0], [0.035 * d, 0, 0], o.ri * 0.97, steps: c[:st]))
        part.add(:chrome, M.cylinder([0, 0, -o.ri], [0, 0, o.ri], [0.06 * d, 3.0].max, steps: 8))
        neck = body_r + 0.4 * d
        tube(part, b, [0, 0, body_r * 0.9], [0, 0, neck], [0.14 * d, 10.0].max, nil, c)
        part.add(b, M.box(M.frame([0, 0, neck], [1, 0, 0], [0, 1, 0]), [0, 0, 5], [0.5 * d, 0.5 * d, 10]))
        if d >= 168.0 && metallic
          g = [0.42 * d, 90.0].max
          part.add(:cast, M.box(M.frame([0, 0, neck + 10], [1, 0, 0], [0, 1, 0]), [0, 0, g * 0.45], [g * 0.9, g, g * 0.9]))
          part.add(:bolt, M.box(M.frame([0, 0, neck + 10 + g * 0.9], [1, 0, 0], [0, 1, 0]), [0, 0, 6], [g * 0.3, g * 0.3, 12]))
          shaft = [0, g * 0.5, neck + 10 + g * 0.45]
          part.add(:chrome, M.cylinder(shaft, Vec.add(shaft, [0, g * 0.8, 0]), [0.03 * d, 8.0].max, steps: 8))
          spoked_wheel(part, :iron, Vec.add(shaft, [0, g * 0.8, 0]), [0, 1, 0], [0.5 * d, 100.0].max, 5, c)
        else
          part.add(b, M.box(M.frame([0, 0, neck + 10], [1, 0, 0], [0, 1, 0]), [0.2 * d, 0, 4], [0.9 * d, 0.3 * d, 8]))
          lever(part, neck + 24, [2.4 * d, 160.0].max, c)
        end
        return unless metallic

        [[-l / 2.0, -1.0], [l / 2.0, 1.0]].each do |x, s|
          part.merge(Parts.flange(o), M.frame([x, 0, 0], [s, 0, 0], [0, 1, 0]))
        end
        Parts.bolts(part, o, -l / 2.0 - fl.thickness - 1.6, l / 2.0 + fl.thickness + 1.6) if c[:det]
      end

      def check_valve(part, c)
        d = c[:d]
        b = c[:body]
        l = c[:len]
        case c[:fam]
        when :flanged
          lathe_x(part, b, [[-0.3 * l, 0], [-0.3 * l, 0.6 * d], [-0.12 * l, 0.8 * d], [0.18 * l, 0.8 * d],
                            [0.3 * l, 0.6 * d], [0.3 * l, 0]], c)
          lathe_z(part, b, [[0.3 * d, 0], [0.3 * d, 0.62 * d], [0.86 * d, 0.62 * d], [0.86 * d, 0]], c, x: -0.04 * l, flat: 0.95)
          top = bonnet_bolted(part, c, 0.86 * d, 0.72 * d, 0.95, cx: -0.04 * l)
          hex(part, :bolt, [-0.04 * l, 0, top], [-0.04 * l, 0, top + 0.1 * d], [0.3 * d, 12.0].max) # lifting boss
          hex(part, b, [-0.2 * l, 0.62 * d, 0.3 * d], [-0.2 * l, 0.78 * d, 0.3 * d], [0.24 * d, 10.0].max) # hinge plug
          arrow(part, c, 0.8 * d)
        when :socket_weld
          tube(part, b, [-0.3 * l, 0, 0], [0.3 * l, 0, 0], 0.64 * d, c[:o].ri, c)
          lathe_z(part, b, [[-0.5 * d, 0], [-0.5 * d, 0.4 * d], [0.62 * d, 0.62 * d], [0.62 * d, 0]], c, flat: 0.85)
          part.add(b, M.box(M.frame([0, 0, 0.62 * d], [1, 0, 0], [0, 1, 0]), [0, 0, 0.07 * d], [1.2 * d, 1.0 * d, 0.14 * d]))
          [[-1, -1], [1, -1], [1, 1], [-1, 1]].each do |sx, sy|
            hex(part, :bolt, [sx * 0.46 * d, sy * 0.36 * d, 0.76 * d], [sx * 0.46 * d, sy * 0.36 * d, 0.88 * d], [0.2 * d, 7.0].max)
          end
          arrow(part, c, 0.64 * d)
        when :threaded
          small_body(part, c, 0.8, 0.6)
          lathe_z(part, b, [[0, 0], [0, 0.58 * d], [0.62 * d, 0.58 * d], [0.62 * d, 0]], c)
          hex(part, b, [0, 0, 0.62 * d], [0, 0, 0.9 * d], 1.1 * d)
          tube(part, b, [0, 0, 0.9 * d], [0, 0, 0.98 * d], 0.3 * d, nil, c)
          hex(part, b, [-0.22 * c[:len], 0.6 * d, 0.12 * d], [-0.22 * c[:len], 0.74 * d, 0.12 * d], [0.26 * d, 7.0].max)
          arrow(part, c, 0.78 * d)
        else
          tube(part, b, [-0.2 * l, 0, 0], [0.2 * l, 0, 0], 0.95 * d, c[:o].ri, c)
          arrow(part, c, 0.95 * d)
        end
      end

      def strainer_valve(part, c)
        d = c[:d]
        b = c[:body]
        l = c[:len]
        leg = Vec.unit([1.0, 0.0, -1.0])
        tip = Vec.scale(leg, 0.52 * l)
        case c[:fam]
        when :flanged
          tube(part, b, [-0.28 * l, 0, 0], [0.28 * l, 0, 0], 0.64 * d, c[:o].ri, c)
          part.add(b, M.sphere([0, 0, 0], 0.72 * d, steps: c[:st]))
          part.add(b, M.cylinder([0, 0, 0], tip, 0.52 * d, steps: c[:st]))
          cover = Vec.add(tip, Vec.scale(leg, 0.12 * d))
          part.add(b, M.cylinder(tip, cover, 0.78 * d, steps: c[:st]))
          if c[:det] # cover bolt heads
            f = M.frame(cover, leg)
            6.times do |k|
              t = 2 * Math::PI * (k + 0.5) / 6
              p = M.apply(f, [0, 0.66 * d * Math.cos(t), 0.66 * d * Math.sin(t)])
              part.add(:bolt, M.ngon_prism(p, Vec.add(p, Vec.scale(leg, [0.08 * d, 4.0].max)), [0.07 * d, 4.0].max, 6))
            end
          end
          part.add(:bolt, M.ngon_prism(cover, Vec.add(cover, Vec.scale(leg, [0.14 * d, 8.0].max)), [0.14 * d, 8.0].max, 6))
        when :socket_weld, :threaded
          small_body(part, c, 0.78, 0.6) if c[:fam] == :threaded
          tube(part, b, [-0.28 * l, 0, 0], [0.28 * l, 0, 0], 0.62 * d, c[:o].ri, c) if c[:fam] == :socket_weld
          part.add(b, M.cylinder([0, 0, 0], tip, 0.46 * d, steps: c[:st]))
          part.add(b, M.ngon_prism(tip, Vec.add(tip, Vec.scale(leg, 0.25 * d)), 1.08 * d / SQ3, 6))
          plug = Vec.add(tip, Vec.scale(leg, 0.25 * d))
          part.add(:bolt, M.ngon_prism(plug, Vec.add(plug, Vec.scale(leg, 0.12 * d)), [0.14 * d, 5.0].max, 6))
        else
          tube(part, b, [-0.2 * l, 0, 0], [0.2 * l, 0, 0], 0.8 * d, c[:o].ri, c)
          part.add(b, M.cylinder([0, 0, 0], tip, 0.62 * d, steps: c[:st]))
          part.add(b, M.ngon_prism(Vec.sub(tip, Vec.scale(leg, 0.15 * d)), Vec.add(tip, Vec.scale(leg, 0.15 * d)),
                                   0.9 * d, 24))
        end
      end

      def prv_valve(part, c)
        d = c[:d]
        b = c[:body]
        l = c[:len]
        if c[:fam] == :flanged || c[:fam] == :socket_weld
          tube(part, b, [-0.3 * l, 0, 0], [0.3 * l, 0, 0], 0.56 * d, c[:o].ri, c)
        else
          small_body(part, c, 0.86, 0.58)
        end
        part.add(b, M.scale(M.sphere([0, 0, 0], 0.8 * d, steps: c[:st]), [0, 0, 0], 1.0, 0.9, 1.0))
        tube(part, b, [0, 0, 0.6 * d], [0, 0, 0.82 * d], 0.34 * d, nil, c)
        big = [1.05 * d, 38.0].max
        part.add(:handle, M.frustum([0, 0, 0.82 * d], [0, 0, 1.0 * d], 0.36 * d, big, steps: c[:st] + 8))
        part.add(:handle, M.frustum([0, 0, 1.03 * d], [0, 0, 1.22 * d], big, 0.4 * d, steps: c[:st] + 8))
        part.add(:handle, M.cylinder([0, 0, 0.99 * d], [0, 0, 1.04 * d], big * 1.04, steps: c[:st] + 8))
        bolt_ring(part, :bolt, 1.04 * d, big * 0.96, 12, [0.08 * d, 5.0].max, [0.05 * d, 3.0].max, c)
        part.add(:handle, M.frustum([0, 0, 1.22 * d], [0, 0, 2.2 * d], 0.4 * d, 0.3 * d, steps: c[:st]))
        stem(part, 2.2 * d, 2.55 * d, c)
        hex(part, :bolt, [0, 0, 2.2 * d], [0, 0, 2.3 * d], [0.2 * d, 8.0].max)
        # outlet pressure gauge on the side
        gy = 0.72 * d
        part.add(:chrome, M.cylinder([0.2 * l, 0.3 * d, 0.2 * d], [0.2 * l, gy + 0.4 * d, 0.2 * d], [0.06 * d, 3.0].max, steps: 8))
        gr = [0.42 * d, 28.0].max
        gc = [0.2 * l, gy + 0.4 * d, 0.2 * d] # gauge back sits on the end of its stem
        part.add(:chrome, M.cylinder(gc, [gc[0], gc[1] + gr * 0.35, gc[2]], gr, steps: 20))
        part.add(:gauge, M.cylinder([gc[0], gc[1] + gr * 0.35, gc[2]], [gc[0], gc[1] + gr * 0.38, gc[2]], gr * 0.86, steps: 20))
      end

      # Horizontal body between threaded/plastic ends.
      def small_body(part, c, bulge, neck)
        d = c[:d]
        l = c[:len]
        lathe_x(part, c[:body], [[-0.25 * l, 0], [-0.25 * l, neck * d], [-0.12 * l, bulge * d], [0.12 * l, bulge * d],
                                 [0.25 * l, neck * d], [0.25 * l, 0]], c)
      end

      def frame_posts(part, c, z0, z1, half, role)
        d = c[:d]
        w = [0.16 * d, 7.0].max
        [-1, 1].each do |s|
          part.add(role, M.bar([s * half, 0, z0], [s * half, 0, z1], w, w * 0.8, [1, 0, 0]))
        end
        part.add(role, M.box(M.frame([0, 0, z1], [1, 0, 0], [0, 1, 0]), [0, 0, w * 0.5],
                             [2 * half + w, w * 1.2, w]))
        hex(part, :bolt, [0, 0, z1 + w], [0, 0, z1 + w * 1.8], [0.3 * d, 10.0].max)
      end

      def plastic_bonnet_valve(part, c, sphere:)
        d = c[:d]
        b = c[:body]
        tube(part, b, [-0.2 * c[:len], 0, 0], [0.2 * c[:len], 0, 0], 0.8 * d, c[:o].ri, c)
        part.add(b, M.sphere([0, 0, 0], 0.95 * d, steps: c[:st])) if sphere
        lathe_z(part, b, [[0, 0], [0, 0.6 * d], [0.8 * d, 0.55 * d], [1.1 * d, 0.42 * d], [1.1 * d, 0]], c)
        stem(part, 1.0 * d, 1.5 * d, c)
        holed_wheel(part, :handle, 1.35 * d, [0.95 * d, 30.0].max, [0.12 * d, 4.0].max, c)
      end

      # Raised flow arrow cast on the +Y side of the body.
      def arrow(part, c, y)
        d = c[:d]
        a = 0.28 * c[:len]
        h = 0.08 * d
        shaft = [[-a, y, -h], [a * 0.35, y, -h], [a * 0.35, y, h], [-a, y, h]]
        head = [[a * 0.35, y, -2.4 * h], [a, y, 0.0], [a * 0.35, y, 2.4 * h]]
        part.add(:bolt, M.extrude(shaft, [0, [0.03 * d, 1.5].max, 0]))
        part.add(:bolt, M.extrude(head, [0, [0.03 * d, 1.5].max, 0]))
      end
    end
  end
end
