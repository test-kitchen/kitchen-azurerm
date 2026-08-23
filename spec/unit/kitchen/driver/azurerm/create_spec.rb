RSpec.describe Kitchen::Driver::Azurerm, "#create" do
  subject(:driver) { build_driver(transport:, **config) }

  let(:config) { {} }
  let(:transport) { transport_double }
  let(:state) { {} }
  let(:arm_client) { arm_client_double }

  # Every deployment the driver submits, in the order it submitted them.
  let(:submitted_deployments) { [] }

  before do
    stub_arm_client(driver, arm_client:)
    record_deployments(arm_client)
  end

  describe "preconditions" do
    it "refuses to run without a subscription_id" do
      driver = build_driver(subscription_id: nil)
      expect { driver.create({}) }.to raise_error(/subscription_id config value was not detected/)
    end

    it "refuses to run with a blank subscription_id" do
      driver = build_driver(subscription_id: "")
      expect { driver.create({}) }.to raise_error(/subscription_id config value was not detected/)
    end
  end

  describe "resource group creation" do
    it "creates the resource group before deploying" do
      driver.create(state)
      expect(arm_client).to have_received(:create_or_update_resource_group)
        .with(state[:azure_resource_group_name], anything)
    end

    it "tags the resource group" do
      driver = build_driver(resource_group_tags: { owner: "platform-team" }, location: "westus3")
      stub_arm_client(driver, arm_client:)
      record_deployments(arm_client)
      driver.create({})

      expect(arm_client).to have_received(:create_or_update_resource_group)
        .with(anything, location: "westus3", tags: { owner: "platform-team" })
    end

    it "re-raises an Azure failure after logging the body" do
      allow(arm_client).to receive(:create_or_update_resource_group)
        .and_raise(azure_operation_error(code: "AuthorizationFailed"))

      expect { driver.create(state) }.to raise_error(Kitchen::Driver::Azure::OperationError)
    end
  end

  describe "the main deployment" do
    it "names the deployment after the instance uuid" do
      driver.create(state)
      expect(submitted_deployments.first).to include(
        resource_group: state[:azure_resource_group_name],
        name: "deploy-#{state[:uuid]}"
      )
    end

    it "sends a deployment whose template is valid ARM JSON" do
      driver.create(state)
      expect(JSON.generate(submitted_deployments.first[:deployment]["properties"]["template"])).to be_a_valid_arm_template
    end

    it "passes the configured location and machine size through" do
      driver.create(state)
      expect(deployment_parameters).to include(
        "location" => { "value" => "eastus2" },
        "vmSize" => { "value" => "Standard_D4_v3" }
      )
    end

    it "derives the public DNS label from the uuid" do
      driver.create(state)
      expect(deployment_parameters["dnsNameForPublicIP"]).to eq("value" => "kitchen-#{state[:uuid]}")
    end

    it "no longer creates a storage account for the OS disk" do
      driver.create(state)
      expect(deployment_parameters).not_to include("newStorageAccountName")
    end

    it "derives the nic name from the vm name" do
      driver.create(state)
      expect(deployment_parameters["nicName"]).to eq("value" => "nic-#{state[:vm_name]}")
    end

    context "with an explicit nic_name" do
      let(:config) { { nic_name: "my-nic" } }

      it "uses it verbatim" do
        driver.create(state)
        expect(deployment_parameters["nicName"]).to eq("value" => "my-nic")
      end
    end

    it "splits the image urn into its four parts" do
      driver = build_driver(image_urn: "RedHat:rhel-byos:rhel-raw76:7.6.20190620")
      stub_arm_client(driver, arm_client:)
      record_deployments(arm_client)
      driver.create({})

      expect(deployment_parameters).to include(
        "imagePublisher" => { "value" => "RedHat" },
        "imageOffer" => { "value" => "rhel-byos" },
        "imageSku" => { "value" => "rhel-raw76" },
        "imageVersion" => { "value" => "7.6.20190620" }
      )
    end

    context "with an image_id" do
      let(:config) { { image_id: "/subscriptions/x/images/my-image" } }

      it "sends imageId and no marketplace parameters" do
        driver.create(state)
        expect(deployment_parameters).to include("imageId" => { "value" => "/subscriptions/x/images/my-image" })
        expect(deployment_parameters).not_to include("imagePublisher")
      end
    end

    context "with a retired image_url" do
      let(:config) { { image_url: "https://sa.blob.core.windows.net/vhds/my.vhd" } }

      it "ignores it and falls back to the marketplace image" do
        driver.create(state)
        expect(deployment_parameters).to include("imagePublisher")
        expect(deployment_parameters).not_to include("imageUrl")
      end
    end

    describe "public IP SKU" do
      # Basic SKU public IPs were retired on 30 September 2025.
      it "defaults to Standard" do
        driver.create(state)
        expect(deployment_parameters["publicIPSKU"]).to eq("value" => "Standard")
      end

      it "forces a static address, which Standard SKUs require" do
        driver.create(state)
        expect(deployment_parameters["publicIPAddressType"]).to eq("value" => "Static")
      end

      context "when a non-Standard SKU is forced" do
        let(:config) { { public_ip_sku: "Basic" } }

        it "leaves the allocation method to the template default" do
          driver.create(state)
          expect(deployment_parameters).not_to include("publicIPAddressType")
        end
      end
    end

    describe "network security group" do
      it "sends no nsgId when it creates its own group" do
        driver.create(state)
        expect(deployment_parameters).not_to include("nsgId")
      end

      context "with an existing nsg_id" do
        let(:config) { { nsg_id: "/subscriptions/x/networkSecurityGroups/mine" } }

        it "passes it through" do
          driver.create(state)
          expect(deployment_parameters["nsgId"]).to eq("value" => "/subscriptions/x/networkSecurityGroups/mine")
        end
      end
    end

    describe "managed identities" do
      let(:config) do
        {
          system_assigned_identity: true,
          user_assigned_identities: ["/subscriptions/x/userAssignedIdentities/id-1"],
        }
      end

      it "passes the system assigned identity flag" do
        driver.create(state)
        expect(deployment_parameters["systemAssignedIdentity"]).to eq("value" => true)
      end

      it "converts user assigned identities into the ARM map shape" do
        driver.create(state)
        expect(deployment_parameters["userAssignedIdentities"])
          .to eq("value" => { "/subscriptions/x/userAssignedIdentities/id-1" => {} })
      end
    end

    describe "boot diagnostics" do
      it "enables managed boot diagnostics by default" do
        driver.create(state)
        expect(deployment_parameters["bootDiagnosticsEnabled"]).to eq("value" => true)
      end

      it "coerces the historical string spelling" do
        driver = build_driver(boot_diagnostics_enabled: "false")
        stub_arm_client(driver, arm_client:)
        record_deployments(arm_client)
        driver.create({})

        expect(deployment_parameters["bootDiagnosticsEnabled"]).to eq("value" => false)
      end
    end

    describe "retired settings" do
      let(:config) { { use_managed_disks: false, existing_storage_account_blob_url: "https://shared.blob.core.windows.net" } }

      it "warns once per retired setting rather than failing" do
        allow(Kitchen.logger).to receive(:warn)
        driver.create(state)

        expect(Kitchen.logger).to have_received(:warn).with(/'use_managed_disks' setting is no longer supported/)
        expect(Kitchen.logger).to have_received(:warn).with(/'existing_storage_account_blob_url' setting is no longer supported/)
      end

      it "explains why" do
        allow(Kitchen.logger).to receive(:warn)
        driver.create(state)
        expect(Kitchen.logger).to have_received(:warn).with(/retired unmanaged disks on 31 March 2026/).at_least(:once)
      end

      it "sends none of them to ARM" do
        driver.create(state)
        expect(deployment_parameters.keys.map(&:to_s)).not_to include("existingStorageAccountBlobURL", "osDiskNameSuffix")
      end

      it "still deploys" do
        expect { driver.create(state) }.not_to raise_error
      end

      it "says nothing when no retired setting is used" do
        driver = build_driver
        stub_arm_client(driver, arm_client:)
        record_deployments(arm_client)
        allow(Kitchen.logger).to receive(:warn)
        driver.create({})

        expect(Kitchen.logger).not_to have_received(:warn).with(/no longer supported/)
      end
    end

    describe "custom data" do
      let(:config) { { custom_data: "#!/bin/sh\necho hi\n" } }

      it "sends it base64 encoded" do
        driver.create(state)
        expect(Base64.decode64(deployment_parameters["customData"]["value"])).to eq("#!/bin/sh\necho hi\n")
      end
    end

    it "omits customData when none is configured" do
      driver.create(state)
      expect(deployment_parameters).not_to include("customData")
    end

    describe "key vault settings" do
      let(:config) { { secret_url: "https://v.vault.azure.net/secrets/c", vault_name: "v", vault_resource_group: "vault-rg" } }

      it "passes all three through as parameters" do
        driver.create(state)
        expect(deployment_parameters).to include(
          "secretUrl" => { "value" => "https://v.vault.azure.net/secrets/c" },
          "vaultName" => { "value" => "v" },
          "vaultResourceGroup" => { "value" => "vault-rg" }
        )
      end

      it "renders the matching secrets block into the template" do
        driver.create(state)
        vm = vm_resource(submitted_deployments.first[:deployment]["properties"]["template"])
        expect(vm["properties"]["osProfile"]).to have_key("secrets")
      end
    end
  end

  describe "pre and post deployments" do
    let(:template_path) { File.join(ENV.fetch("HOME"), "extra.json") }

    before do
      File.write(template_path, JSON.generate("$schema" => "x", "contentVersion" => "1.0.0.0", "resources" => []))
    end

    it "skips both when no templates are configured" do
      driver.create(state)
      expect(deployment_names_submitted).to eq(["deploy-#{state[:uuid]}"])
    end

    context "with a pre-deployment template" do
      let(:config) { { pre_deployment_template: template_path } }

      it "runs it before the main deployment" do
        driver.create(state)
        expect(deployment_names_submitted).to eq(["pre-deploy-#{state[:uuid]}", "deploy-#{state[:uuid]}"])
      end
    end

    context "with a post-deployment template" do
      let(:config) { { post_deployment_template: template_path } }

      it "runs it after the main deployment" do
        driver.create(state)
        expect(deployment_names_submitted).to eq(["deploy-#{state[:uuid]}", "post-deploy-#{state[:uuid]}"])
      end
    end

    context "with both" do
      let(:config) { { pre_deployment_template: template_path, post_deployment_template: template_path } }

      it "runs them in order around the main deployment" do
        driver.create(state)
        expect(deployment_names_submitted).to eq(
          ["pre-deploy-#{state[:uuid]}", "deploy-#{state[:uuid]}", "post-deploy-#{state[:uuid]}"]
        )
      end
    end

    # Written with no value these are nil, not "", and File.file? raises
    # TypeError on nil rather than answering false.
    context "when either is written with no value" do
      let(:config) { { pre_deployment_template: nil, post_deployment_template: nil } }

      it "treats them as unset" do
        driver.create(state)
        expect(deployment_names_submitted).to eq(["deploy-#{state[:uuid]}"])
      end
    end
  end

  describe "credentials in state" do
    context "with a password transport" do
      it "stores the username and generated password" do
        driver.create(state)
        expect(state[:username]).to eq("azure")
        expect(state[:password]).to be_a(String).and(satisfy { |value| !value.empty? })
      end

      it "does not overwrite credentials already in state" do
        state.merge!(username: "existing-user", password: "existing-password")
        driver.create(state)
        expect(state).to include(username: "existing-user", password: "existing-password")
      end

      context "when store_deployment_credentials_in_state is disabled" do
        let(:config) { { store_deployment_credentials_in_state: false } }

        it "stores neither" do
          driver.create(state)
          expect(state).not_to include(:username, :password)
        end
      end
    end

    context "with an SSH key transport" do
      let(:transport) { transport_double(name: "Ssh", ssh_key: File.join(ENV.fetch("HOME"), "id_rsa")) }

      it "stores the username" do
        driver.create(state)
        expect(state[:username]).to eq("azure")
      end

      # Writing a nil password leaves a misleading empty entry in the state
      # file, and Test Kitchen will then hand it to the transport.
      it "leaves no password key in state at all" do
        driver.create(state)
        expect(state).not_to have_key(:password)
      end

      it "sends no adminPassword parameter to ARM" do
        driver.create(state)
        expect(deployment_parameters).not_to include("adminPassword")
      end
    end
  end

  describe "hostname resolution" do
    it "uses the public IP address by default" do
      driver.create(state)
      expect(state[:hostname]).to eq("40.121.0.1")
    end

    context "with use_fqdn_hostname" do
      let(:config) { { use_fqdn_hostname: true } }

      it "uses the DNS name instead" do
        driver.create(state)
        expect(state[:hostname]).to eq("kitchen-abc.eastus2.cloudapp.azure.com")
      end
    end

    context "in a custom vnet with no public IP" do
      let(:config) { { vnet_id: "/vnet", subnet_id: "/subnet" } }

      before { allow(arm_client).to receive(:network_interface).and_return(network_interface_response(private_ip: "10.0.0.7")) }

      it "uses the NIC's private address" do
        driver.create(state)
        expect(state[:hostname]).to eq("10.0.0.7")
      end

      it "looks up the NIC by the name it deployed" do
        driver.create(state)
        expect(arm_client).to have_received(:network_interface).with(state[:azure_resource_group_name], "nic-#{state[:vm_name]}")
      end
    end

    context "in a custom vnet that also has a public IP" do
      let(:config) { { vnet_id: "/vnet", subnet_id: "/subnet", public_ip: true } }

      it "prefers the public address" do
        driver.create(state)
        expect(state[:hostname]).to eq("40.121.0.1")
      end
    end
  end

  # An interrupted `kitchen create` leaves its deployment running in Azure.
  # Re-running it gets DeploymentActive back from ARM, which used to abandon
  # the rest of create: the credentials were never written to state, and the
  # instance was reported as created anyway. The transport then failed with a
  # bare "SSH session could not be established" naming nothing that led to it.
  describe "when a deployment is already running" do
    before do
      allow(arm_client).to receive(:create_deployment)
        .and_raise(azure_operation_error(code: "DeploymentActive"))
    end

    it "does not raise, because the existing deployment is the one we wanted" do
      expect { driver.create(state) }.not_to raise_error
    end

    it "says it is waiting rather than that it gave up" do
      allow(Kitchen.logger).to receive(:info)
      driver.create(state)
      expect(Kitchen.logger).to have_received(:info).with(/already running.*waiting for it/i)
    end

    it "waits for the running deployment to reach an end state" do
      driver.create(state)
      expect(arm_client).to have_received(:deployment).with(anything, /\Adeploy-/)
    end

    it "still resolves a hostname" do
      driver.create(state)
      expect(state[:hostname]).to eq("40.121.0.1")
    end

    # The whole point. Without this the instance is unreachable, and for a
    # password-authenticated instance the generated password is lost for good:
    # the next run generates a different one that was never applied to the VM.
    it "stores the deployment credentials" do
      driver.create(state)
      expect(state[:username]).to eq("azure")
    end

    it "stores the generated password when there is no ssh key" do
      driver = build_driver(transport: transport_double(ssh_key: nil))
      stub_arm_client(driver, arm_client:)
      record_deployments(arm_client)
      allow(arm_client).to receive(:create_deployment)
        .and_raise(azure_operation_error(code: "DeploymentActive"))

      driver.create(state)

      expect(state[:password]).not_to be_nil
    end

    it "surfaces a failure in the deployment it waited for" do
      allow(arm_client).to receive(:deployment).and_return(deployment_response("Failed"))
      allow(arm_client).to receive(:deployment_operations)
        .and_return([deployment_operation(provisioning_state: "Failed", status_code: "Conflict",
          status_message: "quota exceeded")])

      expect { driver.create(state) }.to raise_error(/quota exceeded/)
    end
  end

  describe "when the deployment fails for any other reason" do
    before do
      allow(arm_client).to receive(:create_deployment)
        .and_raise(azure_operation_error(code: "InvalidTemplate", message: "the template is malformed"))
    end

    it "re-raises" do
      expect { driver.create(state) }.to raise_error(Kitchen::Driver::Azure::OperationError)
    end
  end

  # Records every deployment submitted through a doubled client.
  #
  # @param client [Object] the doubled resource management client.
  # @return [void]
  def record_deployments(client)
    allow(client).to receive(:create_deployment) do |resource_group, name, deployment|
      submitted_deployments << { resource_group:, name:, deployment: }
      { "id" => "/deployments/#{name}" }
    end
  end

  # The ARM parameters of the main virtual machine deployment.
  #
  # @return [Hash, nil]
  def deployment_parameters
    main = submitted_deployments.find { |entry| entry[:name].start_with?("deploy-") }
    main && main[:deployment]["properties"]["parameters"]
  end

  # Names of every deployment submitted, in order.
  #
  # @return [Array<String>]
  def deployment_names_submitted
    submitted_deployments.map { |entry| entry[:name] }
  end
end
