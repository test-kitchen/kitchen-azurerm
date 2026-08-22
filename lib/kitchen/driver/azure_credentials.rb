require "inifile"

require "kitchen/errors"
require "kitchen/logging"
autoload :MsRest2, "ms_rest2"
autoload :MsRestAzure2, "ms_rest_azure2"

module Kitchen
  module Driver
    # Resolves Azure Resource Manager credentials and endpoint settings for a
    # single subscription.
    #
    # Credentials are sourced, in order of precedence, from environment
    # variables (+AZURE_TENANT_ID+, +AZURE_CLIENT_ID+, +AZURE_CLIENT_SECRET+)
    # and then from the Azure CLI credentials INI file (by default
    # +~/.azure/credentials+, overridable with +AZURE_CONFIG_FILE+).
    #
    # The combination of values that resolve determines which token provider is
    # used - see {#azure_options}.
    #
    # @example Service principal supplied by environment
    #   ENV["AZURE_TENANT_ID"]     = "..."
    #   ENV["AZURE_CLIENT_ID"]     = "..."
    #   ENV["AZURE_CLIENT_SECRET"] = "..."
    #   options = Kitchen::Driver::AzureCredentials.new(subscription_id: "...").azure_options
    class AzureCredentials
      include Kitchen::Logging

      # Path fragment, relative to the user's home directory, of the Azure CLI
      # credentials file.
      #
      # @return [String]
      CONFIG_FILE = File.join(".azure", "credentials").freeze

      # Azure cloud names understood by {#azure_options}, mapped to the
      # +MsRestAzure2+ constants that describe them. Keys are downcased so
      # lookups are case-insensitive.
      #
      # @return [Hash{String => Symbol}]
      ENVIRONMENTS = {
        "azure" => :Azure,
        "azurechina" => :AzureChina,
        "azuregermancloud" => :AzureGermanCloud,
        "azureusgovernment" => :AzureUSGovernment,
      }.freeze

      # Port the Azure Instance Metadata Service listens on for MSI token requests.
      #
      # @return [Integer]
      MSI_PORT = 50342

      # The Azure subscription these credentials authenticate against.
      #
      # @return [String]
      attr_reader :subscription_id

      # The Azure cloud name, e.g. +"Azure"+ or +"AzureUSGovernment"+.
      #
      # @return [String]
      attr_reader :environment

      # Default path of the Azure CLI credentials file.
      #
      # Resolved lazily (rather than at load time) so that a test - or a caller
      # that manipulates +HOME+ - sees the current home directory rather than
      # whichever one happened to be set when this file was first required.
      #
      # @return [String] absolute path to +~/.azure/credentials+
      def self.default_config_path
        File.join(Dir.home, CONFIG_FILE)
      end

      # @param subscription_id [String] the Azure subscription to authenticate against.
      # @param environment [String] the Azure cloud name. Case-insensitive.
      # @raise [Kitchen::UserError] if +environment+ is not a known Azure cloud.
      def initialize(subscription_id:, environment: "Azure")
        @subscription_id = subscription_id
        @environment = environment || "Azure"

        unless ENVIRONMENTS.key?(@environment.to_s.downcase)
          raise Kitchen::UserError,
            "Unknown azure_environment '#{@environment}'. Valid values are: #{ENVIRONMENTS.keys.join(", ")} (case-insensitive)."
        end
      end

      # Builds the options hash accepted by every +azure_mgmt_*2+ client.
      #
      # The +:credentials+ entry wraps whichever token provider matches the
      # resolved credentials - see {#token_provider}. +:client_id+ and
      # +:client_secret+ are only included when they resolve to a value.
      #
      # @return [Hash] options suitable for
      #   +Azure::Resources2::Profiles::Latest::Mgmt::Client.new+ and friends.
      def azure_options
        options = { tenant_id: tenant_id!,
                    subscription_id:,
                    credentials: ::MsRest2::TokenCredentials.new(token_provider),
                    active_directory_settings: ad_settings,
                    base_url: endpoint_settings.resource_manager_endpoint_url }
        options[:client_id] = client_id if client_id
        options[:client_secret] = client_secret if client_secret
        options
      end

      # Selects a token provider based on which credentials resolved.
      #
      # * +client_id+ + +client_secret+ + +tenant_id+ - service principal.
      # * +client_id+ + +tenant_id+ - user-assigned managed identity.
      # * +tenant_id+ only - system-assigned managed identity.
      # * none of the above - falls back to the +az login+ token cache.
      #
      # @return [MsRestAzure2::ApplicationTokenProvider,
      #   MsRestAzure2::MSITokenProvider, MsRestAzure2::AzureCliTokenProvider]
      def token_provider
        if client_id && client_secret && tenant_id
          ::MsRestAzure2::ApplicationTokenProvider.new(tenant_id, client_id, client_secret, ad_settings)
        elsif client_id && tenant_id
          ::MsRestAzure2::MSITokenProvider.new(MSI_PORT, ad_settings, { client_id: })
        elsif tenant_id
          ::MsRestAzure2::MSITokenProvider.new(MSI_PORT, ad_settings)
        else
          warn("Using tenant id set through `az login`.")
          ::MsRestAzure2::AzureCliTokenProvider.new(ad_settings)
        end
      end

      # Active Directory settings for the configured cloud.
      #
      # @return [MsRestAzure2::ActiveDirectoryServiceSettings]
      def ad_settings
        case environment_key
        when :AzureUSGovernment then ::MsRestAzure2::ActiveDirectoryServiceSettings.get_azure_us_government_settings
        when :AzureChina        then ::MsRestAzure2::ActiveDirectoryServiceSettings.get_azure_china_settings
        when :AzureGermanCloud  then ::MsRestAzure2::ActiveDirectoryServiceSettings.get_azure_german_settings
        else ::MsRestAzure2::ActiveDirectoryServiceSettings.get_azure_settings
        end
      end

      # Endpoint settings (resource manager URL, storage suffixes, ...) for the
      # configured cloud.
      #
      # @return [MsRestAzure2::AzureEnvironment]
      def endpoint_settings
        case environment_key
        when :AzureUSGovernment then ::MsRestAzure2::AzureEnvironments::AzureUSGovernment
        when :AzureChina        then ::MsRestAzure2::AzureEnvironments::AzureChinaCloud
        when :AzureGermanCloud  then ::MsRestAzure2::AzureEnvironments::AzureGermanCloud
        else ::MsRestAzure2::AzureEnvironments::AzureCloud
        end
      end

      # Path of the credentials file actually in use.
      #
      # @return [String] +AZURE_CONFIG_FILE+ if set, otherwise
      #   {.default_config_path}. Always expanded.
      def config_path
        @config_path ||= File.expand_path(ENV["AZURE_CONFIG_FILE"] || self.class.default_config_path)
      end

      private

      # @return [Symbol] the {ENVIRONMENTS} key for the configured cloud.
      def environment_key
        ENVIRONMENTS.fetch(environment.to_s.downcase)
      end

      # @return [Kitchen::Logger] the shared Test Kitchen logger.
      def logger
        Kitchen.logger
      end

      # Parsed credentials file, or an empty Hash when no readable file exists.
      #
      # @return [IniFile, Hash]
      def credentials
        @credentials ||= if File.file?(config_path)
                           IniFile.load(config_path)
                         else
                           debug "#{config_path} was not found or not accessible."
                           {}
                         end
      end

      # Reads a property from the section of the credentials file matching
      # {#subscription_id}.
      #
      # @param property [String] the INI key to read.
      # @return [String, nil]
      def credentials_property(property)
        value = credentials[subscription_id]&.[](property)
        value unless value.to_s.empty?
      end

      # Tenant ID, warning the user when one cannot be resolved.
      #
      # @return [String, nil]
      def tenant_id!
        tenant_id || warn("(#{config_path}) does not contain tenant_id neither is the AZURE_TENANT_ID environment variable set.")
      end

      # @return [String, nil] tenant ID from the environment or credentials file.
      def tenant_id
        env_or_credentials("AZURE_TENANT_ID", "tenant_id")
      end

      # @return [String, nil] client ID from the environment or credentials file.
      def client_id
        env_or_credentials("AZURE_CLIENT_ID", "client_id")
      end

      # @return [String, nil] client secret from the environment or credentials file.
      def client_secret
        env_or_credentials("AZURE_CLIENT_SECRET", "client_secret")
      end

      # Reads a value from the environment, falling back to the credentials file.
      #
      # Empty environment variables are treated as unset - an exported-but-blank
      # +AZURE_CLIENT_SECRET+ should not shadow a real value in the file.
      #
      # @param env_var [String] environment variable name.
      # @param property [String] INI property name.
      # @return [String, nil]
      def env_or_credentials(env_var, property)
        value = ENV[env_var]
        return value unless value.to_s.empty?

        credentials_property(property)
      end
    end
  end
end
