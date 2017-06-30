require 'inifile'

module Kitchen
  module Driver
    #
    # Credentials
    #
    class Credentials
      CONFIG_PATH = "#{ENV['HOME']}/.azure/credentials".freeze

      #
      # Creates and initializes a new instance of the Credentials class.
      #
      def initialize
        config_file = ENV['AZURE_CONFIG_FILE'] || File.expand_path(CONFIG_PATH)
        if File.file?(config_file)
          @credentials = IniFile.load(File.expand_path(config_file))
        else
          warn "#{CONFIG_PATH} was not found or not accessible."
        end
      end

      #
      # Retrieves a [MsRest::TokenCredentials] object representing a token for the given Service Principal.
      # @param subscription_id [String] The subscription_id to retrieve a token for
      #
      # @return [MsRest::TokenCredentials] TokenCredentials object to be passed in with each subsequent request.
      #
      def azure_credentials_for_subscription(subscription_id, azure_environment)
        tenant_id = ENV['AZURE_TENANT_ID'] || @credentials[subscription_id]['tenant_id']
        client_id = ENV['AZURE_CLIENT_ID'] || @credentials[subscription_id]['client_id']
        client_secret = ENV['AZURE_CLIENT_SECRET'] || @credentials[subscription_id]['client_secret']
        token_provider = ::MsRestAzure::ApplicationTokenProvider.new(tenant_id, client_id, client_secret, settings_for_azure_environment(azure_environment))
        ::MsRest::TokenCredentials.new(token_provider)
      end

      #
      # Retrieves a [MsRestAzure::ActiveDirectoryServiceSettings] object representing the settings for the given cloud.
      # @param azure_environment [String] The Azure environment to retrieve settings for.
      #
      # @return [MsRestAzure::ActiveDirectoryServiceSettings] Settings to be used for subsequent requests
      #
      def settings_for_azure_environment(azure_environment)
        case azure_environment.downcase
        when 'azureusgovernment'
          ::MsRestAzure::ActiveDirectoryServiceSettings.get_azure_us_government_settings
        when 'azurechina'
          ::MsRestAzure::ActiveDirectoryServiceSettings.get_azure_china_settings
        when 'azuregermancloud'
          ::MsRestAzure::ActiveDirectoryServiceSettings.get_azure_german_settings
        when 'azure'
          ::MsRestAzure::ActiveDirectoryServiceSettings.get_azure_settings
        end
      end

      def self.singleton
        @credentials ||= Credentials.new
      end
    end
  end
end
