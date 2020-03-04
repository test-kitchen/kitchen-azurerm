require "inifile"

module Kitchen
  module Driver
    #
    # AzureCredentials
    #
    class AzureCredentials
      CONFIG_PATH = "#{ENV["HOME"]}/.azure/credentials".freeze

      #
      # @return [String]
      #
      attr_reader :subscription_id

      #
      # @return [String]
      #
      attr_reader :environment

      #
      # Creates and initializes a new instance of the Credentials class.
      #
      def initialize(subscription_id:, environment: "Azure")
        @subscription_id = subscription_id
        @environment = environment
        config_file = ENV["AZURE_CONFIG_FILE"] || File.expand_path(CONFIG_PATH)
        if File.file?(config_file)
          @credentials = IniFile.load(File.expand_path(config_file))
        else
          warn "#{CONFIG_PATH} was not found or not accessible."
        end
      end

      #
      # Retrieves an object containing options and credentials
      #
      # @return [Object] Object that can be supplied along with all Azure client requests.
      #
      def azure_options
        options = { tenant_id: tenant_id,
                    client_id: client_id,
                    client_secret: client_secret,
                    subscription_id: subscription_id,
                    credentials: ::MsRest::TokenCredentials.new(token_provider),
                    active_directory_settings: ad_settings,
                    base_url: endpoint_settings.resource_manager_endpoint_url }

        options
      end

      private

      def tenant_id
        ENV["AZURE_TENANT_ID"] || @credentials[subscription_id]["tenant_id"]
      end

      def client_id
        ENV["AZURE_CLIENT_ID"] || @credentials[subscription_id]["client_id"]
      end

      def client_secret
        ENV["AZURE_CLIENT_SECRET"] || @credentials[subscription_id]["client_secret"]
      end

      def token_provider
        ::MsRestAzure::ApplicationTokenProvider.new(tenant_id, client_id, client_secret, ad_settings)
      end

      #
      # Retrieves a [MsRestAzure::ActiveDirectoryServiceSettings] object representing the AD settings for the given cloud.
      #
      # @return [MsRestAzure::ActiveDirectoryServiceSettings] Settings to be used for subsequent requests
      #
      def ad_settings
        case environment.downcase
        when "azureusgovernment"
          ::MsRestAzure::ActiveDirectoryServiceSettings.get_azure_us_government_settings
        when "azurechina"
          ::MsRestAzure::ActiveDirectoryServiceSettings.get_azure_china_settings
        when "azuregermancloud"
          ::MsRestAzure::ActiveDirectoryServiceSettings.get_azure_german_settings
        when "azure"
          ::MsRestAzure::ActiveDirectoryServiceSettings.get_azure_settings
        end
      end

      #
      # Retrieves a [MsRestAzure::AzureEnvironment] object representing endpoint settings for the given cloud.
      #
      # @return [MsRestAzure::AzureEnvironment] Settings to be used for subsequent requests
      #
      def endpoint_settings
        case environment.downcase
        when "azureusgovernment"
          ::MsRestAzure::AzureEnvironments::AzureUSGovernment
        when "azurechina"
          ::MsRestAzure::AzureEnvironments::AzureChinaCloud
        when "azuregermancloud"
          ::MsRestAzure::AzureEnvironments::AzureGermanCloud
        when "azure"
          ::MsRestAzure::AzureEnvironments::AzureCloud
        end
      end
    end
  end
end
