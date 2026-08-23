RSpec.describe Kitchen::Driver::Azurerm, "#destroy" do
  subject(:driver) { build_driver(**config) }

  let(:config) { {} }
  let(:arm_client) { arm_client_double }
  let(:state) do
    {
      uuid: "abc123",
      server_id: "vmabc123",
      vm_name: "tk-abc123",
      azure_resource_group_name: "kitchen-default-20260822T134505",
      hostname: "40.121.0.1",
      username: "azure",
      password: "hunter2",
      subscription_id: "115b12cb-b0d3-4ed9-94db-f73733be6f3c",
      azure_environment: "Azure",
    }
  end

  before { stub_arm_client(driver, arm_client:) }

  # An empty subscription_id in state used to be taken as authoritative, so
  # destroy built a client with no subscription at all and Azure was asked to
  # DELETE /subscriptions//resourcegroups/... - a 400 that left the resource
  # group behind, still billing.
  describe "with a blank subscription_id left in state" do
    let(:config) { { subscription_id: "sub-from-config" } }

    before { state[:subscription_id] = "" }

    it "falls back to the configured subscription" do
      driver.destroy(state)
      expect(Kitchen::Driver::AzureCredentials).to have_received(:new)
        .with(hash_including(subscription_id: "sub-from-config"))
    end

    it "repairs the value in state" do
      driver.destroy(state)
      expect(state[:subscription_id]).to eq("sub-from-config")
    end
  end

  describe "with a blank azure_environment left in state" do
    let(:config) { { azure_environment: "AzureUSGovernment" } }

    before { state[:azure_environment] = "" }

    it "falls back to the configured cloud" do
      driver.destroy(state)
      expect(Kitchen::Driver::AzureCredentials).to have_received(:new)
        .with(hash_including(environment: "AzureUSGovernment"))
    end
  end

  describe "the ordinary case" do
    it "deletes the resource group" do
      driver.destroy(state)
      expect(arm_client).to have_received(:delete_resource_group).with("kitchen-default-20260822T134505")
    end

    it "clears the resource group name from state" do
      driver.destroy(state)
      expect(state).not_to have_key(:azure_resource_group_name)
    end

    it "clears the instance identity and credentials from state" do
      driver.destroy(state)
      expect(state).not_to include(:server_id, :hostname, :username, :password)
    end

    it "does not empty the resource group first by default" do
      driver.destroy(state)
      expect(arm_client).not_to have_received(:create_deployment)
    end

    it "re-raises an Azure failure" do
      allow(arm_client).to receive(:delete_resource_group).and_raise(azure_operation_error(code: "InUseSubnetCannotBeDeleted"))
      expect { driver.destroy(state) }.to raise_error(Kitchen::Driver::Azure::OperationError)
    end
  end

  describe "state backfill" do
    it "falls back to config for a missing azure_environment" do
      driver = build_driver(azure_environment: "AzureUSGovernment")
      stub_arm_client(driver, arm_client:)
      state.delete(:azure_environment)

      driver.destroy(state)
      expect(state[:azure_environment]).to eq("AzureUSGovernment")
    end

    it "falls back to config for a missing subscription_id" do
      state.delete(:subscription_id)
      driver.destroy(state)
      expect(state[:subscription_id]).to eq("115b12cb-b0d3-4ed9-94db-f73733be6f3c")
    end
  end

  describe "when the instance was never created" do
    let(:state) { {} }

    it "does nothing" do
      driver.destroy(state)
      expect(arm_client).not_to have_received(:delete_resource_group)
    end

    context "with an explicit resource group the user asked to destroy" do
      let(:config) { { explicit_resource_group_name: "my-shared-rg" } }

      it "deletes the group anyway" do
        driver.destroy(state)
        expect(arm_client).to have_received(:delete_resource_group).with("my-shared-rg")
      end

      it "explains why it is doing so" do
        allow(Kitchen.logger).to receive(:info)
        driver.destroy(state)
        expect(Kitchen.logger).to have_received(:info).with(/This instance doesn't exist but you asked to delete the resource group/)
      end

      it "does nothing when the group does not exist" do
        allow(arm_client).to receive(:resource_group_exists?).and_return(false)
        driver.destroy(state)
        expect(arm_client).not_to have_received(:delete_resource_group)
      end

      it "re-raises an Azure failure" do
        allow(arm_client).to receive(:delete_resource_group).and_raise(azure_operation_error(code: "AuthorizationFailed"))
        expect { driver.destroy(state) }.to raise_error(Kitchen::Driver::Azure::OperationError)
      end

      context "but destroy_explicit_resource_group is off" do
        let(:config) { super().merge(destroy_explicit_resource_group: false) }

        it "leaves the group alone" do
          driver.destroy(state)
          expect(arm_client).not_to have_received(:delete_resource_group)
        end
      end
    end
  end

  describe "with destroy_explicit_resource_group disabled" do
    let(:config) { { explicit_resource_group_name: "my-shared-rg", destroy_explicit_resource_group: false } }

    it "keeps the resource group" do
      driver.destroy(state)
      expect(arm_client).not_to have_received(:delete_resource_group)
    end

    it "warns the user that resources are still running" do
      allow(Kitchen.logger).to receive(:warn)
      driver.destroy(state)
      expect(Kitchen.logger).to have_received(:warn).with(/Remember to manually destroy resources/)
    end

    it "returns the state untouched" do
      expect(driver.destroy(state)).to include(server_id: "vmabc123", hostname: "40.121.0.1")
    end

    context "and destroy_resource_group_contents enabled" do
      let(:config) { super().merge(destroy_resource_group_contents: true) }

      it "empties the group instead of deleting it" do
        driver.destroy(state)
        expect(arm_client).to have_received(:create_deployment)
          .with("kitchen-default-20260822T134505", "empty-deploy-abc123", anything)
      end

      it "does not nag about manual cleanup" do
        allow(Kitchen.logger).to receive(:warn)
        driver.destroy(state)
        expect(Kitchen.logger).not_to have_received(:warn).with(/Remember to manually destroy resources/)
      end
    end
  end

  describe "with destroy_resource_group_contents enabled" do
    let(:config) { { destroy_resource_group_contents: true, location: "eastus2", resource_group_tags: { owner: "platform" } } }

    it "submits an empty Complete-mode deployment" do
      driver.destroy(state)
      expect(arm_client).to have_received(:create_deployment) do |_rg, _name, deployment|
        expect(deployment["properties"]["mode"]).to eq("Complete")
        expect(deployment["properties"]["template"]["resources"]).to eq([])
      end
    end

    it "then deletes the group itself" do
      driver.destroy(state)
      expect(arm_client).to have_received(:delete_resource_group).with("kitchen-default-20260822T134505")
    end

    describe "tag handling" do
      it "clears the tags by default" do
        driver.destroy(state)
        expect(arm_client).to have_received(:create_or_update_resource_group)
          .with(anything, hash_including(tags: {}))
      end

      it "says so" do
        allow(Kitchen.logger).to receive(:warn)
        driver.destroy(state)
        expect(Kitchen.logger).to have_received(:warn).with(/tags on the resource group will be removed/)
      end

      context "with destroy_explicit_resource_group_tags disabled" do
        let(:config) { super().merge(destroy_explicit_resource_group_tags: false) }

        # ARM's PUT on a resource group replaces its tags rather than merging
        # them, so rewriting the group at all is what destroyed the tags this
        # setting promises to keep. An empty Complete-mode deployment leaves
        # them alone, so the way to preserve them is to leave the group be.
        it "leaves the resource group alone so its tags survive" do
          driver.destroy(state)
          expect(arm_client).not_to have_received(:create_or_update_resource_group)
        end

        it "says so" do
          allow(Kitchen.logger).to receive(:warn)
          driver.destroy(state)
          expect(Kitchen.logger).to have_received(:warn).with(/tags on the resource group will NOT be removed/)
        end
      end
    end

    it "re-raises an Azure failure from the empty deployment" do
      allow(arm_client).to receive(:create_deployment)
        .and_raise(azure_operation_error(code: "DeploymentFailed"))

      expect { driver.destroy(state) }.to raise_error(Kitchen::Driver::Azure::OperationError)
    end
  end
end
