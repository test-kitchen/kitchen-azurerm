RSpec.describe Kitchen::Driver::Azurerm, "Azure API retries" do
  subject(:driver) { build_driver(**config) }

  let(:config) { { azure_api_retries: 2 } }
  let(:arm_client) { arm_client_double }
  let(:transient) { Kitchen::Driver::Azure::TransientError.new("Net::ReadTimeout: timed out") }

  before do
    driver.arm_client = arm_client
    allow(Kitchen.logger).to receive(:info)
  end

  describe "#with_azure_retries" do
    it "returns the block's value when nothing goes wrong" do
      expect(driver.send(:with_azure_retries, "doing a thing.") { :the_result }).to eq(:the_result)
    end

    it "does not retry a successful call" do
      calls = 0
      driver.send(:with_azure_retries, "doing a thing.") { calls += 1 }
      expect(calls).to eq(1)
    end

    it "retries a transient failure up to the configured budget, then gives up" do
      calls = 0
      expect do
        driver.send(:with_azure_retries, "doing a thing.") do
          calls += 1
          raise transient
        end
      end.to raise_error(Kitchen::Driver::Azure::TransientError)

      # One initial attempt plus azure_api_retries retries.
      expect(calls).to eq(3)
    end

    it "succeeds if a retry works" do
      calls = 0
      result = driver.send(:with_azure_retries, "doing a thing.") do
        calls += 1
        raise transient if calls < 2

        :recovered
      end

      expect(result).to eq(:recovered)
      expect(calls).to eq(2)
    end

    # An HTTP error response from ARM is a real answer, not a connectivity
    # blip, so retrying it would only delay the failure.
    it "does not retry an Azure error response" do
      calls = 0
      expect do
        driver.send(:with_azure_retries, "doing a thing.") do
          calls += 1
          raise azure_operation_error(code: "InvalidTemplate")
        end
      end.to raise_error(Kitchen::Driver::Azure::OperationError)

      expect(calls).to eq(1)
    end

    it "does not swallow errors it cannot retry" do
      expect { driver.send(:with_azure_retries, "doing a thing.") { raise ArgumentError, "bad input" } }
        .to raise_error(ArgumentError, "bad input")
    end

    it "raises immediately when the retry budget is zero" do
      driver = build_driver(azure_api_retries: 0)
      calls = 0

      expect do
        driver.send(:with_azure_retries, "doing a thing.") do
          calls += 1
          raise transient
        end
      end.to raise_error(Kitchen::Driver::Azure::TransientError)

      expect(calls).to eq(1)
    end

    it "logs the cause and the remaining budget" do
      suppress_error { driver.send(:with_azure_retries, "while doing a thing.") { raise transient } }
      expect(Kitchen.logger).to have_received(:info)
        .with("Could not reach Azure (Net::ReadTimeout: timed out) while doing a thing. 2 retries left.")
    end

    it "counts down the remaining budget in the log" do
      suppress_error { driver.send(:with_azure_retries, "while doing a thing.") { raise transient } }
      expect(Kitchen.logger).to have_received(:info).with(/1 retries left/)
      expect(Kitchen.logger).to have_received(:info).with(/0 retries left/)
    end
  end

  describe "#send_exception_message" do
    it "says nothing useful about an exception it does not recognise" do
      driver.send(:send_exception_message, ArgumentError.new, "while doing a thing.")
      expect(Kitchen.logger).to have_received(:info).with("Unrecognized exception type.")
    end
  end

  describe "the wrapped API calls" do
    {
      resource_group_exists?: :resource_group_exists?,
      delete_resource_group_async: :delete_resource_group,
      list_deployment_operations: :deployment_operations,
      get_public_ip: :public_ip,
      get_network_interface: :network_interface,
    }.each do |driver_method, client_method|
      it "retries ##{driver_method}" do
        calls = 0
        allow(arm_client).to receive(client_method) do
          calls += 1
          raise transient if calls < 2

          :ok
        end

        arity = driver.method(driver_method).arity.abs
        expect(driver.send(driver_method, *Array.new(arity, "arg"))).to eq(:ok)
        expect(calls).to eq(2)
      end
    end

    it "retries #create_resource_group" do
      calls = 0
      allow(arm_client).to receive(:create_or_update_resource_group) do
        calls += 1
        raise transient if calls < 2

        :ok
      end

      expect(driver.send(:create_resource_group, "rg", { location: "eastus2", tags: {} })).to eq(:ok)
    end

    it "retries #create_deployment_async" do
      calls = 0
      allow(arm_client).to receive(:create_deployment) do
        calls += 1
        raise transient if calls < 2

        :ok
      end

      expect(driver.send(:create_deployment_async, "rg", "deploy-1", {})).to eq(:ok)
    end

    it "retries #get_deployment_state and unwraps the provisioning state" do
      calls = 0
      allow(arm_client).to receive(:deployment) do
        calls += 1
        raise transient if calls < 2

        deployment_response("Running")
      end

      expect(driver.send(:get_deployment_state, "rg", "deploy-1")).to eq("Running")
    end
  end

  # Runs a block, discarding any error it raises.
  #
  # @yield the block to run.
  # @return [void]
  def suppress_error
    yield
  rescue StandardError
    nil
  end
end
