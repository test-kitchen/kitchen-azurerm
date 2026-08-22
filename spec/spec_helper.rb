# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "simplecov"

SimpleCov.start do
  add_filter "/spec/"
  enable_coverage :branch
  # Only enforce the floor on a full-suite run; running a single spec file
  # legitimately covers far less than the whole driver.
  # The only uncovered branches are the `require "x" unless defined?(X)` guards
  # at the top of each file, which cannot both be taken in one process. There
  # are 16 of them, so 92% is the practical ceiling.
  minimum_coverage(line: 100, branch: 92) if ARGV.grep(/_spec\.rb/).empty?
end

require "stringio"
require "tmpdir"
require "json"
require "webmock/rspec"

require "kitchen"
require "kitchen/transport/dummy"

require_relative "../lib/kitchen/driver/azurerm"

Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |file| require file }

RSpec.configure do |config|
  config.disable_monkey_patching!

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
    expectations.syntax = :expect
    expectations.max_formatted_output_length = 400
  end

  config.mock_with :rspec do |mocks|
    # Fail loudly when a double is asked to stand in for a method the real
    # object does not have. This is the single most valuable RSpec setting.
    mocks.verify_partial_doubles = true
    mocks.verify_doubled_constant_names = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = ".rspec_status"
  config.default_formatter = "doc" if config.files_to_run.one?
  config.order = :random
  Kernel.srand config.seed

  config.raise_errors_for_deprecations!

  config.include EnvHelper
  config.include DriverHelper
  config.include AzureDoubles

  # Restore the process environment after every example, so specs can set
  # variables directly without leaking into their neighbours.
  config.around do |example|
    original_env = ENV.to_h
    begin
      example.run
    ensure
      ENV.replace(original_env)
    end
  end

  # Point HOME at an empty directory so that no example can accidentally read
  # the credentials of whoever is running the suite.
  config.around do |example|
    Dir.mktmpdir("kitchen-azurerm-home") do |home|
      ENV["HOME"] = home
      ENV.delete_if { |key, _| key.start_with?("AZURE_") }
      example.run
    end
  end

  # Silence Test Kitchen's logger. Examples that assert on log output replace
  # it with their own StringIO-backed logger.
  config.before do
    Kitchen.logger = Kitchen::Logger.new(stdout: StringIO.new, level: :fatal, colorize: false)
  end
end
