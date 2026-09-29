# frozen_string_literal: true

# Writes one JSON scene per reference item for tools/refs/thumbs.js, which
# renders the 128 px JPEG previews shown in the library browser:
#   ruby tools/refs/thumbs.rb /tmp/scenes && node tools/refs/thumbs.js /tmp/scenes src/artk_plant_pipe/refs/thumbs

require 'json'
require 'fileutils'
$LOAD_PATH.unshift File.expand_path('../../src', __dir__)
require 'artk_plant_pipe/lib/refs'

ROLE = {
  'galvanized' => [190, 194, 198], 'black_steel' => [74, 78, 84], 'valve_cast' => [58, 70, 102],
  'valve_green' => [118, 186, 118], 'bronze' => [181, 142, 78], 'pvc_blue' => [34, 128, 206],
  'pvc_white' => [236, 236, 230], 'pvc_grey' => [140, 144, 146], 'pp_black' => [52, 52, 54],
  'pvc_clear' => [214, 228, 236], 'steel_ss' => [205, 207, 210]
}.freeze

R = ArtK::PlantPipe::Refs
out = ARGV[0] or abort 'usage: thumbs.rb <scene dir>'
FileUtils.mkdir_p(out)
R.items.each do |it|
  m = R.mesh(it)
  # canonical +Y (stem) shown upward
  vs = m[:verts].map { |x, y, z| [x, -z, y] }
  faces = m[:faces].map do |f|
    c = f[:mat] && R.materials[f[:mat]]&.first(3)
    { l: f[:loops], h: f[:soft].map { |s| s.map { |x| x ? 0 : 1 } }, c: c || ROLE[it['material']] || [200, 200, 200] }
  end
  File.write(File.join(out, "#{R.thumb_name(it)}.json"), JSON.generate(v: vs, f: faces))
end
puts R.items.size
