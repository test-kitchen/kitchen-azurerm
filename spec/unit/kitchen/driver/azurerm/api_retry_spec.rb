RSpec.describe Kitchen::Driver::Azurerm, "Azure API retries" do
  subject(:driver) { build_driver(**config) }

  let(:config) { { azure_api_retries: 2 } }
  let(:resource_client) { resource_client_double }
  let(:network_client) { network_client_double }

  before do
    driver.resource_management_client = resource_client
    driver.network_management_client = network_client
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

    it "retries a timeout up to the configured budget, then gives up" do
      calls = 0
      expect do
        driver.send(:with_azure_retries, "doing a thing.") do
          calls += 1
          raise Faraday::TimeoutError
        end
      end.to raise_error(Faraday::TimeoutError)

      # One initial attempt plus azure_api_retries retries.
      expect(calls).to eq(3)
    end

    it "succeeds if a retry works" do
      calls = 0
      result = driver.send(:with_azure_retries, "doing a thing.") do
        calls += 1
        raise Faraday::TimeoutError if calls < 2

        :recovered
      end

      expect(result).to eq(:recovered)
      expect(calls).to eq(2)
    end

    it "retries connection resets too" do
      calls = 0
      expect do
        driver.send(:with_azure_retries, "doing a thing.") do
          calls += 1
          raise Faraday::ClientError, "connection reset"
        end
      end.to raise_error(Faraday::ClientError)

      expect(calls).to eq(3)
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
          raise Faraday::TimeoutError
        end
      end.to raise_error(Faraday::TimeoutError)

      expect(calls).to eq(1)
    end

    it "logs a timeout with its cause and the remaining budget" do
      suppress_error { driver.send(:with_azure_retries, "while doing a thing.") { raise Faraday::TimeoutError } }
      expect(Kitchen.logger).to have_received(:info).with("Timed out while doing a thing. 2 retries left.")
    end

    it "counts down the remaining budget in the log" do
      suppress_error { driver.send(:with_azure_retries, "while doing a thing.") { raise Faraday::TimeoutError } }
      expect(Kitchen.logger).to have_received(:info).with(/1 retries left/)
      expect(Kitchen.logger).to have_received(:info).with(/0 retries left/)
    end

    it "logs a connection reset differently from a timeout" do
      suppress_error { driver.send(:with_azure_retries, "while doing a thing.") { raise Faraday::ClientError, "reset" } }
      expect(Kitchen.logger).to have_received(:info).with(/\AConnection reset by peer while doing a thing/).at_least(:once)
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
      resource_group_exists?: %w{check_existence},
      create_resource_group: %w{create_or_update},
      delete_resource_group_async: %w{begin_delete},
    }.each do |method, (api_call)|
      it "retries ##{method}" do
        calls = 0
        allow(resource_client.resource_groups).to receive(api_call) do
          calls += 1
          raise Faraday::TimeoutError if calls < 2

          :ok
        end

        expect(driver.send(method, *Array.new(driver.method(method).arity.abs, "arg"))).to eq(:ok)
        expect(calls).to eq(2)
      end
    end

    it "retries #create_deployment_async" do
      calls = 0
      allow(resource_client.deployments).to receive(:begin_create_or_update_async) do
        calls += 1
        raise Faraday::TimeoutError if calls < 2

        :ok
      end

      expect(driver.send(:create_deployment_async, "rg", "deploy-1", :deployment)).to eq(:ok)
    end

    it "retries #list_deployment_operations" do
      calls = 0
      allow(resource_client.deployment_operations).to receive(:list) do
        calls += 1
        raise Faraday::ClientError, "reset" if calls < 2

        []
      end

      expect(driver.send(:list_deployment_operations, "rg", "deploy-1")).to eq([])
    end

    it "retries #get_deployment_state and unwraps the provisioning state" do
      calls = 0
      allow(resource_client.deployments).to receive(:get) do
        calls += 1
        raise Faraday::TimeoutError if calls < 2

        deployment_extended("Running")
      end

      expect(driver.send(:get_deployment_state, "rg", "deploy-1")).to eq("Running")
    end

    it "retries #get_public_ip" do
      calls = 0
      allow(network_client.public_ipaddresses).to receive(:get) do
        calls += 1
        raise Faraday::TimeoutError if calls < 2

        public_ip(ip_address: "1.2.3.4")
      end

      expect(driver.send(:get_public_ip, "rg", "publicip").ip_address).to eq("1.2.3.4")
    end

    it "retries #get_network_interface" do
      calls = 0
      network_interfaces = instance_double(Azure::Network2::Profiles::Latest::Mgmt::NetworkInterfaces)
      allow(Azure::Network2::Profiles::Latest::Mgmt::NetworkInterfaces).to receive(:new).and_return(network_interfaces)
      allow(network_interfaces).to receive(:get) do
        calls += 1
        raise Faraday::TimeoutError if calls < 2

        network_interface(private_ip: "10.0.0.9")
      end

      expect(driver.send(:get_network_interface, "rg", "nic-1").ip_configurations.first.private_ipaddress).to eq("10.0.0.9")
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
