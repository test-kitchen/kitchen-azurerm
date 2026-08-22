RSpec.describe Kitchen::Driver::Azurerm do
  subject(:driver) { build_driver }

  describe "plugin identity" do
    it "declares driver API version 2" do
      expect(driver.diagnose_plugin[:api_version]).to eq(2)
    end

    it "is named Azurerm" do
      expect(driver.name).to eq("Azurerm")
    end

    it "is a Test Kitchen driver" do
      expect(driver).to be_a(Kitchen::Driver::Base)
    end
  end

  describe "default configuration" do
    subject(:config) { driver_config(driver) }

    # Every default that a user could reasonably depend on. Changing one of
    # these is a breaking change for someone's kitchen.yml, so they are pinned
    # explicitly rather than asserted loosely.
    {
      azure_resource_group_prefix: "kitchen-",
      azure_resource_group_suffix: "",
      explicit_resource_group_name: nil,
      resource_group_tags: {},
      image_url: "",
      image_id: "",
      use_ephemeral_osdisk: false,
      os_disk_size_gb: "",
      os_type: "linux",
      custom_data: "",
      username: "azure",
      vm_prefix: "tk-",
      vm_name: nil,
      store_deployment_credentials_in_state: true,
      nic_name: "",
      vnet_id: "",
      subnet_id: "",
      storage_account_type: "Standard_LRS",
      existing_storage_account_blob_url: "",
      existing_storage_account_container: "vhds",
      boot_diagnostics_enabled: "true",
      winrm_powershell_script: false,
      azure_environment: "Azure",
      pre_deployment_template: "",
      pre_deployment_parameters: {},
      post_deployment_template: "",
      post_deployment_parameters: {},
      plan: {},
      vm_tags: {},
      public_ip: false,
      use_managed_disks: true,
      data_disks: nil,
      format_data_disks: false,
      format_data_disks_powershell_script: false,
      system_assigned_identity: false,
      user_assigned_identities: [],
      destroy_explicit_resource_group: true,
      destroy_explicit_resource_group_tags: true,
      destroy_resource_group_contents: false,
      deployment_sleep: 10,
      secret_url: "",
      vault_name: "",
      vault_resource_group: "",
      public_ip_sku: "Basic",
      azure_api_retries: 5,
      use_fqdn_hostname: false,
    }.each do |key, expected|
      it "defaults #{key} to #{expected.inspect}" do
        # deployment_sleep is overridden by the test helper so the poller does
        # not wait; assert on a driver built without that override.
        driver = described_class.new({})
        allow(driver).to receive(:instance).and_return(instance_double(Kitchen::Instance, name: "default-ubuntu-2204"))
        expect(driver_config(driver)[key]).to eq(expected)
      end
    end

    # Canonical retired the "UbuntuServer" offer after 18.04, so the old
    # default could not be deployed at all.
    it "defaults image_urn to a Marketplace image that still exists" do
      expect(described_class.new({}).instance_variable_get(:@config)[:image_urn])
        .to eq("Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest")
    end

    it "generates a random password" do
      expect(config[:password]).to be_a(String)
      expect(config[:password].length).to be >= 32
    end

    it "generates a different password for every instance" do
      expect(build_driver_password).not_to eq(build_driver_password)
    end

    it "names the resource group after the instance" do
      other = build_driver(instance_name: "windows-2022")
      expect(driver_config(other)[:azure_resource_group_name]).to eq("windows-2022")
    end

    it "reads subscription_id from AZURE_SUBSCRIPTION_ID when unset" do
      ENV["AZURE_SUBSCRIPTION_ID"] = "from-the-environment"
      driver = described_class.new({})
      allow(driver).to receive(:instance).and_return(instance_double(Kitchen::Instance, name: "default"))
      expect(driver_config(driver)[:subscription_id]).to eq("from-the-environment")
    end

    it "lets kitchen.yml override subscription_id" do
      ENV["AZURE_SUBSCRIPTION_ID"] = "from-the-environment"
      expect(driver_config(build_driver(subscription_id: "explicit"))[:subscription_id]).to eq("explicit")
    end
  end

  def build_driver_password
    driver_config(described_class.new({}))[:password]
  end
end
