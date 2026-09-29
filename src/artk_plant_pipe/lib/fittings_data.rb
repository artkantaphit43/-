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
        interpolate(FLANGE_OD, od).round(1)
      end

      # Class 150 flange thickness approximation (≈ 11–30 mm over 1/2"–24").
      def flange_thickness(od)
        [[0.045 * od + 10.0, 11.0].max, 40.0].min.round(1)
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
