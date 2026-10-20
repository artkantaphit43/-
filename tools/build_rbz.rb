# frozen_string_literal: true

# Packages each extension in src/ into dist/<id>-<version>.rbz (an .rbz is
# a zip of the loader .rb plus its folder). Uses the system `zip` command
# so no gems are needed.
#   ruby tools/build_rbz.rb                       # both extensions
#   ruby tools/build_rbz.rb artk_steel_support    # one of them
require 'fileutils'

root = File.expand_path('..', __dir__)
src = File.join(root, 'src')
dist = File.join(root, 'dist')
EXTENSIONS = { 'artk_plant_pipe' => 'PlantPipe', 'artk_steel_support' => 'SteelSupport' }.freeze

FileUtils.mkdir_p(dist)
(ARGV.empty? ? EXTENSIONS.keys : ARGV).each do |id|
  mod = EXTENSIONS.fetch(id) { abort("unknown extension #{id}") }
  require File.join(src, id, 'version')
  version = ArtK.const_get(mod)::VERSION
  out = File.join(dist, "#{id}-#{version}.rbz")
  FileUtils.rm_f(out)
  Dir.chdir(src) do
    files = ["#{id}.rb"] + Dir.glob("#{id}/**/*").select { |f| File.file?(f) }.sort
    system('zip', '-q', '-X', out, *files) or abort('zip failed – is the zip command installed?')
  end
  puts "Built #{out} (#{File.size(out)} bytes)"
end
