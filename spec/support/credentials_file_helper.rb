require "fileutils"
require "tmpdir"

# Helpers for exercising the real Azure CLI credentials-file parsing path.
#
# These write an actual INI file into a temporary directory and point
# +AZURE_CONFIG_FILE+ at it, so the tests drive +IniFile+ for real rather than
# stubbing +File.file?+ and +IniFile.load+.
module CredentialsFileHelper
  # Subscription ids used by the fixture credentials file, one per
  # authentication shape the driver supports.
  SUBSCRIPTIONS = {
    service_principal: "f02932df-7e1d-410f-b094-c626d447f4dc",
    user_assigned_identity: "5d801ddc-acf4-406b-9830-587ca2c6fd80",
    system_assigned_identity: "7c664d3f-6dca-4e6d-9637-13dadbbe59d3",
    azure_cli: "9f8b8a02-6e6e-4a1c-9d0f-8b3f0c2ec4a1",
  }.freeze

  # Path of the fixture credentials file shipped with the suite.
  #
  # @return [String]
  def fixture_credentials_path
    File.expand_path("../fixtures/azure_credentials", __dir__)
  end

  # Copies the fixture credentials file somewhere writable and points
  # +AZURE_CONFIG_FILE+ at the copy.
  #
  # @return [String] path of the credentials file now in use.
  def use_fixture_credentials_file
    use_credentials_file(File.read(fixture_credentials_path))
  end

  # Writes +content+ to a credentials file and points +AZURE_CONFIG_FILE+ at it.
  #
  # @param content [String] INI content.
  # @return [String] path of the credentials file now in use.
  def use_credentials_file(content)
    path = File.join(tmp_home, "credentials.ini")
    File.write(path, content)
    ENV["AZURE_CONFIG_FILE"] = path
    path
  end

  # Writes the fixture credentials file to the default location under +HOME+,
  # without setting +AZURE_CONFIG_FILE+.
  #
  # @return [String] path of the credentials file now in use.
  def use_default_location_credentials_file
    path = Kitchen::Driver::AzureCredentials.default_config_path
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, File.read(fixture_credentials_path))
    path
  end

  # A scratch directory that lives as long as the example does.
  #
  # @return [String]
  def tmp_home
    ENV.fetch("HOME")
  end
end

RSpec.configure { |config| config.include CredentialsFileHelper }
