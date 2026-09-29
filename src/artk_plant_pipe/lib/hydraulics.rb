# frozen_string_literal: true

module ArtK
  module PlantPipe
    # Hydraulic calculations for sizing and checking pipe runs.
    #
    # Units: flow Q in m³/h (actual volumetric flow), diameters in mm,
    # lengths in m, head loss in m of fluid column, velocity in m/s.
    #
    # Method choice:
    # * Water services use Darcy–Weisbach with the Swamee–Jain friction
    #   factor. It is valid for any temperature/viscosity (Hazen–Williams is
    #   only calibrated for ~cold water, so it under-predicts for hot water
    #   and is wrong for oils). Hazen–Williams is also provided because Thai
    #   fire-protection design (NFPA 13/EIT) requires it.
    # * Compressible services (air, steam, gas) are checked on velocity only:
    #   their pressure drop depends on pressure & density along the line,
    #   which is outside what a layout tool should pretend to know.
    # * Gravity drainage uses Manning with the exact partial-flow geometry.
    module Hydraulics
      G = 9.81

      # Density kg/m³, kinematic viscosity m²/s.
      FLUIDS = {
        water:     { rho: 998.2, nu: 1.004e-6, name: 'Water 20 °C' },
        hot_water: { rho: 983.2, nu: 0.474e-6, name: 'Water 60 °C' },
        chemical:  { rho: 1100.0, nu: 1.2e-6,  name: 'Aqueous chemical (assumed)' },
        oil:       { rho: 900.0, nu: 30.0e-6,  name: 'Light fuel oil (assumed)' }
      }.freeze

      LIQUIDS = FLUIDS.keys.freeze

      module_function

      def liquid?(fluid)
        LIQUIDS.include?(fluid)
      end

      def area_m2(id_mm)
        d = id_mm / 1000.0
        Math::PI * d * d / 4.0
      end

      def velocity(q_m3h, id_mm)
        (q_m3h / 3600.0) / area_m2(id_mm)
      end

      def reynolds(v, id_mm, nu)
        v * (id_mm / 1000.0) / nu
      end

      # Darcy friction factor: laminar 64/Re, otherwise Swamee–Jain
      # (explicit approximation of Colebrook, ±1 % for 5e3 < Re < 1e8).
      def friction_factor(re, roughness_mm, id_mm)
        return 0.0 if re <= 0
        return 64.0 / re if re < 2300.0

        rel = (roughness_mm / id_mm) / 3.7
        0.25 / (Math.log10(rel + 5.74 / (re**0.9)))**2
      end

      # Darcy–Weisbach friction head loss (m).
      def darcy_hf(q_m3h, id_mm, roughness_mm, length_m, fluid = :water)
        props = FLUIDS[fluid] || FLUIDS[:water]
        v = velocity(q_m3h, id_mm)
        f = friction_factor(reynolds(v, id_mm, props[:nu]), roughness_mm, id_mm)
        f * (length_m / (id_mm / 1000.0)) * v * v / (2.0 * G)
      end

      # Hazen–Williams friction head loss (m), SI form:
      #   hf = 10.67 · L · Q^1.852 / (C^1.852 · d^4.8704)
      def hazen_williams_hf(q_m3h, id_mm, c, length_m)
        q = q_m3h / 3600.0
        d = id_mm / 1000.0
        10.67 * length_m * q**1.852 / (c**1.852 * d**4.8704)
      end

      # Minor loss for a summed resistance coefficient.
      def minor_loss(k_sum, v)
        k_sum * v * v / (2.0 * G)
      end

      def head_to_bar(h, fluid = :water)
        rho = (FLUIDS[fluid] || FLUIDS[:water])[:rho]
        rho * G * h / 1.0e5
      end

      # Evaluate a catalogue of sizes for a flow; returns rows and the index
      # of the recommended (smallest acceptable) size, or nil.
      #   specs  – array of PipeSpec
      #   vmax   – max velocity m/s (nil = not checked)
      #   hf_max – max friction loss m/100 m (nil = not checked; liquids only)
      def size_table(specs, q_m3h, fluid:, vmax:, hf_max:)
        rows = specs.map do |sp|
          v = velocity(q_m3h, sp.id)
          hf100 = liquid?(fluid) ? darcy_hf(q_m3h, sp.id, sp.roughness_mm, 100.0, fluid) : nil
          ok_v = vmax.nil? || v <= vmax
          ok_hf = hf_max.nil? || hf100.nil? || hf100 <= hf_max
          { size: sp.size, rating: sp.rating, id: sp.id.round(1), v: v.round(2),
            hf100: hf100 && hf100.round(2), ok: ok_v && ok_hf, ok_v: ok_v, ok_hf: ok_hf }
        end
        [rows, rows.index { |r| r[:ok] }]
      end

      # ---------- Gravity drainage (Manning) ----------

      # Manning n – plastic (PVC/HDPE/PP-R) 0.009–0.010; steel 0.012; a
      # conservative 0.011 is used unless supplied.
      MANNING_N = 0.011

      # Flow area & wetted perimeter for depth ratio y/D (0 < y/D ≤ 1).
      def partial_geometry(id_mm, fill)
        d = id_mm / 1000.0
        fill = 1.0 if fill > 1.0
        return [area_m2(id_mm), Math::PI * d] if fill >= 0.9999

        theta = 2.0 * Math.acos(1.0 - 2.0 * fill)
        area = d * d / 8.0 * (theta - Math.sin(theta))
        perim = d * theta / 2.0
        [area, perim]
      end

      # Returns { q_m3h:, v: } for a pipe flowing at the given depth ratio.
      def manning_capacity(id_mm, slope_pct, fill: 0.5, n: MANNING_N)
        a, p = partial_geometry(id_mm, fill)
        r = a / p
        s = slope_pct / 100.0
        v = (1.0 / n) * r**(2.0 / 3.0) * Math.sqrt(s)
        { q_m3h: (v * a * 3600.0), v: v }
      end
    end
  end
end
