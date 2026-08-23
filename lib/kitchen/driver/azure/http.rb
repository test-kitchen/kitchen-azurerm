require "ipaddr" unless defined?(IPAddr)
require "json" unless defined?(JSON)
require "net/http" unless defined?(Net::HTTP)
require "openssl" unless defined?(OpenSSL)
require "uri" unless defined?(URI)

require_relative "errors"

module Kitchen
  module Driver
    module Azure
      # A very small JSON-over-HTTP helper built on the standard library.
      #
      # The driver makes a handful of straightforward requests, so this replaces
      # Faraday and its middleware chain rather than depending on them.
      module Http
        # Network-level failures worth retrying rather than surfacing.
        #
        # @return [Array<Class>]
        TRANSIENT_ERRORS = [
          Net::OpenTimeout,
          Net::ReadTimeout,
          Errno::ECONNREFUSED,
          Errno::ECONNRESET,
          Errno::EHOSTUNREACH,
          Errno::ENETUNREACH,
          Errno::EPIPE,
          EOFError,
          SocketError,
          OpenSSL::SSL::SSLError,
        ].freeze

        # The link-local range, which holds Azure's instance metadata service.
        #
        # @return [IPAddr]
        LINK_LOCAL = IPAddr.new("169.254.0.0/16").freeze

        # Seconds to wait for a connection and for a response.
        #
        # @return [Integer]
        OPEN_TIMEOUT = 30
        # @return [Integer]
        READ_TIMEOUT = 120

        # One HTTP response.
        #
        # @!attribute [r] status
        #   @return [Integer]
        # @!attribute [r] body
        #   @return [String]
        Response = Struct.new(:status, :body) do
          # @return [Boolean] whether the status is in the 2xx range.
          def success?
            status.between?(200, 299)
          end

          # The response body parsed as JSON.
          #
          # @return [Hash, Array, nil] nil when the body is empty or not JSON.
          def json
            return nil if body.nil? || body.empty?

            JSON.parse(body)
          rescue JSON::ParserError
            nil
          end
        end

        # Performs a request.
        #
        # @param method [Symbol] +:get+, +:head+, +:put+, +:post+ or +:delete+.
        # @param url [String] absolute URL.
        # @param headers [Hash{String => String}] request headers.
        # @param body [String, nil] request body, already encoded.
        # @return [Response]
        # @raise [TransientError] on a network failure worth retrying.
        def self.request(method:, url:, headers: {}, body: nil)
          uri = URI.parse(url)
          request = request_class(method).new(uri)
          headers.each { |name, value| request[name] = value }
          request.body = body if body

          response = perform(uri, request)
          Response.new(response.code.to_i, response.body.to_s)
        rescue *TRANSIENT_ERRORS => e
          raise TransientError, "#{e.class}: #{e.message}"
        end

        # Sends a request, honouring the proxy environment variables.
        #
        # @param uri [URI]
        # @param request [Net::HTTPRequest]
        # @return [Net::HTTPResponse]
        # @api private
        def self.perform(uri, request)
          proxy = proxy_for(uri)
          http = if proxy
                   Net::HTTP.new(uri.host, uri.port, proxy.host, proxy.port, proxy.user, proxy.password)
                 else
                   # Explicitly nil rather than Net::HTTP's default of :ENV,
                   # which would send it back to the environment to pick a
                   # proxy we have just decided against.
                   Net::HTTP.new(uri.host, uri.port, nil)
                 end

          http.use_ssl = uri.scheme == "https"
          http.open_timeout = OPEN_TIMEOUT
          http.read_timeout = READ_TIMEOUT
          http.start { |connection| connection.request(request) }
        end

        # The proxy to reach a URL through, if any.
        #
        # Azure's instance metadata service answers on a link-local address,
        # which exists only on the local link and which no proxy can route to.
        # Sending it through one breaks managed identity authentication
        # outright: the connection hangs until the open timeout, surfaces as a
        # {TransientError}, and is then retried. Every Azure SDK carves the
        # same exception out.
        #
        # @param uri [URI]
        # @return [URI, nil]
        # @api private
        def self.proxy_for(uri)
          return nil if link_local?(uri.host)

          uri.find_proxy
        end

        # @param host [String]
        # @return [Boolean] whether the host is a link-local address.
        # @api private
        def self.link_local?(host)
          LINK_LOCAL.include?(IPAddr.new(host.to_s))
        rescue IPAddr::Error
          # Not an IP address at all, so not the metadata service.
          false
        end

        # @param method [Symbol]
        # @return [Class] the matching +Net::HTTP+ request class.
        # @raise [ArgumentError] for an unsupported method.
        # @api private
        def self.request_class(method)
          case method
          when :get then Net::HTTP::Get
          when :head then Net::HTTP::Head
          when :put then Net::HTTP::Put
          when :post then Net::HTTP::Post
          when :delete then Net::HTTP::Delete
          else raise ArgumentError, "Unsupported HTTP method: #{method}"
          end
        end
      end
    end
  end
end
