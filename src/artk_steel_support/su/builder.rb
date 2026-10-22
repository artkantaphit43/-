# frozen_string_literal: true

module ArtK
  module SteelSupport
    # Supports in the model: one group each, numbered per type (A-01 …),
    # with everything needed to rebuild it later stored on it
    # (docs/STEEL_SUPPORTS.md). Types A–D (Std, Placer); wf / wb / th / tt
    # are the 1.0 details, still refitted in files drawn with 1.0.
    module Builder
      FORMAT = 1
      NEAR = 2500.0 # mm, pipes changed this close to a support refit it

      module_function

      def create(model, plan, number: nil, op: true)
        res = plan[:result]
        model.start_operation('Steel Supports: วางซัพพอร์ต', true) if op
        started = op
        g = model.active_entities.add_group
        H.add_part(model, g.entities, res.part)
        g.transformation = H.edit_transform(model).inverse * H.frame_transform(plan[:origin], plan[:x], plan[:y])
        g.layer = H.tag(model)
        number ||= next_number(model, plan[:detail])
        g.name = "#{number} #{title(plan)} (#{res.carried.size} ท่อ)"
        write(g, plan, number)
        guides(g, res)
        drop_hangers(model, plan) if H.settings['drop_hangers']
        model.commit_operation if op
        g
      rescue StandardError
        model.abort_operation if started
        raise
      end

      def title(plan)
        t = plan[:detail]
        return Std.type(t)[:th] if Placer.std?(t)

        "#{Details::TYPES[t][:th]} #{Steel.get(plan[:result].info[:section])[:inch]}"
      end

      # The drawing's places no pipe takes yet: a guide point / line on the
      # steel where that line rests, to draw the pipe onto (Plant Piping's
      # pipe tool lays it there, on the steel).
      def guides(g, res)
        res.info[:rests].to_a.each do |y, z|
          g.entities.add_cpoint(H.to_pt([0.0, y, z]))
          g.entities.add_cline(H.to_pt([-500.0, y, z]), H.to_pt([500.0, y, z])) if g.entities.respond_to?(:add_cline)
        end
      end

      # A point picked on our support in +path+ (Plant Piping's pipe tool)
      # for a pipe { od:, ins: } (nil: not known): where it goes (Std.rest)
      # – { z: (world, its underside), bare:, name:, point: } or nil. The
      # point moves out to the drawing's place it takes and, picked on the
      # steel itself, onto the support's centre line (as its guide point),
      # so a pipe started there crosses the support.
      #
      # SketchUp may give no instance path for a point snapped to a guide
      # line / point (inference), so without our support in +path+ the
      # point is looked for on the guide lines and the steel of the
      # supports in +model+.
      def rest_at(path, point, pipe = nil, model: nil)
        if (g = path.to_a.find { |e| H.ours?(e) })
          return Placer.std?(g.get_attribute(H::DICT, 'detail')) ? rest_on(frame(g), point, pipe) : nil
        end
        return nil unless model

        frames(model).filter_map { |f| rest_on(f, point, pipe, loose: true) }.min_by { |r| r[:lx].abs }
      end

      # loose: only on a guide line (the drawing's places) or the steel.
      def rest_on(f, point, pipe, loose: false)
        v = Vec.sub(point, f[:o])
        lx = Vec.dot(v, f[:x])
        ly = Vec.dot(v, f[:y])
        return nil if lx.abs > (loose ? 503.0 : 600.0)

        r = Std.rest(f[:t], ly, v[2], pipe, f[:taken])
        return nil unless r
        return nil if loose && lx.abs > r[:half] + 5.0 && Std.nominal(f[:t]).none? { |q| (q[:y] - ly).abs <= 3.0 }

        along = lx.abs <= r[:half] + 5.0 ? 0.0 : lx
        on = Vec.add(Vec.along(Vec.along(f[:o], f[:x], along), f[:y], r[:y]), [0.0, 0.0, v[2]])
        name = "#{f[:number]} ที่ #{format('%.2f', r[:y] / 1000.0)} ม. จากหน้าเสา"
        { z: f[:o][2] + r[:z], bare: r[:bare], name: name, point: on, lx: lx }
      end

      # What rest_on needs of support +g+.
      def frame(g)
        taken = H.get_json(g, 'info', {})['nominal'] ? [] : H.get_json(g, 'pipes', []).map { |p| taken_pipe(p) }
        { t: g.get_attribute(H::DICT, 'detail'), number: g.get_attribute(H::DICT, 'number'), o: H.get_json(g, 'origin'),
          x: H.get_json(g, 'xdir'), y: H.get_json(g, 'ydir'), taken: taken }
      end

      # The A–D supports of +model+ (read again after a second / a change).
      def frames(model)
        if @frames.nil? || @frames[:model] != model || Time.now - @frames[:t] > 1.0
          list = H.supports(model).filter_map { |g, _| frame(g) if Placer.std?(g.get_attribute(H::DICT, 'detail')) }
          @frames = { model: model, t: Time.now, list: list }
        end
        @frames[:list]
      end

      def taken_pipe(p)
        od = p['od'].to_f
        { y: p['y'].to_f, z: p['z'].to_f, od: od, ins: p['ins'].to_f, r: od / 2.0 + p['ins'].to_f, label: p['label'] }
      end

      def write(g, plan, number)
        res = plan[:result]
        hit = plan[:hit] || {}
        pipes = res.carried.map do |p|
          { 'pid' => p[:pid], 'label' => p[:label], 'y' => p[:y].round(1), 'z' => p[:z].round(1), 'od' => p[:od].round(2),
            'ins' => p[:ins].to_f, 'src' => p[:src] || 'pp', 'at' => world_at(plan, p).map { |c| c.round(1) } }
        end
        ref = hit[:pipe] || {}
        g.set_attribute(H::DICT, 'kind', 'support')
        g.set_attribute(H::DICT, 'format', FORMAT)
        g.set_attribute(H::DICT, 'detail', plan[:detail])
        g.set_attribute(H::DICT, 'number', number)
        g.set_attribute(H::DICT, 'section', res.info[:section])
        g.set_attribute(H::DICT, 'anchor', res.info[:anchor]) if res.info[:anchor]
        g.set_attribute(H::DICT, 'rod', res.info[:rod]) if res.info[:rod]
        H.set_json(g, 'origin', plan[:origin].map { |c| c.round(2) })
        H.set_json(g, 'xdir', plan[:x])
        H.set_json(g, 'ydir', plan[:y])
        H.set_json(g, 'hit_dir', hit[:dir] || plan[:x])
        H.set_json(g, 'ref', { 'src' => hit[:src], 'pid' => ref[:pid], 'od' => ref[:od], 'label' => ref[:label],
                               'cyl' => hit[:cyl] })
        H.set_json(g, 'opts', plan[:opts] || {})
        H.set_json(g, 'pipes', pipes)
        H.set_json(g, 'struct', plan[:struct])
        H.set_json(g, 'bom', res.bom)
        H.set_json(g, 'checks', res.checks)
        H.set_json(g, 'notes', res.notes)
        H.set_json(g, 'info', res.info.reject { |k, _| k == :chord })
      end

      def world_at(plan, p)
        Vec.add(Vec.add(plan[:origin], Vec.scale(plan[:y], p[:y])), [0, 0, p[:z]])
      end

      def next_number(model, detail)
        key = "seq_#{detail}"
        n = model.get_attribute(H::DICT, key).to_i + 1
        model.set_attribute(H::DICT, key, n)
        format('%<d>s-%<n>02d', d: detail.upcase, n: n)
      end

      # Plant Piping's own single hangers where these pipes are now carried.
      def drop_hangers(model, plan)
        plan[:result].carried.each do |p|
          Link.drop_hangers(model, world_at(plan, p), [p[:pid]]) if p[:pid]
        end
      end

      # World points where our supports carry Plant Piping run +pid+.
      def points_for(model, pid)
        if @cache.nil? || @cache[:model] != model || Time.now - @cache[:t] > 2.0
          map = Hash.new { |h, k| h[k] = [] }
          H.supports(model).each do |g, _|
            H.get_json(g, 'pipes', []).each { |p| map[p['pid']] << p['at'] if p['pid'] }
          end
          @cache = { model: model, t: Time.now, map: map }
        end
        @cache[:map][pid]
      end

      def forget
        @cache = nil
        @frames = nil
      end

      # ---------- refit ----------

      # The clicked pipe again (it may have moved / been resized).
      def rehit(model, g)
        origin = H.get_json(g, 'origin')
        dir = H.get_json(g, 'hit_dir') || H.get_json(g, 'xdir')
        ref = H.get_json(g, 'ref', {})
        if ref['src'] == 'pp' || ref['src'].nil?
          pp = Link.pipe_at(model, origin)
          return pp && { point: pp[:point], dir: pp[:dir], src: 'pp', pipe: pipe_record(pp) }
        end
        cyl = ref['cyl'] && ref['cyl'].transform_keys(&:to_sym)
        return nil unless cyl

        y = Vec.cross(Vec::UP, Vec.horizontal(dir))
        pipe = Generic.pipe(cyl, origin, Vec.horizontal(dir), y)
        { point: origin, dir: dir, src: 'generic', cyl: cyl, pipe: pipe }
      end

      def pipe_record(pp)
        { y: 0.0, z: 0.0, od: pp[:od], ins: pp[:ins], r: pp[:od] / 2.0 + pp[:ins], kg_m: pp[:kg_m], span_m: pp[:span_m],
          label: pp[:label], pid: pp[:pid], src: 'pp' }
      end

      # Rebuild +g+ for the pipes there now: :same, :done or :lost (no pipe).
      # A–D stay where they are (steel as drawn); 1.0 details follow the
      # clicked pipe.
      def refit(model, g, op: true)
        if Placer.std?(g.get_attribute(H::DICT, 'detail'))
          plan = Placer.refit_plan(model, g)
        else
          hit = rehit(model, g)
          return :lost unless hit

          plan = Planner.plan(model, g.get_attribute(H::DICT, 'detail'), hit, H.get_json(g, 'opts', {}))
        end
        same = Pipes.signature(plan[:result].carried) == stored_signature(g) &&
               plan[:result].info[:section] == g.get_attribute(H::DICT, 'section') &&
               H.get_json(g, 'origin') == plan[:origin].map { |c| c.round(2) } &&
               plan[:result].notes == H.get_json(g, 'notes', []) &&
               (!Placer.std?(plan[:detail]) || H.get_json(g, 'info', {}).key?('rests')) # 2.0.4: guides off the steel
        return :same if same

        model.start_operation('Steel Supports: ปรับตามท่อ', true, false, op == :transparent) if op
        number = g.get_attribute(H::DICT, 'number')
        g.erase!
        create(model, plan, number: number, op: false)
        model.commit_operation if op
        forget
        :done
      end

      # World min / max corners of a run's bounds (nil when unknown).
      def box(model, run)
        return nil unless run.respond_to?(:bounds)

        bb = run.bounds
        tr = H.edit_transform(model)
        a = H.from_pt(bb.min.transform(tr))
        b = H.from_pt(bb.max.transform(tr))
        [[a, b].map { |p| p[0] }.minmax, [a, b].map { |p| p[1] }.minmax, [a, b].map { |p| p[2] }.minmax].transpose
      rescue StandardError
        nil
      end

      def stored_signature(g)
        H.get_json(g, 'pipes', []).map do |p|
          [p['y'].round, p['z'].round, p['od'].round(1), p['ins'].to_f.round, p['pid']]
        end
      end

      # Plant Piping redrew +runs+: supports at those pipes, or whose
      # section a changed pipe now crosses, are refitted (one transparent
      # step with the drawing).
      def refit_near(model, runs)
        pids = runs.map(&:persistent_id)
        boxes = runs.filter_map { |r| box(model, r) }
        list = H.supports(model).select do |g, _|
          mine = H.get_json(g, 'pipes', []).map { |p| p['pid'] }
          next true if (mine & pids).any?

          o = H.get_json(g, 'origin')
          next false if boxes.size == runs.size && boxes.none? { |mn, mx| (0..2).all? { |i| o[i].between?(mn[i] - NEAR, mx[i] + NEAR) } }

          x = H.get_json(g, 'xdir')
          Link.pipes_across(model, o, x, reach: Pipes::WIDTH, rise: 1500.0).any? { |p| pids.include?(p[:pid]) }
        end
        return 0 if list.empty? || @refitting

        n = 0
        @refitting = true # what we do to Plant Piping's hangers does not come back here
        model.start_operation('Steel Supports: ปรับตามท่อ', true, false, true)
        list.each do |g, _|
          n += 1 if refit(model, g, op: false) == :done
        rescue StandardError => e
          puts "Steel Supports: #{g.get_attribute(H::DICT, 'number')} not refitted – #{e.message}"
        end
        model.commit_operation
        n
      ensure
        @refitting = false
      end
    end
  end
end
