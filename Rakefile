require "bundler/gem_tasks"
require "rubocop/rake_task"
require "chefstyle"

RuboCop::RakeTask.new

task default: [:rubocop]

begin
  require_relative "../rake_tasks"
  Kitchen::RakeTasks.new
rescue LoadError
  puts ">>>>> Kitchen gem not loaded, omitting tasks' unless ENV['CI']"
end
