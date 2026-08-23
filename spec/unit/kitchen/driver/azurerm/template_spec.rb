RSpec.describe Kitchen::Driver::Azurerm, "deployment template rendering" do
  subject(:driver) { build_driver(transport:, platform_name:, **config) }

  let(:config) { {} }
  let(:transport) { transport_double }
  let(:platform_name) { "ubuntu-22.04" }

  describe "#virtual_machine_deployment_template" do
    it "renders valid JSON for the default configuration" do
      expect(driver.virtual_machine_deployment_template).to be_a_valid_arm_template
    end

    it "uses the public template when no vnet is configured" do
      expect(driver).to receive(:virtual_machine_deployment_template_file).with("public.erb", any_args)
      driver.virtual_machine_deployment_template
    end

    context "when a vnet_id is configured" do
      let(:config) { { vnet_id: "/subscriptions/x/resourceGroups/y/providers/Microsoft.Network/virtualNetworks/vnet", subnet_id: "subnet-1" } }

      it "renders valid JSON" do
        expect(driver.virtual_machine_deployment_template).to be_a_valid_arm_template
      end

      it "uses the internal template" do
        expect(driver).to receive(:virtual_machine_deployment_template_file).with("internal.erb", any_args)
        driver.virtual_machine_deployment_template
      end

      it "logs which vnet is in use" do
        allow(Kitchen.logger).to receive(:info)
        driver.virtual_machine_deployment_template
        expect(Kitchen.logger).to have_received(:info).with(%r{Using custom vnet: .*virtualNetworks/vnet})
      end

      it "references the configured subnet" do
        expect(driver.virtual_machine_deployment_template).to include("subnet-1")
      end

      it "resolves a subnet name against the configured vnet" do
        expect(subnet_ref_of(driver))
          .to eq("/subscriptions/x/resourceGroups/y/providers/Microsoft.Network/virtualNetworks/vnet/subnets/subnet-1")
      end

      # `subnet_id` is named like a resource id and sits next to `vnet_id`,
      # which is one. Supplying a full subnet resource id used to be appended
      # to the vnet id, and ARM answered with an opaque
      # "InvalidJsonReferenceFormat" naming a path that appeared nowhere in
      # the user's configuration.
      context "when subnet_id is a full resource id" do
        let(:subnet_resource_id) do
          "/subscriptions/x/resourceGroups/y/providers/Microsoft.Network/virtualNetworks/vnet/subnets/subnet-1"
        end
        let(:config) { super().merge(subnet_id: subnet_resource_id) }

        it "uses it as-is rather than appending it to the vnet id" do
          expect(subnet_ref_of(driver)).to eq(subnet_resource_id)
        end

        it "does not produce a doubled subnets path" do
          expect(driver.virtual_machine_deployment_template).not_to include("subnets//subscriptions")
        end

        it "still renders valid JSON" do
          expect(driver.virtual_machine_deployment_template).to be_a_valid_arm_template
        end

        it "resolves a subnet in a different resource group than the vnet" do
          elsewhere = "/subscriptions/x/resourceGroups/other/providers/Microsoft.Network/virtualNetworks/v2/subnets/s2"
          other = build_driver(transport:, platform_name:, **config.merge(subnet_id: elsewhere))
          expect(subnet_ref_of(other)).to eq(elsewhere)
        end
      end

      it "creates no public IP resource by default" do
        expect(resource_types(rendered_template(driver))).not_to include("Microsoft.Network/publicIPAddresses")
      end

      context "with public_ip enabled" do
        let(:config) { super().merge(public_ip: true) }

        it "creates a public IP resource" do
          expect(resource_types(rendered_template(driver))).to include("Microsoft.Network/publicIPAddresses")
        end
      end
    end

    describe "marketplace plan" do
      context "when a plan is configured" do
        let(:config) do
          {
            plan: { name: "plan-abc", product: "my-product", publisher: "captain-america", promotion_code: "50-percent-off" },
          }
        end

        it "puts the plan on the virtual machine resource" do
          expect(vm_resource(rendered_template(driver))["plan"]).to eq(
            "name" => "plan-abc",
            "product" => "my-product",
            "publisher" => "captain-america",
            "promotionCode" => "50-percent-off"
          )
        end
      end

      context "when no plan is configured" do
        it "omits the plan" do
          expect(vm_resource(rendered_template(driver))).not_to have_key("plan")
        end
      end

      context "when a partial plan is configured" do
        let(:config) { { plan: { name: "plan-abc", publisher: "captain-america" } } }

        it "emits only the keys that were given" do
          expect(vm_resource(rendered_template(driver))["plan"].keys).to contain_exactly("name", "publisher")
        end
      end

      context "when the plan omits the name and publisher" do
        let(:config) { { plan: { product: "my-product", promotion_code: "code" } } }

        it "emits only the keys that were given" do
          expect(vm_resource(rendered_template(driver))["plan"])
            .to eq("product" => "my-product", "promotionCode" => "code")
        end
      end
    end

    describe "key vault certificates" do
      # These three settings had never reached the template - the renderer did
      # not pass them into the ERB binding, so OpenStruct returned nil and the
      # block was always skipped.
      context "when secret_url, vault_name and vault_resource_group are set" do
        let(:config) do
          {
            secret_url: "https://my-vault.vault.azure.net/secrets/winrm/abc123",
            vault_name: "my-vault",
            vault_resource_group: "vault-rg",
          }
        end

        it "still renders valid JSON" do
          expect(driver.virtual_machine_deployment_template).to be_a_valid_arm_template
        end

        it "adds a secrets block to the osProfile" do
          os_profile = vm_resource(rendered_template(driver))["properties"]["osProfile"]
          expect(os_profile["secrets"]).to eq(
            [
              {
                "sourceVault" => { "id" => "[resourceId(parameters('vaultResourceGroup'), 'Microsoft.KeyVault/vaults', parameters('vaultName'))]" },
                "vaultCertificates" => [{ "certificateUrl" => "[parameters('secretUrl')]", "certificateStore" => "My" }],
              },
            ]
          )
        end

        it "uses the correct resource provider namespace" do
          expect(driver.virtual_machine_deployment_template).to include("Microsoft.KeyVault/vaults")
          expect(driver.virtual_machine_deployment_template).not_to include("Microsoft,KeyVault")
        end

        it "renders for the internal template too" do
          driver = build_driver(**config, vnet_id: "/vnet", subnet_id: "/subnet")
          expect(vm_resource(rendered_template(driver))["properties"]["osProfile"]).to have_key("secrets")
        end
      end

      context "when only some of the key vault settings are given" do
        let(:config) { { vault_name: "my-vault" } }

        it "still emits the secrets block, so ARM reports the missing pieces" do
          expect(vm_resource(rendered_template(driver))["properties"]["osProfile"]).to have_key("secrets")
        end
      end

      context "when none are set" do
        it "omits the secrets block" do
          expect(vm_resource(rendered_template(driver))["properties"]["osProfile"]).not_to have_key("secrets")
        end
      end
    end

    describe "vm tags" do
      let(:config) { { vm_tags: { os_type: "linux", distro: "redhat" } } }

      it "applies the tags to the virtual machine" do
        expect(vm_resource(rendered_template(driver))["tags"]).to eq("os_type" => "linux", "distro" => "redhat")
      end

      it "applies the tags to every taggable resource" do
        tagged = rendered_template(driver)["resources"].select { |r| r["tags"]&.any? }
        expect(tagged.length).to be > 1
      end

      context "when a tag value contains a double quote" do
        let(:config) { { vm_tags: { note: 'he said "hello"' } } }

        it "does not produce an unparseable template" do
          expect(driver.virtual_machine_deployment_template).to be_a_valid_arm_template
        end

        it "round-trips the value intact" do
          expect(vm_resource(rendered_template(driver))["tags"]["note"]).to eq('he said "hello"')
        end
      end

      context "when a tag value contains a backslash" do
        let(:config) { { vm_tags: { path: 'C:\\Windows' } } }

        it "round-trips the value intact" do
          expect(vm_resource(rendered_template(driver))["tags"]["path"]).to eq('C:\\Windows')
        end
      end
    end

    describe "image selection" do
      it "defaults to a marketplace image reference" do
        image = vm_resource(rendered_template(driver))["properties"]["storageProfile"]["imageReference"]
        expect(image).to include("publisher", "offer", "sku", "version")
      end

      context "with an image_id" do
        let(:config) { { image_id: "/subscriptions/x/resourceGroups/y/providers/Microsoft.Compute/images/my-image" } }

        it "references the managed image by id" do
          image = vm_resource(rendered_template(driver))["properties"]["storageProfile"]["imageReference"]
          expect(image).to eq("id" => "[parameters('imageId')]")
        end
      end

      context "with an Azure Compute Gallery image id" do
        let(:config) { { image_id: "/subscriptions/x/resourceGroups/y/providers/Microsoft.Compute/galleries/g/images/i/versions/1.0.0" } }

        it "renders valid JSON" do
          expect(driver.virtual_machine_deployment_template).to be_a_valid_arm_template
        end

        it "references it by id" do
          image = vm_resource(rendered_template(driver))["properties"]["storageProfile"]["imageReference"]
          expect(image).to eq("id" => "[parameters('imageId')]")
        end
      end
    end

    describe "os disk options" do
      context "with use_ephemeral_osdisk" do
        let(:config) { { use_ephemeral_osdisk: true } }

        it "sets the ephemeral disk placement" do
          os_disk = vm_resource(rendered_template(driver))["properties"]["storageProfile"]["osDisk"]
          expect(os_disk["diffDiskSettings"]).to eq("option" => "Local")
        end
      end

      context "with os_disk_size_gb" do
        let(:config) { { os_disk_size_gb: 128 } }

        it "sets the disk size from the parameter" do
          os_disk = vm_resource(rendered_template(driver))["properties"]["storageProfile"]["osDisk"]
          expect(os_disk["diskSizeGB"]).to eq("[parameters('osDiskSizeGb')]")
        end
      end

      context "with no os_disk_size_gb" do
        it "omits the disk size" do
          os_disk = vm_resource(rendered_template(driver))["properties"]["storageProfile"]["osDisk"]
          expect(os_disk).not_to have_key("diskSizeGB")
        end
      end
    end

    describe "data disks" do
      context "with managed disks" do
        let(:config) { { data_disks: [{ lun: 0, disk_size_gb: 128 }, { lun: 1, disk_size_gb: 256 }] } }

        it "adds one entry per configured disk" do
          disks = vm_resource(rendered_template(driver))["properties"]["storageProfile"]["dataDisks"]
          expect(disks).to eq(
            [
              { "name" => "datadisk0", "lun" => 0, "diskSizeGB" => 128, "createOption" => "Empty" },
              { "name" => "datadisk1", "lun" => 1, "diskSizeGB" => 256, "createOption" => "Empty" },
            ]
          )
        end
      end

      context "without data_disks" do
        it "omits the dataDisks key entirely" do
          expect(vm_resource(rendered_template(driver))["properties"]["storageProfile"]).not_to have_key("dataDisks")
        end
      end
    end
  end

  describe "network security group" do
    let(:nsg) { rendered_template(driver)["resources"].find { |r| r["type"] == "Microsoft.Network/networkSecurityGroups" } }
    let(:nic) { rendered_template(driver)["resources"].find { |r| r["type"] == "Microsoft.Network/networkInterfaces" } }

    # Standard SKU public IPs are closed to inbound traffic unless a security
    # group opens it, so a public instance without one is unreachable.
    it "is created alongside a public IP" do
      expect(nsg).not_to be_nil
    end

    it "is attached to the network interface" do
      expect(nic["properties"]["networkSecurityGroup"]["id"])
        .to eq("[resourceId('Microsoft.Network/networkSecurityGroups', variables('nsgName'))]")
    end

    it "is created before the interface that references it" do
      expect(nic["dependsOn"]).to include("[concat('Microsoft.Network/networkSecurityGroups/', variables('nsgName'))]")
    end

    it "opens SSH for an SSH transport" do
      expect(rule_ports(nsg)).to eq(["22"])
    end

    it "gives each rule a distinct priority" do
      priorities = nsg["properties"]["securityRules"].map { |r| r["properties"]["priority"] }
      expect(priorities).to eq(priorities.uniq)
    end

    it "allows inbound TCP" do
      properties = nsg["properties"]["securityRules"].first["properties"]
      expect(properties).to include("protocol" => "Tcp", "access" => "Allow", "direction" => "Inbound")
    end

    context "with a WinRM transport" do
      let(:transport) { transport_double(name: "Winrm") }
      let(:platform_name) { "windows-2022" }

      it "opens both WinRM ports" do
        expect(rule_ports(nsg)).to contain_exactly("5985", "5986")
      end
    end

    # The transport knows which port it will dial; the security group used to
    # assume the default. Setting `port:` on the transport therefore produced
    # an instance nothing could reach, and the only way out was to repeat the
    # port in open_ports.
    context "with a transport on a non-default port" do
      let(:transport) { transport_double(name: "Ssh", port: 2222) }

      it "opens the port the transport will actually connect on" do
        expect(rule_ports(nsg)).to include("2222")
      end

      it "does not open the default port instead" do
        expect(rule_ports(nsg)).to eq(["2222"])
      end
    end

    context "with a WinRM transport on a non-default port" do
      let(:transport) { transport_double(name: "Winrm", port: 5999) }
      let(:platform_name) { "windows-2022" }

      # Both standard listeners are still created by the bootstrap script, so
      # they stay open alongside whatever the transport was pointed at.
      it "opens the configured port as well as the standard pair" do
        expect(rule_ports(nsg)).to contain_exactly("5985", "5986", "5999")
      end
    end

    context "with a transport that reports no port" do
      let(:transport) { transport_double(name: "Ssh") }

      it "falls back to the default" do
        expect(rule_ports(nsg)).to eq(["22"])
      end
    end

    context "with extra open_ports" do
      let(:config) { { open_ports: [443, 8080] } }

      it "opens them alongside the transport's own port" do
        expect(rule_ports(nsg)).to contain_exactly("22", "443", "8080")
      end

      it "does not duplicate a port the transport already opened" do
        driver = build_driver(open_ports: [22, 443])
        nsg = rendered_template(driver)["resources"].find { |r| r["type"] == "Microsoft.Network/networkSecurityGroups" }
        expect(rule_ports(nsg)).to contain_exactly("22", "443")
      end
    end

    context "when an existing nsg_id is supplied" do
      let(:config) { { nsg_id: "/subscriptions/x/resourceGroups/y/providers/Microsoft.Network/networkSecurityGroups/mine" } }

      it "creates no security group of its own" do
        expect(nsg).to be_nil
      end

      it "attaches the supplied one instead" do
        expect(nic["properties"]["networkSecurityGroup"]["id"]).to eq("[parameters('nsgId')]")
      end
    end

    context "in a caller-supplied vnet with no public IP" do
      let(:config) { { vnet_id: "/vnet", subnet_id: "/subnet" } }

      it "creates no security group, leaving the subnet's rules alone" do
        expect(nsg).to be_nil
      end

      it "attaches nothing to the interface" do
        expect(nic["properties"]).not_to have_key("networkSecurityGroup")
      end

      context "but with a public IP" do
        let(:config) { super().merge(public_ip: true) }

        it "creates one, because the public IP needs it" do
          expect(nsg).not_to be_nil
        end
      end
    end
  end

  describe "boot diagnostics" do
    let(:boot_diagnostics) { vm_resource(rendered_template(driver))["properties"]["diagnosticsProfile"]["bootDiagnostics"] }

    # This block used to be emitted only for unmanaged-disk deployments, so on
    # the default path boot diagnostics silently did nothing.
    it "is present on the default managed-disk path" do
      expect(boot_diagnostics).to eq("enabled" => "[parameters('bootDiagnosticsEnabled')]")
    end

    it "needs no storage account" do
      expect(boot_diagnostics).not_to have_key("storageUri")
    end
  end

  describe "#boot_diagnostics_enabled?" do
    it "defaults to enabled" do
      expect(driver.boot_diagnostics_enabled?).to be true
    end

    it "accepts a boolean false" do
      expect(build_driver(boot_diagnostics_enabled: false).boot_diagnostics_enabled?).to be false
    end

    # The setting used to default to the string "true", so kitchen.yml files in
    # the wild carry both spellings.
    it "accepts the string \"false\"" do
      expect(build_driver(boot_diagnostics_enabled: "false").boot_diagnostics_enabled?).to be false
    end

    it "accepts the string \"true\"" do
      expect(build_driver(boot_diagnostics_enabled: "true").boot_diagnostics_enabled?).to be true
    end
  end

  describe "#data_disks_for_vm_json" do
    it "is nil when no data disks are configured" do
      expect(driver.data_disks_for_vm_json).to be_nil
    end

    context "with data disks" do
      let(:config) { { data_disks: [{ lun: 3, disk_size_gb: 64 }] } }

      it "describes each disk for the template" do
        expect(JSON.parse(driver.data_disks_for_vm_json))
          .to eq([{ "name" => "datadisk3", "lun" => 3, "diskSizeGB" => 64, "createOption" => "Empty" }])
      end
    end
  end

  describe "#vm_tag_string" do
    it "is empty for no tags" do
      expect(driver.vm_tag_string({})).to eq("")
    end

    it "is empty for nil" do
      expect(driver.vm_tag_string(nil)).to eq("")
    end

    it "renders a single tag with no trailing comma" do
      expect(driver.vm_tag_string(env: "prod")).to eq('"env": "prod"')
    end

    it "separates multiple tags with a comma and newline" do
      expect(driver.vm_tag_string(a: "1", b: "2")).to eq(%{"a": "1",\n"b": "2"})
    end

    it "escapes characters that would break the surrounding JSON" do
      expect(driver.vm_tag_string(note: 'a "quoted" value')).to eq('"note": "a \"quoted\" value"')
    end

    it "stringifies non-string values" do
      expect(driver.vm_tag_string(count: 3)).to eq('"count": "3"')
    end
  end

  describe "#plan_json" do
    it "is nil when no plan is configured" do
      expect(driver.plan_json).to be_nil
    end

    context "when plan is explicitly nil" do
      let(:config) { { plan: nil } }

      it "is nil rather than raising" do
        expect(driver.plan_json).to be_nil
      end
    end

    context "with a full plan" do
      let(:config) { { plan: { name: "n", product: "p", publisher: "pub", promotion_code: "code" } } }

      it "maps promotion_code to the ARM promotionCode key" do
        expect(JSON.parse(driver.plan_json)).to eq("name" => "n", "product" => "p", "promotionCode" => "code", "publisher" => "pub")
      end
    end
  end

  describe "#template_for_transport_name" do
    context "with an SSH transport carrying a key" do
      let(:transport) { transport_double(name: "Ssh", ssh_key: ssh_key_path) }
      let(:ssh_key_path) { File.join(ENV.fetch("HOME"), "id_rsa") }

      it "generates a key pair when the private key does not exist" do
        driver.template_for_transport_name
        expect(File).to exist(ssh_key_path)
        expect(File).to exist("#{ssh_key_path}.pub")
      end

      it "creates the private key with 0600 permissions" do
        driver.template_for_transport_name
        expect(File.stat(ssh_key_path).mode & 0777).to eq(0600)
      end

      it "injects the public key into the linux configuration" do
        template = JSON.parse(driver.template_for_transport_name)
        linux = vm_resource(template)["properties"]["osProfile"]["linuxConfiguration"]
        expect(linux["disablePasswordAuthentication"]).to eq("true")
        expect(linux["ssh"]["publicKeys"].first["keyData"]).to start_with("ssh-rsa ")
      end

      it "omits adminPassword from the template" do
        expect(driver.template_for_transport_name).not_to include("adminPassword")
      end

      context "when the private key already exists" do
        before do
          File.write(ssh_key_path, "an existing private key")
          File.write("#{ssh_key_path}.pub", "ssh-rsa AAAAEXISTING existing@key\n")
        end

        it "reads the adjacent .pub file rather than generating a new key" do
          template = JSON.parse(driver.template_for_transport_name)
          key_data = vm_resource(template)["properties"]["osProfile"]["linuxConfiguration"]["ssh"]["publicKeys"].first["keyData"]
          expect(key_data).to eq("ssh-rsa AAAAEXISTING existing@key")
        end

        it "does not overwrite the existing private key" do
          driver.template_for_transport_name
          expect(File.read(ssh_key_path)).to eq("an existing private key")
        end

        context "and ssh_public_key names a different file" do
          let(:transport) { transport_double(name: "Ssh", ssh_key: ssh_key_path, ssh_public_key: explicit_public_key) }
          let(:explicit_public_key) { File.join(ENV.fetch("HOME"), "elsewhere.pub") }

          before { File.write(explicit_public_key, "ssh-rsa AAAAEXPLICIT explicit@key\n") }

          it "uses the explicitly configured public key" do
            template = JSON.parse(driver.template_for_transport_name)
            key_data = vm_resource(template)["properties"]["osProfile"]["linuxConfiguration"]["ssh"]["publicKeys"].first["keyData"]
            expect(key_data).to eq("ssh-rsa AAAAEXPLICIT explicit@key")
          end
        end
      end
    end

    context "with a WinRM transport" do
      let(:transport) { transport_double(name: "Winrm") }
      let(:platform_name) { "windows-2022" }
      let(:os_profile) { vm_resource(JSON.parse(driver.template_for_transport_name))["properties"]["osProfile"] }

      it "adds base64 custom data that configures WinRM" do
        expect(Base64.decode64(os_profile["customData"])).to include("winrm create winrm/config/listener")
      end

      it "adds the unattend content that runs the script on first logon" do
        content = os_profile["windowsConfiguration"]["additionalUnattendContent"]
        expect(content.map { |entry| entry["settingName"] }).to contain_exactly("FirstLogonCommands", "AutoLogon")
      end

      it "still renders valid JSON" do
        expect(driver.template_for_transport_name).to be_a_valid_arm_template
      end

      context "on Nano Server, which has no WinRM bootstrap" do
        let(:platform_name) { "windows-nano" }

        it "adds no custom data" do
          expect(os_profile).not_to have_key("customData")
        end
      end

      context "with format_data_disks enabled" do
        let(:config) { { format_data_disks: true, data_disks: [{ lun: 0, disk_size_gb: 128 }] } }

        it "includes the disk formatting script in custom data" do
          expect(Base64.decode64(os_profile["customData"])).to include("Initializing and formatting raw disks")
        end

        it "announces that the disks will be formatted" do
          allow(Kitchen.logger).to receive(:info)
          os_profile
          expect(Kitchen.logger).to have_received(:info).with(/Data disks will be initialized and formatted NTFS/)
        end
      end

      context "with format_data_disks enabled but no data disks" do
        let(:config) { { format_data_disks: true } }

        it "still emits the formatting script, harmlessly" do
          expect(Base64.decode64(os_profile["customData"])).to include("Initializing and formatting raw disks")
        end

        it "does not claim any disks will be formatted" do
          allow(Kitchen.logger).to receive(:info)
          os_profile
          expect(Kitchen.logger).not_to have_received(:info).with(/Data disks will be initialized/)
        end
      end

      context "with a custom winrm_powershell_script" do
        let(:config) { { winrm_powershell_script: "Write-Host 'my own bootstrap'" } }

        it "uses the supplied script instead of the default" do
          decoded = Base64.decode64(os_profile["customData"])
          expect(decoded).to include("my own bootstrap")
          expect(decoded).not_to include("New-SelfSignedCertificate")
        end
      end
    end

    context "with a transport that is neither SSH-keyed nor WinRM" do
      it "leaves the template untouched" do
        expect(JSON.parse(driver.template_for_transport_name)).to eq(rendered_template(driver))
      end
    end
  end

  # A Windows instance carries its WinRM bootstrap in custom data, which is the
  # same single slot the user's own custom_data has to travel in. The bootstrap
  # used to be assigned over the top of it, so configuring custom_data on
  # Windows silently did nothing at all.
  describe "custom_data on Windows" do
    subject(:driver) do
      build_driver(transport: transport_double(name: "Winrm"), platform_name: "windows-2022",
        custom_data: user_script)
    end

    let(:user_script) { "New-Item -Path C:\\kitchen-marker.txt -ItemType File\n" }

    # @return [String] the decoded custom data the VM will actually receive.
    def custom_data_of(driver)
      template = JSON.parse(driver.template_for_transport_name)
      resource = template["resources"].find { |r| r["type"] == "Microsoft.Compute/virtualMachines" }
      Base64.decode64(resource["properties"]["osProfile"]["customData"])
    end

    it "keeps the user's custom_data" do
      expect(custom_data_of(driver)).to include("kitchen-marker.txt")
    end

    it "still installs the WinRM listeners" do
      expect(custom_data_of(driver)).to include("winrm create")
    end

    it "runs the user's script after WinRM is configured" do
      decoded = custom_data_of(driver)
      expect(decoded.index("winrm create")).to be < decoded.index("kitchen-marker.txt")
    end

    it "logs off last, so the script has run before the session ends" do
      expect(custom_data_of(driver).strip).to end_with("logoff")
    end

    it "reads custom_data from a file when it names one" do
      path = File.join(ENV.fetch("HOME"), "bootstrap.ps1")
      File.write(path, "Write-Host 'from a file'\n")
      from_file = build_driver(transport: transport_double(name: "Winrm"),
        platform_name: "windows-2022", custom_data: path)

      expect(custom_data_of(from_file)).to include("from a file")
    end

    it "is unchanged when no custom_data is configured" do
      without = build_driver(transport: transport_double(name: "Winrm"), platform_name: "windows-2022")
      expect(custom_data_of(without)).to include("winrm create")
    end
  end

  describe "#prepared_custom_data" do
    it "is nil when custom_data is not configured" do
      expect(build_driver(custom_data: nil).prepared_custom_data).to be_nil
    end

    context "with inline content" do
      let(:config) { { custom_data: "#!/bin/sh\necho hello\n" } }

      it "base64 encodes it" do
        expect(Base64.decode64(driver.prepared_custom_data)).to eq("#!/bin/sh\necho hello\n")
      end

      it "memoizes the result" do
        expect(driver.prepared_custom_data).to equal(driver.prepared_custom_data)
      end
    end

    context "with a path to a file" do
      let(:path) { File.join(ENV.fetch("HOME"), "cloud-init.yml") }
      let(:config) { { custom_data: path } }

      before { File.write(path, "#cloud-config\npackages:\n  - htop\n") }

      it "base64 encodes the file's contents" do
        expect(Base64.decode64(driver.prepared_custom_data)).to eq("#cloud-config\npackages:\n  - htop\n")
      end
    end

    context "with a multi-line document that resembles nothing on disk" do
      let(:config) { { custom_data: "#cloud-config\n#{"x" * 5000}\n" } }

      it "encodes it inline without touching the filesystem" do
        expect(File).not_to receive(:file?)
        expect(Base64.decode64(driver.prepared_custom_data)).to start_with("#cloud-config")
      end
    end
  end

  # @param nsg [Hash] a parsed network security group resource.
  # @return [Array<String>] the destination port of every rule.
  def rule_ports(nsg)
    nsg["properties"]["securityRules"].map { |rule| rule["properties"]["destinationPortRange"] }
  end

  # @param template [Hash] a parsed ARM template.
  # @return [Array<String>] the type of every resource in the template.
  def resource_types(template)
    template["resources"].map { |resource| resource["type"] }
  end

  # The subnet the network interface is wired to, read out of the rendered
  # template rather than from the driver's internals.
  #
  # @param driver [Kitchen::Driver::Azurerm]
  # @return [String]
  def subnet_ref_of(driver)
    rendered_template(driver).dig("variables", "subnetRef")
  end
end
