RSpec.describe Kitchen::Driver::Azurerm, "#destroy" do
  subject(:driver) { build_driver(**config) }

  let(:config) { {} }
  let(:resource_client) { resource_client_double }
  let(:resource_groups) { resource_client.resource_groups }
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

  before { stub_azure_clients(driver, resource_client:) }

  describe "the ordinary case" do
    it "deletes the resource group" do
      driver.destroy(state)
      expect(resource_groups).to have_received(:begin_delete).with("kitchen-default-20260822T134505")
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
      expect(resource_client.deployments).not_to have_received(:begin_create_or_update_async)
    end

    it "re-raises an Azure failure" do
      allow(resource_groups).to receive(:begin_delete).and_raise(azure_operation_error(code: "InUseSubnetCannotBeDeleted"))
      expect { driver.destroy(state) }.to raise_error(MsRestAzure2::AzureOperationError)
    end
  end

  describe "state backfill" do
    it "falls back to config for a missing azure_environment" do
      driver = build_driver(azure_environment: "AzureUSGovernment")
      stub_azure_clients(driver, resource_client:)
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
      expect(resource_groups).not_to have_received(:begin_delete)
    end

    context "with an explicit resource group the user asked to destroy" do
      let(:config) { { explicit_resource_group_name: "my-shared-rg" } }

      it "deletes the group anyway" do
        driver.destroy(state)
        expect(resource_groups).to have_received(:begin_delete).with("my-shared-rg")
      end

      it "explains why it is doing so" do
        allow(Kitchen.logger).to receive(:info)
        driver.destroy(state)
        expect(Kitchen.logger).to have_received(:info).with(/This instance doesn't exist but you asked to delete the resource group/)
      end

      it "does nothing when the group does not exist" do
        allow(resource_groups).to receive(:check_existence).and_return(false)
        driver.destroy(state)
        expect(resource_groups).not_to have_received(:begin_delete)
      end

      it "re-raises an Azure failure" do
        allow(resource_groups).to receive(:begin_delete).and_raise(azure_operation_error(code: "AuthorizationFailed"))
        expect { driver.destroy(state) }.to raise_error(MsRestAzure2::AzureOperationError)
      end

      context "but destroy_explicit_resource_group is off" do
        let(:config) { super().merge(destroy_explicit_resource_group: false) }

        it "leaves the group alone" do
          driver.destroy(state)
          expect(resource_groups).not_to have_received(:begin_delete)
        end
      end
    end
  end

  describe "with destroy_explicit_resource_group disabled" do
    let(:config) { { explicit_resource_group_name: "my-shared-rg", destroy_explicit_resource_group: false } }

    it "keeps the resource group" do
      driver.destroy(state)
      expect(resource_groups).not_to have_received(:begin_delete)
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
        expect(resource_client.deployments).to have_received(:begin_create_or_update_async)
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
      expect(resource_client.deployments).to have_received(:begin_create_or_update_async) do |_rg, _name, deployment|
        expect(deployment.properties.mode).to eq(Azure::Resources2::Profiles::Latest::Mgmt::Models::DeploymentMode::Complete)
        expect(deployment.properties.template["resources"]).to eq([])
      end
    end

    it "then deletes the group itself" do
      driver.destroy(state)
      expect(resource_groups).to have_received(:begin_delete).with("kitchen-default-20260822T134505")
    end

    describe "tag handling" do
      it "clears the tags by default" do
        driver.destroy(state)
        expect(resource_groups).to have_received(:create_or_update) do |_name, group|
          expect(group.tags).to eq({})
        end
      end

      it "says so" do
        allow(Kitchen.logger).to receive(:warn)
        driver.destroy(state)
        expect(Kitchen.logger).to have_received(:warn).with(/tags on the resource group will be removed/)
      end

      context "with destroy_explicit_resource_group_tags disabled" do
        let(:config) { super().merge(destroy_explicit_resource_group_tags: false) }

        it "restores the configured tags instead" do
          driver.destroy(state)
          expect(resource_groups).to have_received(:create_or_update) do |_name, group|
            expect(group.tags).to eq(owner: "platform")
          end
        end

        it "says so" do
          allow(Kitchen.logger).to receive(:warn)
          driver.destroy(state)
          expect(Kitchen.logger).to have_received(:warn).with(/tags on the resource group will NOT be removed/)
        end

        it "does not also clear them" do
          driver.destroy(state)
          expect(resource_groups).to have_received(:create_or_update).once
        end
      end
    end

    it "re-raises an Azure failure from the empty deployment" do
      allow(resource_client.deployments).to receive(:begin_create_or_update_async)
        .and_raise(azure_operation_error(code: "DeploymentFailed"))

      expect { driver.destroy(state) }.to raise_error(MsRestAzure2::AzureOperationError)
    end
  end
end
