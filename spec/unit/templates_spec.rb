# The ARM templates are string-interpolated ERB, so any conditional that emits
# a stray comma or an unbalanced brace produces a template that only fails at
# deploy time. These specs render every template across the option matrix and
# assert the result actually parses.
RSpec.describe "ARM deployment templates" do
  let(:driver) { build_driver }

  # Options that change the shape of the rendered template. Each is toggled
  # independently against the default configuration.
  TEMPLATE_VARIATIONS = {
    "defaults" => {},
    "unmanaged disks" => { use_managed_disks: false },
    "ephemeral os disk" => { use_ephemeral_osdisk: true },
    "sized os disk" => { os_disk_size_gb: 128 },
    "custom data" => { custom_data: "#cloud-config\npackages:\n  - htop\n" },
    "data disks" => { data_disks: [{ lun: 0, disk_size_gb: 128 }] },
    "data disks, unmanaged" => { data_disks: [{ lun: 0, disk_size_gb: 128 }], use_managed_disks: false },
    "vhd image" => { image_url: "https://sa.blob.core.windows.net/vhds/my.vhd", use_managed_disks: false },
    "managed image" => { image_id: "/subscriptions/x/images/my-image" },
    "shared storage account" => { existing_storage_account_blob_url: "https://shared.blob.core.windows.net", use_managed_disks: false },
    "shared storage account, no container" => { existing_storage_account_blob_url: "https://shared.blob.core.windows.net", existing_storage_account_container: "", use_managed_disks: false },
    "marketplace plan" => { plan: { name: "n", product: "p", publisher: "pub" } },
    "vm tags" => { vm_tags: { owner: "platform", env: "ci" } },
    "key vault certificate" => { secret_url: "https://v.vault.azure.net/secrets/c", vault_name: "v", vault_resource_group: "rg" },
    "standard public ip" => { public_ip_sku: "Standard" },
    "everything at once" => {
      os_disk_size_gb: 256,
      custom_data: "#cloud-config\n",
      data_disks: [{ lun: 0, disk_size_gb: 128 }],
      plan: { name: "n", product: "p", publisher: "pub", promotion_code: "c" },
      vm_tags: { owner: "platform" },
      secret_url: "https://v.vault.azure.net/secrets/c",
      vault_name: "v",
      vault_resource_group: "rg",
      public_ip_sku: "Standard",
    },
  }.freeze

  TEMPLATE_VARIATIONS.each do |label, options|
    context "with #{label}" do
      %i{password ssh_key}.each do |auth|
        context "authenticating by #{auth}" do
          let(:transport) do
            auth == :ssh_key ? transport_double(name: "Ssh", ssh_key: File.join(ENV.fetch("HOME"), "id_rsa")) : transport_double
          end

          it "renders a valid public template" do
            driver = build_driver(transport:, **options)
            expect(driver.virtual_machine_deployment_template).to be_a_valid_arm_template
          end

          it "renders a valid internal template" do
            driver = build_driver(transport:, vnet_id: "/vnet", subnet_id: "/subnet", **options)
            expect(driver.virtual_machine_deployment_template).to be_a_valid_arm_template
          end

          it "renders a valid internal template with a public IP" do
            driver = build_driver(transport:, vnet_id: "/vnet", subnet_id: "/subnet", public_ip: true, **options)
            expect(driver.virtual_machine_deployment_template).to be_a_valid_arm_template
          end
        end
      end
    end
  end

  describe "structural invariants" do
    %w{public internal}.each do |name|
      context "#{name}.erb" do
        let(:template) do
          driver = name == "public" ? build_driver : build_driver(vnet_id: "/vnet", subnet_id: "/subnet")
          rendered_template(driver)
        end

        it "declares the 2015-01-01 deployment template schema" do
          expect(template["$schema"]).to eq("https://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#")
        end

        it "declares a content version" do
          expect(template["contentVersion"]).to eq("1.0.0.0")
        end

        it "contains exactly one virtual machine" do
          expect(template["resources"].count { |r| r["type"] == "Microsoft.Compute/virtualMachines" }).to eq(1)
        end

        it "contains exactly one network interface" do
          expect(template["resources"].count { |r| r["type"] == "Microsoft.Network/networkInterfaces" }).to eq(1)
        end

        it "gives every resource a type, name and apiVersion" do
          template["resources"].each do |resource|
            expect(resource).to include("type", "name", "apiVersion")
          end
        end

        it "references only parameters it declares" do
          declared = template["parameters"].keys.map(&:downcase)
          referenced = JSON.generate(template).scan(/parameters\('([^']+)'\)/).flatten.map(&:downcase).uniq

          expect(referenced - declared).to be_empty
        end

        it "references only variables it declares" do
          declared = template["variables"].keys.map(&:downcase)
          referenced = JSON.generate(template).scan(/variables\('([^']+)'\)/).flatten.map(&:downcase).uniq

          expect(referenced - declared).to be_empty
        end
      end
    end
  end

  describe "empty.erb" do
    subject(:template) { driver.send(:virtual_machine_deployment_template_file, "empty.erb", nil) }

    it "is valid ARM JSON" do
      expect(template).to be_a_valid_arm_template
    end

    it "declares no resources, which is what makes a Complete deployment delete everything" do
      expect(JSON.parse(template)["resources"]).to eq([])
    end

    it "declares no parameters" do
      expect(JSON.parse(template)["parameters"]).to eq({})
    end
  end

  describe "every parameter the driver sends is declared by the template" do
    let(:state) { { uuid: "abc123", vm_name: "tk-abc123", azure_resource_group_name: "kitchen-rg" } }

    TEMPLATE_VARIATIONS.each do |label, options|
      it "holds for #{label}" do
        driver = build_driver(**options)
        sent = driver.build_deployment_parameters(state).keys.map { |key| key.to_s.downcase }
        declared = rendered_template(driver)["parameters"].keys.map(&:downcase)

        expect(sent - declared).to be_empty
      end
    end
  end
end
