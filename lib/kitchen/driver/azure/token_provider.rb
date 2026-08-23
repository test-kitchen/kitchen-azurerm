require "json" unless defined?(JSON)
require "open3" unless defined?(Open3)
require "time" unless defined?(Time.parse)
require "uri" unless defined?(URI)

require_relative "errors"
require_relative "http"

module Kitchen
  module Driver
    module Azure
      # Acquires and caches Entra ID (Azure AD) access tokens for ARM.
      #
      # Replaces the +MsRestAzure2+ token providers. Each subclass knows how to
      # fetch a token one way; the caching and expiry handling is shared.
      class TokenProvider
        # Seconds before actual expiry at which a cached token is considered
        # stale, so a long deployment does not fail mid-flight.
        #
        # @return [Integer]
        EXPIRY_MARGIN = 300

        # @param environment [Environments::Environment] the target cloud.
        def initialize(environment:)
          @environment = environment
          @token = nil
          @expires_at = nil
        end

        # @return [Environments::Environment]
        attr_reader :environment

        # A valid access token, fetching or refreshing one if needed.
        #
        # @return [String]
        def access_token
          return @token if @token && @expires_at && Time.now.to_i < @expires_at - EXPIRY_MARGIN

          @token, @expires_at = fetch_token
          @token
        end

        # The value for the Authorization header.
        #
        # @return [String]
        def authorization_header
          "Bearer #{access_token}"
        end

        # Fetches a fresh token.
        #
        # @return [Array(String, Integer)] the token and its expiry, as a Unix time.
        # @raise [NotImplementedError] subclasses must implement this.
        def fetch_token
          raise NotImplementedError
        end

        private

        # Turns a token endpoint response into a token and expiry pair.
        #
        # @param response [Http::Response]
        # @param source [String] describes the endpoint, for error messages.
        # @return [Array(String, Integer)]
        # @raise [OperationError] if the endpoint did not return a token.
        def token_from(response, source)
          payload = response.json
          unless response.success? && payload.is_a?(Hash) && payload["access_token"]
            raise OperationError.new(
              "Could not acquire an Azure access token from #{source} (HTTP #{response.status}).",
              status: response.status,
              body: payload.is_a?(Hash) ? payload : {}
            )
          end

          [payload["access_token"], expiry_from(payload)]
        end

        # Reads the expiry out of a token response, which spells it differently
        # depending on the endpoint.
        #
        # @param payload [Hash]
        # @return [Integer] Unix time at which the token expires.
        def expiry_from(payload)
          return payload["expires_on"].to_i if payload["expires_on"].to_s.match?(/\A\d+\z/)
          return Time.now.to_i + payload["expires_in"].to_i if payload["expires_in"]

          Time.now.to_i + 3600
        end
      end

      # Authenticates as a service principal, using a client id and secret.
      class ServicePrincipalToken < TokenProvider
        # @param environment [Environments::Environment]
        # @param tenant_id [String]
        # @param client_id [String]
        # @param client_secret [String]
        def initialize(environment:, tenant_id:, client_id:, client_secret:)
          super(environment:)
          @tenant_id = tenant_id
          @client_id = client_id
          @client_secret = client_secret
        end

        # @return [Array(String, Integer)]
        def fetch_token
          response = Http.request(
            method: :post,
            url: environment.token_url(@tenant_id),
            headers: { "Content-Type" => "application/x-www-form-urlencoded" },
            body: URI.encode_www_form(
              grant_type: "client_credentials",
              client_id: @client_id,
              client_secret: @client_secret,
              resource: environment.token_audience
            )
          )

          token_from(response, "the service principal token endpoint")
        end
      end

      # Authenticates with a federated token issued by another identity
      # provider - GitHub Actions, GitLab, Azure DevOps, or a Kubernetes
      # service account - rather than a stored secret.
      #
      # The platform writes a short-lived signed assertion to a file and
      # rotates it; the file is therefore re-read on every token fetch rather
      # than cached, or a long +kitchen test+ run would start presenting an
      # assertion that has since expired.
      class WorkloadIdentityToken < TokenProvider
        # @return [String] the client assertion type required by Entra ID.
        ASSERTION_TYPE = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer".freeze

        # @param environment [Environments::Environment]
        # @param tenant_id [String]
        # @param client_id [String]
        # @param token_file [String] path to the federated token file.
        def initialize(environment:, tenant_id:, client_id:, token_file:)
          super(environment:)
          @tenant_id = tenant_id
          @client_id = client_id
          @token_file = token_file
        end

        # @return [String] path to the federated token file.
        attr_reader :token_file

        # @return [Array(String, Integer)]
        # @raise [OperationError] if the assertion file cannot be read.
        def fetch_token
          response = Http.request(
            method: :post,
            url: environment.token_url_v2(@tenant_id),
            headers: { "Content-Type" => "application/x-www-form-urlencoded" },
            body: URI.encode_www_form(
              grant_type: "client_credentials",
              client_id: @client_id,
              client_assertion_type: ASSERTION_TYPE,
              client_assertion: assertion,
              scope: environment.default_scope
            )
          )

          token_from(response, "the workload identity token endpoint")
        end

        private

        # The current federated assertion, read fresh each time.
        #
        # @return [String]
        # @raise [OperationError] if the file is missing or unreadable.
        def assertion
          File.read(token_file).strip
        rescue SystemCallError => e
          raise OperationError.new(
            "Could not read the federated token file at #{token_file} (#{e.class}). " \
            "AZURE_FEDERATED_TOKEN_FILE must point at a readable assertion issued by your CI platform."
          )
        end
      end

      # Authenticates as a managed identity, via the Instance Metadata Service.
      #
      # This replaces the legacy MSI extension endpoint on port 50342 that the
      # old SDK used; IMDS is the supported endpoint on modern Azure VMs.
      class ManagedIdentityToken < TokenProvider
        # @return [String] the IMDS token endpoint.
        IMDS_URL = "http://169.254.169.254/metadata/identity/oauth2/token".freeze

        # @return [String] IMDS API version.
        API_VERSION = "2018-02-01".freeze

        # @param environment [Environments::Environment]
        # @param client_id [String, nil] the user-assigned identity to use, or
        #   nil for the system-assigned identity.
        def initialize(environment:, client_id: nil)
          super(environment:)
          @client_id = client_id
        end

        # @return [Array(String, Integer)]
        def fetch_token
          query = { "api-version" => API_VERSION, "resource" => environment.token_audience }
          query["client_id"] = @client_id if @client_id

          response = Http.request(
            method: :get,
            url: "#{IMDS_URL}?#{URI.encode_www_form(query)}",
            headers: { "Metadata" => "true" }
          )

          token_from(response, "the instance metadata service")
        end
      end

      # Reuses whatever the Azure CLI is already signed in as.
      class AzureCliToken < TokenProvider
        # @return [Array(String, Integer)]
        # @raise [OperationError] if the CLI is missing or not signed in.
        def fetch_token
          stdout, stderr, status = Open3.capture3(
            "az", "account", "get-access-token",
            "--resource", environment.token_audience,
            "--output", "json"
          )

          unless status.success?
            raise OperationError.new("Could not acquire an Azure access token via `az account get-access-token`. Run `az login` first. (#{stderr.strip})")
          end

          payload = JSON.parse(stdout)
          [payload.fetch("accessToken"), cli_expiry(payload)]
        rescue Errno::ENOENT
          raise OperationError.new("The Azure CLI (`az`) was not found on PATH, and no other Azure credentials were configured.")
        rescue JSON::ParserError, KeyError
          raise OperationError.new("Could not understand the response from `az account get-access-token`.")
        end

        private

        # The CLI reports a local timestamp rather than a Unix time.
        #
        # @param payload [Hash]
        # @return [Integer]
        def cli_expiry(payload)
          return payload["expires_on"].to_i if payload["expires_on"].to_s.match?(/\A\d+\z/)

          Time.parse(payload["expiresOn"]).to_i
        rescue ::StandardError
          Time.now.to_i + 3600
        end
      end
    end
  end
end
