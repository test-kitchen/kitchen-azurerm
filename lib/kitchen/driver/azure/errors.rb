module Kitchen
  module Driver
    # Direct Azure Resource Manager access: endpoints, authentication, and the
    # handful of REST calls this driver makes.
    #
    # This replaces the +azure_mgmt_*+ and +ms_rest*+ gems, which are forks of
    # Microsoft's retired Azure SDK for Ruby.
    module Azure
      # Raised when Azure Resource Manager returns an error response.
      #
      # Replaces +MsRestAzure2::AzureOperationError+, keeping the +body+
      # accessor the driver's rescue blocks already rely on.
      #
      # Note the explicit +::StandardError+: Test Kitchen defines
      # +Kitchen::StandardError+, and this class lives inside +module Kitchen+,
      # so a bare +StandardError+ here would resolve to that instead.
      class OperationError < ::StandardError
        # The parsed error body, as returned by ARM.
        #
        # @return [Hash] typically +{"error" => {"code" => ..., "message" => ...}}+.
        attr_reader :body

        # The HTTP status code of the failing response.
        #
        # @return [Integer]
        attr_reader :status

        # @param message [String] human-readable summary.
        # @param status [Integer] HTTP status code.
        # @param body [Hash] parsed ARM error body.
        def initialize(message, status: nil, body: {})
          super(message)
          @status = status
          @body = body
        end

        # The Azure error code, when ARM supplied one.
        #
        # @return [String, nil] e.g. +"DeploymentActive"+.
        def code
          body.is_a?(Hash) ? body.dig("error", "code") : nil
        end
      end

      # Raised when a request could not be completed and is worth retrying:
      # timeouts, resets, DNS failures and the like.
      class TransientError < ::StandardError; end
    end
  end
end
