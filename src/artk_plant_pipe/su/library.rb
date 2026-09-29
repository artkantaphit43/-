# frozen_string_literal: true

require 'json'
require 'fileutils'

module ArtK
  module PlantPipe
    # User component library: use real valve models (e.g. from a
    # manufacturer / 3D Warehouse / your own VALVEDATABASE.skp) instead of
    # the built-in parametric shapes.
    #
    # Registering a model stores:
    #   * the component as its own .skp in the library folder
    #   * its inlet and outlet connection centres (picked by the user, in the
    #     component's own coordinates) → flow axis, pipe axis, face-to-face
    #   * which of its axes is "up" (stem direction)
    #   * the pipe size it is valid for, or nil = every size (scaled)
    # Placing it maps inlet/outlet exactly onto the pipe axis, stem up, and
    # scales uniformly so its face-to-face equals ASME B16.10 for the size
    # (exact-size models are used at 1:1).
    module Library
      H = ModelHelpers
      INDEX = 'index.json'

      module_function

      def dir
        d = File.join(Dir.home, 'PlantPipingLibrary')
        FileUtils.mkdir_p(d)
        d
      end

      def entries
        path = File.join(dir, INDEX)
        return [] unless File.exist?(path)

        JSON.parse(File.read(path, encoding: 'UTF-8'))
      rescue StandardError
        []
      end

      def save_entries(list)
        File.write(File.join(dir, INDEX), JSON.pretty_generate(list), encoding: 'UTF-8')
      end

      # Best entry for a valve type & size: exact size first, then "all sizes".
      def find(type, size)
        list = entries.select { |e| e['type'] == type && File.exist?(File.join(dir, e['file'])) }
        list.find { |e| e['size'] == size } || list.find { |e| e['size'].nil? }
      end

      # Register +defn+ (a ComponentDefinition). inlet/outlet/up are in the
      # definition's local coordinates (mm / unit vector).
      def register(defn, type:, size:, inlet:, outlet:, up:)
        raise 'จุดเข้า-ออกต้องห่างกันอย่างน้อย 10 mm (inlet/outlet too close)' if Vec.dist(inlet, outlet) < 10.0

        f = Vec.unit(Vec.sub(outlet, inlet))
        u = Vec.sub(up, Vec.scale(f, Vec.dot(up, f)))
        raise 'ทิศขึ้นต้องไม่ขนานกับแนวท่อ (up axis parallel to flow)' if Vec.length(u) < 0.1

        stamp = Time.now.strftime('%Y%m%d%H%M%S')
        file = "#{type}_#{(size || 'all').gsub(/[^0-9A-Za-z]+/, '_')}_#{stamp}.skp"
        path = File.join(dir, file)
        ok = defn.save_as(path)
        raise "บันทึกโมเดลไม่ได้ (could not save #{path})" if ok == false || !File.exist?(path)

        list = entries.reject { |e| e['type'] == type && e['size'] == size }
        list << { 'type' => type, 'size' => size, 'file' => file, 'name' => defn.name,
                  'inlet' => inlet, 'outlet' => outlet, 'up' => Vec.unit(u) }
        save_entries(list)
        list.last
      end

      def remove(entry)
        save_entries(entries.reject { |e| e['file'] == entry['file'] })
        FileUtils.rm_f(File.join(dir, entry['file']))
      end

      # Transformation placing +entry+'s model at +at+ (mm, run-local) along
      # unit +dir+ with its up axis on unit +up+, scaled to +length+ (mm).
      def transform(entry, at, dir, up, length)
        inlet = entry['inlet']
        outlet = entry['outlet']
        f = Vec.unit(Vec.sub(outlet, inlet))
        u = Vec.unit(entry['up'])
        s = Vec.cross(u, f)
        c = Vec.lerp(inlet, outlet, 0.5)
        k = length ? length / Vec.dist(inlet, outlet) : 1.0
        local = Geom::Transformation.axes(Geom::Point3d.new(0, 0, 0), H.to_vec(f), H.to_vec(s), H.to_vec(u))
        world = H.frame_transform(Mesh.frame(at, dir, Vec.cross(up, dir)))
        world * Geom::Transformation.scaling(k) * local.inverse *
          Geom::Transformation.translation(Geom::Vector3d.new(*c.map { |v| -H.mm(v) }))
      end

      def load_definition(model, entry)
        model.definitions.load(File.join(dir, entry['file']))
      end
    end

    # Tool: select one component, then click its inlet and outlet centres.
    class RegisterModelTool
      H = ModelHelpers

      def activate
        @model = Sketchup.active_model
        @inst = @model.selection.find { |e| e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group) }
        unless @inst
          UI.messagebox("เลือกโมเดลวาล์ว 1 ชิ้น (Component) ก่อน แล้วค่อยเรียกคำสั่งนี้\n" \
                        "(select one valve component first)\n\n" \
                        'ทิป: เปิด VALVEDATABASE.skp → คัดลอกวาล์ว → วางในโมเดลนี้ → เลือก → เรียกคำสั่ง')
          return @model.select_tool(nil)
        end
        @ip = Sketchup::InputPoint.new
        @pts = []
        status
      end

      def onMouseMove(_f, x, y, view)
        @ip.pick(view, x, y)
        view.tooltip = @ip.tooltip
        view.invalidate
      end

      def onLButtonDown(_f, _x, _y, view)
        return unless @ip.valid?

        @pts << @ip.position
        if @pts.size == 2
          finish
          return @model.select_tool(nil)
        end
        status
        view.invalidate
      end

      def draw(view)
        @ip.draw(view) if @ip.valid? && @ip.display?
        view.draw_points(@pts, 12, 4, Sketchup::Color.new(220, 0, 0)) unless @pts.empty?
      end

      def onCancel(_r, _view)
        @model.select_tool(nil)
      end

      private

      def status
        Sketchup.status_text = @pts.empty? ? 'คลิกจุดศูนย์กลางหน้าแปลน/ปลายต่อ ด้านขาเข้า (inlet centre)' :
                                             'คลิกจุดศูนย์กลางด้านขาออก (outlet centre)'
      end

      def finish
        types = FittingsData::VALVES.keys
        names = types.map { |t| "#{t} – #{FittingsData::VALVES[t][:th]}" }
        sizes = ['ทุกขนาด (all sizes, scaled)'] + Catalog.all.values.flat_map { |c| c[:sizes].map { |z| z[:size] } }.uniq
        ups = ['+Z (blue)', '+Y (green)', '+X (red)', '-Z', '-Y', '-X']
        res = UI.inputbox(['ชนิดวาล์ว (valve type)', 'ใช้กับขนาด (size)', 'ทิศก้านวาล์วของโมเดล (stem axis)'],
                          [names.first, sizes.first, ups.first],
                          [names.join('|'), sizes.join('|'), ups.join('|')], 'Register valve model')
        return unless res

        type = types[names.index(res[0])]
        size = res[1] == sizes.first ? nil : res[1]
        up = { '+Z (blue)' => [0, 0, 1], '+Y (green)' => [0, 1, 0], '+X (red)' => [1, 0, 0],
               '-Z' => [0, 0, -1], '-Y' => [0, -1, 0], '-X' => [-1, 0, 0] }[res[2]]
        @inst = @inst.to_component if @inst.is_a?(Sketchup::Group)
        world = H.edit_transform(@model) * @inst.transformation
        inv = world.inverse
        inlet = H.from_pt(@pts[0].transform(inv))
        outlet = H.from_pt(@pts[1].transform(inv))
        e = Library.register(@inst.definition, type: type, size: size, inlet: inlet, outlet: outlet,
                                               up: up.map(&:to_f))
        UI.messagebox("บันทึกโมเดลแล้ว: #{e['name']} → #{FittingsData::VALVES[type][:name]} " \
                      "(#{size || 'ทุกขนาด'})\nวาล์วชนิดนี้ที่ใส่ต่อจากนี้ และที่ Rebuild จะใช้โมเดลนี้\n" \
                      "#{Library.dir}")
      rescue StandardError => ex
        UI.messagebox("Plant Piping: ลงทะเบียนโมเดลไม่สำเร็จ\n#{ex.message}")
      end
    end
  end
end
