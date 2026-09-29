# frozen_string_literal: true

module ArtK
  module PlantPipe
    # Bill of Materials aggregation from item records collected in the model.
    #
    # Records are plain hashes (string keys, as stored in SketchUp attribute
    # dictionaries). Aggregation is purchasing-oriented:
    # * pipe      → total metres, number of stock lengths incl. cut waste,
    #               empty weight (kg)
    # * fittings  → pieces, grouped by type/angle/size
    # * insulation→ metres by thickness & size
    # * joints    → estimated field joints (welds / solvent / fusion), for
    #               labour estimating
    module Bom
      CATEGORY_ORDER = %w[pipe elbow tee valve flange mitre insulation support rod member].freeze

      CATEGORY_TH = {
        'pipe' => 'ท่อ', 'elbow' => 'ข้องอ', 'tee' => 'สามทาง', 'valve' => 'วาล์ว',
        'flange' => 'หน้าแปลน', 'mitre' => 'รอยต่อเฉียง', 'insulation' => 'ฉนวน',
        'support' => 'ซัพพอร์ต', 'rod' => 'เหล็กเส้นเกลียว', 'member' => 'เหล็กโครงสร้าง'
      }.freeze

      HEADER = ['No.', 'Category', 'Description', 'Service', 'Material / Standard', 'Size',
                'Rating', 'Qty', 'Unit', 'Stock lengths', 'Weight (kg)', 'Remark'].freeze

      Row = Struct.new(:category, :description, :service, :material, :size, :rating,
                       :qty, :unit, :sticks, :weight, :remark, keyword_init: true)

      module_function

      # waste: cutting allowance fraction added before counting stock lengths.
      def aggregate(records, waste: 0.05)
        groups = {}
        records.flat_map { |r| expand(r) }.each do |r|
          key, row = classify(r)
          next unless key

          g = groups[key]
          if g
            g.qty += row.qty
            g.weight = g.weight.to_f + row.weight.to_f if row.weight
          else
            groups[key] = row
          end
          (g || row).remark = merge_remark((g || row).remark, r['remark'])
        end
        rows = groups.values
        rows.each do |row|
          next unless row.category == 'pipe'

          # While aggregating, `sticks` carries the stock length (m); it is
          # converted to a count of stock lengths here.
          stick = row.sticks.to_f
          row.qty = row.qty.round(2)
          row.sticks = stick.positive? ? ((row.qty * (1.0 + waste)) / stick).ceil : nil
          row.weight = row.weight && row.weight.round(1)
        end
        rows.each { |row| row.qty = row.qty.round(2) if row.unit == 'm' }
        rows.sort_by do |row|
          [CATEGORY_ORDER.index(row.category) || 99, row.service.to_s, row.material.to_s,
           size_sort_key(row.size), row.description.to_s]
        end
      end

      def classify(r)
        t = r['type'].to_s
        svc = r['service'].to_s
        mat = r['catalog_name'] || r['material']
        size = r['size'].to_s
        rating = r['rating'].to_s
        case t
        when 'pipe'
          len_m = r['length_mm'].to_f / 1000.0
          weight = r['weight_kg_m'] ? r['weight_kg_m'].to_f * len_m : nil
          row = Row.new(category: 'pipe', description: "Pipe #{r['material']}", service: svc,
                        material: mat, size: size, rating: rating, qty: len_m, unit: 'm',
                        sticks: r['stick_m'], weight: weight, remark: nil)
          [['pipe', svc, mat, size, rating], row]
        when 'elbow'
          ang = r['nominal_angle'] ? "#{fmt_angle(r['nominal_angle'])}°" : "#{fmt_angle(r['angle'])}° (bend)"
          rt = r['radius_type'].to_s.upcase
          desc = "Elbow #{ang} #{rt}".strip
          [['elbow', svc, mat, size, rating, desc], pcs('elbow', desc, svc, mat, size, rating)]
        when 'tee'
          desc = tee_desc(r)
          bsize = r['branch_size'] && r['branch_size'] != size ? "#{size} x #{r['branch_size']}" : size
          [['tee', svc, mat, bsize, rating, desc], pcs('tee', desc, svc, mat, bsize, rating)]
        when 'valve'
          desc = r['valve_name'] || r['valve_type'].to_s
          cat = r['valve_type'] == 'flange' ? 'flange' : 'valve'
          [[cat, svc, mat, size, desc], pcs(cat, desc, svc, mat, size, r['valve_rating'] || 'Class 150')]
        when 'mitre'
          desc = "Mitre joint #{fmt_angle(r['angle'])}°"
          [['mitre', svc, mat, size, desc], pcs('mitre', desc, svc, mat, size, rating)]
        when 'support'
          desc = r['support_name'] || r['support_type'].to_s
          [['support', svc, r['pipe_size'], desc], pcs('support', desc, svc, 'Galvanised / steel', r['pipe_size'].to_s, '')]
        when 'rod'
          desc = "Threaded rod #{r['rod_label']}"
          row = Row.new(category: 'rod', description: desc, service: '', material: 'Galvanised steel', size: r['rod_label'].to_s,
                        rating: '', qty: r['length_mm'].to_f / 1000.0, unit: 'm', sticks: nil, weight: nil, remark: nil)
          [['rod', desc], row]
        when 'member'
          desc = r['member_name'].to_s
          row = Row.new(category: 'member', description: desc, service: '', material: 'Steel', size: '',
                        rating: '', qty: r['length_mm'].to_f / 1000.0, unit: 'm', sticks: nil, weight: nil, remark: nil)
          [['member', desc], row]
        when 'insulation'
          len_m = r['length_mm'].to_f / 1000.0
          desc = "Insulation #{r['thickness'].to_f.round} mm thk"
          row = Row.new(category: 'insulation', description: desc, service: svc, material: r['insulation_material'] || '-',
                        size: size, rating: '', qty: len_m, unit: 'm', sticks: nil, weight: nil, remark: nil)
          [['insulation', svc, size, desc], row]
        end
      end

      # A support also consumes threaded rod and steel members, bought by
      # the metre – split them into their own purchasing lines.
      def expand(r)
        return [r] unless r['type'] == 'support'

        out = [r]
        if r['rod_length_mm'].to_f.positive?
          out << { 'type' => 'rod', 'rod_label' => r['rod_label'], 'length_mm' => r['rod_length_mm'] }
        end
        if r['member_length_mm'].to_f.positive?
          out << { 'type' => 'member', 'member_name' => r['member_name'], 'length_mm' => r['member_length_mm'] }
        end
        out
      end

      def pcs(cat, desc, svc, mat, size, rating)
        Row.new(category: cat, description: desc, service: svc, material: mat, size: size,
                rating: rating, qty: 1, unit: 'pcs', sticks: nil, weight: nil, remark: nil)
      end

      def tee_desc(r)
        case r['kind'].to_s
        when 'cross' then 'Cross'
        when 'lateral' then "Lateral / Wye #{fmt_angle(r['branch_angle'])}°"
        when 'manifold' then 'Header / manifold junction'
        else r['branch_size'] && r['branch_size'] != r['size'] ? 'Reducing Tee' : 'Equal Tee'
        end
      end

      def fmt_angle(a)
        f = a.to_f
        (f - f.round).abs < 0.05 ? f.round.to_s : f.round(1).to_s
      end

      def merge_remark(a, b)
        return a if b.nil? || b.to_s.empty?
        return b.to_s if a.nil? || a.empty?
        return a if a.split('; ').include?(b.to_s)

        "#{a}; #{b}"
      end

      # Sort 1/2" < 3/4" < 1" < 1-1/4" … and "20 mm" < "110 mm".
      def size_sort_key(size)
        s = size.to_s.split(' x ').first.to_s
        if s =~ /(\d+(?:\.\d+)?)\s*mm/
          Regexp.last_match(1).to_f
        else
          whole = 0.0
          frac = 0.0
          body = s.delete('"')
          if body.include?('-')
            w, f = body.split('-', 2)
            whole = w.to_f
            body = f
          end
          if body.include?('/')
            n, d = body.split('/')
            frac = n.to_f / d.to_f
          else
            whole += body.to_f
          end
          (whole + frac) * 25.4
        end
      end

      # Field joints estimate: fitting ends + joints between stock lengths.
      def joint_estimate(records)
        joints = 0
        records.each do |r|
          joints += case r['type']
                    when 'elbow' then 2
                    when 'tee' then r['kind'] == 'cross' ? 4 : 3
                    when 'valve' then 2
                    when 'mitre' then 1
                    when 'pipe'
                      stick = r['stick_m'].to_f
                      stick.positive? ? [(r['length_mm'].to_f / 1000.0 / stick).ceil - 1, 0].max : 0
                    else 0
                    end
        end
        joints
      end

      def csv_escape(v)
        s = v.nil? ? '' : v.to_s
        s =~ /[",\r\n]/ ? "\"#{s.gsub('"', '""')}\"" : s
      end

      # UTF-8 CSV with BOM so Excel (Thai Windows) opens Thai text correctly.
      def to_csv(rows, title: nil, joints: nil)
        lines = []
        lines << csv_escape(title) if title
        lines << HEADER.map { |h| csv_escape(h) }.join(',')
        rows.each_with_index do |r, i|
          cat = "#{r.category} (#{CATEGORY_TH[r.category]})"
          lines << [i + 1, cat, r.description, r.service, r.material, r.size, r.rating,
                    r.qty, r.unit, r.sticks, r.weight, r.remark].map { |v| csv_escape(v) }.join(',')
        end
        if joints
          lines << ''
          lines << csv_escape("Estimated field joints / จำนวนรอยต่อโดยประมาณ: #{joints}")
        end
        "﻿" + lines.join("\r\n") + "\r\n"
      end
    end
  end
end
