# frozen_string_literal: true

require 'json'

module ArtK
  module PlantPipe
    # Resolved dimensions of one pipe (standard + size + rating). All mm.
    PipeSpec = Struct.new(
      :catalog_key, :catalog_name, :material, :joint, :size, :rating,
      :od, :wall, :nps_in, :hw_c, :roughness_mm, :density,
      :elbow_radius_lr, :elbow_radius_sr, :tee_c, :fitting_od, :stick_length_m,
      :estimated, :style, :family,
      keyword_init: true
    ) do
      def id
        od - 2.0 * wall
      end

      # Internal flow area in m².
      def area_m2
        d = id / 1000.0
        Math::PI * d * d / 4.0
      end

      # Mass per metre (kg/m) of the empty pipe: π·t·(OD−t)·ρ.
      # For carbon steel (ρ = 7850) this is the familiar 0.02466·t·(OD−t).
      def weight_kg_m
        Math::PI * wall * (od - wall) * density / 1.0e6
      end

      # Mass of the water content per metre, useful for support loads.
      def water_kg_m
        area_m2 * 1000.0
      end

      def label
        "#{size} #{rating}"
      end
    end

    # Pipe standards catalogue.
    #
    # Sources (dimensions reproduced from the published tables):
    # * ASME B36.10M  – welded & seamless wrought steel pipe (carbon steel)
    # * ASME B36.19M  – stainless steel pipe (5S/10S/40S)
    # * BS 1387 Medium / TIS 277 (มอก.277) – galvanised steel pipe (GSP)
    # * DIN 8077 / ISO 15874 – PP-R pipe (PN10/16/20)
    # * ISO 4427 – PE100 pipe (SDR17 = PN10, SDR11 = PN16)
    # * ASTM B88 Type L – seamless copper water tube
    # * TIS 17-2532 (มอก.17) – PVC-U water pipe. OD per standard; wall
    #   thickness is *estimated* from the class pressure with the hoop-stress
    #   formula (see PVC_WALL) and flagged so the UI can warn the user.
    #
    # Fitting dimensions:
    # * ASME B16.9 long-radius 90° elbow centre-to-end (A) and straight tee
    #   centre-to-end (C) for butt-weld steel.
    # * Plastic / threaded fittings use proportional approximations of
    #   typical manufacturer geometry – good for layout and clash checks, not
    #   for fabrication spool drawings.
    module Catalog
      INCH = 25.4

      # NPS => [OD mm, B16.9 tee C mm]
      STEEL_NPS = {
        '1/2"'   => [0.5,   21.3,  25],
        '3/4"'   => [0.75,  26.7,  29],
        '1"'     => [1.0,   33.4,  38],
        '1-1/4"' => [1.25,  42.2,  48],
        '1-1/2"' => [1.5,   48.3,  57],
        '2"'     => [2.0,   60.3,  64],
        '2-1/2"' => [2.5,   73.0,  76],
        '3"'     => [3.0,   88.9,  86],
        '4"'     => [4.0,  114.3, 105],
        '5"'     => [5.0,  141.3, 124],
        '6"'     => [6.0,  168.3, 143],
        '8"'     => [8.0,  219.1, 178],
        '10"'    => [10.0, 273.0, 216],
        '12"'    => [12.0, 323.8, 254],
        '14"'    => [14.0, 355.6, 279],
        '16"'    => [16.0, 406.4, 305],
        '18"'    => [18.0, 457.0, 343],
        '20"'    => [20.0, 508.0, 381],
        '24"'    => [24.0, 610.0, 432]
      }.freeze

      # ASME B36.10M wall thickness (mm), same order as STEEL_NPS.
      CS_WALLS = {
        'SCH40' => [2.77, 2.87, 3.38, 3.56, 3.68, 3.91, 5.16, 5.49, 6.02, 6.55,
                    7.11, 8.18, 9.27, 10.31, 11.13, 12.70, 14.27, 15.09, 17.48],
        'SCH80' => [3.73, 3.91, 4.55, 4.85, 5.08, 5.54, 7.01, 7.62, 8.56, 9.53,
                    10.97, 12.70, 15.09, 17.48, 19.05, 21.44, 23.83, 26.19, 30.96]
      }.freeze

      # ASME B36.19M wall thickness (mm).
      SS_WALLS = {
        '5S'  => [1.65, 1.65, 1.65, 1.65, 1.65, 1.65, 2.11, 2.11, 2.11, 2.77,
                  2.77, 2.77, 3.40, 3.96, 3.96, 4.19, 4.19, 4.78, 5.54],
        '10S' => [2.11, 2.11, 2.77, 2.77, 2.77, 2.77, 3.05, 3.05, 3.05, 3.40,
                  3.40, 3.76, 4.19, 4.57, 4.78, 4.78, 4.78, 5.54, 6.35],
        '40S' => [2.77, 2.87, 3.38, 3.56, 3.68, 3.91, 5.16, 5.49, 6.02, 6.55,
                  7.11, 8.18, 9.27, 9.53, 9.53, 9.53, 9.53, 9.53, 9.53]
      }.freeze

      # BS 1387 Medium: size => [nps, OD, wall]
      GSP_MEDIUM = {
        '1/2"'   => [0.5,   21.4, 2.6],
        '3/4"'   => [0.75,  26.9, 2.6],
        '1"'     => [1.0,   33.8, 3.2],
        '1-1/4"' => [1.25,  42.5, 3.2],
        '1-1/2"' => [1.5,   48.4, 3.2],
        '2"'     => [2.0,   60.3, 3.6],
        '2-1/2"' => [2.5,   76.0, 3.6],
        '3"'     => [3.0,   88.8, 4.0],
        '4"'     => [4.0,  114.1, 4.5],
        '5"'     => [5.0,  139.6, 5.0],
        '6"'     => [6.0,  165.1, 5.0]
      }.freeze

      # TIS 17-2532 PVC-U: size => [nps, OD]
      PVC_OD = {
        '1/2"'   => [0.5,   22.0],
        '3/4"'   => [0.75,  26.0],
        '1"'     => [1.0,   34.0],
        '1-1/4"' => [1.25,  42.0],
        '1-1/2"' => [1.5,   48.0],
        '2"'     => [2.0,   60.0],
        '2-1/2"' => [2.5,   76.0],
        '3"'     => [3.0,   89.0],
        '4"'     => [4.0,  114.0],
        '5"'     => [5.0,  140.0],
        '6"'     => [6.0,  165.0],
        '8"'     => [8.0,  216.0],
        '10"'    => [10.0, 267.0],
        '12"'    => [12.0, 318.0]
      }.freeze

      # Working pressure classes (kgf/cm²) of TIS 17.
      PVC_CLASSES = { 'Class 5' => 5.0, 'Class 8.5' => 8.5, 'Class 13.5' => 13.5 }.freeze
      # Hoop-stress wall estimate e = P·D / (2σ + P), σ ≈ 125 kgf/cm² (12.3 MPa)
      # calibrated so the estimate matches published catalogue walls for 4"
      # (≈2.2 / 3.8 / 5.7 mm) within ±0.2 mm. Minimum practical wall 1.5 mm.
      PVC_SIGMA = 125.0
      PVC_MIN_WALL = 1.5

      # PP-R (ISO 15874 / DIN 8077): OD => {rating => wall}
      PPR = {
        20  => { 'PN10' => 1.9,  'PN16' => 2.8,  'PN20' => 3.4 },
        25  => { 'PN10' => 2.3,  'PN16' => 3.5,  'PN20' => 4.2 },
        32  => { 'PN10' => 2.9,  'PN16' => 4.4,  'PN20' => 5.4 },
        40  => { 'PN10' => 3.7,  'PN16' => 5.5,  'PN20' => 6.7 },
        50  => { 'PN10' => 4.6,  'PN16' => 6.9,  'PN20' => 8.4 },
        63  => { 'PN10' => 5.8,  'PN16' => 8.6,  'PN20' => 10.5 },
        75  => { 'PN10' => 6.8,  'PN16' => 10.3, 'PN20' => 12.5 },
        90  => { 'PN10' => 8.2,  'PN16' => 12.3, 'PN20' => 15.0 },
        110 => { 'PN10' => 10.0, 'PN16' => 15.1, 'PN20' => 18.3 }
      }.freeze

      # PE100 (ISO 4427): OD => {rating => wall}
      HDPE = {
        32  => { 'SDR17 PN10' => 2.0,  'SDR11 PN16' => 3.0 },
        40  => { 'SDR17 PN10' => 2.4,  'SDR11 PN16' => 3.7 },
        50  => { 'SDR17 PN10' => 3.0,  'SDR11 PN16' => 4.6 },
        63  => { 'SDR17 PN10' => 3.8,  'SDR11 PN16' => 5.8 },
        75  => { 'SDR17 PN10' => 4.5,  'SDR11 PN16' => 6.8 },
        90  => { 'SDR17 PN10' => 5.4,  'SDR11 PN16' => 8.2 },
        110 => { 'SDR17 PN10' => 6.6,  'SDR11 PN16' => 10.0 },
        125 => { 'SDR17 PN10' => 7.4,  'SDR11 PN16' => 11.4 },
        160 => { 'SDR17 PN10' => 9.5,  'SDR11 PN16' => 14.6 },
        200 => { 'SDR17 PN10' => 11.9, 'SDR11 PN16' => 18.2 },
        250 => { 'SDR17 PN10' => 14.8, 'SDR11 PN16' => 22.7 },
        315 => { 'SDR17 PN10' => 18.7, 'SDR11 PN16' => 28.6 }
      }.freeze

      # ASTM B88 Type L: size => [nps, OD mm, wall mm]
      COPPER_L = {
        '1/2"'   => [0.5,  15.88, 1.02],
        '3/4"'   => [0.75, 22.23, 1.14],
        '1"'     => [1.0,  28.58, 1.27],
        '1-1/4"' => [1.25, 34.93, 1.40],
        '1-1/2"' => [1.5,  41.28, 1.52],
        '2"'     => [2.0,  53.98, 1.78],
        '2-1/2"' => [2.5,  66.68, 2.03],
        '3"'     => [3.0,  79.38, 2.29],
        '4"'     => [4.0, 104.78, 2.79]
      }.freeze

      # Catalogue definitions. `sizes` is an ordered array of hashes:
      #   { size:, nps:, od:, walls: {rating => wall}, tee_c: (optional) }
      # Factors (× OD) are used where no dimensional standard table is given.
      def self.build_defaults
        cats = {}

        steel_sizes = lambda do |walls_table|
          STEEL_NPS.each_with_index.map do |(size, (nps, od, tee_c)), i|
            walls = {}
            walls_table.each { |rating, arr| walls[rating] = arr[i] }
            { size: size, nps: nps, od: od, tee_c: tee_c, walls: walls }
          end
        end

        cats['CS_B36_10'] = {
          name: 'Carbon Steel – ASME B36.10M (A106/A53 Gr.B)',
          name_th: 'ท่อเหล็กดำ (Carbon Steel)',
          material: 'Carbon Steel', joint: 'Butt weld / Grooved',
          hw_c: 120, roughness_mm: 0.045, density: 7850,
          elbow: :b16_9, fitting_od_factor: 1.0, stick_length_m: 6.0,
          style: :butt_weld, default_rating: 'SCH40',
          sizes: steel_sizes.call(CS_WALLS)
        }

        cats['SS_B36_19'] = {
          name: 'Stainless Steel – ASME B36.19M (304/316L)',
          name_th: 'ท่อสแตนเลส (Stainless Steel)',
          material: 'Stainless Steel 304/316L', joint: 'Butt weld (orbital) / Flanged',
          hw_c: 140, roughness_mm: 0.015, density: 7930,
          elbow: :b16_9, fitting_od_factor: 1.0, stick_length_m: 6.0,
          style: :butt_weld, default_rating: '10S',
          sizes: steel_sizes.call(SS_WALLS)
        }

        cats['GSP_BS1387'] = {
          name: 'Galvanised Steel – BS 1387 Medium / TIS 277',
          name_th: 'ท่อเหล็กอาบสังกะสี (GSP) มอก.277',
          material: 'Galvanised Steel', joint: 'Threaded (BSPT) / Grooved',
          hw_c: 120, roughness_mm: 0.15, density: 7850,
          elbow_factor: 1.0, elbow_sr_factor: 0.75, tee_c_factor: 0.9,
          fitting_od_factor: 1.25, stick_length_m: 6.0,
          style: :threaded, default_rating: 'Medium',
          sizes: GSP_MEDIUM.map { |s, (nps, od, w)| { size: s, nps: nps, od: od, walls: { 'Medium' => w } } }
        }

        cats['PVC_TIS17'] = {
          name: 'PVC-U – TIS 17-2532 (มอก.17)',
          name_th: 'ท่อพีวีซี (PVC) มอก.17',
          material: 'PVC-U', joint: 'Solvent cement',
          hw_c: 150, roughness_mm: 0.0015, density: 1400,
          elbow_factor: 1.0, elbow_sr_factor: 0.75, tee_c_factor: 0.8,
          fitting_od_factor: 1.2, stick_length_m: 4.0,
          style: :socket, default_rating: 'Class 13.5', estimated: true,
          sizes: PVC_OD.map do |s, (nps, od)|
            walls = {}
            PVC_CLASSES.each { |rating, p| walls[rating] = pvc_wall(od, p) }
            { size: s, nps: nps, od: od, walls: walls }
          end
        }

        # White PVC-U Schedule 40 (drain / waste / vent): same OD and wall as
        # steel Sch40 (ASTM D1785); fittings are the DWV patterns of the
        # reference library (sanitary tee, wye, long-sweep elbows).
        cats['PVCS40_ASTM'] = {
          name: 'PVC-U Schedule 40 – ASTM D1785 / D2665 (DWV)',
          name_th: 'ท่อพีวีซี Sch40 (สีขาว, ASTM)',
          material: 'PVC-U', joint: 'Solvent cement',
          hw_c: 150, roughness_mm: 0.0015, density: 1400,
          elbow_factor: 1.3, elbow_sr_factor: 1.0, tee_c_factor: 1.2,
          fitting_od_factor: 1.2, stick_length_m: 6.0,
          style: :socket, default_rating: 'SCH40',
          sizes: steel_sizes.call('SCH40' => CS_WALLS['SCH40']).first(9)
        }

        cats['PPR_DIN8077'] = {
          name: 'PP-R – DIN 8077 / ISO 15874',
          name_th: 'ท่อพีพีอาร์ (PP-R)',
          material: 'PP-R', joint: 'Socket heat fusion',
          hw_c: 150, roughness_mm: 0.007, density: 900,
          elbow_factor: 1.0, elbow_sr_factor: 0.75, tee_c_factor: 0.8,
          fitting_od_factor: 1.3, stick_length_m: 4.0,
          style: :socket, default_rating: 'PN20',
          sizes: PPR.map { |od, walls| { size: "#{od} mm", nps: nil, od: od.to_f, walls: walls } }
        }

        cats['HDPE_PE100'] = {
          name: 'HDPE PE100 – ISO 4427',
          name_th: 'ท่อเอชดีพีอี (HDPE PE100)',
          material: 'HDPE PE100', joint: 'Butt fusion / Electrofusion',
          hw_c: 150, roughness_mm: 0.007, density: 955,
          elbow_factor: 1.5, elbow_sr_factor: 1.0, tee_c_factor: 1.0,
          fitting_od_factor: 1.0, stick_length_m: 6.0,
          style: :fusion, default_rating: 'SDR11 PN16',
          sizes: HDPE.map { |od, walls| { size: "#{od} mm", nps: nil, od: od.to_f, walls: walls } }
        }

        cats['CU_B88_L'] = {
          name: 'Copper – ASTM B88 Type L',
          name_th: 'ท่อทองแดง Type L',
          material: 'Copper', joint: 'Brazed / Soldered',
          hw_c: 140, roughness_mm: 0.0015, density: 8940,
          elbow_factor: 1.0, elbow_sr_factor: 0.75, tee_c_factor: 0.8,
          fitting_od_factor: 1.1, stick_length_m: 5.8,
          style: :socket, default_rating: 'Type L',
          sizes: COPPER_L.map { |s, (nps, od, w)| { size: s, nps: nps, od: od, walls: { 'Type L' => w } } }
        }

        cats
      end

      def self.pvc_wall(od, pressure)
        e = pressure * od / (2.0 * PVC_SIGMA + pressure)
        e = PVC_MIN_WALL if e < PVC_MIN_WALL
        (e * 10.0).ceil / 10.0
      end

      @catalogs = build_defaults

      class << self
        def all
          @catalogs
        end

        def keys
          @catalogs.keys
        end

        def get(key)
          @catalogs[key] or raise ArgumentError, "Unknown pipe catalogue: #{key}"
        end

        def sizes(key)
          get(key)[:sizes].map { |s| s[:size] }
        end

        def ratings(key, size = nil)
          cat = get(key)
          if size
            find_size(cat, size)[:walls].keys
          else
            cat[:sizes].flat_map { |s| s[:walls].keys }.uniq
          end
        end

        def find_size(cat, size)
          cat[:sizes].find { |s| s[:size] == size } or
            raise ArgumentError, "Size #{size} not in #{cat[:name]}"
        end

        # Resolve a PipeSpec. Falls back to the catalogue default rating (or
        # the first available one) if the requested rating does not exist for
        # this size – e.g. SDR17 is not made in small HDPE sizes.
        def spec(key, size, rating = nil)
          cat = get(key)
          s = find_size(cat, size)
          rating = cat[:default_rating] if rating.nil? || !s[:walls].key?(rating)
          rating = s[:walls].keys.first unless s[:walls].key?(rating)
          od = s[:od].to_f
          wall = s[:walls][rating].to_f
          lr, sr = elbow_radii(cat, s)
          tee_c = s[:tee_c] ? s[:tee_c].to_f : [od * (cat[:tee_c_factor] || 0.8), 20.0].max
          PipeSpec.new(
            catalog_key: key, catalog_name: cat[:name], material: cat[:material],
            joint: cat[:joint], size: size, rating: rating,
            od: od, wall: wall, nps_in: s[:nps], hw_c: cat[:hw_c],
            roughness_mm: cat[:roughness_mm], density: cat[:density],
            elbow_radius_lr: lr, elbow_radius_sr: sr, tee_c: tee_c,
            fitting_od: od * (cat[:fitting_od_factor] || 1.0),
            stick_length_m: cat[:stick_length_m] || 6.0,
            estimated: cat[:estimated] ? true : false,
            style: cat[:style] || :butt_weld, family: key.split('_').first
          )
        end

        # Elbow centreline radius (mm).
        # * B16.9 steel: LR = 1.5 × NPS (with the tabulated exceptions for
        #   1/2" and 3/4"), SR (B16.28) = 1.0 × NPS, available from NPS 1".
        # * Others: factor × OD, but never tighter than 0.75 OD so the swept
        #   solid cannot self-intersect.
        def elbow_radii(cat, s)
          od = s[:od].to_f
          if cat[:elbow] == :b16_9 && s[:nps]
            nps = s[:nps]
            lr = { 0.5 => 38.0, 0.75 => 29.0, 1.0 => 38.0 }[nps] || 1.5 * nps * INCH
            sr = nps >= 1.0 ? nps * INCH : lr
            [lr, sr]
          else
            lr = od * (cat[:elbow_factor] || 1.0)
            sr = od * (cat[:elbow_sr_factor] || 0.75)
            [[lr, 0.75 * od].max, [sr, 0.75 * od].max]
          end
        end

        # Merge user catalogues from a JSON file (see
        # docs/custom_catalog.example.json). Returns the keys loaded.
        def load_custom(path)
          return [] unless File.exist?(path)

          data = JSON.parse(File.read(path, encoding: 'UTF-8'))
          loaded = []
          data.each do |key, c|
            sizes = (c['sizes'] || []).map do |s|
              { size: s['size'].to_s, nps: s['nps'], od: s['od'].to_f,
                tee_c: s['tee_c'], walls: s['walls'].transform_values(&:to_f) }
            end
            raise ArgumentError, "#{key}: no sizes" if sizes.empty?

            @catalogs[key] = {
              name: c['name'] || key, name_th: c['name_th'] || c['name'] || key,
              material: c['material'] || 'Custom', joint: c['joint'] || '-',
              hw_c: (c['hw_c'] || 130).to_f, roughness_mm: (c['roughness_mm'] || 0.05).to_f,
              density: (c['density'] || 7850).to_f,
              elbow_factor: (c['elbow_factor'] || 1.0).to_f,
              elbow_sr_factor: (c['elbow_sr_factor'] || 0.75).to_f,
              tee_c_factor: (c['tee_c_factor'] || 0.8).to_f,
              fitting_od_factor: (c['fitting_od_factor'] || 1.0).to_f,
              stick_length_m: (c['stick_length_m'] || 6.0).to_f,
              style: (c['style'] || 'butt_weld').to_sym,
              default_rating: c['default_rating'] || sizes.first[:walls].keys.first,
              sizes: sizes
            }
            loaded << key
          end
          loaded
        end

        def reset!
          @catalogs = build_defaults
        end
      end
    end
  end
end
