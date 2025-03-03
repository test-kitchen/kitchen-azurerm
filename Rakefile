require "bundler/gem_tasks"
require "rspec/core/rake_task"
RSpec::Core::RakeTask.new(:test)

begin
  require "cookstyle/chefstyle"
  require "rubocop/rake_task"
  RuboCop::RakeTask.new(:style) do |task|
    task.options += ["--display-cop-names", "--no-color"]
  end
rescue LoadError
  puts "cookstyle/chefstyle is not available. (sudo) gem install cookstyle to do style checking."
end

task default: %i{test style}
