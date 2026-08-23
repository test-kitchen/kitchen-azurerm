require "json" unless defined?(JSON)
require "uri" unless defined?(URI)

require_relative "errors"
require_relative "http"

module Kitchen
  module Driver
    module Azure
      # A minimal Azure Resource Manager client covering exactly the operations
      # this driver performs.
      #
      # Replaces +azure_mgmt_resources2+, +azure_mgmt_network2+, +ms_rest2+ and
      # +ms_rest_azure2+, which are forks of Microsoft's retired Azure SDK for
      # Ruby. Responses are returned as parsed JSON, so callers see ARM's own
      # camelCase property names rather than the SDK's generated model objects.
      class ArmClient
        # ARM API version used for resource group and deployment requests.
        #
        # @return [String]
        RESOURCES_API_VERSION = "2025-04-01".freeze

        # ARM API version used for network resource requests.
        #
        # @return [String]
        NETWORK_API_VERSION = "2025-07-01".freeze

        # ARM API version used for compute resource requests. Matches the
        # version the bundled deployment templates declare for virtual
        # machines.
        #
        # @return [String]
        COMPUTE_API_VERSION = "2025-04-01".freeze

        # @param subscription_id [String]
        # @param environment [Environments::Environment]
        # @param token_provider [TokenProvider]
        def initialize(subscription_id:, environment:, token_provider:)
          @subscription_id = subscription_id
          @environment = environment
          @token_provider = token_provider
        end

        # @return [String]
        attr_reader :subscription_id

        # @return [Environments::Environment]
        attr_reader :environment

        # @return [TokenProvider]
        attr_reader :token_provider

        # Whether a resource group exists.
        #
        # @param name [String] resource group name, case-insensitive.
        # @return [Boolean]
        def resource_group_exists?(name)
          response = call(:head, resource_group_path(name), api_version: RESOURCES_API_VERSION, allow: [404])
          response.status != 404
        end

        # Creates or updates a resource group.
        #
        # @param name [String] resource group name.
        # @param location [String] Azure region.
        # @param tags [Hash] resource tags.
        # @return [Hash] the resource group as ARM returned it.
        def create_or_update_resource_group(name, location:, tags: {})
          call(:put, resource_group_path(name),
            api_version: RESOURCES_API_VERSION,
            body: { "location" => location, "tags" => tags || {} }).json
        end

        # Requests deletion of a resource group, returning as soon as ARM
        # accepts the request rather than waiting for it to finish.
        #
        # @param name [String] resource group name.
        # @return [void]
        def delete_resource_group(name)
          call(:delete, resource_group_path(name), api_version: RESOURCES_API_VERSION)
          nil
        end

        # Submits a deployment, returning once ARM accepts it.
        #
        # @param resource_group [String]
        # @param name [String] deployment name.
        # @param deployment [Hash] the deployment body, as built by the driver.
        # @return [Hash] the deployment as ARM returned it.
        def create_deployment(resource_group, name, deployment)
          call(:put, deployment_path(resource_group, name),
            api_version: RESOURCES_API_VERSION,
            body: deployment).json
        end

        # Reads a deployment.
        #
        # @param resource_group [String]
        # @param name [String] deployment name.
        # @return [Hash]
        def deployment(resource_group, name)
          call(:get, deployment_path(resource_group, name), api_version: RESOURCES_API_VERSION).json
        end

        # Lists every operation belonging to a deployment.
        #
        # @param resource_group [String]
        # @param name [String] deployment name.
        # @return [Array<Hash>]
        def deployment_operations(resource_group, name)
          payload = call(:get, "#{deployment_path(resource_group, name)}/operations",
            api_version: RESOURCES_API_VERSION).json

          payload.is_a?(Hash) ? Array(payload["value"]) : []
        end

        # Reads a virtual machine's instance view, which carries its current
        # power state.
        #
        # @param resource_group [String]
        # @param name [String] virtual machine name.
        # @return [Hash]
        def virtual_machine_instance_view(resource_group, name)
          call(:get, "#{compute_path(resource_group, "virtualMachines", name)}/instanceView",
            api_version: COMPUTE_API_VERSION).json
        end

        # Reads a public IP address resource.
        #
        # @param resource_group [String]
        # @param name [String] public IP resource name.
        # @return [Hash]
        def public_ip(resource_group, name)
          call(:get, network_path(resource_group, "publicIPAddresses", name),
            api_version: NETWORK_API_VERSION).json
        end

        # Reads a network interface resource.
        #
        # @param resource_group [String]
        # @param name [String] network interface name.
        # @return [Hash]
        def network_interface(resource_group, name)
          call(:get, network_path(resource_group, "networkInterfaces", name),
            api_version: NETWORK_API_VERSION).json
        end

        private

        # @param name [String]
        # @return [String]
        def resource_group_path(name)
          "/subscriptions/#{subscription_id}/resourcegroups/#{escape(name)}"
        end

        # @param resource_group [String]
        # @param name [String]
        # @return [String]
        def deployment_path(resource_group, name)
          "#{resource_group_path(resource_group)}/providers/Microsoft.Resources/deployments/#{escape(name)}"
        end

        # @param resource_group [String]
        # @param type [String] e.g. +"publicIPAddresses"+.
        # @param name [String]
        # @return [String]
        def network_path(resource_group, type, name)
          "#{resource_group_path(resource_group)}/providers/Microsoft.Network/#{type}/#{escape(name)}"
        end

        # @param resource_group [String]
        # @param type [String] e.g. +"virtualMachines"+.
        # @param name [String]
        # @return [String]
        def compute_path(resource_group, type, name)
          "#{resource_group_path(resource_group)}/providers/Microsoft.Compute/#{type}/#{escape(name)}"
        end

        # @param value [String]
        # @return [String] path-escaped
        def escape(value)
          URI::DEFAULT_PARSER.escape(value.to_s)
        end

        # Performs an authenticated ARM request.
        #
        # @param method [Symbol]
        # @param path [String] path below the resource manager URL.
        # @param api_version [String]
        # @param body [Hash, nil] request body, serialized as JSON.
        # @param allow [Array<Integer>] non-2xx statuses to treat as success.
        # @return [Http::Response]
        # @raise [OperationError] when ARM returns an unexpected status.
        def call(method, path, api_version:, body: nil, allow: [])
          url = "#{environment.resource_manager_url.chomp("/")}#{path}?api-version=#{api_version}"
          headers = {
            "Authorization" => token_provider.authorization_header,
            "Accept" => "application/json",
            "User-Agent" => "kitchen-azurerm/#{Kitchen::Driver::AZURERM_VERSION}",
          }
          headers["Content-Type"] = "application/json" if body

          response = Http.request(method:, url:, headers:, body: body && JSON.generate(body))
          return response if response.success? || allow.include?(response.status)

          raise OperationError.new(
            "Azure returned HTTP #{response.status} for #{method.to_s.upcase} #{path}",
            status: response.status,
            body: error_body(response)
          )
        end

        # @param response [Http::Response]
        # @return [Hash] the parsed error body, or a synthesized one.
        def error_body(response)
          parsed = response.json
          return parsed if parsed.is_a?(Hash) && parsed.key?("error")

          { "error" => { "code" => "Unknown", "message" => response.body.to_s } }
        end
      end
    end
  end
end
