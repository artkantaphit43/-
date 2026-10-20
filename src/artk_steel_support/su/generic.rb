# frozen_string_literal: true

module ArtK
  module SteelSupport
    # Pipes not drawn with Plant Piping: any round (faceted) surface – a
    # Follow-Me tube, an imported pipe – is found from one of its faces.
    # Weight is estimated as steel Sch 40 full of water.
    module Generic
      SMOOTH = 40.0 * Math::PI / 180.0 # neighbour faces of one round surface
      MAX_FACES = 400
      MAX_R = 400.0

      module_function

      # Cylinder through +face+ (transformation tr to world):
      # { point:, axis:, radius:, length: } or nil.
      def cylinder(face, tr)
        return nil unless face.respond_to?(:normal) && face.respond_to?(:edges)

        @cache ||= {}
        key = [face.object_id, tr.respond_to?(:to_a) ? tr.to_a : tr.object_id]
        return @cache[key] if @cache.key?(key)

        faces = gather(face)
        normals = faces.map { |f| Vec.unit(H.from_vec(f.normal.transform(tr))) }
        points = faces.flat_map { |f| f.vertices.map { |v| H.transform_mm(tr, H.from_pt(v.position)) } }
        c = faces.size >= 3 ? Pipes.fit_cylinder(normals, points.uniq) : nil
        c = nil if c && c[:radius] > MAX_R
        @cache.clear if @cache.size > 500
        @cache[key] = c
      end

      def gather(face)
        seen = { face => true }
        queue = [face]
        out = []
        while (f = queue.shift) && out.size < MAX_FACES
          out << f
          f.edges.each do |e|
            e.faces.each do |g|
              next if seen[g]

              seen[g] = true
              queue << g if f.normal.angle_between(g.normal) < SMOOTH
            end
          end
        end
        out
      end

      # Face and its world transformation at the end of a pick / ray path.
      def face_of(path)
        return nil unless path && !path.empty?

        face = path.last
        return nil unless face.is_a?(Sketchup::Face)

        tr = Geom::Transformation.new
        path[0...-1].each { |e| tr *= e.transformation if e.respond_to?(:transformation) }
        [face, tr]
      end

      # Pipe record (support coordinates of origin / x / y) of a cylinder.
      def pipe(cyl, origin, x, y)
        a = cyl[:axis]
        den = Vec.dot(a, x)
        t = den.abs < 1e-6 ? 0.0 : Vec.dot(Vec.sub(origin, cyl[:point]), x) / den
        c = Vec.along(cyl[:point], a, t)
        od = 2.0 * cyl[:radius]
        { y: Vec.dot(Vec.sub(c, origin), y).round(1), z: (c[2] - origin[2]).round(1), od: od, ins: 0.0, r: od / 2.0,
          kg_m: Pipes.generic_kg_m(od), span_m: Pipes.default_span_m(od), label: "Ø#{od.round}", pid: nil,
          src: 'generic', cyl: cyl }
      end

      def parallel?(cyl, x)
        Vec.dot(cyl[:axis], x).abs > Math.cos(5.0 * Math::PI / 180.0)
      end

      # Round pipes beside origin across x (rays along ±y at heights
      # dz0..dz1): cylinders parallel to x, nearest first per ray.
      def scan(model, origin, x, y, known: [], reach: 2500.0, dz0: -400.0, dz1: 1300.0, step: 25.0)
        found = known.dup
        [y, Vec.scale(y, -1.0)].each do |v|
          dz = dz0
          while dz <= dz1
            from = Vec.add(origin, [0, 0, dz])
            pt = from
            20.times do
              hit = model.raytest([H.to_pt(pt), H.to_vec(v)], true)
              break unless hit

              hp = H.from_pt(hit[0])
              break if Vec.dist(from, hp) > reach

              path = hit[1] || []
              unless path.any? { |e| H.ours?(e) || Link.pp_entity?(e) } || Probe.in_pipe?(hp, found)
                fc = face_of(path)
                cyl = fc && cylinder(*fc)
                break unless cyl && parallel?(cyl, x) # a wall or anything else stops the ray

                found << cyl
              end
              pt = Vec.along(hp, v, 1.0)
            end
            dz += step
          end
        end
        found - known
      end
    end
  end
end
