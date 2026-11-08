# frozen_string_literal: true

module ArtK
  module PlantPipe
    # Elevation reference "BOP" (ท้องท่อ, bottom of pipe) – 1.21.2.
    #
    # In BOP mode the point you pick on the model is the pipe's underside –
    # the insulation's when insulated – for every pipe kind (PVC, HDPE rigid
    # or coiled, GSP …): the centre goes up by half the OD plus the
    # insulation. Used by drawing (model and draft lines), Convert Edges and
    # the Stretch tool.
    #
    # What counts as picked: the position really lies ON a piece of the
    # model that gives a level –
    #   * an endpoint (any vertex) or a guide point,
    #   * an edge or a guide line that is not vertical,
    #   * a face that is not vertical (beam top, slab, floor), inside it,
    #   * the ground (nothing under the cursor, z = 0),
    # and is not one of our pipes (those are joined at their centre).
    #
    # Checked by geometry, not by what SketchUp says the cursor is over: a
    # point inferred from the last one (along an axis, in the air above a
    # beam that SketchUp still reports) is not on the beam, so it is not
    # lifted a second time; walls and columns (vertical) give no level and
    # are taken as they are. Every way a pick can be placed (inside groups,
    # components, an open edit context) is tried, so the check holds however
    # SketchUp reports the coordinates.
    module BopPick
      H = ModelHelpers
      TOL = 0.5     # mm – on the geometry
      FLAT = 0.1    # |normal z| below this: a vertical face (no level)
      STEEP = 0.995 # |direction z| above this: a vertical line (no level)

      module_function

      def on?(settings)
        settings['elevation_ref'] == 'bop'
      end

      # Centre above the picked underside: half the OD + the insulation.
      def lift(spec, settings)
        spec.od / 2.0 + settings['insulation_mm'].to_f
      end

      # What is under the cursor besides the InputPoint's own answer:
      # [[leaf, transformation, path], …] from a PickHelper.
      def under(view, x, y)
        ph = view.pick_helper
        ph.do_pick(x, y)
        (0...ph.count).map { |i| [ph.leaf_at(i), ph.transformation_at(i), ph.path_at(i).to_a] }
      rescue StandardError
        []
      end

      # Does the InputPoint's position lie on a level-giving piece of the
      # model (not ours)? +picks+ as #under gives them.
      def picked?(ip, picks = [], model = nil)
        pos = H.from_pt(ip.position)
        path = path_of(ip)
        return false if ours?(path)

        own = [ip.vertex, ip.edge, ip.face, path.last].compact.uniq
        return true if own.empty? && pos[2].abs <= TOL # the ground

        trs = transforms(path, model, ip.respond_to?(:transformation) ? ip.transformation : nil)
        cands = own.map { |e| [e, trs] }
        picks.each do |leaf, tr, ppath|
          next if leaf.nil? || ours?(ppath.to_a)

          cands << [leaf, transforms(ppath.to_a, model, tr)]
        end
        cands.any? { |e, ts| ts.any? { |t| on_geometry?(e, t, pos) } }
      rescue StandardError => e
        # once a session in the Ruby Console – the pick is then the centre
        unless @told
          @told = true
          puts "Plant Piping BOP: #{e.class}: #{e.message} (#{e.backtrace&.first})"
        end
        false
      end

      def path_of(ip)
        ip.respond_to?(:instance_path) ? ip.instance_path.to_a : []
      rescue StandardError
        []
      end

      # A path through our pipes / pieces (a pipe to join, not a surface).
      def ours?(path)
        path.any? { |e| e.respond_to?(:get_attribute) && H.type_of(e) }
      end

      # Ways the leaf's coordinates may map to the model: as they are (an
      # open edit context reports world positions), through the groups /
      # components on its path (or only the inner ones), through the given
      # transformation, and each of those inside the open context.
      def transforms(path, model, given = nil)
        insts = path.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
        list = [Geom::Transformation.new]
        list << given if given
        (0...insts.size).each do |k|
          list << insts[k..].reduce(Geom::Transformation.new) { |t, g| t * g.transformation }
        end
        if model && model.respond_to?(:active_path) && model.active_path
          et = H.edit_transform(model)
          list += list.map { |t| et * t }
        end
        list
      end

      def on_geometry?(e, tr, pos)
        case e
        when Sketchup::Vertex, Sketchup::ConstructionPoint
          Vec.dist(world(tr, e.position), pos) <= TOL
        when Sketchup::Edge
          a = world(tr, e.start.position)
          b = world(tr, e.end.position)
          level_line?(a, b) && seg_dist(pos, a, b) <= TOL
        when Sketchup::ConstructionLine
          a = world(tr, e.position)
          b = H.transform_mm(tr, Vec.add(H.from_pt(e.position), Vec.scale(Vec.unit(H.from_vec(e.direction)), 1000.0)))
          level_line?(a, b) && line_dist(pos, a, b) <= TOL
        when Sketchup::Face
          on_face?(face_points(e).map { |p| world(tr, p) }, pos)
        else
          false
        end
      end

      def world(tr, pt)
        H.from_pt(pt.transform(tr))
      end

      def face_points(face)
        verts = face.respond_to?(:outer_loop) && face.outer_loop ? face.outer_loop.vertices : face.vertices
        verts.map(&:position)
      end

      def level_line?(a, b)
        d = Vec.sub(b, a)
        len = Vec.length(d)
        len > 1e-6 && (d[2] / len).abs < STEEP
      end

      def seg_dist(p, a, b)
        ab = Vec.sub(b, a)
        t = Vec.dot(Vec.sub(p, a), ab) / Vec.dot(ab, ab)
        Vec.dist(p, Vec.add(a, Vec.scale(ab, t.clamp(0.0, 1.0))))
      end

      def line_dist(p, a, b)
        ab = Vec.sub(b, a)
        t = Vec.dot(Vec.sub(p, a), ab) / Vec.dot(ab, ab)
        Vec.dist(p, Vec.add(a, Vec.scale(ab, t)))
      end

      # On the face's plane, within its extent, and the face not vertical.
      def on_face?(pts, pos)
        return false if pts.size < 3

        n = newell(pts)
        len = Vec.length(n)
        return false if len < 1e-9

        n = Vec.scale(n, 1.0 / len)
        return false if n[2].abs < FLAT
        return false if Vec.dot(Vec.sub(pos, pts[0]), n).abs > TOL

        (0..2).all? do |i|
          lo, hi = pts.map { |p| p[i] }.minmax
          pos[i].between?(lo - TOL, hi + TOL)
        end
      end

      # Polygon normal (any winding, any number of points).
      def newell(pts)
        n = [0.0, 0.0, 0.0]
        pts.each_with_index do |p, i|
          q = pts[(i + 1) % pts.size]
          n[0] += (p[1] - q[1]) * (p[2] + q[2])
          n[1] += (p[2] - q[2]) * (p[0] + q[0])
          n[2] += (p[0] - q[0]) * (p[1] + q[1])
        end
        n
      end
    end
  end
end
