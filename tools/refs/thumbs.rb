# frozen_string_literal: true

# Writes one JSON scene per reference item for tools/refs/thumbs.js, which
# renders the 128 px JPEG previews shown in the library browser:
#   ruby tools/refs/thumbs.rb /tmp/scenes && node tools/refs/thumbs.js /tmp/scenes src/artk_plant_pipe/refs/thumbs

require 'json'
require 'fileutils'
$LOAD_PATH.unshift File.expand_path('../../src', __dir__)
require 'artk_plant_pipe/lib/refs'
require 'artk_plant_pipe/lib/finishes'

F = ArtK::PlantPipe::Finishes
# Realistic finishes (lib/finishes.rb) – the same colours the plugin paints.
def face_color(f, it)
  if f[:mat]
    fin = F.source(f[:mat], it['material'])
    return [F.rgb(fin), 1.0] if fin

    src = R.materials[f[:mat]]
    return [src.first(3), src[3] || 1.0] if src
  end
  return F::CLEAR if it['material'] == 'pvc_clear'

  fin = F.role(it['material'])
  [fin ? F.rgb(fin) : [200, 200, 200], 1.0]
end

R = ArtK::PlantPipe::Refs
out = ARGV[0] or abort 'usage: thumbs.rb <scene dir>'
FileUtils.mkdir_p(out)
R.items.each do |it|
  m = R.mesh(it)
  # canonical +Y (stem) shown upward; gauges: +X (away from the pipe) up,
  # dial toward the viewer
  map = it['type'] == 'gauge' ? ->(x, y, z) { [z, -y, x] } : ->(x, y, z) { [x, -z, y] }
  vs = m[:verts].map { |x, y, z| map.call(x, y, z) }
  faces = m[:faces].map do |f|
    c, a = face_color(f, it)
    rec = { l: f[:loops], h: f[:soft].map { |s| s.map { |x| x ? 0 : 1 } }, c: c }
    tex = f[:pins] && R.texture_path(f[:mat])
    if tex && File.exist?(tex)
      rec[:t] = "data:image/jpeg;base64,#{[File.binread(tex)].pack('m0')}"
      rec[:p] = f[:pins].map { |(x, y, z), uv| [map.call(x, y, z), uv] }
    end
    # translucent materials (glass, clear tubes)
    rec[:a] = a if a < 1.0
    rec
  end
  File.write(File.join(out, "#{R.thumb_name(it)}.json"), JSON.generate(v: vs, f: faces))
end
puts R.items.size
