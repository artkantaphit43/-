# frozen_string_literal: true

require_relative 'finishes'

module ArtK
  module PlantPipe
    # Piping services (systems). Each service carries:
    # * code       – short line-number prefix used on drawings (e.g. CW)
    # * th / en    – display names
    # * fluid      – :water, :hot_water, :steam, :air, :gas, :chemical, :oil,
    #                used to pick fluid properties & sizing criteria
    # * gravity    – true for drainage lines drawn with a fall (slope)
    # * catalog / size / rating – sensible default material for a Thai plant
    # * insulation – default insulation thickness (mm)
    # * vmax       – recommended max velocity (m/s) for sizing (design
    #                guidance, not a code limit – editable in settings)
    # * hf_max     – recommended max friction loss (m per 100 m) for liquids
    # * asme / jis – identification category for the colour schemes
    # * rgb        – distinct display colour (default "Distinct" scheme)
    module Services
      LIST = [
        { code: 'CW',   th: 'น้ำประปา / น้ำเย็น',            en: 'Cold Water',               fluid: :water,
          catalog: 'PVC_TIS17',  size: '1"',     rating: 'Class 13.5', insulation: 0,
          vmax: 2.0, hf_max: 4.0, asme: :water, jis: :water, rgb: [30, 136, 229] },
        { code: 'HW',   th: 'น้ำร้อน',                         en: 'Hot Water Supply',         fluid: :hot_water,
          catalog: 'PPR_DIN8077', size: '32 mm', rating: 'PN20', insulation: 25,
          vmax: 1.5, hf_max: 4.0, asme: :water, jis: :water, rgb: [229, 57, 53] },
        { code: 'HWR',  th: 'น้ำร้อนไหลกลับ',                  en: 'Hot Water Return',         fluid: :hot_water,
          catalog: 'PPR_DIN8077', size: '25 mm', rating: 'PN20', insulation: 25,
          vmax: 1.5, hf_max: 4.0, asme: :water, jis: :water, rgb: [244, 143, 177] },
        { code: 'SAN',  th: 'ท่อน้ำเสีย / โสโครก',            en: 'Soil & Waste (gravity)',   fluid: :water, gravity: true,
          catalog: 'PVC_TIS17',  size: '4"',     rating: 'Class 8.5', insulation: 0,
          vmax: 3.0, hf_max: nil, asme: :water, jis: :water, rgb: [121, 85, 72] },
        { code: 'V',    th: 'ท่ออากาศ (Vent)',                  en: 'Vent',                     fluid: :air, gravity: true,
          catalog: 'PVC_TIS17',  size: '2"',     rating: 'Class 5', insulation: 0,
          vmax: nil, hf_max: nil, asme: :other, jis: :air, rgb: [158, 158, 158] },
        { code: 'SD',   th: 'ท่อระบายน้ำฝน',                   en: 'Storm Drain (gravity)',    fluid: :water, gravity: true,
          catalog: 'PVC_TIS17',  size: '4"',     rating: 'Class 8.5', insulation: 0,
          vmax: 3.0, hf_max: nil, asme: :water, jis: :water, rgb: [0, 172, 193] },
        { code: 'FP',   th: 'ท่อดับเพลิง (Sprinkler/Hydrant)', en: 'Fire Protection',          fluid: :water,
          catalog: 'CS_B36_10',  size: '4"',     rating: 'SCH40', insulation: 0,
          vmax: 4.5, hf_max: nil, asme: :fire, jis: :fire, rgb: [211, 47, 47] },
        { code: 'CHWS', th: 'น้ำเย็นจ่าย (Chiller)',          en: 'Chilled Water Supply',     fluid: :water,
          catalog: 'CS_B36_10',  size: '4"',     rating: 'SCH40', insulation: 50,
          vmax: 2.4, hf_max: 4.0, asme: :water, jis: :water, rgb: [3, 169, 244] },
        { code: 'CHWR', th: 'น้ำเย็นกลับ (Chiller)',          en: 'Chilled Water Return',     fluid: :water,
          catalog: 'CS_B36_10',  size: '4"',     rating: 'SCH40', insulation: 50,
          vmax: 2.4, hf_max: 4.0, asme: :water, jis: :water, rgb: [0, 131, 143] },
        { code: 'CDW',  th: 'น้ำหล่อเย็น (Cooling Tower)',     en: 'Condenser / Cooling Water', fluid: :water,
          catalog: 'CS_B36_10',  size: '6"',     rating: 'SCH40', insulation: 0,
          vmax: 2.4, hf_max: 4.0, asme: :water, jis: :water, rgb: [67, 160, 71] },
        { code: 'PW',   th: 'น้ำใช้ในกระบวนการผลิต',          en: 'Process Water',            fluid: :water,
          catalog: 'HDPE_PE100', size: '63 mm', rating: 'SDR11 PN16', insulation: 0,
          vmax: 2.0, hf_max: 4.0, asme: :water, jis: :water, rgb: [124, 179, 66] },
        { code: 'DI',   th: 'น้ำบริสุทธิ์ (RO/DI)',           en: 'Purified Water (RO/DI)',   fluid: :water,
          catalog: 'SS_B36_19',  size: '1"',     rating: '10S', insulation: 0,
          vmax: 2.0, hf_max: 4.0, asme: :water, jis: :water, rgb: [128, 222, 234] },
        { code: 'STM',  th: 'ไอน้ำ',                           en: 'Steam',                    fluid: :steam,
          catalog: 'CS_B36_10',  size: '2"',     rating: 'SCH40', insulation: 50,
          vmax: 30.0, hf_max: nil, asme: :water, jis: :steam, rgb: [183, 28, 28] },
        { code: 'CON',  th: 'น้ำคอนเดนเสท',                   en: 'Condensate Return',        fluid: :hot_water,
          catalog: 'CS_B36_10',  size: '1-1/2"', rating: 'SCH80', insulation: 25,
          vmax: 1.5, hf_max: 4.0, asme: :water, jis: :water, rgb: [255, 112, 67] },
        { code: 'CA',   th: 'ลมอัด',                           en: 'Compressed Air',           fluid: :air,
          catalog: 'GSP_BS1387', size: '1"',     rating: 'Medium', insulation: 0,
          vmax: 8.0, hf_max: nil, asme: :air, jis: :air, rgb: [25, 118, 210] },
        { code: 'NG',   th: 'ก๊าซเชื้อเพลิง (NG/LPG)',        en: 'Fuel Gas (NG/LPG)',        fluid: :gas,
          catalog: 'CS_B36_10',  size: '1"',     rating: 'SCH40', insulation: 0,
          vmax: 15.0, hf_max: nil, asme: :flammable, jis: :gas, rgb: [251, 192, 45] },
        { code: 'CHM',  th: 'สารเคมี',                         en: 'Chemical',                 fluid: :chemical,
          catalog: 'HDPE_PE100', size: '50 mm', rating: 'SDR11 PN16', insulation: 0,
          vmax: 1.5, hf_max: 4.0, asme: :toxic, jis: :acid, rgb: [245, 124, 0] },
        { code: 'IWW',  th: 'น้ำเสียจากกระบวนการผลิต',        en: 'Industrial Wastewater',    fluid: :water,
          catalog: 'HDPE_PE100', size: '110 mm', rating: 'SDR11 PN16', insulation: 0,
          vmax: 2.0, hf_max: 4.0, asme: :toxic, jis: :water, rgb: [93, 64, 55] },
        { code: 'OIL',  th: 'น้ำมัน',                          en: 'Oil / Fuel Oil',           fluid: :oil,
          catalog: 'CS_B36_10',  size: '1"',     rating: 'SCH40', insulation: 0,
          vmax: 1.5, hf_max: nil, asme: :combustible, jis: :oil, rgb: [109, 76, 65] },
        { code: 'VAC',  th: 'ระบบสุญญากาศ',                   en: 'Vacuum',                   fluid: :air,
          catalog: 'SS_B36_19',  size: '2"',     rating: '10S', insulation: 0,
          vmax: 20.0, hf_max: nil, asme: :other, jis: :air, rgb: [96, 125, 139] }
      ].freeze

      # ASME A13.1 identification (label background) colours.
      ASME_A13_1 = {
        fire:        [200, 16, 46],   # Fire quenching – red
        toxic:       [255, 130, 0],   # Toxic & corrosive – orange
        flammable:   [255, 205, 0],   # Flammable – yellow
        combustible: [120, 78, 40],   # Combustible – brown
        water:       [0, 132, 61],    # Potable, cooling, boiler feed & other water – green
        air:         [0, 84, 166],    # Compressed air – blue
        other:       [128, 128, 128]  # Defined by user – grey
      }.freeze

      # JIS Z 9102 pipe identification colours (common in Japanese-run plants
      # in Thailand).
      JIS_Z9102 = {
        water: [0, 102, 204],     # 青 blue
        steam: [139, 0, 0],       # 暗い赤 dark red
        air:   [245, 245, 245],   # 白 white
        gas:   [255, 236, 139],   # うすい黄 light yellow
        acid:  [150, 120, 170],   # 灰紫 grey-violet (acids & alkalis)
        oil:   [140, 70, 20],     # 茶色 dark yellow-red (oils)
        fire:  [200, 16, 46]      # 赤 red (fire)
      }.freeze

      # Real material colours (default scheme). Keyed by catalogue family –
      # taken from the realistic finish palette (lib/finishes.rb).
      MATERIAL_COLORS = Finishes::PIPE.transform_values { |f| Finishes.rgb(f) }.freeze
      # Services that are painted a code colour whatever the material.
      PAINTED = Finishes::PAINTED.transform_values { |f| Finishes.rgb(f) }.freeze

      SCHEMES = {
        'material' => 'สีตามวัสดุจริง (Material)',
        'distinct' => 'แยกสีตามระบบ (Distinct)',
        'asme'     => 'ASME A13.1',
        'jis'      => 'JIS Z 9102'
      }.freeze

      module_function

      def all
        LIST
      end

      def codes
        LIST.map { |s| s[:code] }
      end

      def get(code)
        LIST.find { |s| s[:code] == code } or raise ArgumentError, "Unknown service: #{code}"
      end

      def color(code, scheme = 'material', family = nil)
        s = get(code)
        case scheme
        when 'material'
          PAINTED[code] || MATERIAL_COLORS[(family || s[:catalog].split('_').first).to_s] || s[:rgb]
        when 'asme' then ASME_A13_1[s[:asme]] || ASME_A13_1[:other]
        when 'jis'  then JIS_Z9102[s[:jis]] || JIS_Z9102[:water]
        else s[:rgb]
        end
      end

      def gravity?(code)
        get(code)[:gravity] ? true : false
      end

      # Minimum fall for gravity drainage (%), after IPC Table 704.1:
      # < 3"  → 1/4" per ft (2.08 %); 3"–6" → 1/8" per ft (1.04 %);
      # ≥ 8"  → 1/16" per ft (0.52 %). Keyed on OD so it works for any
      # catalogue (boundary between 2-1/2" (≤ 76 mm OD) and 3" (≥ 88.9 mm OD) taken at 80 mm; 8" at 200 mm).
      def min_drain_slope_pct(od_mm)
        if od_mm < 80.0 then 2.08
        elsif od_mm < 200.0 then 1.04
        else 0.52
        end
      end
    end
  end
end
