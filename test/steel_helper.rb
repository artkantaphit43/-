# frozen_string_literal: true

# Steel Supports TH test setup: its core library, and (for the SketchUp
# layer) the SketchUp stub with Plant Piping loaded beside it.
require_relative 'test_helper'

SS_ROOT = File.expand_path('../src/artk_steel_support', __dir__)
%w[vec mesh steel hardware beam pipes details std].each { |f| require File.join(SS_ROOT, 'lib', f) }
SS = ArtK::SteelSupport

module SteelSU
  module_function

  def load!
    return if @loaded

    require_relative 'su_stub'
    ArtK::PlantPipe.const_set(:PLUGIN_ROOT, File.expand_path('../src/artk_plant_pipe', __dir__)) unless defined?(ArtK::PlantPipe::PLUGIN_ROOT)
    ArtK::PlantPipe.const_set(:VERSION, 'test') unless defined?(ArtK::PlantPipe::VERSION)
    %w[model_helpers migrate builder ref_models ref_builder support_builder collector picker reports commands pipe_tool
       support_tool api].each { |f| require File.expand_path("../src/artk_plant_pipe/su/#{f}", __dir__) }
    ArtK::SteelSupport.const_set(:PLUGIN_ROOT, SS_ROOT) unless defined?(ArtK::SteelSupport::PLUGIN_ROOT)
    require File.join(SS_ROOT, 'version')
    %w[helpers link probe generic planner placer builder place_tool report commands dialog].each do |f|
      require File.join(SS_ROOT, 'su', f)
    end
    @loaded = true
  end

  # Ray tests against boxes [[min], [max]] and cylinders
  # { axis: 0 (x) / 1 (y), c: [a, b] (the other two coordinates), r:, range: [lo, hi] } (mm).
  def rays(boxes: [], cyls: [])
    lambda do |pt, dir|
      ts = boxes.filter_map { |b| box_t(pt, dir, *b) } + cyls.filter_map { |c| cyl_t(pt, dir, c) }
      t = ts.min
      t && [pt.each_with_index.map { |v, i| v + dir[i] * t }, []]
    end
  end

  def box_t(pt, dir, mn, mx)
    t0 = -Float::INFINITY
    t1 = Float::INFINITY
    3.times do |i|
      if dir[i].abs < 1e-12
        return nil unless pt[i].between?(mn[i], mx[i])
      else
        a = (mn[i] - pt[i]) / dir[i]
        b = (mx[i] - pt[i]) / dir[i]
        a, b = b, a if a > b
        t0 = [t0, a].max
        t1 = [t1, b].min
        return nil if t0 > t1
      end
    end
    t = t0 > 1e-6 ? t0 : t1
    t > 1e-6 ? t : nil
  end

  def cyl_t(pt, dir, c)
    ax = c[:axis]
    i, j = [0, 1, 2] - [ax]
    px = pt[i] - c[:c][0]
    pz = pt[j] - c[:c][1]
    dx = dir[i]
    dz = dir[j]
    a = dx * dx + dz * dz
    return nil if a < 1e-12

    b = 2 * (px * dx + pz * dz)
    cc = px * px + pz * pz - c[:r]**2
    disc = b * b - 4 * a * cc
    return nil if disc.negative?

    [(-b - Math.sqrt(disc)) / (2 * a), (-b + Math.sqrt(disc)) / (2 * a)].sort.find do |t|
      next false unless t > 1e-6

      along = pt[ax] + dir[ax] * t
      c[:range].nil? || along.between?(*c[:range])
    end
  end

  def pipe(y, z, od, ins = 0.0, label = 'p')
    { y: y.to_f, z: z.to_f, od: od.to_f, ins: ins.to_f, r: od / 2.0 + ins, kg_m: SS::Pipes.generic_kg_m(od, ins),
      span_m: SS::Pipes.default_span_m(od), label: label }
  end
end
