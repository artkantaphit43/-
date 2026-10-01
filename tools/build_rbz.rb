# frozen_string_literal: true

# Packages src/ into dist/artk_plant_pipe-<version>.rbz (an .rbz is a zip of
# the loader .rb plus its folder). Uses the system `zip` command so no gems
# are needed.  Usage:  ruby tools/build_rbz.rb
require 'fileutils'

root = File.expand_path('..', __dir__)
src = File.join(root, 'src')
dist = File.join(root, 'dist')
require File.join(src, 'artk_plant_pipe', 'version')
version = ArtK::PlantPipe::VERSION

FileUtils.mkdir_p(dist)
out = File.join(dist, "artk_plant_pipe-#{version}.rbz")
FileUtils.rm_f(out)
Dir.chdir(src) do
  files = ['artk_plant_pipe.rb'] + Dir.glob('artk_plant_pipe/**/*').select { |f| File.file?(f) }.sort
  system('zip', '-q', '-X', out, *files) or abort('zip failed – is the zip command installed?')
end
puts "Built #{out} (#{File.size(out)} bytes)"
