# frozen_string_literal: true

module ArtK
  module PlantPipe
    # Realistic surface finishes (v1.7): one palette for pipes, the copied
    # reference parts and the generated parts, reasoned from what each part
    # is really made of and how it is finished on site – not from the source
    # file's display colours. Only colours/surfaces; geometry is untouched.
    #
    # Each finish: [rgb, metalness, roughness]. Metalness/roughness feed the
    # PBR material of SketchUp 2025+ (metallic sheen); older versions use
    # the plain colour only.
    module Finishes
      # Bump when the palette changes: reference definitions built with an
      # older palette are repainted on next use (RefModels.definition).
      VERSION = 1

      LIST = {
        # pipe materials
        'pvc_blue'      => [[30, 118, 196], 0.0, 0.35],   # Thai PVC-U TIS 17 blue
        'pvc_white'     => [[236, 236, 230], 0.0, 0.40],  # PVC Sch40 DWV white
        'pvc_white_2'   => [[214, 214, 208], 0.0, 0.40],  # printed band / shaded white
        'ppr_green'     => [[58, 128, 70], 0.0, 0.40],    # PP-R green
        'hdpe_black'    => [[36, 37, 40], 0.0, 0.55],     # PE100 black
        'black_steel'   => [[66, 68, 72], 0.55, 0.60],    # A106 / A234 black steel, mill scale
        'stainless'     => [[198, 201, 204], 1.0, 0.28],  # SS304/316 brushed
        'galvanized'    => [[172, 177, 180], 0.85, 0.50], # hot-dip zinc, dull silver
        'copper'        => [[186, 112, 70], 1.0, 0.35],
        'fire_red'      => [[200, 30, 36], 0.0, 0.35],    # fire line paint (red)
        'gas_yellow'    => [[232, 190, 40], 0.0, 0.35],   # gas line paint (yellow)
        # valves & equipment
        'epoxy_blue'    => [[24, 80, 160], 0.0, 0.30],    # cast iron / DI / WCB body, blue epoxy
        'handle_blue'   => [[32, 100, 196], 0.0, 0.35],   # handwheels, levers, vinyl grips
        'epoxy_green'   => [[62, 136, 86], 0.0, 0.30],    # JIS 10K green epoxy
        'brass'         => [[198, 160, 86], 1.0, 0.35],   # brass / bronze body
        'brass_dark'    => [[160, 124, 60], 1.0, 0.45],
        'forged_steel'  => [[150, 154, 158], 0.9, 0.45],  # A105 forged, natural
        'chrome'        => [[214, 216, 220], 1.0, 0.12],  # chrome-plated (taps, stems)
        'aluminium'     => [[194, 197, 200], 0.8, 0.45],  # actuator / gearbox housings
        'zinc_bolt'     => [[168, 172, 176], 0.9, 0.40],  # zinc-plated bolts & nuts
        'pvc_grey'      => [[92, 98, 102], 0.0, 0.45],    # PVC-U valves, RAL 7011 grey
        'plastic_grey'  => [[122, 126, 130], 0.0, 0.50],  # plastic handles
        'pp_black'      => [[40, 40, 42], 0.0, 0.50],     # PP-H / PE valve body
        'rubber_black'  => [[34, 34, 34], 0.0, 0.85],     # gaskets, seats, plugs
        'dial_white'    => [[246, 246, 242], 0.0, 0.30],  # gauge dial
        'red_paint'     => [[196, 32, 36], 0.0, 0.35],    # tap lever, flowmeter float
        # supports & site
        'hdg_steel'     => [[150, 155, 158], 0.8, 0.55],  # hot-dip galvanised structural steel
        'concrete'      => [[184, 182, 174], 0.0, 0.90],
        'weld'          => [[72, 72, 74], 0.7, 0.60],
        'insulation'    => [[225, 225, 215], 0.0, 0.80]
      }.freeze

      # Pipe colour per catalogue family (default "material" scheme).
      PIPE = {
        'PVC' => 'pvc_blue', 'PVCS40' => 'pvc_white', 'PPR' => 'ppr_green', 'HDPE' => 'hdpe_black',
        'CS' => 'black_steel', 'SS' => 'stainless', 'GSP' => 'galvanized', 'CU' => 'copper'
      }.freeze
      # Services painted a code colour whatever the material.
      PAINTED = { 'FP' => 'fire_red', 'NG' => 'gas_yellow' }.freeze

      # Unpainted faces of a reference part, by what the part is made of.
      ROLE = {
        'galvanized' => 'galvanized', 'black_steel' => 'black_steel', 'valve_cast' => 'epoxy_blue',
        'valve_green' => 'epoxy_green', 'bronze' => 'brass', 'pvc_blue' => 'pvc_blue',
        'pvc_white' => 'pvc_white', 'pvc_grey' => 'pvc_grey', 'pp_black' => 'pp_black',
        'steel_ss' => 'stainless', 'chrome' => 'chrome'
      }.freeze
      # Transparent role (rotameter tube) keeps a see-through colour.
      CLEAR = [[214, 228, 236], 0.45].freeze

      # Painted faces of a reference part: source material → finish, or a
      # hash by the part's material (:default for the rest). Source
      # materials not listed (glass, dial print, pointers, the meter dial
      # texture) keep their source colour.
      SOURCE = {
        'piping:Valve Metal' => { 'bronze' => 'brass', 'black_steel' => 'forged_steel', 'steel_ss' => 'stainless',
                                  'galvanized' => 'galvanized', default: 'epoxy_blue' },
        'piping:Valve Blue' => 'handle_blue',
        'pvc:[0097_DeepSkyBlue]' => 'pvc_blue',
        'sch40:[Color_001]' => 'pvc_white',
        'sch40:[Color_002]' => 'pvc_white_2',
        'valves:[Color_003]' => 'aluminium',                                   # JIS actuator housing
        'valves:[Color_002]' => { 'valve_cast' => 'epoxy_blue', default: 'aluminium' }, # JIS wafer body
        'valves:[Color_001]' => { 'valve_cast' => 'epoxy_blue', default: 'aluminium' },
        'valves:[Color_008]' => 'rubber_black',
        'valves:Black' => 'rubber_black',
        'valves:[Color_G04]' => 'epoxy_green',
        'valves:Plastic grey' => { 'pvc_grey' => 'pvc_grey', default: 'plastic_grey' },
        'valves:Plastic red' => 'red_paint',
        'gauge:[Metal Silver]' => 'stainless',
        'gauge:[Color M00]' => 'dial_white',
        'gauge:[Color E05]' => 'rubber_black',                                 # fill plug
        'meter:[Color D06]' => 'brass',
        'meter:[Color D07]' => 'brass_dark',
        'faucet:[0132_LightGray]' => 'chrome',
        'faucet:_5' => 'red_paint'
      }.freeze

      # Roles of the generated parts (valve_models, parts, supports).
      FIXED = {
        valve: 'epoxy_blue', valve_plastic: 'pvc_grey', cast: 'epoxy_blue', forged: 'forged_steel',
        brass: 'brass', chrome: 'chrome', iron: 'handle_blue', grip: 'handle_blue', gauge: 'dial_white',
        handle: 'handle_blue', bolt: 'zinc_bolt', galv: 'galvanized', steel: 'hdg_steel',
        concrete: 'concrete', weld: 'weld', gasket: 'rubber_black'
      }.freeze

      module_function

      def rgb(name)
        LIST.fetch(name)[0]
      end

      # [metalness, roughness]
      def pbr(name)
        LIST.fetch(name)[1, 2]
      end

      def pipe(family)
        PIPE[family.to_s]
      end

      def role(item_material)
        ROLE[item_material.to_s]
      end

      # Finish for a painted face of a reference part, or nil (keep source).
      def source(key, item_material = nil)
        f = SOURCE[key]
        f.is_a?(Hash) ? (f[item_material.to_s] || f[:default]) : f
      end

      # Material name used in the model for a finish.
      def material_name(name)
        "PP_Fin #{name}"
      end
    end
  end
end
