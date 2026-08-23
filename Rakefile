require "bundler/gem_tasks"

require "rspec/core/rake_task"
RSpec::Core::RakeTask.new(:test)
task spec: :test

begin
  require "cookstyle/chefstyle"
  require "rubocop/rake_task"
  RuboCop::RakeTask.new(:style) do |task|
    task.options += ["--display-cop-names", "--no-color"]
  end
rescue LoadError
  puts "cookstyle/chefstyle is not available. (sudo) gem install cookstyle to do style checking."
end

begin
  require "yard"

  YARD::Rake::YardocTask.new(:yard) do |task|
    task.stats_options = ["--list-undoc"]
  end
  desc "Generate YARD documentation into doc/"
  task doc: :yard

  desc "Report YARD documentation coverage without failing"
  task :"yard:stats" do
    sh "yard stats --list-undoc"
  end

  desc "Serve YARD documentation at http://localhost:8808"
  task :"yard:server" do
    sh "yard server --reload"
  end
rescue LoadError
  puts "yard is not available. (sudo) gem install yard to generate documentation."
end

namespace :integration do
  # Deliberately not part of any default task: these deploy real virtual
  # machines into a real subscription, and cost real money.
  desc "Run the integration suites against Azure (requires a subscription)"
  task :test do
    Dir.chdir("integration") { sh "bundle exec kitchen test --concurrency 4" }
  end

  desc "Destroy anything the integration suites left behind"
  task :destroy do
    Dir.chdir("integration") { sh "bundle exec kitchen destroy --concurrency 4" }
  end

  desc "List the integration suites"
  task :list do
    Dir.chdir("integration") { sh "bundle exec kitchen list" }
  end
end

# Documentation is deliberately not part of the default task: missing YARD tags
# should never fail a build.
task default: %i{test style}
