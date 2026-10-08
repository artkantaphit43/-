# frozen_string_literal: true

require 'json'
require 'zlib'
require_relative 'meter_models'

module ArtK
  module PlantPipe
    # Reference models copied 1:1 from the user's reference SketchUp files
    # (see tools/refs/extract.rb). Each item is stored in a canonical frame:
    #
    #   inline (valves, couplings, unions, flanges, reducers):
    #       origin = midway between the two end faces, +X = port 0 → port 1,
    #       +Y = stem / operator side ("up")
    #   elbows: origin = intersection of the two port axes, port 0 faces −X,
    #       port 1 lies in +Y
    #   tees / wyes / crosses: origin = run axis ∩ branch axis, run along X
    #       (port 0 at −X, port 1 at +X), branch toward +Y
    #   caps: origin = the open end face, body along +X
    #
    # Ports: p (mm, canonical frame), d (outward unit vector), ri (bore
    # radius at the end face = pipe OD/2 for socket ends), ro, depth (socket
    # depth, nil for weld / flange faces).
    module Refs
      DIR = File.join(__dir__, '..', 'refs')

      # Which reference family a pipe spec uses for its fittings.
      #   GSP threaded → malleable iron galvanised (THRD)
      #   steel < 2"   → forged socket weld (SW), ≥ 2" → butt weld (BW)
      #   PVC TIS 17   → Thai PVC pressure fittings (thick), drainage above 2"
      #   PVC Sch40    → Sch40 DWV
      def self.fitting_families(spec)
        case spec.catalog_key
        when 'GSP_BS1387' then %w[gi_thrd]
        when 'CS_B36_10', 'SS_B36_19' then spec.od < 60.0 ? %w[cs_sw] : %w[cs_bw]
        when 'PVC_TIS17' then %w[pvc_tis pvc_tis_dwv]
        when 'PVCS40_ASTM' then %w[pvc_s40]
        else []
        end
      end

      # Preferred valve models, per pipe family and valve type (first match
      # with this size wins). Reasoning:
      # * steel lines: flanged Class 150 cast steel valves; butterflies are
      #   JIS 10K wafer with lever up to 8" (what the user's own library
      #   uses), lug + gear above; checks are swing (≤ 1½") or dual-plate
      #   wafer (≥ 2").
      # * GI threaded lines: bronze threaded ball / globe / check / strainer;
      #   larger sizes and butterflies go flanged/wafer as in practice.
      # * PVC lines: PVC-U true-union ball / diaphragm / PRV, PVC butterfly.
      # Entries: [reference type, family, operator/variant or '-'].
      VALVES = {
        steel: {
          'gate' => [%w[gate flg150 wheel]],
          'globe' => [%w[globe flg150 wheel], %w[globe flg150 -]],
          'ball' => [%w[ball cs_sw -], %w[ball flg150 lever], %w[ball flg150 -]],
          'butterfly' => [%w[butterfly jis10k lever], %w[butterfly lug150 gear], %w[butterfly lug150 lever]],
          'check' => [%w[check flg150 -], %w[check wafer150 -]],
          'strainer' => [%w[strainer flg150 -]],
          'flange' => [%w[flange flg150 -]]
        },
        gi: {
          'gate' => [%w[gate flg150 wheel]],
          'globe' => [%w[globe gi_thrd -], %w[globe flg150 wheel]],
          'ball' => [%w[ball gi_thrd -], %w[ball flg150 lever]],
          'butterfly' => [%w[butterfly jis10k lever], %w[butterfly lug150 gear]],
          'check' => [%w[check gi_thrd -], %w[check wafer150 -]],
          'strainer' => [%w[strainer gi_thrd -], %w[strainer flg150 -]],
          'flange' => [%w[flange flg150 -]]
        },
        # PVC: there is no PVC gate/globe valve – isolating and throttling
        # duty is done with a diaphragm valve, which is what the user's
        # library contains.
        plastic: {
          'ball' => [%w[ball pl_union lever]],
          'butterfly' => [%w[butterfly pl_flg lever], %w[butterfly pl_flg gear]],
          'prv' => [%w[prv pl_union -]],
          'gate' => [%w[diaphragm pl_union pph]],
          'globe' => [%w[diaphragm pl_union pph]]
        }
      }.freeze

      TYPE_NAMES = {
        'elbow90' => ['ข้องอ 90°', 'Elbow 90°'], 'elbow45' => ['ข้องอ 45°', 'Elbow 45°'],
        'tee' => ['สามทาง', 'Tee'], 'san_tee' => ['สามทางวาย (TY)', 'Sanitary tee'], 'wye' => ['วาย 45°', 'Wye 45°'],
        'double_wye' => ['วายคู่', 'Double wye'], 'cross' => ['สี่ทาง', 'Cross'], 'san_cross' => ['สี่ทางวาย', 'Sanitary cross'],
        'coupling' => ['ข้อต่อตรง (ต่อตรง/ซ็อกเก็ต)', 'Coupling / socket'], 'reducer' => ['ข้อลด', 'Reducer'],
        'union' => ['ยูเนี่ยน', 'Union'], 'cap' => ['ฝาครอบ', 'Cap'], 'hex_nipple' => ['นิปเปิ้ลหกเหลี่ยม', 'Hex nipple'],
        'nipple' => ['นิปเปิ้ล', 'Pipe nipple'], 'flange' => ['หน้าแปลน', 'Flange'], 'flange_wn' => ['หน้าแปลนคอเชื่อม (WN)', 'Weld-neck flange'],
        'blind' => ['หน้าแปลนปิด', 'Blind flange'], 'hose' => ['ข้อต่อสายยาง', 'Hose adapter'],
        'p_trap' => ['พีแทรป', 'P-trap'], 'u_trap' => ['ยูแทรป', 'U-trap'],
        'gate' => ['เกทวาล์ว', 'Gate valve'], 'globe' => ['โกลบวาล์ว', 'Globe valve'], 'ball' => ['บอลวาล์ว', 'Ball valve'],
        'butterfly' => ['บัตเตอร์ฟลายวาล์ว', 'Butterfly valve'], 'check' => ['เช็ควาล์ว', 'Check valve'],
        'strainer' => ['วายสเตรนเนอร์', 'Y-strainer'], 'steam_trap' => ['สตีมแทรป', 'Steam trap'],
        'prv' => ['วาล์วลดแรงดัน (PRV)', 'Pressure reducing valve'], 'diaphragm' => ['ไดอะแฟรมวาล์ว', 'Diaphragm valve'],
        'flowmeter' => ['โฟลว์มิเตอร์', 'Flowmeter (rotameter)'], 'gauge' => ['เกจวัดแรงดัน', 'Pressure gauge'],
        'water_meter' => ['มิเตอร์น้ำ', 'Water meter'], 'faucet' => ['ก๊อกน้ำ', 'Faucet / bib tap']
      }.freeze

      FAMILY_NAMES = {
        'gi_thrd' => 'GI เกลียว (เหล็กหล่ออาบสังกะสี)', 'cs_sw' => 'เหล็ก Socket weld 3000#', 'cs_bw' => 'เหล็ก Butt weld',
        'flg150' => 'หน้าแปลน Class 150', 'flgpn' => 'หน้าแปลน PN16', 'lug150' => 'Lug Class 150',
        'wafer150' => 'Wafer Class 150', 'jis10k' => 'Wafer JIS 10K', 'pl_flg' => 'PVC หน้าแปลน PN10',
        'pl_union' => 'พลาสติก ยูเนี่ยน', 'pvc_tis' => 'PVC ฟ้า มอก.17 (หนา)', 'pvc_tis_dwv' => 'PVC ฟ้า มอก.17 (บาง/ระบายน้ำ)',
        'pvc_s40' => 'PVC Sch40 ขาว (DWV)', 'instrument' => 'เครื่องวัด',
        'meter' => 'มิเตอร์น้ำ ทองเหลือง', 'tap' => 'ก๊อกน้ำ ชุบโครเมียม'
      }.freeze

      OPERATORS = { 'wheel' => 'พวงมาลัย', 'lever' => 'ก้านโยก', 'gear' => 'เกียร์', 'actuator' => 'หัวขับไฟฟ้า' }.freeze

      # Types whose real model exists only in small sizes; larger sizes use
      # the largest real one, scaled along the pipe to the standard
      # face-to-face and across it to the standard flange diameter.
      SCALABLE = { 'gate' => %w[flg150 wheel] }.freeze

      # Parts made in real standard sizes instead of a scaled copy.
      #   water meter: ISO 4064 multi-jet with threaded union ends, DN15–DN50
      #     – DN => [laying length L mm, body / register width relative to
      #     DN15]. DN65–DN300: flanged Woltman meters (MeterModels).
      #     Only the connection (bosses, union nuts, tails) follows the pipe;
      #     the body and register grow as real meters do.
      #   faucet: bib taps ½"–1" (DN => scale of the ½" model)
      METER_ISO4064 = {
        15 => [165, 1.0], 20 => [190, 1.0], 25 => [260, 1.1], 32 => [260, 1.26], 40 => [300, 1.58], 50 => [300, 1.79]
      }.freeze
      FAUCET_SIZES = { 15 => 1.0, 20 => 1.15, 25 => 1.3 }.freeze
      SIZED_TEXT = { 'water_meter' => '½"–12" (DN15–300)', 'faucet' => '½"–1"' }.freeze
      METER_SPLIT = 44.0 # mm: body / register inside |x| ≤ this, connection outside

      NPS_DN = {
        0.125 => 6, 0.25 => 8, 0.375 => 10, 0.5 => 15, 0.75 => 20, 1.0 => 25, 1.25 => 32, 1.5 => 40, 2.0 => 50,
        2.5 => 65, 3.0 => 80, 3.5 => 90, 4.0 => 100, 5.0 => 125, 6.0 => 150, 8.0 => 200, 10.0 => 250, 12.0 => 300,
        14.0 => 350, 16.0 => 400, 18.0 => 450, 20.0 => 500, 24.0 => 600
      }.freeze
      # metric plastic pipe OD => DN (ISO 4065 / DIN 8074)
      OD_DN = {
        16 => 10, 20 => 15, 25 => 20, 32 => 25, 40 => 32, 50 => 40, 63 => 50, 75 => 65, 90 => 80, 110 => 100,
        125 => 100, 140 => 125, 160 => 150, 200 => 200, 250 => 250, 315 => 300, 355 => 350, 400 => 400,
        450 => 450, 500 => 500, 630 => 600
      }.freeze

      # Companion flanges bolted to each end of a flanged / wafer / lug valve.
      FLANGED = %w[flg150 lug150 wafer150 jis10k flgpn pl_flg woltman].freeze

      class << self
        def index
          @index ||= begin
            path = File.join(DIR, 'refs.json')
            File.exist?(path) ? JSON.parse(File.read(path, encoding: 'UTF-8')) : { 'items' => [], 'materials' => {} }
          end
        end

        def items
          index['items']
        end

        def materials
          @materials ||= index['materials'].merge(MeterModels::MATERIALS)
        end

        def available?
          !items.empty?
        end

        # Item by key; a standard-size key ("…@DN25-33.4") gives its base part.
        def get(key)
          @by_key ||= items.to_h { |i| [i['key'], i] }
          @by_key[key] || @by_key[key.to_s.sub(/@DN[\d.-]+\z/, '')]
        end

        # ---------------- standard sizes ----------------

        def sized_type?(item)
          SIZED_TEXT.key?(item['type'])
        end

        # Nominal diameter of a pipe spec (DN).
        def dn_for(spec)
          if spec.nps_in
            NPS_DN.min_by { |n, _| (n - spec.nps_in.to_f).abs }[1]
          else
            OD_DN.min_by { |od, _| (od - spec.od.to_f).abs }[1]
          end
        end

        # The part in the standard size for +spec+ (an item hash with its own
        # key, ports and bounding box), or nil when no such size is made.
        def sized_item(item, spec)
          dn = dn_for(spec)
          return woltman_item(item, dn, spec) if item['type'] == 'water_meter' && MeterModels::WOLTMAN.key?(dn)

          table = item['type'] == 'water_meter' ? METER_ISO4064 : FAUCET_SIZES
          return nil unless table.key?(dn)

          key = "#{item['key']}@DN#{dn}-#{spec.od.to_f.round(1)}"
          @sized ||= {}
          @sized[key] ||= begin
            f = sizing(item, dn, spec.od)
            ports = item['ports'].map do |pt|
              pt.merge('p' => f.call(pt['p']), 'ri' => pt['ri'] * f.radial, 'ro' => pt['ro'] * f.radial,
                       'depth' => pt['depth'] && pt['depth'] * f.radial)
            end
            box = mesh(item)[:verts].map { |v| f.call(v) }
            item.merge('key' => key, 'sized_from' => item['key'], 'size' => spec.size,
                       'dn' => dn, 'scalable' => false, 'ports' => ports, 'pipe_od' => spec.od,
                       'bbox' => [box.transpose.map(&:min), box.transpose.map(&:max)], 'sizing' => f)
          end
        end

        # Flanged Woltman meter for DN65–DN300 (built from the standard
        # dimensions, see MeterModels).
        def woltman_item(item, dn, spec)
          key = "gen:woltman@DN#{dn}-#{spec.od.to_f.round(1)}"
          @sized ||= {}
          @sized[key] ||= begin
            len = MeterModels.length(dn)
            ro = MeterModels.flange_od(dn) / 2.0
            ports = [-1.0, 1.0].map do |sg|
              { 'p' => [sg * len / 2.0, 0.0, 0.0], 'd' => [sg, 0.0, 0.0], 'ri' => spec.od / 2.0, 'ro' => ro }
            end
            mate = flange_bolting(companion_flange(spec, 'family' => 'woltman'))
            m = MeterModels.woltman(dn, spec.od, mate)
            (@mesh_cache ||= {})[key] = m
            box = m[:verts]
            { 'key' => key, 'mate' => mate, 'sized_from' => item['key'], 'generated' => 'woltman', 'type' => 'water_meter',
              'family' => 'woltman', 'size' => spec.size, 'dn' => dn, 'scalable' => false, 'material' => 'valve_cast',
              'src' => 'generated', 'src_name' => 'Plant Piping (ISO 4064 / EN 1092-2)',
              'standard' => "Woltman water meter DN#{dn}, flanged PN16 (EN 1092-2), L = #{len.round} mm (ISO 4064)",
              'ports' => ports, 'pipe_od' => spec.od,
              'bbox' => [box.transpose.map(&:min), box.transpose.map(&:max)] }
          end
        end

        # Revision of an item's geometry (stored on its definition).
        # Library items re-extracted with corrected ports carry 'rev'.
        def geometry_rev(item)
          item['generated'] ? MeterModels::REV : (item['rev'] || 1)
        end

        # Bolt holes of a flange model: { 'pcd', 'angles' (about +X, from
        # +Y toward +Z), 'hole' (dia), 'thick' } or nil.
        def flange_bolting(fl)
          return nil unless fl

          v = mesh(fl)[:verts]
          bore = fl['ports'].map { |q| q['ri'].to_f }.max
          fx = fl['ports'][1]['p'][0]
          holes = mesh(fl)[:faces].flat_map { |f| f[:loops][1..] }.filter_map do |lp|
            pts = lp.map { |i| v[i] }
            next unless pts.all? { |q| (q[0] - fx).abs < 0.5 }

            c = pts.transpose.map { |a| a.sum / a.size }
            rc = Math.hypot(c[1], c[2])
            next if rc < bore + 1.0

            [c, pts.map { |q| Math.hypot(q[1] - c[1], q[2] - c[2]) }.max]
          end
          return nil if holes.size < 4

          { 'pcd' => 2.0 * holes.sum { |c, _| Math.hypot(c[1], c[2]) } / holes.size,
            'angles' => holes.map { |c, _| Math.atan2(c[2], c[1]) }.sort,
            'hole' => 2.0 * holes.sum { |_, r| r } / holes.size,
            'thick' => (fl['ports'][1]['p'][0] - fl['ports'][0]['p'][0]).abs }
        end

        Sizing = Struct.new(:fn, :radial) do
          def call(p)
            fn.call(p)
          end
        end

        # Point map from the modelled size to DN +dn+ on a pipe of +od+.
        def sizing(item, dn, od)
          kp = od.to_f / item['pipe_od'].to_f
          if item['type'] == 'water_meter'
            len, kh = METER_ISO4064[dn]
            l15 = METER_ISO4064[15][0]
            half0 = item['ports'].map { |pt| pt['p'][0].abs }.max
            half = half0 * len / l15.to_f
            xc = METER_SPLIT
            ka = (half - xc * kh) / (half0 - xc)
            fn = lambda do |(x, y, z)|
              if x.abs <= xc
                [x * kh, y * kh, z * kh]
              else
                s = x.negative? ? -1.0 : 1.0
                [s * (xc * kh + (x.abs - xc) * ka), y * kp, z * kp]
              end
            end
            Sizing.new(fn, kp)
          else
            k = FAUCET_SIZES[dn]
            Sizing.new(->(p) { p.map { |c| c * k } }, k)
          end
        end

        # First item matching all given attributes (string keys) with ports.
        def find(**q)
          items.find do |i|
            !i['ports'].empty? && q.all? { |k, v| v.nil? || i[k.to_s] == v }
          end
        end

        def valve_group(spec)
          return :plastic if %w[PVC PVCS40 PPR HDPE].include?(spec.family)
          return :gi if spec.catalog_key == 'GSP_BS1387'

          :steel
        end

        # Reference valve for a pipe spec, or nil. Models from the valve
        # database are preferred over the piping file's where both exist;
        # socket-weld valves only on steel below 2".
        def valve_for(type, spec)
          (VALVES.dig(valve_group(spec), type) || []).each do |rtype, fam, v|
            next if fam == 'cs_sw' && spec.od >= 60.0

            it = items.select do |i|
              i['type'] == rtype && i['family'] == fam && i['size'] == spec.size && !i['ports'].empty? &&
                (v == '-' || [i['operator'], i['variant']].include?(v))
            end.min_by { |i| i['src'] == 'valves' ? 0 : 1 }
            return it if it
          end
          nil
        end

        # [item, source size] or nil.
        def scalable_valve(type, spec)
          fam, op = SCALABLE[type]
          return nil unless fam && valve_group(spec) != :plastic && spec.nps_in

          items.select do |i|
            i['type'] == type && i['family'] == fam && i['operator'] == op && !i['ports'].empty? && i['nps']
          end.min_by { |i| (i['nps'] - spec.nps_in).abs }
        end

        def companion_flange(spec, valve)
          fam = %w[pl_flg jis10k woltman].include?(valve['family']) ? 'flgpn' : 'flg150'
          find(type: 'flange', family: fam, size: spec.size) || find(type: 'flange', family: 'flg150', size: spec.size)
        end

        # Fitting for a pipe spec: type elbow90 / elbow45 / tee / coupling /
        # cap / union; variant 'lr' / 'sr' for elbows.
        def fitting_for(type, spec, variant: nil)
          fams = fitting_families(spec)
          fams.each do |fam|
            cands = items.select do |i|
              i['family'] == fam && i['type'] == type && i['size'] == spec.size && i['size2'].nil? &&
                !i['ports'].empty?
            end
            next if cands.empty?

            return cands.find { |i| i['variant'] == variant } || cands.first
          end
          nil
        end

        # Take-out of an elbow / tee: distance from the origin to a port
        # face along its axis.
        def takeout(item, port = 0)
          p = item['ports'][port]['p']
          Math.sqrt(p.sum { |v| v * v })
        end

        # Decoded geometry: { verts: [[x,y,z] mm], faces: [{ mat:, loops:
        # [[vertex index…]], soft: [[bool…]] }] }
        def mesh(item)
          @mesh_cache ||= {}
          @mesh_cache[item['key']] ||= if item['generated']
                                         MeterModels.woltman(item['dn'], item['pipe_od'], item['mate'])
                                       elsif item['sized_from']
                                         sized_mesh(mesh(get(item['sized_from'])), item['sizing'])
                                       else
                                         decode(item)
                                       end
        end

        def sized_mesh(m, f)
          faces = m[:faces].map do |fc|
            fc[:pins] ? fc.merge(pins: fc[:pins].map { |pt, uv| [f.call(pt), uv] }) : fc
          end
          { verts: m[:verts].map { |v| f.call(v) }, faces: faces }
        end

        def decode(item)
          off, n = item['bin']
          @bin ||= File.binread(File.join(DIR, 'refs.bin'))
          raw = Zlib::Inflate.inflate(@bin.byteslice(off, n))
          nv, nf, nm = raw.unpack('VVv')
          p = 10
          mats = Array.new(nm) do
            l = raw.getbyte(p)
            s = raw.byteslice(p + 1, l).force_encoding('UTF-8')
            p += 1 + l
            s
          end
          coords = raw.unpack("@#{p}l<#{nv * 3}")
          p += nv * 12
          verts = coords.each_slice(3).map { |c| c.map { |v| v / 100.0 } }
          faces = Array.new(nf) do
            mi, nl = raw.unpack("@#{p}vv")
            p += 4
            pins = nil
            if nl & 0x8000 != 0
              nl &= 0x7fff
              pins = Array.new(3) do
                pt = raw.unpack("@#{p}l<3").map { |v| v / 100.0 }
                uv = raw.unpack("@#{p + 12}e2")
                p += 20
                [pt, uv]
              end
            end
            loops = []
            soft = []
            nl.times do
              k = raw.unpack1("@#{p}v")
              idx = raw.unpack("@#{p + 2}V#{k}")
              p += 2 + 4 * k
              loops << idx.map { |i| i & 0x7fffffff }
              soft << idx.map { |i| i & 0x80000000 != 0 }
            end
            { mat: mi == 0xFFFF ? nil : mats[mi], loops: loops, soft: soft, pins: pins }
          end
          { verts: verts, faces: faces }
        end

        # Image file of a textured source material (refs/textures), or nil.
        def texture_path(mat_key)
          f = materials.dig(mat_key, 4)
          f && File.join(DIR, 'textures', f)
        end

        # How a part goes onto a pipe:
        #   :inline – two opposite ends on one axis (valves, unions, meters…)
        #   :top    – bottom connection into the top of a pipe (gauges)
        #   :end    – first port onto an open pipe end (elbows, tees, caps,
        #             flanges, faucets…)
        #   nil     – placed freely
        def mount(item)
          ps = item['ports']
          return nil if ps.empty?
          return :top if item['type'] == 'gauge'
          return :inline if ps.size == 2 && ps[0]['d'].zip(ps[1]['d']).sum { |a, b| a * b } < -0.99

          :end
        end

        # The same part in the pipe's size (same family, type and operator /
        # variant), or nil.
        def variant_for(item, spec)
          return item if item['size'] == spec.size

          items.select do |i|
            i['type'] == item['type'] && i['family'] == item['family'] && i['operator'] == item['operator'] &&
              i['variant'] == item['variant'] && i['size'] == spec.size && i['size2'].nil? && !i['ports'].empty?
          end.min_by { |i| i['src'] == item['src'] ? 0 : 1 }
        end

        # Uniform scale that fits +item+ to a pipe of +od+ mm (1.0 when the
        # part was modelled for that pipe).
        def scale_for(item, od)
          base = item['pipe_od'].to_f
          return 1.0 unless base.positive? && od.to_f.positive?

          k = od.to_f / base
          (k - 1.0).abs < 0.03 ? 1.0 : k
        end

        # Placement frame (Mesh.frame-style hash, mm) that puts port +i+ of
        # +item+ (scaled by k) at point +m+, facing −u – i.e. looking into a
        # pipe whose end points along u – with canonical +Y toward +y_hint.
        # Ports of end-mounted parts face −X in the canonical frame, so +X
        # maps onto u.
        def port_frame(item, i, m, u, y_hint, k = 1.0)
          x = Vec.unit(u)
          y = Vec.sub(y_hint, Vec.scale(x, Vec.dot(y_hint, x)))
          y = Vec.perpendicular(x) if Vec.length(y) < 1e-6
          y = Vec.unit(y)
          z = Vec.cross(x, y)
          p = item['ports'][i]['p'].map { |c| c * k }
          off = Vec.add(Vec.add(Vec.scale(x, p[0]), Vec.scale(y, p[1])), Vec.scale(z, p[2]))
          { o: Vec.sub(m, off), x: x, y: y, z: z }
        end

        # Where the port face sits for a pipe ending at +e+ (pointing along
        # u): a socket swallows the pipe, so its mouth is one socket depth
        # back; weld, thread and flange faces meet the pipe end itself.
        def mouth_point(item, i, e, u, k = 1.0)
          depth = item['ports'][i]['depth'].to_f * k
          Vec.sub(e, Vec.scale(Vec.unit(u), depth))
        end

        # File name (without .jpg) of the item's preview in refs/thumbs.
        def thumb_name(item)
          item['key'].gsub(/[^A-Za-z0-9]+/, '_')
        end

        def display_name(item)
          th, en = TYPE_NAMES.fetch(item['type'], [item['type'], item['type']])
          size = if item['sized_from'] then item['size']
                 elsif sized_type?(item) then SIZED_TEXT[item['type']]
                 elsif item['scalable'] then 'ทุกขนาด'
                 else [item['size'], item['size2']].compact.join(' x ')
                 end
          extra = [OPERATORS[item['operator']], { 'lr' => 'รัศมียาว', 'sr' => 'รัศมีสั้น' }.fetch(item['variant'], item['variant'])].compact
          fam = item['scalable'] || item['sized_from'] ? nil : FAMILY_NAMES[item['family']]
          "#{th} #{size} #{fam}#{" (#{extra.join(', ')})" unless extra.empty?} – #{en}".squeeze(' ')
        end

        def reset!
          @index = @by_key = @bin = @mesh_cache = @sized = @materials = nil
        end
      end
    end
  end
end
