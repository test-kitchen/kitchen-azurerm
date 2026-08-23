module Kitchen
  module Driver
    module Azure
      # Endpoints for each Azure cloud the driver can target.
      #
      # These used to come from +MsRestAzure2::AzureEnvironments+ and
      # +MsRestAzure2::ActiveDirectoryServiceSettings+. They are stable,
      # published values, so carrying the table ourselves costs a few lines and
      # removes a dependency on a retired SDK.
      module Environments
        # One Azure cloud's endpoints.
        #
        # @!attribute [r] name
        #   @return [String] canonical cloud name, e.g. +"AzureUSGovernment"+.
        # @!attribute [r] resource_manager_url
        #   @return [String] base URL for Azure Resource Manager requests.
        # @!attribute [r] authentication_endpoint
        #   @return [String] Entra ID (Azure AD) token endpoint.
        # @!attribute [r] token_audience
        #   @return [String] audience/resource the access token is requested for.
        Environment = Struct.new(:name, :resource_manager_url, :authentication_endpoint, :token_audience) do
          # The OAuth2 token URL for a tenant in this cloud.
          #
          # @param tenant_id [String]
          # @return [String]
          def token_url(tenant_id)
            "#{authentication_endpoint.chomp("/")}/#{tenant_id}/oauth2/token"
          end
        end

        # Every supported cloud, keyed by its downcased name so that lookups are
        # case-insensitive.
        #
        # @return [Hash{String => Environment}]
        ALL = [
          Environment.new("Azure",
            "https://management.azure.com/",
            "https://login.microsoftonline.com/",
            "https://management.core.windows.net/"),
          Environment.new("AzureUSGovernment",
            "https://management.usgovcloudapi.net",
            "https://login.microsoftonline.us/",
            "https://management.core.usgovcloudapi.net/"),
          Environment.new("AzureChina",
            "https://management.chinacloudapi.cn",
            "https://login.chinacloudapi.cn/",
            "https://management.core.chinacloudapi.cn/"),
          Environment.new("AzureGermanCloud",
            "https://management.microsoftazure.de",
            "https://login.microsoftonline.de/",
            "https://management.core.cloudapi.de/"),
        ].each(&:freeze).to_h { |environment| [environment.name.downcase, environment] }.freeze

        # Looks a cloud up by name.
        #
        # @param name [String] cloud name, case-insensitive.
        # @return [Environment]
        # @raise [Kitchen::UserError] if the name is not a known Azure cloud.
        def self.fetch(name)
          ALL.fetch(name.to_s.downcase) do
            raise Kitchen::UserError,
              "Unknown azure_environment '#{name}'. Valid values are: #{names.join(", ")} (case-insensitive)."
          end
        end

        # @return [Array<String>] the canonical name of every supported cloud.
        def self.names
          ALL.values.map(&:name)
        end
      end
    end
  end
end
