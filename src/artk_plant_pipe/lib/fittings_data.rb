# frozen_string_literal: true

module ArtK
  module PlantPipe
    # Valve & fitting reference data used for layout geometry and head-loss.
    #
    # Valve face-to-face lengths follow ASME B16.10 Class 150 (flanged) for
    # the listed pipe ODs and are linearly interpolated by OD for anything in
    # between (e.g. metric plastic sizes). They are *layout* dimensions –
    # always confirm with the selected vendor before fabrication.
    module FittingsData
      # type => { name:, th:, k: resistance coefficient (fully open, typical
      #          values after Crane TP-410), ff: [[OD mm, face-to-face mm], ...] }
      VALVES = {
        'gate' => {
          name: 'Gate Valve', th: 'ประตูน้ำ (Gate)', k: 0.15, operator: :handwheel,
          ff: [[21.3, 108], [33.4, 127], [48.3, 165], [60.3, 178], [88.9, 203],
               [114.3, 229], [168.3, 267], [219.1, 292], [273.0, 330], [323.8, 356]]
        },
        'globe' => {
          name: 'Globe Valve', th: 'โกล๊บวาล์ว (Globe)', k: 6.0, operator: :handwheel,
          ff: [[21.3, 108], [33.4, 127], [48.3, 165], [60.3, 203], [88.9, 241],
               [114.3, 292], [168.3, 406], [219.1, 495], [273.0, 622], [323.8, 698]]
        },
        'ball' => {
          name: 'Ball Valve', th: 'บอลวาล์ว (Ball)', k: 0.05, operator: :lever,
          ff: [[21.3, 108], [33.4, 127], [48.3, 165], [60.3, 178], [88.9, 203],
               [114.3, 229], [168.3, 394], [219.1, 457], [273.0, 533], [323.8, 610]]
        },
        'butterfly' => {
          name: 'Butterfly Valve (wafer)', th: 'บัตเตอร์ฟลายวาล์ว', k: 0.8, operator: :gear,
          ff: [[48.3, 33], [60.3, 43], [88.9, 46], [114.3, 52], [168.3, 56],
               [219.1, 60], [273.0, 68], [323.8, 78], [406.4, 102], [610.0, 154]]
        },
        'check' => {
          name: 'Swing Check Valve', th: 'เช็ควาล์ว (Swing Check)', k: 2.0, operator: :none,
          ff: [[21.3, 108], [33.4, 127], [48.3, 165], [60.3, 203], [88.9, 241],
               [114.3, 292], [168.3, 356], [219.1, 495], [273.0, 622], [323.8, 698]]
        },
        'strainer' => {
          name: 'Y-Strainer', th: 'วายสเตรนเนอร์ (Y-Strainer)', k: 2.5, operator: :basket,
          ff: [[21.3, 110], [33.4, 140], [48.3, 180], [60.3, 203], [88.9, 254],
               [114.3, 305], [168.3, 406], [219.1, 495], [273.0, 600], [323.8, 700]]
        },
        'prv' => {
          name: 'Pressure Reducing Valve', th: 'วาล์วลดแรงดัน (PRV)', k: 10.0, operator: :pilot,
          ff: [[21.3, 150], [33.4, 180], [48.3, 210], [60.3, 254], [88.9, 298],
               [114.3, 352], [168.3, 451], [219.1, 543], [273.0, 673], [323.8, 737]]
        },
        'flange' => {
          name: 'Flange Pair (Class 150)', th: 'หน้าแปลนคู่', k: 0.0, operator: :none,
          ff: nil
        }
      }.freeze

      # ASME B16.5 Class 150 flange OD by pipe OD (mm).
      FLANGE_OD = [[21.3, 90], [26.7, 100], [33.4, 110], [42.2, 115], [48.3, 125],
                   [60.3, 150], [73.0, 180], [88.9, 190], [114.3, 230], [141.3, 255],
                   [168.3, 280], [219.1, 345], [273.0, 405], [323.8, 485], [355.6, 535],
                   [406.4, 595], [457.0, 635], [508.0, 700], [610.0, 815]].freeze

      # ASME B16.5 Class 150 weld-neck flange, keyed by pipe OD (mm):
      #   [pipe OD, flange OD, thickness, bolt circle, bolts, hole Ø,
      #    raised-face Ø, length through hub Y, hub Ø at base X]
      FLANGE150 = [
        [21.3,   90.0,  9.6,  60.3,  4, 15.9,  34.9,  47.6,  30.2],
        [26.7,  100.0, 11.2,  69.9,  4, 15.9,  42.9,  52.4,  38.1],
        [33.4,  110.0, 12.7,  79.4,  4, 15.9,  50.8,  55.6,  49.2],
        [42.2,  115.0, 14.3,  88.9,  4, 15.9,  63.5,  57.2,  58.7],
        [48.3,  125.0, 15.9,  98.4,  4, 15.9,  73.0,  61.9,  65.1],
        [60.3,  150.0, 17.5, 120.7,  4, 19.1,  92.1,  63.5,  77.8],
        [73.0,  180.0, 20.7, 139.7,  4, 19.1, 104.8,  69.9,  90.5],
        [88.9,  190.0, 22.3, 152.4,  4, 19.1, 127.0,  69.9, 108.0],
        [114.3, 230.0, 22.3, 190.5,  8, 19.1, 157.2,  76.2, 134.9],
        [141.3, 255.0, 22.3, 215.9,  8, 22.2, 185.7,  88.9, 163.5],
        [168.3, 280.0, 23.9, 241.3,  8, 22.2, 215.9,  88.9, 192.1],
        [219.1, 345.0, 27.0, 298.5,  8, 22.2, 269.9, 101.6, 246.1],
        [273.0, 405.0, 28.6, 362.0, 12, 25.4, 323.8, 101.6, 304.8],
        [323.8, 485.0, 30.2, 431.8, 12, 25.4, 381.0, 114.3, 365.1],
        [355.6, 535.0, 33.4, 476.3, 12, 28.6, 412.8, 127.0, 400.1],
        [406.4, 595.0, 35.0, 539.8, 16, 28.6, 469.9, 127.0, 457.2],
        [457.0, 635.0, 38.1, 577.9, 16, 31.8, 533.4, 139.7, 505.0],
        [508.0, 700.0, 41.3, 635.0, 20, 31.8, 584.2, 144.5, 558.8],
        [610.0, 815.0, 46.1, 749.3, 20, 35.1, 692.2, 152.4, 663.4]
      ].freeze

      Flange = Struct.new(:od, :thickness, :bolt_circle, :bolts, :hole, :raised_face, :hub_length, :hub_base,
                          keyword_init: true)

      # Typical resistance coefficients for fittings (fully turbulent flow).
      K_FITTINGS = {
        elbow90_lr: 0.3, elbow90_sr: 0.5, elbow45: 0.2,
        tee_run: 0.3, tee_branch: 1.0, cross: 1.0,
        mitre: 1.1, entrance: 0.5, exit: 1.0
      }.freeze

      module_function

      def valve(type)
        VALVES[type] or raise ArgumentError, "Unknown valve type: #{type}"
      end

      def valve_types
        VALVES.keys
      end

      # Piecewise-linear interpolation, clamped proportionally outside range.
      def interpolate(table, x)
        return table.first[1] * x / table.first[0] if x <= table.first[0]
        return table.last[1] * x / table.last[0] if x >= table.last[0]

        table.each_cons(2) do |(x0, y0), (x1, y1)|
          next unless x >= x0 && x <= x1

          return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
        end
      end

      def face_to_face(type, od)
        ff = valve(type)[:ff]
        return 2.0 * flange_thickness(od) + 3.0 if ff.nil? # flange pair + gasket

        interpolate(ff, od).round(1)
      end

      def flange_od(od)
        flange(od).od
      end

      def flange_thickness(od)
        flange(od).thickness
      end

      # Class 150 flange for a pipe OD. Tabulated sizes are exact; other ODs
      # (metric plastic pipe with flange adaptors) are interpolated and take
      # the bolt count of the nearest tabulated size.
      def flange(od)
        col = ->(i) { interpolate(FLANGE150.map { |r| [r[0], r[i]] }, od).round(1) }
        nearest = FLANGE150.min_by { |r| (r[0] - od).abs }
        Flange.new(od: col.call(1), thickness: col.call(2), bolt_circle: col.call(3), bolts: nearest[4],
                   hole: col.call(5), raised_face: col.call(6), hub_length: col.call(7), hub_base: col.call(8))
      end

      # ASME B16.9 concentric/eccentric reducer end-to-end length H by the
      # large-end pipe OD (mm).
      REDUCER_H = [[26.7, 38.0], [33.4, 51.0], [42.2, 51.0], [48.3, 64.0], [60.3, 76.0], [73.0, 89.0],
                   [88.9, 89.0], [114.3, 102.0], [141.3, 127.0], [168.3, 140.0], [219.1, 152.0],
                   [273.0, 178.0], [323.8, 203.0], [355.6, 330.0], [406.4, 356.0], [457.0, 381.0],
                   [508.0, 508.0], [610.0, 508.0]].freeze

      # Reducer length: B16.9 for butt-weld; for socket/threaded reducers
      # (bushes) both socket depths plus a short transition.
      def reducer_length(od_large, od_small, style = :butt_weld)
        if %i[socket threaded].include?(style)
          (socket_depth(od_large) + socket_depth(od_small) + 0.3 * od_large).round(1)
        else
          [interpolate(REDUCER_H, od_large), 1.2 * (od_large - od_small) + 20.0].max.round(1)
        end
      end

      # Socket depth for solvent-cement / fusion / solder sockets (≈ ISO 727
      # minimum 0.5·OD + 6 mm) and thread engagement for threaded fittings.
      def socket_depth(od)
        [0.5 * od + 6.0, 14.0].max.round(1)
      end

      def thread_engagement(od)
        [0.35 * od, 10.0].max.round(1)
      end

      # K for an elbow of a given angle / radius type.
      def elbow_k(angle_deg, radius_type)
        k90 = radius_type == :sr ? K_FITTINGS[:elbow90_sr] : K_FITTINGS[:elbow90_lr]
        return K_FITTINGS[:elbow45] if (angle_deg - 45.0).abs < 1.0

        # Scale roughly with the deflection angle for non-standard bends.
        k90 * [angle_deg / 90.0, 0.2].max
      end
    end
  end
end
