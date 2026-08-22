RSpec.describe Kitchen::Driver::Azurerm, "#create" do
  subject(:driver) { build_driver(transport:, **config) }

  let(:config) { {} }
  let(:transport) { transport_double }
  let(:state) { {} }
  let(:resource_client) { resource_client_double }
  let(:network_client) { network_client_double }

  # Every deployment the driver submits, in the order it submitted them.
  let(:submitted_deployments) { [] }

  before do
    stub_azure_clients(driver, resource_client:, network_client:)
    record_deployments(resource_client)
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
      expect(resource_client.resource_groups).to have_received(:create_or_update)
        .with(state[:azure_resource_group_name], anything)
    end

    it "tags the resource group" do
      driver = build_driver(resource_group_tags: { owner: "platform-team" }, location: "westus3")
      stub_azure_clients(driver, resource_client:, network_client:)
      record_deployments(resource_client)
      driver.create({})

      expect(resource_client.resource_groups).to have_received(:create_or_update) do |_name, group|
        expect(group.tags).to eq(owner: "platform-team")
        expect(group.location).to eq("westus3")
      end
    end

    it "re-raises an Azure failure after logging the body" do
      allow(resource_client.resource_groups).to receive(:create_or_update)
        .and_raise(azure_operation_error(code: "AuthorizationFailed"))

      expect { driver.create(state) }.to raise_error(MsRestAzure2::AzureOperationError)
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
      expect(JSON.generate(submitted_deployments.first[:deployment].properties.template)).to be_a_valid_arm_template
    end

    it "passes the configured location and machine size through" do
      driver.create(state)
      expect(deployment_parameters).to include(
        location: { "value" => "eastus2" },
        vmSize: { "value" => "Standard_D4_v3" }
      )
    end

    it "derives the storage account and DNS names from the uuid" do
      driver.create(state)
      expect(deployment_parameters).to include(
        newStorageAccountName: { "value" => "storage#{state[:uuid]}" },
        dnsNameForPublicIP: { "value" => "kitchen-#{state[:uuid]}" }
      )
    end

    it "derives the nic name from the vm name" do
      driver.create(state)
      expect(deployment_parameters[:nicName]).to eq("value" => "nic-#{state[:vm_name]}")
    end

    context "with an explicit nic_name" do
      let(:config) { { nic_name: "my-nic" } }

      it "uses it verbatim" do
        driver.create(state)
        expect(deployment_parameters[:nicName]).to eq("value" => "my-nic")
      end
    end

    it "splits the image urn into its four parts" do
      driver = build_driver(image_urn: "RedHat:rhel-byos:rhel-raw76:7.6.20190620")
      stub_azure_clients(driver, resource_client:, network_client:)
      record_deployments(resource_client)
      driver.create({})

      expect(deployment_parameters).to include(
        imagePublisher: { "value" => "RedHat" },
        imageOffer: { "value" => "rhel-byos" },
        imageSku: { "value" => "rhel-raw76" },
        imageVersion: { "value" => "7.6.20190620" }
      )
    end

    context "with an image_id" do
      let(:config) { { image_id: "/subscriptions/x/images/my-image" } }

      it "sends imageId and no marketplace parameters" do
        driver.create(state)
        expect(deployment_parameters).to include(imageId: { "value" => "/subscriptions/x/images/my-image" })
        expect(deployment_parameters).not_to include(:imagePublisher)
      end
    end

    context "with an image_url" do
      let(:config) { { image_url: "https://sa.blob.core.windows.net/vhds/my.vhd", os_type: "windows", use_managed_disks: false } }

      it "sends imageUrl and the os type" do
        driver.create(state)
        expect(deployment_parameters).to include(
          imageUrl: { "value" => "https://sa.blob.core.windows.net/vhds/my.vhd" },
          osType: { "value" => "windows" }
        )
      end
    end

    describe "public IP SKU" do
      it "defaults to Basic with no address type override" do
        driver.create(state)
        expect(deployment_parameters[:publicIPSKU]).to eq("value" => "Basic")
        expect(deployment_parameters).not_to include(:publicIPAddressType)
      end

      context "with a Standard SKU" do
        let(:config) { { public_ip_sku: "Standard" } }

        it "forces a static address, which Standard SKUs require" do
          driver.create(state)
          expect(deployment_parameters[:publicIPAddressType]).to eq("value" => "Static")
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
        expect(deployment_parameters[:systemAssignedIdentity]).to eq("value" => true)
      end

      it "converts user assigned identities into the ARM map shape" do
        driver.create(state)
        expect(deployment_parameters[:userAssignedIdentities])
          .to eq("value" => { "/subscriptions/x/userAssignedIdentities/id-1" => {} })
      end
    end

    describe "shared storage accounts" do
      let(:config) { { existing_storage_account_blob_url: "https://shared.blob.core.windows.net" } }

      it "adds a per-resource-group suffix so instances do not collide on disk names" do
        driver.create(state)
        expect(deployment_parameters[:osDiskNameSuffix]).to eq("value" => "-#{state[:azure_resource_group_name]}")
      end

      it "passes the blob url through" do
        driver.create(state)
        expect(deployment_parameters[:existingStorageAccountBlobURL])
          .to eq("value" => "https://shared.blob.core.windows.net")
      end
    end

    it "does not send an osDiskNameSuffix without a shared storage account" do
      driver.create(state)
      expect(deployment_parameters).not_to include(:osDiskNameSuffix)
    end

    describe "custom data" do
      let(:config) { { custom_data: "#!/bin/sh\necho hi\n" } }

      it "sends it base64 encoded" do
        driver.create(state)
        expect(Base64.decode64(deployment_parameters[:customData]["value"])).to eq("#!/bin/sh\necho hi\n")
      end
    end

    it "omits customData when none is configured" do
      driver.create(state)
      expect(deployment_parameters).not_to include(:customData)
    end

    describe "key vault settings" do
      let(:config) { { secret_url: "https://v.vault.azure.net/secrets/c", vault_name: "v", vault_resource_group: "vault-rg" } }

      it "passes all three through as parameters" do
        driver.create(state)
        expect(deployment_parameters).to include(
          secretUrl: { "value" => "https://v.vault.azure.net/secrets/c" },
          vaultName: { "value" => "v" },
          vaultResourceGroup: { "value" => "vault-rg" }
        )
      end

      it "renders the matching secrets block into the template" do
        driver.create(state)
        vm = vm_resource(submitted_deployments.first[:deployment].properties.template)
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
        expect(deployment_parameters).not_to include(:adminPassword)
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
      let(:network_interfaces) { instance_double(Azure::Network2::Profiles::Latest::Mgmt::NetworkInterfaces, get: network_interface(private_ip: "10.0.0.7")) }

      before do
        allow(Azure::Network2::Profiles::Latest::Mgmt::NetworkInterfaces).to receive(:new).and_return(network_interfaces)
      end

      it "uses the NIC's private address" do
        driver.create(state)
        expect(state[:hostname]).to eq("10.0.0.7")
      end

      it "looks up the NIC by the name it deployed" do
        driver.create(state)
        expect(network_interfaces).to have_received(:get).with(state[:azure_resource_group_name], "nic-#{state[:vm_name]}")
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

  describe "when a deployment is already running" do
    before do
      allow(resource_client.deployments).to receive(:begin_create_or_update_async)
        .and_raise(azure_operation_error(code: "DeploymentActive"))
    end

    it "does not raise, because the existing deployment will finish on its own" do
      expect { driver.create(state) }.not_to raise_error
    end

    it "tells the user what happened" do
      allow(Kitchen.logger).to receive(:info)
      driver.create(state)
      expect(Kitchen.logger).to have_received(:info).with(/Deployment for resource group .* is ongoing/)
    end

    it "still resolves a hostname" do
      driver.create(state)
      expect(state[:hostname]).to eq("40.121.0.1")
    end
  end

  describe "when the deployment fails for any other reason" do
    before do
      allow(resource_client.deployments).to receive(:begin_create_or_update_async)
        .and_raise(azure_operation_error(code: "InvalidTemplate", message: "the template is malformed"))
    end

    it "re-raises" do
      expect { driver.create(state) }.to raise_error(MsRestAzure2::AzureOperationError)
    end
  end

  # Records every deployment submitted through a doubled client.
  #
  # @param client [Object] the doubled resource management client.
  # @return [void]
  def record_deployments(client)
    allow(client.deployments).to receive(:begin_create_or_update_async) do |resource_group, name, deployment|
      submitted_deployments << { resource_group:, name:, deployment: }
      accepted_request
    end
  end

  # The ARM parameters of the main virtual machine deployment.
  #
  # @return [Hash, nil]
  def deployment_parameters
    main = submitted_deployments.find { |entry| entry[:name].start_with?("deploy-") }
    main && main[:deployment].properties.parameters
  end

  # Names of every deployment submitted, in order.
  #
  # @return [Array<String>]
  def deployment_names_submitted
    submitted_deployments.map { |entry| entry[:name] }
  end
end
