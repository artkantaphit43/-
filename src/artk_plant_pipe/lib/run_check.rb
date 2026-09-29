# frozen_string_literal: true

require_relative 'vec'
require_relative 'hydraulics'
require_relative 'fittings_data'
require_relative 'services'
require_relative 'profile'

module ArtK
  module PlantPipe
    # Hydraulic check of one drawn run at its design flow.
    #
    # Pressure services: friction (Darcy–Weisbach, plus Hazen–Williams for
    # fire protection per NFPA 13) + fitting/valve minor losses (K method) +
    # static head from the drawn elevations.
    # Gravity services: Manning capacity at the *flattest* drawn slope with
    # the pipe half full (the usual design depth for sanitary drains, which
    # keeps the vent path open), and a check against the IPC minimum fall.
    # Compressible services: velocity only.
    module RunCheck
      DESIGN_FILL = 0.5

      module_function

      # run: {
      #   spec:, service:, flow_m3h:,
      #   cl:     [[[x,y,z], [x,y,z]], ...] centreline segments in draw order,
      #   pipes:  [{ from: [mm], to: [mm], length_mm: }],
      #   elbows: [{ angle_deg:, radius_type:, radius_mm: }],
      #   tees:   [{ kind:, role: 'run'|'branch' }],
      #   valves: ['gate', ...] }
      def check(run)
        spec = run[:spec]
        svc = Services.get(run[:service])
        q = run[:flow_m3h].to_f
        pipes = run[:pipes] || []
        elbows = run[:elbows] || []
        res = { messages: [], ok: true, flow_m3h: q, id_mm: spec.id.round(1) }

        pipe_len = pipes.sum { |p| p[:length_mm].to_f } / 1000.0
        arc_len = elbows.sum { |e| e[:radius_mm].to_f * e[:angle_deg].to_f * Math::PI / 180.0 } / 1000.0
        res[:length_m] = (pipe_len + arc_len).round(2)
        profile_advice(res, svc, run[:cl] || [])

        if q <= 0
          res[:ok] = false
          res[:messages] << 'ยังไม่ได้กำหนดอัตราการไหลออกแบบ (no design flow set)'
          return res
        end

        v = Hydraulics.velocity(q, spec.id)
        res[:velocity] = v.round(2)
        if svc[:vmax] && v > svc[:vmax]
          res[:ok] = false
          res[:messages] << "ความเร็ว #{v.round(2)} m/s เกินค่าแนะนำ #{svc[:vmax]} m/s – " \
                            'ควรเพิ่มขนาดท่อ (velocity above recommended, upsize)'
        end
        if Hydraulics.liquid?(svc[:fluid]) && !svc[:gravity] && v < 0.3
          res[:messages] << "ความเร็วต่ำ #{v.round(2)} m/s อาจเกิดตะกอน/น้ำนิ่ง " \
                            '(low velocity, risk of sediment/stagnation)'
        end

        if svc[:gravity]
          gravity_check(res, spec, q)
        elsif Hydraulics.liquid?(svc[:fluid])
          pressure_check(res, run, spec, svc, q, v, pipe_len + arc_len)
        else
          res[:messages] << 'ของไหลอัดตัวได้: ตรวจเฉพาะความเร็ว (compressible fluid: velocity check only)'
        end
        res
      end

      def pressure_check(res, run, spec, svc, q, v, length_m)
        fluid = svc[:fluid]
        hf = Hydraulics.darcy_hf(q, spec.id, spec.roughness_mm, length_m, fluid)
        k = k_sum(run)
        hm = Hydraulics.minor_loss(k, v)
        dz = elevation_change(run[:cl])
        res[:hf_friction] = hf.round(3)
        res[:hf100] = length_m.positive? ? (hf / length_m * 100.0).round(2) : 0.0
        if svc[:code] == 'FP'
          res[:hf_hazen_williams] = Hydraulics.hazen_williams_hf(q, spec.id, spec.hw_c, length_m).round(3)
        end
        res[:k_sum] = k.round(2)
        res[:hf_minor] = hm.round(3)
        res[:dz] = dz.round(3)
        total = hf + hm + dz
        res[:total_head] = total.round(3)
        res[:total_bar] = Hydraulics.head_to_bar(total, fluid).round(3)
        if svc[:hf_max] && res[:hf100] > svc[:hf_max]
          res[:ok] = false
          res[:messages] << "แรงเสียดทาน #{res[:hf100]} m/100m เกินค่าแนะนำ #{svc[:hf_max]} m/100m " \
                            '(friction loss above recommended)'
        end
      end

      def gravity_check(res, spec, q)
        slopes = res[:slopes] || []
        if slopes.empty?
          res[:messages] << 'ไม่มีช่วงท่อแนวนอนสำหรับตรวจความลาดเอียง (no horizontal pipe to check)'
          return
        end
        min_s = slopes.min
        res[:min_slope_pct] = min_s.round(2)
        need = Services.min_drain_slope_pct(spec.od)
        res[:required_slope_pct] = need
        if min_s < 0.01
          res[:ok] = false
          res[:messages] << 'มีช่วงท่อระบายที่ไม่มีความลาดเอียง (flat drainage pipe)'
          return
        end
        if min_s + 1e-6 < need
          res[:ok] = false
          res[:messages] << "ความลาดต่ำสุด #{min_s.round(2)}% น้อยกว่าที่แนะนำ #{need}% (IPC 704.1) " \
                            '(fall below recommended minimum)'
        end
        cap = Hydraulics.manning_capacity(spec.id, min_s, fill: DESIGN_FILL)
        res[:capacity_m3h] = cap[:q_m3h].round(2)
        res[:velocity_half_full] = cap[:v].round(2)
        if q > cap[:q_m3h]
          res[:ok] = false
          res[:messages] << "อัตราการไหล #{q} m³/h เกินความสามารถที่ครึ่งท่อ #{cap[:q_m3h].round(2)} m³/h " \
                            '(exceeds half-full capacity, upsize or steepen)'
        end
        return unless cap[:v] < 0.6

        res[:messages] << "ความเร็วที่ครึ่งท่อ #{cap[:v].round(2)} m/s < 0.6 m/s ไม่เพียงพอสำหรับ " \
                          'การชำระล้างตัวเอง (below self-cleansing velocity)'
      end

      # High/low point advice by service type.
      def profile_advice(res, svc, cl)
        return if cl.empty?

        prof = Profile.analyse(cl)
        res[:slopes] = prof[:slopes]
        res[:low_points] = prof[:low]
        res[:high_points] = prof[:high]
        low_msg, high_msg =
          if svc[:gravity]
            ['จุดท้องช้าง (sag) ในท่อระบาย – ของเสียจะค้าง ต้องแก้แนวท่อ (sag in gravity drain)',
             'ท่อระบายลาดย้อน (reverse fall) – ต้องแก้แนวท่อ']
          else
            case svc[:fluid]
            when :steam
              ['จุดต่ำ: ติดตั้ง drip leg + steam trap (low point: drip leg & steam trap)', nil]
            when :air
              ['จุดต่ำ: ติดตั้ง auto drain ระบายน้ำควบแน่น (low point: condensate drain)', nil]
            when :gas
              ['จุดต่ำ: ติดตั้ง drip / sediment trap (low point: drip leg)', nil]
            else
              ['จุดต่ำ: ติดตั้งวาล์วระบายน้ำทิ้ง (low point: drain valve)',
               'จุดสูง: ติดตั้งวาล์วระบายอากาศ (high point: air release valve)']
            end
          end
        if low_msg && !prof[:low].empty?
          res[:ok] = false if svc[:gravity]
          res[:messages] << "#{low_msg} × #{prof[:low].size}"
        end
        return unless high_msg && !prof[:high].empty?

        res[:ok] = false if svc[:gravity]
        res[:messages] << "#{high_msg} × #{prof[:high].size}"
      end

      def k_sum(run)
        k = 0.0
        (run[:elbows] || []).each do |e|
          k += FittingsData.elbow_k(e[:angle_deg].to_f, e[:radius_type].to_s == 'sr' ? :sr : :lr)
        end
        (run[:tees] || []).each do |t|
          k += if t[:kind].to_s == 'cross' then FittingsData::K_FITTINGS[:cross]
               elsif t[:role].to_s == 'branch' then FittingsData::K_FITTINGS[:tee_branch]
               else FittingsData::K_FITTINGS[:tee_run]
               end
        end
        (run[:mitres] || []).each { k += FittingsData::K_FITTINGS[:mitre] }
        (run[:valves] || []).each do |vt|
          k += (FittingsData::VALVES[vt.to_s] || { k: 0.0 })[:k]
        end
        k
      end

      # Elevation gain from the first drawn point to the last one
      # (positive = flowing uphill = extra head required).
      def elevation_change(cl)
        return 0.0 if cl.nil? || cl.empty?

        (cl.last[1][2].to_f - cl.first[0][2].to_f) / 1000.0
      end
    end
  end
end
