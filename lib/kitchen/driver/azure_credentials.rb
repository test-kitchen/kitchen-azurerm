require "inifile"

require "kitchen/errors"
require "kitchen/logging"

require_relative "azure/arm_client"
require_relative "azure/environments"
require_relative "azure/token_provider"

module Kitchen
  module Driver
    # Resolves Azure Resource Manager credentials for a single subscription.
    #
    # Credentials are sourced, in order of precedence, from environment
    # variables (+AZURE_TENANT_ID+, +AZURE_CLIENT_ID+, +AZURE_CLIENT_SECRET+)
    # and then from the Azure CLI credentials INI file (by default
    # +~/.azure/credentials+, overridable with +AZURE_CONFIG_FILE+).
    #
    # The combination of values that resolve determines which token provider is
    # used - see {#token_provider}.
    #
    # @example Service principal supplied by environment
    #   ENV["AZURE_TENANT_ID"]     = "..."
    #   ENV["AZURE_CLIENT_ID"]     = "..."
    #   ENV["AZURE_CLIENT_SECRET"] = "..."
    #   client = Kitchen::Driver::AzureCredentials.new(subscription_id: "...").arm_client
    class AzureCredentials
      include Kitchen::Logging

      # Path fragment, relative to the user's home directory, of the Azure CLI
      # credentials file.
      #
      # @return [String]
      CONFIG_FILE = File.join(".azure", "credentials").freeze

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

        # Validate eagerly so a typo surfaces before any Azure call is made.
        azure_environment
      end

      # An ARM client authenticated with these credentials.
      #
      # @return [Azure::ArmClient]
      def arm_client
        Azure::ArmClient.new(subscription_id:, environment: azure_environment, token_provider:)
      end

      # Endpoints for the configured cloud.
      #
      # +AZURE_AUTHORITY_HOST+ overrides the Entra ID endpoint, which is how
      # platforms that issue federated tokens point at their own authority.
      #
      # @return [Azure::Environments::Environment]
      # @raise [Kitchen::UserError] if the cloud name is not recognised.
      def azure_environment
        @azure_environment ||= Azure::Environments.fetch(environment).with_authority(ENV["AZURE_AUTHORITY_HOST"])
      end

      # Selects a token provider based on which credentials resolved.
      #
      # In precedence order:
      #
      # * +AZURE_FEDERATED_TOKEN_FILE+ + +client_id+ + +tenant_id+ - workload
      #   identity federation, the secretless option for CI.
      # * +client_id+ + +client_secret+ + +tenant_id+ - service principal.
      # * +AZURE_USE_MSI+ - managed identity, explicitly.
      # * +client_id+ without a secret - user-assigned managed identity.
      # * +tenant_id+ only - system-assigned managed identity.
      # * none of the above - falls back to the +az login+ token cache.
      #
      # @return [Azure::TokenProvider]
      def token_provider
        @token_provider ||= build_token_provider
      end

      # Path of the credentials file actually in use.
      #
      # @return [String] +AZURE_CONFIG_FILE+ if set, otherwise
      #   {.default_config_path}. Always expanded.
      def config_path
        @config_path ||= File.expand_path(ENV["AZURE_CONFIG_FILE"] || self.class.default_config_path)
      end

      private

      # @return [Azure::TokenProvider]
      def build_token_provider
        if federated_token_file && client_id && tenant_id
          debug "Authenticating with workload identity federation (#{federated_token_file})."
          Azure::WorkloadIdentityToken.new(environment: azure_environment, tenant_id:, client_id:,
            token_file: federated_token_file)
        elsif client_id && client_secret && tenant_id
          debug "Authenticating as a service principal."
          Azure::ServicePrincipalToken.new(environment: azure_environment, tenant_id:, client_id:, client_secret:)
        elsif use_managed_identity?
          debug "Authenticating as a managed identity."
          Azure::ManagedIdentityToken.new(environment: azure_environment, client_id:)
        elsif tenant_id
          # A tenant with no client credentials means a system-assigned identity.
          debug "Authenticating as a system-assigned managed identity."
          Azure::ManagedIdentityToken.new(environment: azure_environment)
        else
          warn_about_unusable_credentials
          debug "No Azure credentials were configured; using the token cached by `az login`."
          Azure::AzureCliToken.new(environment: azure_environment)
        end
      end

      # Warns when credentials were supplied but cannot be used.
      #
      # Reaching the Azure CLI with nothing configured is a supported way to
      # run the driver, so it passes without comment - warning about it on
      # every create and destroy only taught users to ignore the warnings that
      # matter. Reaching it having half-configured a service principal is a
      # mistake worth interrupting for, because the run is about to
      # authenticate as somebody else entirely.
      #
      # @return [void]
      def warn_about_unusable_credentials
        if partial_credentials?
          warn("Incomplete Azure credentials: no #{missing_credentials.join(" or ")} was found in the " \
               "environment or #{config_path}. Falling back to the credentials from `az login`.")
        elsif credentials_file_without_subscription?
          warn("#{config_path} has no [#{subscription_id}] section. " \
               "Falling back to the credentials from `az login`.")
        end
      end

      # Whether some, but not enough, client credentials were supplied.
      #
      # @return [Boolean]
      def partial_credentials?
        !(client_id.nil? && client_secret.nil? && federated_token_file.nil?)
      end

      # The credential values needed to use what was supplied.
      #
      # @return [Array<String>]
      def missing_credentials
        { "tenant_id" => tenant_id, "client_id" => client_id }.select { |_key, value| value.nil? }.keys
      end

      # Whether a credentials file exists but says nothing about the
      # subscription under test. An empty section is deliberate - it is how a
      # user opts one subscription in to the CLI - so it does not count.
      #
      # @return [Boolean]
      def credentials_file_without_subscription?
        File.file?(config_path) && !credentials.has_section?(subscription_id)
      end

      # Whether to authenticate as a managed identity.
      #
      # A +client_id+ with no accompanying secret means a user-assigned managed
      # identity, which is how the Azure SDKs read the same combination.
      # Crucially this does not require a tenant: the instance metadata service
      # never sees one, so demanding it only prevented the identity from being
      # used at all.
      #
      # @return [Boolean]
      def use_managed_identity?
        return true unless ENV["AZURE_USE_MSI"].to_s.empty?

        !client_id.nil? && client_secret.nil?
      end

      # @return [String, nil] path to a federated token file, if one is configured.
      def federated_token_file
        value = ENV["AZURE_FEDERATED_TOKEN_FILE"]
        value unless value.to_s.empty?
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
      # Reads through +to_h+ rather than +IniFile#[]+, which auto-vivifies:
      # asking an +IniFile+ for a section it does not have *adds* that section.
      # Looking up the credentials of an unconfigured subscription therefore
      # used to leave the parsed file claiming to contain it.
      #
      # @param property [String] the INI key to read.
      # @return [String, nil]
      def credentials_property(property)
        value = credentials.to_h[subscription_id]&.[](property)
        value unless value.to_s.empty?
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
