RSpec.describe Kitchen::Driver::Azurerm, "#status" do
  subject(:driver) { build_driver }

  let(:arm_client) { arm_client_double }
  let(:state) do
    {
      uuid: "abc123",
      server_id: "vmabc123",
      vm_name: "tk-abc123",
      azure_resource_group_name: "kitchen-default-20260822T134505",
      subscription_id: "115b12cb-b0d3-4ed9-94db-f73733be6f3c",
      azure_environment: "Azure",
    }
  end

  before { stub_arm_client(driver, arm_client:) }

  describe "before the instance has been created" do
    it "reports it as not created" do
      expect(driver.status({})).to include(live: false, state: "not_created")
    end

    it "does not ask Azure about a machine that cannot exist" do
      driver.status({})
      expect(arm_client).not_to have_received(:virtual_machine_instance_view)
    end
  end

  describe "when the virtual machine is running" do
    before do
      allow(arm_client).to receive(:virtual_machine_instance_view)
        .and_return(instance_view_response("PowerState/running", "VM running"))
    end

    it "reports it live" do
      expect(driver.status(state)).to include(live: true, state: "running")
    end

    it "passes Azure's own wording along" do
      expect(driver.status(state)[:message]).to eq("VM running")
    end

    it "names the machine it asked about" do
      expect(driver.status(state)[:resource_id]).to eq(
        "/subscriptions/115b12cb-b0d3-4ed9-94db-f73733be6f3c/resourceGroups/" \
        "kitchen-default-20260822T134505/providers/Microsoft.Compute/virtualMachines/tk-abc123"
      )
    end
  end

  describe "when the virtual machine is deallocated" do
    before do
      allow(arm_client).to receive(:virtual_machine_instance_view)
        .and_return(instance_view_response("PowerState/deallocated", "VM deallocated"))
    end

    it "reports it not live" do
      expect(driver.status(state)).to include(live: false, state: "deallocated")
    end
  end

  describe "when Azure reports a power state we do not recognise" do
    before do
      allow(arm_client).to receive(:virtual_machine_instance_view)
        .and_return(instance_view_response("PowerState/hibernated", "VM hibernated"))
    end

    it "passes the state through rather than guessing whether it is live" do
      expect(driver.status(state)).to include(live: nil, state: "hibernated")
    end
  end

  describe "when the instance view carries no power state" do
    before { allow(arm_client).to receive(:virtual_machine_instance_view).and_return({ "statuses" => [] }) }

    it "reports unknown" do
      expect(driver.status(state)).to include(state: "unknown")
    end
  end

  describe "when the virtual machine is gone" do
    before do
      allow(arm_client).to receive(:virtual_machine_instance_view)
        .and_raise(azure_operation_error(code: "ResourceNotFound", status: 404))
    end

    it "reports it as not created rather than as an error" do
      expect(driver.status(state)).to include(live: false, state: "not_created")
    end
  end

  describe "when Azure cannot be reached" do
    before do
      allow(arm_client).to receive(:virtual_machine_instance_view)
        .and_raise(Kitchen::Driver::Azure::TransientError, "Net::OpenTimeout: timed out")
    end

    it "reports unknown rather than failing the listing" do
      expect(driver.status(state)).to include(live: nil, state: "unknown")
    end

    it "says why" do
      expect(driver.status(state)[:message]).to include("timed out")
    end
  end

  describe "when Azure refuses the request" do
    before do
      allow(arm_client).to receive(:virtual_machine_instance_view)
        .and_raise(azure_operation_error(code: "AuthorizationFailed", status: 403))
    end

    it "reports unknown and says why" do
      expect(driver.status(state)).to include(live: nil, state: "unknown")
      expect(driver.status(state)[:message]).to include("AuthorizationFailed")
    end
  end

  # Test Kitchen skips a driver whose #status takes no arguments.
  it "accepts the instance state" do
    expect(described_class.instance_method(:status).arity).to eq(1)
  end
end
