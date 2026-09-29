# frozen_string_literal: true

# Builds the reference-model pack shipped with the extension from the
# user's reference .skp files:
#
#   ruby tools/refs/extract.rb <out_dir> piping.skp pvc.skp sch40.skp valves.skp
#
# For every item placed in those files it
#   * classifies it (type, joint family, nominal size, material) from its
#     name – or, for anonymous library parts, from its row/column in the
#     valve database and the names of its sub-components,
#   * finds its connection ports from the geometry (annular end faces at the
#     extremes of the part: socket mouths, weld bevels, flange raised faces),
#   * moves it into a canonical frame (see Refs in the extension),
#   * stores the exact faces (with holes, soft edges, source materials).
#
# Output: refs.json (index) + refs.bin (zlib blocks, one per item).

require 'json'
require 'zlib'
require_relative 'skp_reader'

module ArtK
  module PlantPipe
    module RefExtract
      module_function

      FRAC = { '½' => '1/2', '¾' => '3/4', '¼' => '1/4' }.freeze
      DEC = {
        0.375 => '3/8"', 0.5 => '1/2"', 0.75 => '3/4"', 1.0 => '1"', 1.25 => '1-1/4"', 1.5 => '1-1/2"',
        2.0 => '2"', 2.5 => '2-1/2"', 3.0 => '3"', 3.5 => '3-1/2"', 4.0 => '4"', 5.0 => '5"', 6.0 => '6"',
        8.0 => '8"', 10.0 => '10"', 12.0 => '12"', 14.0 => '14"', 16.0 => '16"', 18.0 => '18"',
        20.0 => '20"', 24.0 => '24"'
      }.freeze
      DN = { 40 => 1.5, 50 => 2.0, 65 => 2.5, 80 => 3.0, 100 => 4.0, 125 => 5.0, 150 => 6.0,
             200 => 8.0, 250 => 10.0, 300 => 12.0 }.freeze
      D_MM = { 16 => 0.375, 20 => 0.5, 25 => 0.75, 32 => 1.0, 40 => 1.25, 50 => 1.5, 63 => 2.0, 75 => 2.5 }.freeze

      # "1½" → 1-1/2", "¾" → 3/4", "10" → 10"
      def size_from_glyph(s)
        s = s.strip
        whole = s[/\A\d+/]
        frac = FRAC.find { |g, _| s.include?(g) }&.last
        return "#{whole}\"" unless frac
        return "#{frac}\"" unless whole

        "#{whole}-#{frac}\""
      end

      def dec(x)
        DEC.fetch(x.to_f) { raise "no size for #{x}" }
      end

      # ---------------------------------------------------------------
      # Classification. Each rule returns a hash or nil (= not an item).
      # ---------------------------------------------------------------

      GI_TYPES = {
        'Elbow' => 'elbow90', 'Tee' => 'tee', 'Coupling' => 'coupling', 'Union' => 'union', 'Cap' => 'cap',
        'CAP' => 'cap', 'Hex Nipple' => 'hex_nipple', 'Nipple Pipe' => 'nipple', 'Flange' => 'flange',
        'Flange Blind' => 'blind', 'Ball Valve' => 'ball', 'Globe Valve' => 'globe', 'Check Valve' => 'check',
        'Strainer' => 'strainer', 'Steam Trap' => 'steam_trap', 'Hose Adapter' => 'hose', 'Hose Adpater' => 'hose'
      }.freeze

      # Piping file: "<Type> - <size> - <end>"
      def classify_piping(name, _doc, _inst)
        m = name.match(/\A(.+?) - ([\d½¾¼]+) - (.+?)(?:#\d+)?\z/) || name.match(/\A(Hex Nipple|Nipple Pipe) - ([\d½¾¼]+)\z/)
        return nil unless m

        type = GI_TYPES[m[1]] or return nil
        size = size_from_glyph(m[2])
        ends = m[3].to_s
        fam, mat, std =
          case ends
          when /THRD/ then ['gi_thrd', 'galvanized', 'Malleable iron, hot-dip galvanised, BSPT (EN 10242 / ISO 49)']
          when /SW/ then ['cs_sw', 'black_steel', 'Forged carbon steel A105, socket weld Class 3000 (ASME B16.11)']
          when /BW/ then ['cs_bw', 'black_steel', 'Carbon steel A234 WPB, butt weld (ASME B16.9)']
          when /SO,150#|\A150#/ then ['flg150', 'black_steel', 'Forged A105, Class 150 RF (ASME B16.5)']
          when /SO,PN|\APN\z/ then ['flgpn', 'black_steel', 'Steel flange PN16 (EN 1092-1)']
          when /Flanged 150/ then ['flg150', 'valve_cast', 'Cast steel WCB / ductile iron, flanged Class 150']
          when /Wafer/ then ['wafer150', 'valve_cast', 'Dual-plate wafer check, Class 150']
          when /PN16/ then ['flgpn', 'valve_cast', 'Cast iron / cast steel, flanged PN16']
          when /Welding/ then ['cs_bw', 'black_steel', 'Carbon steel, weld end']
          else return nil
          end
        fam = 'gi_thrd' if %w[hex_nipple nipple].include?(type)
        if fam == 'gi_thrd' && %w[ball globe check strainer steam_trap].include?(type)
          mat = 'bronze'
          std = 'Bronze / brass body, BSPT female ends (PN16–PN20)'
        end
        { type: type, family: fam, size: size, material: mat, standard: std, variant: ends.include?('LR') ? 'lr' : nil }
      end

      # Thai PVC file (TIS 17 / มอก.17, solvent cement, blue).
      def pvc_size(s)
        if (m = s.match(/(\d+) (\d)-(\d) inch/)) then "#{m[1]}-#{m[2]}/#{m[3]}\""
        elsif (m = s.match(/(\d)-(\d) inch/)) then "#{m[1]}/#{m[2]}\""
        elsif (m = s.match(/(\d+) inch/)) then "#{m[1]}\""
        end
      end

      def classify_pvc(name, _doc, _inst)
        thick = name.include?('thick')
        pressure = ['pvc_tis', 'PVC-U TIS 17 (มอก.17), pressure pattern (หนา / class 13.5 fittings), solvent cement']
        drain = ['pvc_tis_dwv', 'PVC-U TIS 17 (มอก.17) drainage pattern (บาง), solvent cement']
        fam, std = thick ? pressure : drain
        base = { family: fam, material: 'pvc_blue', standard: std }
        case name
        when /\AElbows 90 (.+?)(Long|Short|thick)/
          v = { 'Long' => 'lr', 'Short' => 'sr', 'thick' => 'sr' }[$2]
          base.merge(type: 'elbow90', size: pvc_size($1 + ' inch'), variant: v)
        when /\AElbows 45 (.+?)inch/ then base.merge(type: 'elbow45', size: pvc_size($1 + 'inch'))
        when /\ASocket (.+)/ then base.merge(type: 'coupling', size: pvc_size($1))
        when /\AREDUCING SOCKET (.+?inch) -? ?(.+inch)/
          base.merge(type: 'reducer', size: pvc_size($1), size2: pvc_size($2))
        when /\AREDUCING TEE (\d+) inch x (\d+) inch/
          base.merge(type: 'tee', size: "#{$1}\"", size2: "#{$2}\"")
        when /\ATee-90 (.+)/ then base.merge(type: 'tee', size: pvc_size($1))
        when /\ATee-TY 90 (.+)/ then base.merge(type: 'san_tee', size: pvc_size($1), family: 'pvc_tis_dwv', standard: drain[1])
        when /\ATee-Y 45 (.+)/ then base.merge(type: 'wye', size: pvc_size($1), family: 'pvc_tis_dwv', standard: drain[1])
        when /\AP-TRAP (.+)/ then base.merge(type: 'p_trap', size: pvc_size($1), family: 'pvc_tis_dwv', standard: drain[1])
        when /\AU-TRAP (.+)/ then base.merge(type: 'u_trap', size: pvc_size($1), family: 'pvc_tis_dwv', standard: drain[1])
        end
      end

      # Schedule 40 PVC DWV file (ASTM D2665 patterns, white).
      S40 = { 'L_90' => 'elbow90', 'L_45' => 'elbow45', 'S_90' => 'san_tee', 'SX_90' => 'san_cross',
              'T_90' => 'tee', 'X_90' => 'cross', 'Y_45' => 'wye', 'YY_45' => 'double_wye', 'Socket' => 'coupling' }.freeze

      def classify_s40(name, _doc, _inst)
        base = { family: 'pvc_s40', material: 'pvc_white',
                 standard: 'PVC-U Schedule 40 DWV (ASTM D2665 / D2466), solvent cement' }
        if (m = name.match(/\A([\d.]+)(?:R([\d.]+))?_(\w+?)(?:sch)?-40\z/))
          type = S40[m[3]] or return nil
          h = base.merge(type: type, size: dec(m[1]))
          h[:size2] = dec(m[2]) if m[2]
          h[:variant] = 'lr' if type == 'elbow90'
          h
        elsif (m = name.match(/\A([\d.]+)R([\d.]+)-sch40\z/))
          base.merge(type: 'reducer', size: dec(m[1]), size2: dec(m[2]))
        end
      end

      # Valve database: anonymous parts laid out in rows (type) × columns
      # (size); named parts identified by name / sub-component names.
      COLS = [[11.8, 0.5], [23.6, 0.75], [35.4, 1.0], [47.2, 1.25], [59.1, 1.5], [82.7, 2.0], [106.3, 2.5],
              [129.9, 3.0], [141.7, 3.5], [153.5, 4.0], [177.2, 5.0], [200.8, 6.0], [224.4, 8.0], [259.8, 10.0],
              [295.3, 12.0], [330.7, 14.0], [366.1, 16.0], [401.6, 18.0], [448.8, 20.0], [496.1, 24.0]].freeze
      ROWS = {
        11.8 => ['gate', 'flg150', 'valve_cast', 'Cast steel gate valve, flanged Class 150 RF (ASME B16.34 / B16.10)', 'wheel'],
        47.2 => ['globe', 'flg150', 'valve_cast', 'Cast steel globe valve, flanged Class 150 RF (ASME B16.34)', 'wheel'],
        82.7 => ['ball', 'flg150', 'valve_cast', 'Cast steel ball valve, flanged Class 150 RF (ASME B16.34)', 'lever'],
        118.1 => ['butterfly', 'lug150', 'valve_cast', 'Lug butterfly valve, ductile iron, Class 150 (API 609)', 'lever'],
        153.5 => ['butterfly', 'lug150', 'valve_cast', 'Lug butterfly valve, ductile iron, Class 150, gear operator (API 609)', 'gear'],
        189.0 => ['check', 'flg150', 'valve_cast', 'Swing check valve, cast steel, flanged Class 150', nil],
        224.4 => ['check', 'wafer150', 'valve_cast', 'Dual-plate wafer check valve, Class 150 (API 594)', nil],
        259.8 => ['flange_wn', 'flg150', 'black_steel', 'Weld-neck flange A105, Class 150 RF (ASME B16.5)', nil]
      }.freeze

      def classify_valves(name, doc, inst)
        x = inst[:tr][9] / 25.4
        y = inst[:tr][10] / 25.4
        subs = doc.descendant_names(inst[:def]).join(' ')
        case name
        when /JIS10K/
          dn = name[/(\d+) DN/, 1].to_i
          return { type: 'butterfly', family: 'jis10k', size: dec(DN.fetch(dn)), dn: dn, operator: 'lever',
                   material: 'valve_green',
                   standard: 'Wafer butterfly valve JIS 10K, ductile iron body (FCD) epoxy coated, EPDM seat, lever' }
        when /Electrically Operated Valve/
          dn = name[/(\d+) DN/, 1].to_i
          return { type: 'butterfly', family: 'jis10k', size: dec(DN.fetch(dn)), dn: dn, operator: 'actuator',
                   material: 'valve_cast',
                   standard: 'Wafer butterfly valve with electric actuator (on/off), short neck' }
        when /\A(Gate|Globe|Ball) Valve, flanged NPS/, /\A[A-Za-z0-9+\/=]{20,}\z/
          row = ROWS.keys.min_by { |r| (r - y).abs }
          if (row - y).abs < 4 && y < 280
            col = COLS.min_by { |c, _| (c - x).abs }
            return nil if (col[0] - x).abs > 4

            type, fam, mat, std, op = ROWS[row]
            h = { type: type, family: fam, size: dec(col[1]), material: mat, standard: std }
            h[:operator] = op if op
            return h
          end
        end
        d = subs[/\^d(\d+)mm/, 1]&.to_i || subs[/d(\d+)(?:-d\d+)*_/, 1]&.to_i
        case subs
        when /VBU\^.*?DN(\d+)/
          dn = Regexp.last_match(1).to_i
          op = subs.include?('Gear') ? 'gear' : 'lever'
          { type: 'butterfly', family: 'pl_flg', size: dec(DN.fetch(dn)), dn: dn, operator: op, material: 'pvc_grey',
            standard: "PVC-U butterfly valve PN10, flanged EN 1092-1, #{op == 'gear' ? 'gear operator' : 'lever'}" }
        when /PRV\^Body/
          { type: 'prv', family: 'pl_union', size: dec(D_MM.fetch(subs[/UGf\^d(\d+)mm/, 1].to_i)), material: 'pvc_grey',
            standard: 'PVC-U pressure reducing valve with gauge, true-union socket ends' }
        when /VM\^Body/
          pe = subs.include?('PiPP')
          { type: 'diaphragm', family: 'pl_union', size: dec(D_MM.fetch(subs[/UGf\^d(\d+)mm/, 1].to_i)),
            material: 'pp_black', variant: pe ? 'pe' : 'pph',
            standard: "Diaphragm valve, #{pe ? 'PE' : 'PP-H'} body, true-union socket ends" }
        when /Handle\^ButterflyValve/
          { type: 'ball', family: 'pl_union', size: nil, material: 'pp_black', operator: 'lever',
            standard: 'True-union ball valve (plastic), socket ends' }
        when /TN\^U(?:G|Tr)f\^d(\d+)mm/
          { type: 'flowmeter', family: 'pl_union', size: dec(D_MM.fetch(Regexp.last_match(1).to_i)),
            material: 'pvc_clear', standard: 'Variable-area flowmeter (rotameter), PVC-U, true-union ends' }
        when /\AiP/
          { type: 'gauge', family: 'instrument', size: nil, material: 'steel_ss',
            standard: 'Pressure gauge, stainless case' }
        end.tap { |h| h&.delete(:size) if h && h[:size].nil? && false }
      rescue KeyError
        nil
      end

      SOURCES = {
        'piping' => { label: 'Steel / GI piping components', rule: :classify_piping },
        'pvc' => { label: 'PVC fittings (TIS 17)', rule: :classify_pvc },
        'sch40' => { label: 'PVC Sch40 DWV fittings', rule: :classify_s40 },
        'valves' => { label: 'Valve database', rule: :classify_valves }
      }.freeze

      # ---------------------------------------------------------------
      # Geometry helpers
      # ---------------------------------------------------------------

      def sub(a, b)
        [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
      end

      def add(a, b)
        [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
      end

      def mul(a, k)
        [a[0] * k, a[1] * k, a[2] * k]
      end

      def dot(a, b)
        a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
      end

      def cross(a, b)
        [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
      end

      def len(a)
        Math.sqrt(dot(a, a))
      end

      def unit(a)
        l = len(a)
        l < 1e-12 ? [0.0, 0.0, 0.0] : mul(a, 1.0 / l)
      end

      def newell(pts)
        n = [0.0, 0.0, 0.0]
        pts.each_with_index do |a, i|
          b = pts[(i + 1) % pts.size]
          n[0] += (a[1] - b[1]) * (a[2] + b[2])
          n[1] += (a[2] - b[2]) * (a[0] + b[0])
          n[2] += (a[0] - b[0]) * (a[1] + b[1])
        end
        unit(n)
      end

      def centroid(pts)
        mul(pts.reduce([0.0, 0.0, 0.0]) { |s, p| add(s, p) }, 1.0 / pts.size)
      end

      def circle(pts)
        return nil if pts.size < 8

        c = centroid(pts)
        rs = pts.map { |p| len(sub(p, c)) }
        r = rs.sum / rs.size
        return nil if r < 1.0 || (rs.max - rs.min) / r > 0.04

        [c, r]
      end

      # Annular end faces standing at an extreme of the part.
      def port_candidates(faces, verts, center, diag)
        tol = [0.6, diag * 0.002].max
        cands = []
        faces.each do |f|
          next if f[:loops].size < 2

          outer = f[:loops][0]
          n = newell(outer)
          oc = centroid(outer)
          hole = f[:loops][1..].filter_map { |lp| (ci = circle(lp)) && [ci, len(sub(ci[0], oc))] }
                                .select { |(c, r), off| off < 0.08 * r + 0.3 && c }
                                .min_by { |_, off| off }
          next unless hole

          (c, ri), = hole
          ro = outer.map { |p| len(sub(p, c)) }.max
          # outward = the side with no material in front of the face (a
          # socket mouth / weld end / flange face has the body only behind)
          reach = ro * 1.03
          free = [n, mul(n, -1.0)].select do |dir|
            verts.none? do |v|
              t = dot(sub(v, c), dir)
              next false unless t > tol

              radial = len(sub(sub(v, c), mul(dir, t)))
              # internals inside the bore (open butterfly disc, ball) don't count
              radial < reach && radial > ri * 1.02
            end
          end
          next unless free.size == 1

          s = free[0]
          cands << { p: c, d: s, ri: ri, ro: ro }
        end
        # merge coplanar duplicates, keep the smallest bore
        cands.sort_by { |c| c[:ri] }.each_with_object([]) do |c, acc|
          acc << c unless acc.any? { |a| len(sub(a[:p], c[:p])) < 1.0 && dot(a[:d], c[:d]) > 0.99 }
        end
      end

      def collinear_opposite?(a, b)
        return false if dot(a[:d], b[:d]) > -0.998

        off = sub(b[:p], a[:p])
        lateral = len(sub(off, mul(a[:d], dot(off, a[:d]))))
        lateral < 0.05 * [a[:ro], b[:ro]].max + 0.5
      end

      # Closest points of two lines (p1 + t·d1, p2 + u·d2).
      def line_closest(p1, d1, p2, d2)
        w = sub(p1, p2)
        b = dot(d1, d2)
        den = 1.0 - b * b
        return nil if den < 1e-6

        t = (b * dot(d2, w) - dot(d1, w)) / den
        u = (dot(d2, w) - b * dot(d1, w)) / den
        q1 = add(p1, mul(d1, t))
        q2 = add(p2, mul(d2, u))
        [q1, q2, len(sub(q1, q2))]
      end

      ONE_PORT = %w[cap blind].freeze
      TWO_INLINE = %w[coupling union hex_nipple nipple flange flange_wn reducer hose gate globe ball butterfly check
                      strainer steam_trap prv diaphragm flowmeter].freeze
      ANGLED = { 'elbow90' => 90.0, 'elbow45' => 45.0, 'p_trap' => nil, 'u_trap' => nil }.freeze
      BRANCHED = %w[tee san_tee wye cross san_cross double_wye].freeze

      # Picks the ports for the item type and returns [ports, frame] where
      # frame = [origin, x, y] of the canonical placement frame.
      def resolve(meta, cands, up_hint, verts = [])
        t = meta[:type]
        if ONE_PORT.include?(t)
          pt = cands.max_by { |c| c[:ri] } or return nil
          return [[pt], [pt[:p], mul(pt[:d], -1.0), perp(pt[:d], up_hint)]]
        end
        if TWO_INLINE.include?(t)
          pairs = cands.combination(2).select { |a, b| collinear_opposite?(a, b) }
          pairs.select! { |a, b| (a[:ri] - b[:ri]).abs <= 0.35 * [a[:ri], b[:ri]].max } unless %w[reducer flange flange_wn].include?(t)
          # butterfly: the seat faces carry the full bore; smaller coaxial
          # rings (actuator coupling, stem bushes) must not win on length
          score = t == 'butterfly' ? ->(x, y) { [x[:ri], y[:ri]].min * 1e4 + len(sub(x[:p], y[:p])) } : ->(x, y) { len(sub(x[:p], y[:p])) }
          best = pairs.max_by { |x, y| score.call(x, y) } || mirrored_pair(cands, verts) or return nil
          a, b = best
          if %w[flange flange_wn].include?(t)
            a, b = [a, b].sort_by { |c| c[:ro] } # port 0 = pipe side, port 1 = face
          elsif t == 'reducer'
            a, b = [a, b].sort_by { |c| -c[:ri] } # port 0 = large end
          end
          x = unit(sub(b[:p], a[:p]))
          return [[a, b], [mul(add(a[:p], b[:p]), 0.5), x, perp(x, up_hint)]]
        end
        if ANGLED.key?(t)
          best = nil
          cands.combination(2).each do |a, b|
            next if dot(a[:d], b[:d]) > 0.999

            ang = Math.acos(dot(a[:d], b[:d]).clamp(-1.0, 1.0)) * 180.0 / Math::PI
            defl = 180.0 - ang
            nominal = ANGLED[t]
            next if nominal && (defl - nominal).abs > 3.0

            if nominal
              q = line_closest(a[:p], a[:d], b[:p], b[:d]) or next
              next if q[2] > 0.1 * a[:ro] + 1.0

              score = (a[:ri] - b[:ri]).abs + q[2]
            else
              next if (a[:ri] - b[:ri]).abs > 0.2 * a[:ri]

              score = -len(sub(a[:p], b[:p]))
            end
            best = [score, a, b] if best.nil? || score < best[0]
          end
          return nil unless best

          _, a, b = best
          a, b = [a, b].sort_by { |c| -dot(c[:d], [0, 0, 1]) } unless ANGLED[t] # trap: inlet (up) first
          if ANGLED[t]
            q = line_closest(a[:p], a[:d], b[:p], b[:d])
            corner = mul(add(q[0], q[1]), 0.5)
            x = mul(a[:d], -1.0)
            y = unit(sub(b[:d], mul(x, dot(b[:d], x))))
            return [[a, b], [corner, x, y]]
          end
          x = mul(a[:d], -1.0)
          return [[a, b], [a[:p], x, perp(x, up_hint)]]
        end
        if BRANCHED.include?(t)
          runs = cands.combination(2).select { |a, b| collinear_opposite?(a, b) }
          best_run = runs.max_by { |x, y| len(sub(x[:p], y[:p])) + [x[:ri], y[:ri]].min } or return nil
          a, b = best_run
          others = cands - [a, b]
          branches = others.select do |c|
            q = line_closest(a[:p], a[:d], c[:p], c[:d])
            q && q[2] < 0.1 * c[:ro] + 1.0 && dot(sub(c[:p], a[:p]), c[:d]).positive?
          end
          return nil if branches.empty?

          # the wye/sanitary branch leans toward port b (flow into b)
          x = unit(sub(b[:p], a[:p]))
          br = branches.max_by { |c| c[:ri] }
          if %w[wye san_tee].include?(t) && dot(br[:d], x).negative?
            a, b = b, a
            x = mul(x, -1.0)
          end
          q = line_closest(a[:p], a[:d], br[:p], br[:d])
          origin = q[0]
          y = unit(sub(br[:d], mul(x, dot(br[:d], x))))
          ports = [a, b] + branches.sort_by { |c| -dot(c[:d], y) }
          return [ports, [origin, x, y]]
        end
        nil
      end

      # Inline part with only one annular end (the other closed by a disc
      # or plates): the far end is the opposite extreme along the same axis.
      def mirrored_pair(cands, verts)
        a = cands.max_by { |c| c[:ri] } or return nil
        back = verts.filter_map do |v|
          t = dot(sub(v, a[:p]), a[:d])
          radial = len(sub(sub(v, a[:p]), mul(a[:d], t)))
          -t if radial < a[:ro] * 1.03
        end.max
        return nil if back.nil? || back < 1.0

        [a.merge(p: sub(a[:p], mul(a[:d], back)), d: mul(a[:d], -1.0)), a]
      end

      def perp(x, hint)
        y = sub(hint, mul(x, dot(hint, x)))
        if len(y) < 0.2
          alt = x[2].abs < 0.9 ? [0.0, 0.0, 1.0] : [1.0, 0.0, 0.0]
          y = sub(alt, mul(x, dot(alt, x)))
        end
        unit(y)
      end

      # Socket depth of a port: nearest inward shoulder coaxial with it.
      def socket_depth(port, faces)
        best = nil
        faces.each do |f|
          next if f[:loops].size < 2

          n = newell(f[:loops][0])
          next if dot(n, port[:d]).abs < 0.995

          f[:loops].each do |lp|
            ci = circle(lp) or next
            c, r = ci
            off = sub(c, port[:p])
            t = dot(off, port[:d])
            next if t > -0.5

            next if len(sub(off, mul(port[:d], t))) > 0.03 * port[:ri] + 0.3
            next unless (r - port[:ri]).abs < 0.06 * port[:ri] || r < port[:ri] * 0.97

            outer_r = f[:loops][0].map { |p| len(sub(p, c)) }.max
            next unless (outer_r - port[:ri]).abs < 0.06 * port[:ri] && r < port[:ri] * 0.97

            best = -t if best.nil? || -t < best
          end
        end
        best
      end

      # ---------------------------------------------------------------

      def transform_to(frame, p)
        o, x, y = frame
        z = cross(x, y)
        q = sub(p, o)
        [dot(q, x), dot(q, y), dot(q, z)]
      end

      def rotate_to(frame, v)
        _, x, y = frame
        z = cross(x, y)
        [dot(v, x), dot(v, y), dot(v, z)]
      end

      def run(out_dir, files)
        index = { 'version' => 1, 'units' => 'mm', 'materials' => {}, 'items' => [] }
        bin = +''.b
        seen = {}
        keys = Hash.new(0)
        files.each do |src, path|
          doc = SkpReader::Doc.new(path)
          rule = SOURCES.fetch(src)[:rule]
          doc.colors.each do |n, (r, g, b, a)|
            next if n.start_with?('Layer_')

            index['materials']["#{src}:#{n}"] = [r, g, b, a]
          end
          doc.root[:inst].each do |inst|
            defn = doc.defs[inst[:def]]
            key0 = "#{src}/#{defn[:name]}"
            next if seen[key0]

            meta = send(rule, defn[:name], doc, inst) or next
            faces = doc.flatten(inst[:def])
            next if faces.empty?

            seen[key0] = true
            item = build_item(src, defn[:name], meta, faces, inst) or next
            item['key'] += "##{keys[item['key']]}" if (keys[item['key']] += 1) > 1
            block = encode(item[:faces], src)
            item.delete(:faces)
            item['bin'] = [bin.bytesize, block.bytesize]
            bin << block
            index['items'] << item
          end
        end
        index['items'].sort_by! { |i| [i['family'], i['type'], i['nps'] || 0, i['key']] }
        File.write(File.join(out_dir, 'refs.json'), JSON.pretty_generate(index))
        File.binwrite(File.join(out_dir, 'refs.bin'), bin)
        index
      end

      def build_item(src, name, meta, faces, inst)
        verts = faces.flat_map { |f| f[:loops].flatten(1) }
        mn = (0..2).map { |i| verts.map { |v| v[i] }.min }
        mx = (0..2).map { |i| verts.map { |v| v[i] }.max }
        center = mul(add(mn, mx), 0.5)
        diag = len(sub(mx, mn))
        # world Z (the model is laid out upright) expressed in part axes
        tr = inst[:tr]
        up = unit([tr[2], tr[5], tr[8]])
        cands = port_candidates(faces, verts.uniq, center, diag)
        res = resolve(meta, cands, up, verts.uniq)
        warn "no ports: #{src}/#{name} (#{meta[:type]}, #{cands.size} candidates)" unless res
        nps = meta[:size] && DEC.key(meta[:size])
        if res && nps && res[0].map { |pt| pt[:ri] }.max * 2 < 0.55 * nps * 25.4
          warn "bore too small, ports dropped: #{src}/#{name} (#{meta[:size]})"
          res = nil
        end
        if res && nps && TWO_INLINE.include?(meta[:type]) && meta[:type] != 'flowmeter'
          a, b = res[0]
          if len(sub(a[:p], b[:p])) > 4 * nps * 25.4 + 250
            warn "implausible length (spool, not a single part), ports dropped: #{src}/#{name}"
            res = nil
          end
        end
        # no ports: upright as laid out in the source file, origin at the
        # centre of the base
        base = verts.map { |v| dot(v, up) }.min
        base_pt = add(sub(center, mul(up, dot(center, up))), mul(up, base))
        ports, frame = res || [[], [base_pt, perp(up, [1.0, 0.0, 0.0]), up]]
        frame = [frame[0], frame[1], frame[2]]
        ports = ports.map do |p|
          depth = socket_depth(p, faces)
          { 'p' => transform_to(frame, p[:p]).map { |v| v.round(2) }, 'd' => rotate_to(frame, p[:d]).map { |v| v.round(5) },
            'ri' => p[:ri].round(2), 'ro' => p[:ro].round(2), 'depth' => depth&.round(2) }
        end
        local = faces.map do |f|
          { loops: f[:loops].map { |lp| lp.map { |v| transform_to(frame, v) } }, soft: f[:soft], mat: f[:mat] }
        end
        if STEMMED.include?(meta[:type]) && ports.size == 2
          hangs = %w[strainer steam_trap].include?(meta[:type]) # basket / trap body hangs down
          bore = ports.map { |p| p['ri'] }.max
          ang = stem_angle(local, ports)
          if ang.nil?
            dy, dz = asymmetry(local)
            ang = Math.atan2(dz, dy) if Math.hypot(dy, dz) > 0.3 * bore
          end
          if ang
            ang += Math::PI if hangs
            local, ports = roll(local, ports, ang)
            # the operator (wheel, lever, actuator) must sit on +Y
            dy, = asymmetry(local)
            local, ports = roll(local, ports, Math::PI) if (hangs ? dy > 0.3 * bore : dy < -0.5 * bore)
          end
        end
        lv = local.flat_map { |f| f[:loops].flatten(1) }
        size = meta[:size] || size_from_bore(ports, meta)
        nps = size && DEC.key(size)
        item = {
          'key' => "#{src}:#{meta[:family]}/#{meta[:type]}/#{meta[:variant] || meta[:operator] || '-'}/#{size}#{"x#{meta[:size2]}" if meta[:size2]}",
          'src' => src, 'src_name' => name, 'type' => meta[:type], 'family' => meta[:family],
          'size' => size, 'size2' => meta[:size2], 'nps' => nps, 'dn' => meta[:dn], 'variant' => meta[:variant],
          'operator' => meta[:operator], 'material' => meta[:material], 'standard' => meta[:standard],
          'ports' => ports, 'faces' => faces.size,
          'bbox' => [(0..2).map { |i| lv.map { |v| v[i] }.min.round(1) }, (0..2).map { |i| lv.map { |v| v[i] }.max.round(1) }]
        }.compact
        item[:faces] = local
        item
      end

      STEMMED = %w[gate globe ball butterfly check strainer steam_trap prv diaphragm].freeze

      # Angle (about X, from +Y) of the stem: circles perpendicular to the
      # bore whose centres lie on one line through the origin (stem,
      # bonnet, gland, handwheel hub …). Area-weighted vote.
      def stem_angle(local, ports)
        bore = ports.map { |p| p['ri'] }.max
        acc = [0.0, 0.0]
        local.each do |f|
          f[:loops].each do |lp|
            ci = circle(lp) or next
            c, r = ci
            n = newell(lp)
            next if n[0].abs > 0.1

            t = dot(c, n)
            next if t.abs < bore * 0.9

            next if len(sub(c, mul(n, t))) > 0.05 * t.abs + 2.0

            w = r * r * (t.positive? ? 1.0 : -1.0)
            acc[0] += n[1] * w
            acc[1] += n[2] * w
          end
        end
        return nil if Math.hypot(*acc) < 1e-6

        Math.atan2(acc[1], acc[0])
      end

      # Extent beyond the axis on +Y minus −Y, and +Z minus −Z.
      def asymmetry(local)
        vs = local.flat_map { |f| f[:loops].flatten(1) }
        ys = vs.map { |v| v[1] }
        zs = vs.map { |v| v[2] }
        [ys.max + ys.min, zs.max + zs.min]
      end

      # Rotate the part about X by −ang so the stem lies on +Y.
      def roll(local, ports, ang)
        c = Math.cos(-ang)
        s = Math.sin(-ang)
        rot = ->(v) { [v[0], v[1] * c - v[2] * s, v[1] * s + v[2] * c] }
        local = local.map { |f| f.merge(loops: f[:loops].map { |lp| lp.map(&rot) }) }
        ports = ports.map do |p|
          p.merge('p' => rot.call(p['p']).map { |v| v.round(2) }, 'd' => rot.call(p['d']).map { |v| v.round(5) })
        end
        [local, ports]
      end

      # For parts named without size (plastic ball valves): nearest plastic
      # pipe size from the socket bore (bore = pipe OD).
      def size_from_bore(ports, _meta)
        return nil if ports.empty?

        od = ports.map { |p| p['ri'] }.max * 2.0
        d = D_MM.keys.min_by { |k| (k - od).abs }
        (d - od).abs < 4 ? DEC[D_MM[d]] : nil
      end

      # Block: zlib(verts int32 ×3 at 0.01 mm, faces). Face: u16 material
      # index (0xFFFF = none), u16 loop count; loop: u16 n, n × u32 vertex
      # index with bit 31 set when the edge from that vertex is soft.
      def encode(faces, src)
        vidx = {}
        verts = []
        mats = []
        body = +''.b
        faces.each do |f|
          mi = f[:mat] ? (mats.index("#{src}:#{f[:mat]}") || (mats << "#{src}:#{f[:mat]}").size - 1) : 0xFFFF
          body << [mi, f[:loops].size].pack('vv')
          f[:loops].each_with_index do |lp, li|
            body << [lp.size].pack('v')
            lp.each_with_index do |v, k|
              q = v.map { |c| (c * 100).round }
              i = vidx[q] ||= (verts << q).size - 1
              soft = f[:soft] && f[:soft][li] && f[:soft][li][k]
              body << [i | (soft ? 0x80000000 : 0)].pack('V')
            end
          end
        end
        head = [verts.size, faces.size, mats.size].pack('VVv')
        mats.each { |m| head << [m.bytesize].pack('C') << m.b }
        raw = head + verts.flatten.pack('l<*') + body
        Zlib::Deflate.deflate(raw, Zlib::BEST_COMPRESSION)
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  out = ARGV.shift
  srcs = %w[piping pvc sch40 valves]
  files = srcs.zip(ARGV).reject { |_, p| p.nil? }
  idx = ArtK::PlantPipe::RefExtract.run(out, files)
  by = idx['items'].group_by { |i| [i['family'], i['type']] }
  by.sort.each { |(f, t), l| puts format('%-12s %-11s %3d  %s', f, t, l.size, l.map { |i| i['size'] }.uniq.join(' ')) }
  puts "#{idx['items'].size} items, #{File.size(File.join(out, 'refs.bin')) / 1024} KB"
end
