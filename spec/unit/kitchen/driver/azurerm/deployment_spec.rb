RSpec.describe Kitchen::Driver::Azurerm, "deployments" do
  subject(:driver) { build_driver(**config) }

  let(:config) { {} }

  describe "#parameters_in_values_format" do
    it "wraps each value in the ARM value envelope" do
      expect(driver.parameters_in_values_format(location: "eastus2", vmSize: "Standard_D2_v3")).to eq(
        "location" => { "value" => "eastus2" },
        "vmSize" => { "value" => "Standard_D2_v3" }
      )
    end

    it "stringifies symbol keys, matching ARM's own JSON" do
      expect(driver.parameters_in_values_format(nicName: "nic-1")).to eq("nicName" => { "value" => "nic-1" })
    end

    it "preserves non-string values" do
      expect(driver.parameters_in_values_format(count: 3, enabled: false)).to eq(
        "count" => { "value" => 3 },
        "enabled" => { "value" => false }
      )
    end

    it "is nil for an empty Hash" do
      expect(driver.parameters_in_values_format({})).to be_nil
    end

    it "is nil for nil" do
      expect(driver.parameters_in_values_format(nil)).to be_nil
    end
  end

  describe "#deployment" do
    subject(:deployment) { driver.deployment(location: "eastus2") }

    it "uses Incremental mode" do
      expect(deployment["properties"]["mode"]).to eq("Incremental")
    end

    it "carries the rendered virtual machine template" do
      expect(deployment["properties"]["template"]["resources"].map { |r| r["type"] })
        .to include("Microsoft.Compute/virtualMachines")
    end

    it "carries the parameters in ARM value format" do
      expect(deployment["properties"]["parameters"]).to eq("location" => { "value" => "eastus2" })
    end
  end

  describe "#pre_deployment and #post_deployment" do
    let(:template_path) { File.join(ENV.fetch("HOME"), "extra.json") }
    let(:template) do
      {
        "$schema" => "https://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#",
        "contentVersion" => "1.0.0.0",
        "resources" => [],
      }
    end

    before { File.write(template_path, JSON.generate(template)) }

    it "reads and parses the pre-deployment template from disk" do
      deployment = driver.pre_deployment(template_path, {})
      expect(deployment["properties"]["template"]).to eq(template)
    end

    it "reads and parses the post-deployment template from disk" do
      deployment = driver.post_deployment(template_path, {})
      expect(deployment["properties"]["template"]).to eq(template)
    end

    it "uses Incremental mode so existing resources survive" do
      expect(driver.pre_deployment(template_path, {})["properties"]["mode"]).to eq("Incremental")
    end

    it "formats supplied parameters" do
      deployment = driver.pre_deployment(template_path, storageName: "mystorage")
      expect(deployment["properties"]["parameters"]).to eq("storageName" => { "value" => "mystorage" })
    end

    it "leaves parameters unset when none are supplied" do
      expect(driver.pre_deployment(template_path, {})["properties"]).not_to have_key("parameters")
    end

    it "raises a readable error when the template file is missing" do
      expect { driver.pre_deployment("/nope/missing.json", {}) }.to raise_error(Errno::ENOENT)
    end
  end

  describe "#empty_deployment" do
    subject(:deployment) { driver.empty_deployment }

    it "uses Complete mode, which is what actually deletes the resources" do
      expect(deployment["properties"]["mode"]).to eq("Complete")
    end

    it "contains no resources" do
      expect(deployment["properties"]["template"]["resources"]).to eq([])
    end

    it "sets no parameters" do
      expect(deployment["properties"]).not_to have_key("parameters")
    end
  end

  describe "#follow_deployment_until_end_state" do
    before { driver.arm_client = arm_client }

    let(:arm_client) { arm_client_double }

    it "returns once the deployment succeeds" do
      expect { driver.follow_deployment_until_end_state("rg", "deploy-1") }.not_to raise_error
    end

    it "reports the end state it reached" do
      allow(Kitchen.logger).to receive(:info)
      driver.follow_deployment_until_end_state("rg", "deploy-1")
      expect(Kitchen.logger).to have_received(:info).with(/reached end state of 'Succeeded'/)
    end

    it "sleeps between polls for the configured interval" do
      driver = build_driver(deployment_sleep: 42)
      driver.arm_client = arm_client
      driver.follow_deployment_until_end_state("rg", "deploy-1")
      expect(driver).to have_received(:sleep).with(42)
    end

    it "keeps polling until a terminal state is reached" do
      allow(arm_client).to receive(:deployment).and_return(
        deployment_response("Running"),
        deployment_response("Running"),
        deployment_response("Succeeded")
      )

      driver.follow_deployment_until_end_state("rg", "deploy-1")
      expect(arm_client).to have_received(:deployment).exactly(3).times
    end

    %w{Canceled Deleted Succeeded}.each do |state|
      it "treats #{state} as terminal, rather than polling forever" do
        allow(arm_client).to receive(:deployment).and_return(deployment_response(state))
        driver.follow_deployment_until_end_state("rg", "deploy-1")
      rescue RuntimeError
        # Terminal but unsuccessful states raise; the point here is that the
        # poll loop ends at all.
      end
    end

    # Azure has four terminal states and only one of them means the machine
    # exists. Canceled and Deleted were treated exactly like Succeeded, so
    # create carried on and handed the transport a hostname for a VM that was
    # never built.
    %w{Canceled Deleted}.each do |state|
      context "when the deployment ends as #{state}" do
        let(:arm_client) { arm_client_double(deployment: deployment_response(state), deployment_operations: []) }

        it "raises rather than reporting success" do
          expect { driver.follow_deployment_until_end_state("rg", "deploy-1") }
            .to raise_error(/deploy-1.*#{state}/)
        end
      end
    end

    context "when the deployment fails" do
      let(:arm_client) { arm_client_double(deployment: deployment_response("Failed"), deployment_operations: operations) }
      let(:operations) do
        [
          deployment_operation(status_code: "OK"),
          deployment_operation(status_code: "Conflict", status_message: "VM size not available in this region"),
        ]
      end

      it "raises with the failing operation's message" do
        expect { driver.follow_deployment_until_end_state("rg", "deploy-1") }
          .to raise_error(/VM size not available in this region/)
      end

      it "reports every failure, not just the first" do
        allow(arm_client).to receive(:deployment_operations).and_return(
          [
            deployment_operation(status_code: "Conflict", status_message: "first problem"),
            deployment_operation(status_code: "BadRequest", status_message: "second problem"),
          ]
        )

        expect { driver.follow_deployment_until_end_state("rg", "deploy-1") }
          .to raise_error(/first problem.*second problem/m)
      end

      # A deployment can fail without any single operation reporting a
      # non-OK status - a preflight rejection, or a failure Azure records
      # against the deployment rather than an operation. Returning quietly
      # here reported the failed deployment as a successful create.
      it "still raises when no individual operation reported a failure" do
        allow(arm_client).to receive(:deployment_operations).and_return([deployment_operation(status_code: "OK")])
        expect { driver.follow_deployment_until_end_state("rg", "deploy-1") }
          .to raise_error(/deploy-1.*Failed/)
      end

      it "names the resource group it was deploying into" do
        allow(arm_client).to receive(:deployment_operations).and_return([])
        expect { driver.follow_deployment_until_end_state("rg", "deploy-1") }.to raise_error(/rg/)
      end
    end
  end

  describe "#list_outstanding_deployment_operations" do
    before do
      driver.arm_client = arm_client_double(deployment_operations: operations)
      allow(Kitchen.logger).to receive(:info)
    end

    let(:operations) do
      [
        deployment_operation(provisioning_state: "Running", resource_name: "my-vm", resource_type: "Microsoft.Compute/virtualMachines"),
        deployment_operation(provisioning_state: "Succeeded", resource_name: "my-nic", resource_type: "Microsoft.Network/networkInterfaces"),
        deployment_operation(provisioning_state: "Failed", resource_name: "my-ip", resource_type: "Microsoft.Network/publicIPAddresses"),
      ]
    end

    it "logs operations that are still in flight" do
      driver.list_outstanding_deployment_operations("rg", "deploy-1")
      expect(Kitchen.logger).to have_received(:info)
        .with("Resource Microsoft.Compute/virtualMachines 'my-vm' provisioning status is Running")
    end

    it "stays quiet about operations that already finished" do
      driver.list_outstanding_deployment_operations("rg", "deploy-1")
      expect(Kitchen.logger).not_to have_received(:info).with(/my-nic|my-ip/)
    end

    context "when an operation has no target resource yet" do
      let(:operations) { [deployment_operation(provisioning_state: "Accepted")] }

      it "logs without a name rather than raising" do
        expect { driver.list_outstanding_deployment_operations("rg", "deploy-1") }.not_to raise_error
        expect(Kitchen.logger).to have_received(:info).with(/provisioning status is Accepted/)
      end
    end
  end

  describe "#run_deployment" do
    let(:state) { { uuid: "abc123", azure_resource_group_name: "kitchen-rg" } }
    let(:arm_client) { arm_client_double }

    before { driver.arm_client = arm_client }

    it "names the deployment from the prefix and the instance uuid" do
      driver.run_deployment(state, "pre-deploy", driver.empty_deployment)
      expect(arm_client).to have_received(:create_deployment)
        .with("kitchen-rg", "pre-deploy-abc123", anything)
    end

    it "waits for the deployment to finish before returning" do
      expect(driver).to receive(:follow_deployment_until_end_state).with("kitchen-rg", "deploy-abc123")
      driver.run_deployment(state, "deploy", driver.empty_deployment)
    end
  end
end
