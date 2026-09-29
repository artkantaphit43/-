# frozen_string_literal: true

require 'zlib'

module ArtK
  module PlantPipe
    # Offline reader for SketchUp 2021+ .skp files (no SketchUp needed).
    #
    # A 2021+ .skp is a small UTF-16 header followed by a ZIP archive holding
    # model.dat, materials/<name>/material.xml, thumbnails, styles … .
    # model.dat is a tree of records: u16 tag, u32 length, payload – a
    # payload is either raw data or more records. The tags used here:
    #
    #   0x157c definition        0x157e name       0x1388 entities
    #   0x1389 vertices  -> 0x09c4 vertex (0x09c5 = 3 × f64, inches)
    #   0x138a edges     -> 0x0bb8 edge (0x0bb9 start, 0x0bba end vertex id,
    #                                    header 0x07d3 flags: 0x18 = soft/smooth)
    #   0x138b faces     -> 0x0dac face (0x0dad plane, 0x0dae loops ->
    #                       0x1194 loop -> 0x1195 -> 0x0fa0 edge use:
    #                       0x0fa1 edge id, 0x0fa2 reversed)
    #   0x138c / 0x138d component instances / groups -> 0x1964 instance:
    #                       0x1966 = 13 × f64 (3 axis vectors, origin, scale)
    #                       0x1967 definition id
    #   entity header 0x07d0 -> 0x05dc/0x05de id (u24), 0x07d1 material id
    #   0x1f6/0x1388 model root entities, 0x32c8 material (0x32cc name)
    #
    # Worked out by inspection; verified by rendering every definition of the
    # reference files against their embedded thumbnails.
    module SkpReader
      class Doc
        attr_reader :defs, :root, :materials, :colors

        def initialize(path)
          raw = File.binread(path)
          zip = Zip.new(raw[raw.index("PK\x03\x04".b)..])
          @d = zip.read('model.dat')
          @colors = {}
          zip.names.grep(%r{\Amaterials/(.+)/material\.xml\z}).each do |n|
            xml = zip.read(n).force_encoding('UTF-8')
            m = xml.match(/colorRed="(\d+)" colorGreen="(\d+)" colorBlue="(\d+)"/)
            next unless m

            # keyed by folder name = material name as stored in model.dat
            a = xml[/trans="([\d.]+)"[^>]*useTrans="1"/, 1]
            @colors[n.split('/')[1]] = [m[1].to_i, m[2].to_i, m[3].to_i, a ? a.to_f : 1.0]
          end
          decode
        end

        # Flattened faces of a definition: [{loops: [[[x,y,z] mm …] …],
        # soft: [[bool …] …], mat: name|nil}], nested instances resolved.
        def flatten(def_id, tr = IDENTITY, mat = nil, out = [])
          g = @defs[def_id]
          g[:faces].each do |f|
            loops = f[:loops].map { |lp| lp.map { |vid| apply(tr, g[:verts][vid]) } }
            out << { loops: loops, soft: f[:soft], mat: f[:mat] || mat }
          end
          g[:inst].each do |i|
            flatten(i[:def], compose(tr, i[:tr]), i[:mat] || mat, out)
          end
          out
        end

        # Names of all nested definitions (for identifying anonymous items).
        def descendant_names(def_id, acc = [], depth = 0)
          @defs[def_id][:inst].each do |i|
            acc << @defs[i[:def]][:name]
            descendant_names(i[:def], acc, depth + 1) if depth < 5
          end
          acc
        end

        IDENTITY = [1.0, 0, 0, 0, 1.0, 0, 0, 0, 1.0, 0, 0, 0].freeze
        INCH = 25.4

        # tr: x axis (3), y axis (3), z axis (3), origin (3) – origin in mm.
        def apply(tr, p)
          (0..2).map { |i| tr[9 + i] + p[0] * tr[i] + p[1] * tr[3 + i] + p[2] * tr[6 + i] }
        end

        def compose(a, b)
          axes = (0..2).flat_map do |k|
            v = b[3 * k, 3]
            (0..2).map { |i| a[i] * v[0] + a[3 + i] * v[1] + a[6 + i] * v[2] }
          end
          axes + apply(a, b[9, 3])
        end

        private

        def parse(a, b)
          out = []
          p = a
          while p < b
            return nil if p + 6 > b

            t, l = @d.unpack("@#{p}vV")
            return nil if p + 6 + l > b

            out << [t, p + 6, p + 6 + l]
            p += 6 + l
          end
          out
        end

        def kid(rec, tag)
          (parse(*rec) || []).each { |t, a, b| return [a, b] if t == tag }
          nil
        end

        def kids(rec, tag)
          (parse(*rec) || []).select { |t, _, _| t == tag }.map { |_, a, b| [a, b] }
        end

        def u24(rec)
          # little-endian, 1–4 bytes (small ids are stored shorter)
          @d.byteslice(rec[0], rec[1] - rec[0]).bytes.each_with_index.sum { |v, i| v << (8 * i) }
        end

        def entity_id(rec)
          (parse(*rec) || []).each do |t, a, b|
            if t == 0x05dc
              i = kid([a, b], 0x05de)
              return u24(i) if i
            elsif t == 0x07d0
              return entity_id([a, b])
            end
          end
          nil
        end

        def header_material(rec)
          h = kid(rec, 0x07d0)
          m = h && kid(h, 0x07d1)
          m && u24(m)
        end

        def doubles(rec, n)
          @d.unpack("@#{rec[0]}E#{n}")
        end

        def decode
          top = parse(0, @d.bytesize)
          root = top[0][1, 2]
          @defs = {}
          @materials = {}
          model_ent = nil
          parse(*root).each do |t, a, b|
            case t
            when 0x1f6
              model_ent = kid([a, b], 0x1388)
            when 0x1f9
              walk_defs([a, b], 0)
            when 0x1f7
              collect_materials([a, b], 0)
            end
          end
          @root = geom(model_ent)
        end

        def walk_defs(rec, depth)
          (parse(*rec) || []).each do |t, a, b|
            if t == 0x157c
              name = kid([a, b], 0x157e)
              g = geom(kid([a, b], 0x1388))
              g[:name] = @d.byteslice(name[0], name[1] - name[0]).force_encoding('UTF-8')
              @defs[g[:id]] = g
            elsif depth < 4 && [0x1770, 0x1771].include?(t)
              walk_defs([a, b], depth + 1)
            end
          end
        end

        def collect_materials(rec, depth)
          (parse(*rec) || []).each do |t, a, b|
            if t == 0x32c8
              n = kid([a, b], 0x32cc)
              @materials[entity_id([a, b])] = @d.byteslice(n[0], n[1] - n[0]).force_encoding('UTF-8')
            elsif depth < 3 && [0x30d4, 0x30d5].include?(t)
              collect_materials([a, b], depth + 1)
            end
          end
        end

        def geom(ent)
          g = { id: entity_id(ent), verts: {}, faces: [], inst: [] }
          edges = {}
          face_recs = []
          parse(*ent).each do |t, a, b|
            case t
            when 0x1389
              kids([a, b], 0x09c4).each do |r|
                p = kid(r, 0x09c5)
                g[:verts][entity_id(r)] = doubles(p, 3).map { |v| v * INCH }
              end
            when 0x138a
              kids([a, b], 0x0bb8).each do |r|
                h = kid(r, 0x07d0)
                fl = @d.getbyte(kid(h, 0x07d3)[0])
                edges[entity_id(r)] = [u24(kid(r, 0x0bb9)), u24(kid(r, 0x0bba)), (fl & 0x18) != 0]
              end
            when 0x138b
              face_recs = kids([a, b], 0x0dac)
            when 0x138c, 0x138d
              list = t == 0x138d ? kids([a, b], 0x1d4c).map { |r| kid(r, 0x1964) } : kids([a, b], 0x1964)
              list.each do |ci|
                m = doubles(kid(ci, 0x1966), 13)
                # stored row-major: transpose into axis vectors; origin → mm
                tr = [m[0], m[3], m[6], m[1], m[4], m[7], m[2], m[5], m[8]] + m[9, 3].map { |v| v * INCH }
                g[:inst] << { def: u24(kid(ci, 0x1967)), tr: tr, mat: mat_name(header_material(ci)) }
              end
            end
          end
          face_recs.each do |r|
            loops = []
            soft = []
            kids(kid(r, 0x0dae), 0x1194).each do |lr|
              pts = []
              sf = []
              kids(kid(lr, 0x1195), 0x0fa0).each do |u|
                s, e, fs = edges[u24(kid(u, 0x0fa1))]
                rev = @d.getbyte(kid(u, 0x0fa2)[0]) != 0
                pts << (rev ? e : s)
                sf << fs
              end
              loops << pts
              soft << sf
            end
            g[:faces] << { loops: loops, soft: soft, mat: mat_name(header_material(r)) }
          end
          g
        end

        def mat_name(id)
          id && @materials[id]
        end
      end

      # Minimal ZIP reader (stored / deflated entries, central directory).
      class Zip
        def initialize(bytes)
          @b = bytes
          @entries = {}
          eocd = @b.rindex("PK\x05\x06".b) or raise 'not a zip'
          n, _size, off = @b.unpack("@#{eocd + 10}vVV")
          p = off
          n.times do
            meth, _t, _d, _crc, csize, _usize, nlen, xlen, clen = @b.unpack("@#{p + 10}vvvVVVvvv")
            local = @b.unpack1("@#{p + 42}V")
            name = @b.byteslice(p + 46, nlen).force_encoding('UTF-8')
            @entries[name] = [meth, csize, local]
            p += 46 + nlen + xlen + clen
          end
        end

        def names
          @entries.keys
        end

        def read(name)
          meth, csize, local = @entries.fetch(name)
          nlen, xlen = @b.unpack("@#{local + 26}vv")
          data = @b.byteslice(local + 30 + nlen + xlen, csize)
          meth.zero? ? data : Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(data)
        end
      end
    end
  end
end
