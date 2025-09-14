require "spec_helper"
require "kitchen/transport/dummy"

describe Kitchen::Driver::Azurerm do
  let(:logged_output) { StringIO.new }
  let(:logger)        { Logger.new(logged_output) }
  let(:platform)      { Kitchen::Platform.new(name: "fake_platform") }
  let(:transport)     { Kitchen::Transport::Dummy.new }
  let(:instance_name) { "my-instance-name" }
  let(:driver)        { described_class.new(config) }

  let(:subscription_id) { "115b12cb-b0d3-4ed9-94db-f73733be6f3c" }
  let(:location) { "eastus2" }
  let(:machine_size) { "Standard_D4_v3" }
  let(:vm_tags) do
    {
      os_type: "linux",
      distro: "redhat",
    }
  end

  let(:azure_environment) { "AzureChina" }

  let(:image_urn) { "RedHat:rhel-byos:rhel-raw76:7.6.20190620" }
  let(:vm_name) { "my-awesome-vm" }

  let(:config) do
    {
      subscription_id: subscription_id,
      location: location,
      machine_size: machine_size,
      vm_tags: vm_tags,
      image_urn: image_urn,
      vm_name: vm_name,
      azure_environment: azure_environment,
    }
  end

  let(:credentials) do
    Kitchen::Driver::AzureCredentials.new(subscription_id: config[:subscription_id],
      environment: config[:azure_environment])
  end

  let(:options) do
    credentials.azure_options
  end

  let(:client) do
    Azure::Resources2::Profiles::Latest::Mgmt::Client.new(options)
  end

  let(:instance) do
    instance_double(Kitchen::Instance,
      name:      instance_name,
      logger:    logger,
      transport: transport,
      platform:  platform,
      to_str:    "instance_str")
  end

  let(:resource_group) do
    Azure::Resources2::Profiles::Latest::Mgmt::Models::ResourceGroup.new
  end

  let(:resource_groups) do
    client.resource_groups
  end

  before do
    allow(driver).to receive(:instance).and_return(instance)
  end

  it "driver API version is 2" do
    expect(driver.diagnose_plugin[:api_version]).to eq(2)
  end

  describe "#name" do
    it "has an overridden name" do
      expect(driver.name).to eq("Azurerm")
    end
  end

  describe "#default_config" do
    let(:default_config) { driver.instance_variable_get(:@config) }

    it "Should have the username option available" do
      expect(default_config).to have_key(:username)
    end

    it "Should use 'azure' as the default username" do
      expect(default_config[:username]).to eq("azure")
    end

    it "Should have the password option available" do
      expect(default_config).to have_key(:password)
    end

    it "Should have the use_fqdn_hostname option available" do
      expect(default_config).to have_key(:use_fqdn_hostname)
    end

    it "Should use the IP to communicate with VM by default" do
      expect(default_config[:use_fqdn_hostname]).to eq(false)
    end

    it "Should use basic public IP resources" do
      expect(default_config[:public_ip_sku]).to eq("Basic")
    end

    it "should set store_deployment_credentials_in_state to true" do
      expect(default_config[:store_deployment_credentials_in_state]).to eq(true)
    end

    it "Should use tk- vm prefix" do
      expect(default_config[:vm_prefix]).to eq("tk-")
    end
  end

  describe "#validate_state" do
    let(:state) { {} }
    let(:uuid) { SecureRandom.hex(8) }

    it "generates uuid, when one does not exist" do
      driver.validate_state(state)
      expect(state[:uuid].length).to eq(16)
      expect(state[:uuid]).to be_an_instance_of(String)
      expect(state[:uuid]).not_to eq(uuid)
    end

    it "does not set uuid, when one exists" do
      state[:uuid] = uuid
      driver.validate_state(state)
      expect(state[:uuid]).to eq(uuid)
    end

    context "when vm_name is set in config" do
      before do
        config[:vm_name] = vm_name
      end

      it "sets state[:vm_name] to config vm_name" do
        driver.validate_state(state)
        expect(state[:vm_name]).to eq(vm_name)
      end
    end

    context "when vm_name is not set in config" do
      before do
        config.delete(:vm_name)
      end

      it "generates vm_name, when one does not exist in state" do
        driver.validate_state(state)
        expect(state[:vm_name].length).to eq(15)
        expect(state[:vm_name]).to be_an_instance_of(String)
        expect(state[:vm_name]).not_to eq(vm_name)
        expect(state[:vm_name]).to start_with("tk-")
      end

      it "does not generate vm_name, when one exists in state" do
        vm_name_in_state = "blah-doh"
        state[:vm_name] = vm_name_in_state
        driver.validate_state(state)
        expect(state[:vm_name]).to eq(vm_name_in_state)
      end

      context "when vm_prefix is set in config" do
        before do
          config[:vm_prefix] = "ab-"
        end

        it "generates vm_name with prefix, when one does not exist in state" do
          driver.validate_state(state)
          expect(state[:vm_name].length).to eq(15)
          expect(state[:vm_name]).to be_an_instance_of(String)
          expect(state[:vm_name]).not_to eq(vm_name)
          expect(state[:vm_name]).to start_with("ab-")
        end
      end
    end
  end

  describe "#create" do
    let(:tenant_id) { "2d38055e-66a1-435c-be53-TENANT_ID" }
    let(:client_id) { "2e201a46-44a8-4508-84aa-CLIENT_ID" }
    let(:client_secret) { "2e201a46-44a8-4508-84aa-CLIENT_SECRET" }
    let(:environment) { "AzureChina" }
    let(:resource_group_name) { "testingrocks" }
    let(:base_url) { "https://management.chinacloudapi.cn" }

    let(:deployment_double) { double("DeploymentDouble", value!: nil) }
    let(:network_interfaces_double) { double("NetworkInterfacesDouble", ip_configurations: [ip_configuration_double]) }
    let(:ip_configuration_double) { double("IPConfigurationDouble", private_ipaddress: "192.168.1.5") }
    let(:public_ip_double) { double("PublicIPDouble", ip_address: "100.100.2.5", dns_settings: dns_settings_double) }
    let(:dns_settings_double) { double("DNSSettingsDouble", fqdn: "dns-settings-fqdn") }

    before do
      allow(ENV).to receive(:[]).with("AZURE_TENANT_ID").and_return(tenant_id)
      allow(ENV).to receive(:[]).with("AZURE_CLIENT_ID").and_return(client_id)
      allow(ENV).to receive(:[]).with("AZURE_CLIENT_SECRET").and_return(client_secret)
      allow(ENV).to receive(:[]).with("AZURE_SUBSCRIPTION_ID").and_return(subscription_id)
      allow(ENV).to receive(:[]).with("https_proxy").and_return("")
      allow(ENV).to receive(:[]).with("AZURE_HTTP_LOGGING").and_return("")
      allow(ENV).to receive(:[]).with("GEM_SKIP").and_return("")
      allow(ENV).to receive(:[]).with("http_proxy").and_return("")
      allow(ENV).to receive(:[]).with("GEM_REQUIREMENT_AZURE_MGMT_RESOURCES").and_return("azure_mgmt_resources")
      allow(ENV).to receive(:[]).with("SSL_CERT_FILE").and_call_original
    end

    it "has credentials available" do
      expect(credentials).to be_an_instance_of(Kitchen::Driver::AzureCredentials)
    end

    it "has options" do
      expect(options[:tenant_id]).to eq(tenant_id)
      expect(options[:client_id]).to eq(client_id)
      expect(options[:client_secret]).to eq(client_secret)
    end

    # it "fails to create or update a resource group because we are not authenticated" do
    #   rgn = resource_group_name
    #   rg = resource_group
    #   rg.location = location
    #   rg.tags = vm_tags

    #   # https://github.com/Azure/azure-sdk-for-ruby/blob/master/runtime/ms_rest_azure2/spec/azure_operation_error_spec.rb
    #   expect { resource_groups.create_or_update(rgn, rg) }.to raise_error( an_instance_of(MsRestAzure2::AzureOperationError) )
    # end

    # it "saves deployment credentials to state, when store_deployment_credentials_in_state is true" do
    #   # This MUST come first
    #   config[:store_deployment_credentials_in_state] = true
    #   config[:username] = "azure"
    #   config[:password] = "admin-password"

    #   allow(driver).to receive(:create_resource_group)
    #   allow(driver).to receive(:deployment)
    #   allow(driver).to receive(:create_deployment_async).and_return(deployment_double)
    #   allow(driver).to receive(:follow_deployment_until_end_state)
    #   allow(driver).to receive(:get_network_interface).and_return(network_interfaces_double)
    #   allow(driver).to receive(:get_public_ip).and_return(public_ip_double)

    #   state = {}
    #   driver.create(state)
    #   expect(state[:username]).to eq("azure")
    #   expect(state[:password]).to eq("admin-password")
    # end

    # it "does not save deployment credentials to state, when store_deployment_credentials_in_state is false" do
    #   # This MUST come first
    #   config[:store_deployment_credentials_in_state] = false
    #   config[:username] = "azure"
    #   config[:password] = "admin-password"

    #   allow(driver).to receive(:create_resource_group)
    #   allow(driver).to receive(:deployment)
    #   allow(driver).to receive(:create_deployment_async).and_return(deployment_double)
    #   allow(driver).to receive(:follow_deployment_until_end_state)
    #   allow(driver).to receive(:get_network_interface).and_return(network_interfaces_double)
    #   allow(driver).to receive(:get_public_ip).and_return(public_ip_double)

    #   state = {}
    #   driver.create(state)
    #   expect(state[:username]).to eq(nil)
    #   expect(state[:password]).to eq(nil)
    # end
  end

  describe "#virtual_machine_deployment_template" do
    subject { driver.send(:virtual_machine_deployment_template) }

    let(:parsed_json) { JSON.parse(subject) }
    let(:vm_resource) { parsed_json["resources"].find { |x| x["type"] == "Microsoft.Compute/virtualMachines" } }

    context "when plan config is provided" do
      let(:plan_name) { "plan-abc" }
      let(:plan_product) { "my-product" }
      let(:plan_publisher) { "captain-america" }
      let(:plan_promotion_code) { "50-percent-off" }

      let(:plan) do
        {
          name: plan_name,
          product: plan_product,
          publisher: plan_publisher,
          promotion_code: plan_promotion_code,
        }
      end

      let(:config) do
        {
          subscription_id: subscription_id,
          location: location,
          machine_size: machine_size,
          vm_tags: vm_tags,
          plan: plan,
          image_urn: image_urn,
          vm_name: vm_name,
        }
      end

      it "includes plan information in deployment template" do
        expect(vm_resource).to have_key("plan")
        expect(vm_resource["plan"]["name"]).to eq(plan_name)
        expect(vm_resource["plan"]["product"]).to eq(plan_product)
        expect(vm_resource["plan"]["publisher"]).to eq(plan_publisher)
        expect(vm_resource["plan"]["promotionCode"]).to eq(plan_promotion_code)
      end
    end

    context "when plan config is not provided" do
      let(:config) do
        {
          subscription_id: subscription_id,
          location: location,
          machine_size: machine_size,
          vm_tags: vm_tags,
          image_urn: image_urn,
          vm_name: vm_name,
        }
      end

      it "does not include plan information in deployment template" do
        expect(vm_resource).not_to have_key("plan")
      end
    end
  end
end
