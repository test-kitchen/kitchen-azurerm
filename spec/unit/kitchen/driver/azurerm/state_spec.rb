RSpec.describe Kitchen::Driver::Azurerm, "state management" do
  subject(:driver) { build_driver(transport:, **config) }

  let(:config) { {} }
  let(:transport) { transport_double }
  let(:state) { {} }

  describe "#existing_state_value?" do
    it "is false when the key is absent" do
      expect(driver.existing_state_value?({}, :uuid)).to be false
    end

    it "is false when the value is nil" do
      expect(driver.existing_state_value?({ uuid: nil }, :uuid)).to be false
    end

    it "is true when the value is present" do
      expect(driver.existing_state_value?({ uuid: "abc" }, :uuid)).to be true
    end

    it "is true for a falsey but non-nil value" do
      expect(driver.existing_state_value?({ use_managed_disks: false }, :use_managed_disks)).to be true
    end

    # A blank value is not a value. Left standing, one written into state by a
    # failed run shadows the real one in config for the rest of the instance's
    # life.
    it "is false when the value is blank" do
      expect(driver.existing_state_value?({ subscription_id: "" }, :subscription_id)).to be false
    end
  end

  describe "#validate_state" do
    it "returns the same Hash it was given" do
      expect(driver.validate_state(state)).to equal(state)
    end

    it "defaults to an empty state" do
      expect(driver.validate_state).to include(:uuid, :vm_name, :server_id)
    end

    describe "uuid" do
      it "generates a 16 character hex uuid" do
        driver.validate_state(state)
        expect(state[:uuid]).to match(/\A[0-9a-f]{16}\z/)
      end

      it "generates a different uuid each time" do
        first = driver.validate_state({})[:uuid]
        expect(driver.validate_state({})[:uuid]).not_to eq(first)
      end

      it "keeps an existing uuid" do
        expect(driver.validate_state(uuid: "deadbeefdeadbeef")[:uuid]).to eq("deadbeefdeadbeef")
      end
    end

    describe "server_id" do
      it "derives from the uuid" do
        driver.validate_state(state)
        expect(state[:server_id]).to eq("vm#{state[:uuid]}")
      end

      it "keeps an existing server_id" do
        expect(driver.validate_state(server_id: "vmexisting")[:server_id]).to eq("vmexisting")
      end
    end

    describe "vm_name" do
      it "uses the configured vm_name verbatim" do
        driver = build_driver(vm_name: "my-awesome-vm")
        expect(driver.validate_state({})[:vm_name]).to eq("my-awesome-vm")
      end

      it "generates a name from the default prefix and the uuid" do
        driver.validate_state(state)
        expect(state[:vm_name]).to start_with("tk-")
        expect(state[:vm_name].length).to eq(15)
      end

      it "honours a custom vm_prefix" do
        driver = build_driver(vm_prefix: "ab-")
        expect(driver.validate_state({})[:vm_name]).to start_with("ab-")
      end

      # Azure caps Windows computer names at 15 characters. A prefix longer
      # than the documented three characters used to push the generated name
      # past that limit, producing a deployment Azure rejects.
      it "never exceeds 15 characters, whatever the prefix" do
        driver = build_driver(vm_prefix: "a-very-long-prefix-")
        expect(driver.validate_state({})[:vm_name].length).to eq(15)
      end

      it "still includes uuid entropy with a longer-than-documented prefix" do
        driver = build_driver(vm_prefix: "kitchen-")
        name = driver.validate_state({})[:vm_name]
        expect(name).to start_with("kitchen-")
        expect(name.length).to eq(15)
      end

      # The network interface name is derived from the VM name, and Azure
      # requires both to end with a word character. Truncating the prefix to
      # exactly 15 characters could leave a trailing separator, which ARM
      # rejected at preflight:
      #
      #   Resource name nic-verylongprefix- is invalid. [...] it must end with
      #   a word character or with '_'.
      it "does not end with a separator when the prefix fills the whole name" do
        driver = build_driver(vm_prefix: "verylongprefix-")
        expect(driver.validate_state({})[:vm_name]).to match(/\w\z/)
      end

      it "derives a network interface name Azure will accept" do
        driver = build_driver(vm_prefix: "verylongprefix-")
        state = driver.validate_state({})
        expect(driver.nic_name(state)).to match(/\A\w[\w.-]*\w\z/)
      end

      it "keeps uuid entropy even when the prefix fills the whole name" do
        driver = build_driver(vm_prefix: "verylongprefix-")
        names = Array.new(5) { driver.validate_state({})[:vm_name] }
        expect(names.uniq.length).to be > 1
      end

      it "still caps a prefix that is longer than the whole budget" do
        driver = build_driver(vm_prefix: "an-absurdly-long-prefix-indeed-")
        name = driver.validate_state({})[:vm_name]
        expect(name.length).to eq(15)
        expect(name).to match(/\w\z/)
      end

      it "keeps an existing vm_name" do
        expect(driver.validate_state(vm_name: "from-state")[:vm_name]).to eq("from-state")
      end
    end

    describe "azure_resource_group_name" do
      it "is generated when absent" do
        driver.validate_state(state)
        expect(state[:azure_resource_group_name]).to start_with("kitchen-default-ubuntu-2204-")
      end

      it "keeps an existing name, so a re-run targets the same group" do
        expect(driver.validate_state(azure_resource_group_name: "kitchen-existing")[:azure_resource_group_name])
          .to eq("kitchen-existing")
      end

      # The name is generated from the instance name, which is the suite and
      # platform joined together, so a descriptive suite on a long platform
      # overruns Azure's limit and `kitchen create` fails on its first call:
      #
      #   InvalidResourceGroup: The provided resource group name '...' has a
      #   length of '107' which exceeds the maximum length of '90'.
      context "when the instance name is long" do
        let(:long_instance) { "install-and-configure-monitoring-agent-windows-server-2022-datacenter-azure-edition" }

        subject(:name) { build_driver(instance_name: long_instance).azure_resource_group_name }

        it "stays within Azure's 90 character limit" do
          expect(name.length).to be <= 90
        end

        it "keeps the timestamp, which is what makes it unique" do
          expect(name).to match(/-\d{8}T\d{6}\z/)
        end

        it "keeps the configured prefix" do
          expect(name).to start_with("kitchen-")
        end

        it "keeps a configured suffix" do
          suffixed = build_driver(instance_name: long_instance, azure_resource_group_suffix: "-ci")
          expect(suffixed.azure_resource_group_name).to end_with("-ci")
          expect(suffixed.azure_resource_group_name.length).to be <= 90
        end

        it "still identifies the instance it belongs to" do
          expect(name).to include("install-and-configure")
        end
      end

      it "does not truncate a name that already fits" do
        expect(build_driver(instance_name: "default-ubuntu-2204").azure_resource_group_name)
          .to start_with("kitchen-default-ubuntu-2204-")
      end

      it "copes with a prefix that consumes the whole budget" do
        driver = build_driver(azure_resource_group_prefix: "p" * 95)
        expect(driver.azure_resource_group_name).to start_with("p" * 90)
      end
    end

    describe "config values copied into state" do
      let(:config) { { subscription_id: "sub-123", azure_environment: "AzureChina", use_managed_disks: false } }

      it "copies subscription_id, azure_environment and use_managed_disks" do
        driver.validate_state(state)
        expect(state).to include(subscription_id: "sub-123", azure_environment: "AzureChina", use_managed_disks: false)
      end

      it "does not overwrite values already in state" do
        driver.validate_state(state.merge!(subscription_id: "sub-from-state"))
        expect(state[:subscription_id]).to eq("sub-from-state")
      end

      it "replaces a blank value left in state by an earlier run" do
        driver.validate_state(state.merge!(subscription_id: ""))
        expect(state[:subscription_id]).to eq("sub-123")
      end
    end

    describe "password handling" do
      context "when the transport uses a password" do
        it "leaves an existing password alone" do
          expect(driver.validate_state(password: "hunter2")[:password]).to eq("hunter2")
        end
      end

      context "when the transport uses an SSH key" do
        let(:transport) { transport_double(name: "Ssh", ssh_key: "~/.ssh/id_rsa") }

        it "removes any password from state" do
          expect(driver.validate_state(password: "hunter2")).not_to have_key(:password)
        end
      end
    end
  end

  describe "#azure_resource_group_name" do
    # Freeze time so the timestamp component is deterministic. The clock is
    # deliberately set to a non-UTC zone so that a missing .utc call shows up.
    before { allow(Time).to receive(:now).and_return(Time.new(2026, 8, 22, 18, 45, 5, "+05:00")) }

    it "combines the prefix, instance name, timestamp and suffix" do
      expect(driver.azure_resource_group_name).to eq("kitchen-default-ubuntu-2204-20260822T134505")
    end

    it "applies a configured prefix and suffix" do
      driver = build_driver(azure_resource_group_prefix: "tk_", azure_resource_group_suffix: "_ci")
      expect(driver.azure_resource_group_name).to eq("tk_default-ubuntu-2204-20260822T134505_ci")
    end

    it "stamps the name in UTC rather than the local zone" do
      expect(driver.azure_resource_group_name).to end_with("20260822T134505")
    end

    context "when explicit_resource_group_name is set" do
      let(:config) { { explicit_resource_group_name: "my-existing-rg" } }

      it "uses it verbatim, with no timestamp" do
        expect(driver.azure_resource_group_name).to eq("my-existing-rg")
      end
    end
  end
end
