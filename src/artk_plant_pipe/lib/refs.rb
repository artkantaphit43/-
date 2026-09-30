# frozen_string_literal: true

require 'json'
require 'zlib'

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

      # Companion flanges bolted to each end of a flanged / wafer / lug valve.
      FLANGED = %w[flg150 lug150 wafer150 jis10k flgpn pl_flg].freeze

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
          index['materials']
        end

        def available?
          !items.empty?
        end

        def get(key)
          @by_key ||= items.to_h { |i| [i['key'], i] }
          @by_key[key]
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
          fam = valve['family'] == 'pl_flg' || valve['family'] == 'jis10k' ? 'flgpn' : 'flg150'
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
          @mesh_cache[item['key']] ||= decode(item)
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
          size = item['scalable'] ? 'ทุกขนาด' : [item['size'], item['size2']].compact.join(' x ')
          extra = [OPERATORS[item['operator']], { 'lr' => 'รัศมียาว', 'sr' => 'รัศมีสั้น' }.fetch(item['variant'], item['variant'])].compact
          fam = item['scalable'] ? nil : FAMILY_NAMES[item['family']]
          "#{th} #{size} #{fam}#{" (#{extra.join(', ')})" unless extra.empty?} – #{en}".squeeze(' ')
        end

        def reset!
          @index = @by_key = @bin = @mesh_cache = nil
        end
      end
    end
  end
end
