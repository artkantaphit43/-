# frozen_string_literal: true

require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.pattern = 'test/test_*.rb'
  t.warning = false
end

desc 'Package the extension as dist/artk_plant_pipe.rbz'
task :package do
  ruby 'tools/build_rbz.rb'
end

task default: :test
