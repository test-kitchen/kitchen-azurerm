require "kitchen"

require_relative "azure_credentials"
require_relative "azure/errors"
require "securerandom" unless defined?(SecureRandom)
require "base64" unless defined?(Base64)
autoload :SSHKey, "sshkey"
require "fileutils" unless defined?(FileUtils)
require "erb" unless defined?(Erb)
require "ostruct" unless defined?(OpenStruct)
require "json" unless defined?(JSON)

# Test Kitchen's top-level namespace.
module Kitchen
  # Namespace for Test Kitchen driver plugins.
  module Driver
    # Test Kitchen driver for the Microsoft Azure Resource Manager API.
    #
    # Provisions each Test Kitchen instance as an ARM deployment inside its own
    # resource group, then tears the whole group down again on destroy. The
    # deployment template is rendered from the ERB files in +templates/+ - see
    # {#virtual_machine_deployment_template}.
    #
    # @see https://github.com/test-kitchen/kitchen-azurerm
    class Azurerm < Kitchen::Driver::Base
      # Client for the Azure Resource Manager API, built during {#create} or
      # {#destroy} once credentials have been resolved.
      #
      # @return [Azure::ArmClient, nil]
      attr_accessor :arm_client

      kitchen_driver_api_version 2

      # Settings that Azure retirements have made inoperable. They are still
      # accepted so that an existing kitchen.yml keeps loading, but they no
      # longer do anything and {#warn_about_deprecated_config} says so.
      #
      # @return [Hash{Symbol => String}]
      DEPRECATED_CONFIG = {
        use_managed_disks: "Azure retired unmanaged disks on 31 March 2026; every deployment now uses managed disks.",
        image_url: "Deploying from a VHD URL required unmanaged disks, which Azure retired on 31 March 2026. Use image_id with a managed image or an Azure Compute Gallery image instead.",
        os_type: "os_type only ever applied to VHD (image_url) deployments, which Azure retired on 31 March 2026.",
        existing_storage_account_blob_url: "Azure retired unmanaged disks on 31 March 2026, so OS disks are no longer placed in a storage account you supply.",
        existing_storage_account_container: "Azure retired unmanaged disks on 31 March 2026, so OS disks are no longer placed in a storage account you supply.",
      }.freeze

      default_config(:azure_resource_group_prefix) do |_config|
        "kitchen-"
      end

      default_config(:azure_resource_group_suffix) do |_config|
        ""
      end

      default_config(:azure_resource_group_name) do |config|
        config.instance.name.to_s
      end

      default_config(:explicit_resource_group_name) do |_config|
        nil
      end

      default_config(:resource_group_tags) do |_config|
        {}
      end

      # Ubuntu 22.04 LTS, generation 2. Canonical renamed their offers after
      # 18.04, so the old "UbuntuServer" offer no longer resolves at all.
      default_config(:image_urn) do |_config|
        "Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest"
      end

      default_config(:image_id) do |_config|
        ""
      end

      default_config(:use_ephemeral_osdisk) do |_config|
        false
      end

      default_config(:os_disk_size_gb) do |_config|
        ""
      end

      default_config(:custom_data) do |_config|
        ""
      end

      default_config(:username) do |_config|
        "azure"
      end

      default_config(:password) do |_config|
        SecureRandom.base64(25)
      end

      # This prefix MUST be no longer than 3 characters
      default_config(:vm_prefix) do |_config|
        "tk-"
      end

      default_config :vm_name, nil

      default_config :store_deployment_credentials_in_state, true

      default_config(:nic_name) do |_config|
        ""
      end

      default_config(:vnet_id) do |_config|
        ""
      end

      default_config(:subnet_id) do |_config|
        ""
      end

      # Standard HDD OS disks are retired in September 2028, and Standard SSD is
      # the current baseline for a short-lived test instance.
      default_config(:storage_account_type) do |_config|
        "StandardSSD_LRS"
      end

      default_config(:boot_diagnostics_enabled) do |_config|
        true
      end

      default_config(:winrm_powershell_script) do |_config|
        false
      end

      default_config(:azure_environment) do |_config|
        "Azure"
      end

      default_config(:pre_deployment_template) do |_config|
        ""
      end

      default_config(:pre_deployment_parameters) do |_config|
        {}
      end

      default_config(:post_deployment_template) do |_config|
        ""
      end

      default_config(:post_deployment_parameters) do |_config|
        {}
      end

      default_config(:plan) do |_config|
        {}
      end

      default_config(:vm_tags) do |_config|
        {}
      end

      default_config(:public_ip) do |_config|
        false
      end

      default_config(:data_disks) do |_config|
        nil
      end

      default_config(:format_data_disks) do |_config|
        false
      end

      default_config(:format_data_disks_powershell_script) do |_config|
        false
      end

      default_config(:system_assigned_identity) do |_config|
        false
      end

      default_config(:user_assigned_identities) do |_config|
        []
      end

      default_config(:destroy_explicit_resource_group) do |_config|
        true
      end

      default_config(:destroy_explicit_resource_group_tags) do |_config|
        true
      end

      default_config(:destroy_resource_group_contents) do |_config|
        false
      end

      default_config(:deployment_sleep) do |_config|
        10
      end

      default_config(:secret_url) do |_config|
        ""
      end

      default_config(:vault_name) do |_config|
        ""
      end

      default_config(:vault_resource_group) do |_config|
        ""
      end

      default_config(:subscription_id) do |_config|
        ENV["AZURE_SUBSCRIPTION_ID"]
      end

      # Basic SKU public IPs were retired on 30 September 2025 and can no longer
      # be created, so Standard is the only usable value.
      default_config(:public_ip_sku) do |_config|
        "Standard"
      end

      default_config(:azure_api_retries) do |_config|
        5
      end

      default_config(:use_fqdn_hostname) do |_config|
        false
      end

      # Resource id of an existing network security group to attach to the NIC.
      # When empty, and a public IP is being created, one is generated with rules
      # for the transport in use.
      default_config(:nsg_id) do |_config|
        ""
      end

      # Extra inbound TCP ports to open, on top of the transport's own port.
      default_config(:open_ports) do |_config|
        []
      end

      # Provisions the Azure resource group and ARM deployment backing this
      # Test Kitchen instance.
      #
      # Runs, in order: the optional pre-deployment template, the virtual
      # machine deployment, and the optional post-deployment template. On
      # success +state+ gains a +:hostname+ that the transport can connect to.
      #
      # @param state [Hash] the instance state, mutated in place.
      # @return [void]
      # @raise [RuntimeError] if no +subscription_id+ can be resolved.
      # @raise [Azure::OperationError] if an Azure API call fails
      #   for any reason other than an already-running deployment.
      def create(state)
        warn_about_deprecated_config
        state = validate_state(state)
        deployment_parameters = build_deployment_parameters(state)

        if config[:subscription_id].to_s == ""
          raise "A subscription_id config value was not detected and kitchen-azurerm cannot continue. Please check your kitchen.yml configuration. Exiting."
        end

        debug "Azure environment: #{config[:azure_environment]}"
        @arm_client = Kitchen::Driver::AzureCredentials.new(subscription_id: config[:subscription_id],
          environment: config[:azure_environment]).arm_client

        begin
          info "Creating Resource Group: #{state[:azure_resource_group_name]}"
          create_resource_group(state[:azure_resource_group_name], get_resource_group)
        rescue Azure::OperationError => operation_error
          error operation_error.body
          raise operation_error
        end

        begin
          run_deployment(state, "pre-deploy", pre_deployment(config[:pre_deployment_template], config[:pre_deployment_parameters])) if File.file?(config[:pre_deployment_template])

          run_deployment(state, "deploy", deployment(deployment_parameters))
          store_deployment_credentials(state, deployment_parameters)

          run_deployment(state, "post-deploy", post_deployment(config[:post_deployment_template], config[:post_deployment_parameters])) if File.file?(config[:post_deployment_template])
        rescue Azure::OperationError => operation_error
          info operation_error.body["error"]
          raise operation_error
        end

        state[:hostname] = resolve_hostname(state, deployment_parameters["nicName"])
      end

      # Builds the ARM parameter values for the virtual machine deployment.
      #
      # @param state [Hash] instance state, already through {#validate_state}.
      # @return [Hash] parameter name to value, ready for
      #   {#parameters_in_values_format}.
      def build_deployment_parameters(state)
        parameters = {
          location: config[:location],
          vmSize: config[:machine_size],
          storageAccountType: config[:storage_account_type],
          bootDiagnosticsEnabled: boot_diagnostics_enabled?,
          adminUsername: config[:username],
          dnsNameForPublicIP: "kitchen-#{state[:uuid]}",
          vmName: state[:vm_name],
          systemAssignedIdentity: config[:system_assigned_identity],
          userAssignedIdentities: Array(config[:user_assigned_identities]).to_h { |identity| [identity, {}] },
          secretUrl: config[:secret_url],
          vaultName: config[:vault_name],
          vaultResourceGroup: config[:vault_resource_group],
        }

        parameters[:adminPassword] = config[:password] if instance.transport[:ssh_key].nil?

        parameters[:publicIPSKU] = config[:public_ip_sku]
        parameters[:publicIPAddressType] = "Static" if config[:public_ip_sku] == "Standard"

        parameters["nicName"] = nic_name(state)
        parameters["customData"] = prepared_custom_data unless config[:custom_data].to_s.empty?
        parameters["osDiskSizeGb"] = os_disk_size_gb unless config[:os_disk_size_gb].to_s.empty?
        parameters["nsgId"] = config[:nsg_id] unless config[:nsg_id].to_s.empty?

        parameters.merge(image_parameters)
      end

      # ARM parameters describing which image the VM boots from: either a managed
      # image (or Azure Compute Gallery image) by resource id, or a Marketplace
      # image URN.
      #
      # @return [Hash]
      def image_parameters
        return { "imageId" => config[:image_id] } if config[:image_id].to_s != ""

        publisher, offer, sku, version = config[:image_urn].split(":", 4)
        { "imagePublisher" => publisher, "imageOffer" => offer, "imageSku" => sku, "imageVersion" => version }
      end

      # The OS disk size, as a number ARM will accept.
      #
      # YAML makes +os_disk_size_gb: 64+ an Integer and +os_disk_size_gb: "64"+
      # a String, and the ARM parameter is typed +int+ - Azure rejects the
      # String outright rather than coercing it:
      #
      #   The provided value for the template parameter 'osDiskSizeGb' is not
      #   valid. Expected a value of type 'Integer', but received a value of
      #   type 'String'.
      #
      # Quoting a number in kitchen.yml is an easy thing to do, and the driver
      # already tolerates the same ambiguity for +boot_diagnostics_enabled+.
      #
      # @return [Integer]
      # @raise [Kitchen::UserError] if the value is not a whole number.
      def os_disk_size_gb
        Integer(config[:os_disk_size_gb])
      rescue ArgumentError, TypeError
        raise Kitchen::UserError,
          "os_disk_size_gb must be a whole number of gigabytes, but was #{config[:os_disk_size_gb].inspect}."
      end

      # Whether managed boot diagnostics should be switched on.
      #
      # Historically this setting defaulted to the *string* +"true"+, and plenty
      # of kitchen.yml files still say +"false"+, so both spellings are honoured.
      #
      # @return [Boolean]
      def boot_diagnostics_enabled?
        value = config[:boot_diagnostics_enabled]
        return false if value.to_s.casecmp("false") == 0

        !!value
      end

      # Name of the network interface the VM is attached to.
      #
      # @param state [Hash] instance state.
      # @return [String] +nic_name+ from config, or one derived from the VM name.
      def nic_name(state)
        config[:nic_name].to_s.empty? ? "nic-#{state[:vm_name]}" : config[:nic_name].to_s
      end

      # Submits a named deployment and blocks until it reaches an end state.
      #
      # @param state [Hash] instance state, used for the resource group and uuid.
      # @param prefix [String] deployment name prefix, e.g. +"pre-deploy"+.
      # @param deployment [Hash] the deployment body
      # @return [void]
      def run_deployment(state, prefix, deployment)
        name = "#{prefix}-#{state[:uuid]}"
        info "Creating deployment: #{name}"
        begin
          create_deployment_async(state[:azure_resource_group_name], name, deployment)
        rescue Azure::OperationError => operation_error
          raise unless operation_error.code == "DeploymentActive"

          # An interrupted `kitchen create` leaves its deployment running in
          # Azure. Wait for that one instead of abandoning the rest of create:
          # the deployment already in flight is the one we wanted, and the
          # steps after this still have to run for the instance to be usable.
          info "Deployment #{name} is already running; waiting for it rather than submitting it again."
          info "To deploy a changed template, run `kitchen destroy` for this instance first."
        end
        follow_deployment_until_end_state(state[:azure_resource_group_name], name)
      end

      # Persists the generated admin credentials into instance state, when
      # +store_deployment_credentials_in_state+ is enabled.
      #
      # No password is stored when the transport authenticates with an SSH key -
      # there is no password in that case, and writing a +nil+ one leaves a
      # misleading empty entry in the state file.
      #
      # @param state [Hash] instance state, mutated in place.
      # @param deployment_parameters [Hash] as built by {#build_deployment_parameters}.
      # @return [void]
      def store_deployment_credentials(state, deployment_parameters)
        return unless config[:store_deployment_credentials_in_state] == true

        state[:username] = deployment_parameters[:adminUsername] unless existing_state_value?(state, :username)

        return unless instance.transport[:ssh_key].nil?

        state[:password] = deployment_parameters[:adminPassword] unless existing_state_value?(state, :password)
      end

      # Determines the address the transport should connect to.
      #
      # Uses the public IP (or its FQDN, when +use_fqdn_hostname+ is set) unless
      # the instance was deployed into a caller-supplied vnet without a public IP,
      # in which case the NIC's private address is used.
      #
      # @param state [Hash] instance state.
      # @param vmnic [String] name of the network interface.
      # @return [String] IP address or fully-qualified domain name.
      def resolve_hostname(state, vmnic)
        if public_ip?
          result = get_public_ip(state[:azure_resource_group_name], "publicip")
          ip_address = result.dig("properties", "ipAddress")
          fqdn = result.dig("properties", "dnsSettings", "fqdn")
          info "IP Address is: #{ip_address} [#{fqdn}]"
          if config[:use_fqdn_hostname]
            info "Using FQDN to communicate instead of IP"
            fqdn
          else
            ip_address
          end
        else
          result = get_network_interface(state[:azure_resource_group_name], vmnic.to_s)
          private_ip = result.dig("properties", "ipConfigurations", 0, "properties", "privateIPAddress")
          info "IP Address is: #{private_ip}"
          private_ip
        end
      end

      # Whether a state property is already populated.
      #
      # @param state [Hash] Hash of existing state values.
      # @param property [Symbol, String] the property to check.
      # @return [Boolean] true when the key exists and its value is not nil.
      def existing_state_value?(state, property)
        state.key?(property) && !state[property].nil?
      end

      # Fills in any state values that are not already present.
      #
      # @param state [Hash] existing Hash of state values.
      # @return [Hash] the same Hash, with defaults applied.
      def validate_state(state = {})
        state[:uuid] = SecureRandom.hex(8) unless existing_state_value?(state, :uuid)
        state[:vm_name] = generated_vm_name(state) unless existing_state_value?(state, :vm_name)
        state[:server_id] = "vm#{state[:uuid]}" unless existing_state_value?(state, :server_id)
        state[:azure_resource_group_name] = azure_resource_group_name unless existing_state_value?(state, :azure_resource_group_name)
        %i{subscription_id azure_environment use_managed_disks}.each do |config_element|
          state[config_element] = config[config_element] unless existing_state_value?(state, config_element)
        end
        state.delete(:password) unless instance.transport[:ssh_key].nil?
        state
      end

      # Maximum length of a generated VM name.
      #
      # Windows computer names are capped at 15 characters, which is the lower
      # of the two Azure limits, so we honour it for every platform.
      #
      # @return [Integer]
      MAX_VM_NAME_LENGTH = 15

      # The VM name to use, either the configured one or one generated from
      # +vm_prefix+ plus part of the instance uuid.
      #
      # The prefix is capped one character short of {MAX_VM_NAME_LENGTH} so
      # that a +vm_prefix+ longer than the documented three characters still
      # yields a name Azure will accept. Leaving room for at least one uuid
      # character does two things: it keeps some entropy in every generated
      # name, and it guarantees the name ends with one, because a prefix that
      # filled the whole budget could end on the separator it was written
      # with. Azure rejects that outright - both for the VM and for the
      # network interface named after it, which must end with a word
      # character.
      #
      # @param state [Hash] instance state, must already have a +:uuid+.
      # @return [String]
      def generated_vm_name(state)
        return config[:vm_name] if config[:vm_name]

        prefix = config[:vm_prefix].to_s[0, MAX_VM_NAME_LENGTH - 1]
        "#{prefix}#{state[:uuid][0, MAX_VM_NAME_LENGTH - prefix.length]}"
      end

      # Maximum length of an Azure resource group name.
      #
      # @return [Integer]
      MAX_RESOURCE_GROUP_NAME_LENGTH = 90

      # Name of the resource group this instance deploys into.
      #
      # The instance name is the suite and platform joined together, so a
      # descriptive suite on a long platform overruns Azure's limit and
      # +kitchen create+ fails on its very first call - over a name the user
      # never chose. Only that part is shortened: the prefix and suffix were
      # asked for explicitly, and the timestamp is what keeps the name unique.
      #
      # @return [String] +explicit_resource_group_name+ when set, otherwise
      #   prefix + instance name + UTC timestamp + suffix.
      def azure_resource_group_name
        return config[:explicit_resource_group_name] if config[:explicit_resource_group_name]

        formatted_time = Time.now.utc.strftime "%Y%m%dT%H%M%S"
        prefix = config[:azure_resource_group_prefix].to_s
        suffix = config[:azure_resource_group_suffix].to_s
        room = MAX_RESOURCE_GROUP_NAME_LENGTH - prefix.length - suffix.length - formatted_time.length - 1
        name = config[:azure_resource_group_name].to_s[0, [room, 0].max]

        "#{prefix}#{name}-#{formatted_time}#{suffix}"
      end

      # JSON fragment describing the data disks to attach to the VM.
      #
      # @return [String, nil] a JSON array, or nil when no +data_disks+ are
      #   configured.
      def data_disks_for_vm_json
        return nil if config[:data_disks].nil?

        disks = config[:data_disks].map do |data_disk|
          { name: "datadisk#{data_disk[:lun]}", lun: data_disk[:lun], diskSizeGB: data_disk[:disk_size_gb], createOption: "Empty" }
        end
        debug "Additional disks being added to configuration: #{disks.inspect}"
        disks.to_json
      end

      # The deployment template, adjusted for the transport in use.
      #
      # WinRM instances get a custom data bootstrap script and unattend content;
      # SSH instances get the public half of the transport's key injected into
      # the Linux configuration.
      #
      # @return [String] the deployment template as JSON.
      def template_for_transport_name
        template = JSON.parse(virtual_machine_deployment_template)

        if instance.transport.name.casecmp("winrm") == 0 && instance.platform.name.to_s.index("nano").nil?
          info "Adding WinRM configuration to provisioning profile."
          encoded_command = Base64.strict_encode64(custom_data_script_windows)
          virtual_machine_resources(template).each do |resource|
            resource["properties"]["osProfile"]["customData"] = encoded_command
            resource["properties"]["osProfile"]["windowsConfiguration"] = windows_unattend_content
          end
        end

        unless instance.transport[:ssh_key].nil?
          info "Adding public key from #{File.expand_path(instance.transport[:ssh_key])}.pub to the deployment."
          public_key = public_key_for_deployment(File.expand_path(instance.transport[:ssh_key]))
          virtual_machine_resources(template).each do |resource|
            resource["properties"]["osProfile"]["linuxConfiguration"] = JSON.parse(custom_linux_configuration(public_key))
          end
        end

        template.to_json
      end

      # Selects the virtual machine resources from a parsed ARM template.
      #
      # @param template [Hash] a parsed ARM template.
      # @return [Array<Hash>]
      def virtual_machine_resources(template)
        template["resources"].select { |resource| resource["type"] == "Microsoft.Compute/virtualMachines" }
      end

      # Returns the public key to inject into the deployment, generating a new
      # key pair on disk when the configured private key does not yet exist.
      #
      # @param private_key_filename [String] path to the transport's private key.
      # @return [String] the OpenSSH-format public key, stripped of whitespace.
      def public_key_for_deployment(private_key_filename)
        unless File.file?(private_key_filename)
          key = SSHKey.generate

          ::FileUtils.mkdir_p(File.dirname(private_key_filename))
          File.write(private_key_filename, key.private_key)
          File.chmod(0600, private_key_filename)
          File.write("#{private_key_filename}.pub", key.ssh_public_key)
          File.chmod(0600, "#{private_key_filename}.pub")

          return key.ssh_public_key.strip
        end

        public_key_filename = instance.transport[:ssh_public_key] || "#{private_key_filename}.pub"
        File.read(public_key_filename).strip
      end

      # Builds the pre-deployment from a caller-supplied ARM template file.
      #
      # @param pre_deployment_template_filename [String] path to an ARM template.
      # @param pre_deployment_parameters [Hash] parameter name to value.
      # @return [Hash] the deployment body
      def pre_deployment(pre_deployment_template_filename, pre_deployment_parameters)
        build_deployment(::File.read(pre_deployment_template_filename), pre_deployment_parameters)
      end

      # Builds the virtual machine deployment.
      #
      # @param parameters [Hash] parameter name to value.
      # @return [Hash] the deployment body
      def deployment(parameters)
        deployment = build_deployment(template_for_transport_name, parameters)
        debug(JSON.pretty_generate(deployment_template(deployment)))
        deployment
      end

      # Builds the post-deployment from a caller-supplied ARM template file.
      #
      # @param post_deployment_template_filename [String] path to an ARM template.
      # @param post_deployment_parameters [Hash] parameter name to value.
      # @return [Hash] the deployment body
      def post_deployment(post_deployment_template_filename, post_deployment_parameters)
        build_deployment(::File.read(post_deployment_template_filename), post_deployment_parameters)
      end

      # An empty Complete-mode deployment, used to delete every resource inside
      # a resource group while leaving the group itself in place.
      #
      # @return [Hash] the deployment body
      def empty_deployment
        deployment = build_deployment(virtual_machine_deployment_template_file("empty.erb", nil), nil, mode: "Complete")
        debug(JSON.pretty_generate(deployment_template(deployment)))
        deployment
      end

      # Assembles an ARM deployment object.
      #
      # @param template [String] the ARM template as JSON.
      # @param parameters [Hash, nil] parameter name to value, or nil for none.
      # @param mode [String] the ARM deployment mode.
      # @return [Hash] the deployment body
      def build_deployment(template, parameters, mode: "Incremental")
        properties = { "mode" => mode, "template" => JSON.parse(template) }
        formatted = parameters_in_values_format(parameters)
        properties["parameters"] = formatted if formatted

        { "properties" => properties }
      end

      # The parsed ARM template inside a deployment body.
      #
      # @param deployment [Hash] as built by {#build_deployment}.
      # @return [Hash]
      def deployment_template(deployment)
        deployment["properties"]["template"]
      end

      # Renders resource tags as a JSON object body (no surrounding braces), for
      # interpolation into the ERB deployment templates.
      #
      # Keys and values are JSON-encoded so that tags containing quotes or
      # backslashes cannot produce an unparseable template.
      #
      # @param vm_tags_in [Hash] tag name to value.
      # @return [String] e.g. +"os_type": "linux",\n"distro": "redhat"+
      def vm_tag_string(vm_tags_in)
        return "" if vm_tags_in.nil? || vm_tags_in.empty?

        vm_tags_in.map { |key, value| "#{key.to_s.to_json}: #{value.to_s.to_json}" }.join(",\n")
      end

      # Converts a flat parameter Hash into the ARM +{name: {"value" => v}}+ shape.
      #
      # @param parameters_in [Hash] parameter name to value.
      # @return [Hash, nil] nil when +parameters_in+ is empty.
      def parameters_in_values_format(parameters_in)
        return nil if parameters_in.nil? || parameters_in.empty?

        parameters_in.each_with_object({}) do |(key, value), acc|
          acc[key.to_s] = { "value" => value }
        end
      end

      # Polls a deployment until it reaches a terminal provisioning state,
      # logging the resources still in flight along the way.
      #
      # @param resource_group [String] the resource group name.
      # @param deployment_name [String] the deployment name.
      # @return [void]
      # @raise [RuntimeError] with the Azure status message if the deployment failed.
      def follow_deployment_until_end_state(resource_group, deployment_name)
        end_provisioning_states = %w{Canceled Failed Deleted Succeeded}
        deployment_provisioning_state = nil

        until end_provisioning_states.include?(deployment_provisioning_state)
          list_outstanding_deployment_operations(resource_group, deployment_name)
          sleep config[:deployment_sleep]
          deployment_provisioning_state = get_deployment_state(resource_group, deployment_name)
        end

        info "Resource Template deployment reached end state of '#{deployment_provisioning_state}'."
        return if deployment_provisioning_state == "Succeeded"

        show_failed_operations(resource_group, deployment_name)
        raise "Deployment '#{deployment_name}' in resource group '#{resource_group}' " \
              "ended in state '#{deployment_provisioning_state}'."
      end

      # Raises with the status messages of every failed operation in a deployment.
      #
      # Returns quietly when no single operation reported a failure, leaving
      # the caller to raise: a deployment can fail without one, and its own
      # provisioning state is the authority on whether it worked.
      #
      # @param resource_group [String] the resource group name.
      # @param deployment_name [String] the deployment name.
      # @return [void]
      # @raise [RuntimeError] if any operation reported a non-OK status code.
      def show_failed_operations(resource_group, deployment_name)
        failures = list_deployment_operations(resource_group, deployment_name).reject do |operation|
          operation.dig("properties", "statusCode") == "OK"
        end
        return if failures.empty?

        raise failures.map { |operation| operation.dig("properties", "statusMessage").inspect }.join("\n")
      end

      # Logs every deployment operation that has not yet reached a terminal state.
      #
      # @param resource_group [String] the resource group name.
      # @param deployment_name [String] the deployment name.
      # @return [void]
      def list_outstanding_deployment_operations(resource_group, deployment_name)
        end_operation_states = %w{Failed Succeeded}
        list_deployment_operations(resource_group, deployment_name).each do |operation|
          resource_provisioning_state = operation.dig("properties", "provisioningState")
          next if end_operation_states.include?(resource_provisioning_state)

          target = operation.dig("properties", "targetResource") || {}
          info "Resource #{target["resourceType"]} '#{target["resourceName"]}' provisioning status is #{resource_provisioning_state}"
        end
      end

      # Tears down whatever {#create} built.
      #
      # @param state [Hash] the instance state, mutated in place.
      # @return [void]
      # @raise [Azure::OperationError] if an Azure API call fails.
      def destroy(state)
        # TODO: We have some not so fun state issues we need to clean up
        state[:azure_environment] = config[:azure_environment] unless state[:azure_environment]
        state[:subscription_id] = config[:subscription_id] unless state[:subscription_id]

        @arm_client = Kitchen::Driver::AzureCredentials.new(subscription_id: state[:subscription_id],
          environment: state[:azure_environment]).arm_client

        return if destroy_orphaned_explicit_resource_group(state)

        info "Azure environment: #{state[:azure_environment]}"

        # Nothing was ever created for this instance.
        return if state[:server_id].nil?

        destroy_resource_group_contents(state) if config[:destroy_resource_group_contents] == true

        if config[:destroy_explicit_resource_group] == false && !config[:explicit_resource_group_name].nil?
          warn 'The "destroy_explicit_resource_group" setting value is set to "false". The resource group will not be deleted.'
          warn 'Remember to manually destroy resources, or set "destroy_resource_group_contents: true" to save costs!' unless config[:destroy_resource_group_contents] == true
          return state
        end

        begin
          info "Destroying Resource Group: #{state[:azure_resource_group_name]}"
          delete_resource_group_async(state[:azure_resource_group_name])
          info "Destroy operation accepted and will continue in the background."
          state.delete(:azure_resource_group_name)
        rescue Azure::OperationError => operation_error
          error operation_error.body
          raise operation_error
        end

        state.delete(:server_id)
        state.delete(:hostname)
        state.delete(:username)
        state.delete(:password)
      end

      # Deletes an explicitly-named resource group when the instance itself was
      # never created but the user asked for the group to be removed.
      #
      # @param state [Hash] the instance state.
      # @return [Boolean] true when the group was deleted and {#destroy} should stop.
      # @raise [Azure::OperationError] if the delete request fails.
      def destroy_orphaned_explicit_resource_group(state)
        return false unless state[:server_id].nil? && state[:azure_resource_group_name].nil?
        return false if config[:explicit_resource_group_name].nil?
        return false unless config[:destroy_explicit_resource_group]
        return false unless resource_group_exists?(config[:explicit_resource_group_name])

        info "This instance doesn't exist but you asked to delete the resource group."
        info "Destroying Resource Group: #{config[:explicit_resource_group_name]}"
        delete_resource_group_async(config[:explicit_resource_group_name])
        info "Destroy operation accepted and will continue in the background."
        true
      rescue Azure::OperationError => operation_error
        error operation_error.body
        raise operation_error
      end

      # Empties a resource group by deploying an empty template in Complete
      # mode, then restores or clears the group's tags per configuration.
      #
      # @param state [Hash] the instance state.
      # @return [void]
      # @raise [Azure::OperationError] if an Azure API call fails.
      def destroy_resource_group_contents(state)
        info "Destroying individual resources within the Resource Group."
        run_deployment(state, "empty-deploy", empty_deployment)

        if config[:destroy_explicit_resource_group_tags] == false
          warn 'The "destroy_explicit_resource_group_tags" setting value is set to "false". The tags on the resource group will NOT be removed.'
          create_resource_group(state[:azure_resource_group_name], get_resource_group)
        else
          warn 'The "destroy_explicit_resource_group_tags" setting value is set to "true". The tags on the resource group will be removed.'
          create_resource_group(state[:azure_resource_group_name], get_resource_group.merge(tags: {}))
        end
      rescue Azure::OperationError => operation_error
        error operation_error.body
        raise operation_error
      end

      # PowerShell that opens the WinRM HTTP and HTTPS listeners and firewall ports.
      #
      # @return [String] the configured script, or the built-in default.
      def enable_winrm_powershell_script
        config[:winrm_powershell_script] ||
          <<-PS1
  $cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\\LocalMachine\\My
  $config = '@{CertificateThumbprint="' + $cert.Thumbprint + '"}'
  winrm create winrm/config/listener?Address=*+Transport=HTTPS $config
  winrm create winrm/config/Listener?Address=*+Transport=HTTP
  winrm set winrm/config/service/auth '@{Basic="true";Kerberos="false";Negotiate="true";Certificate="false";CredSSP="true"}'
  New-NetFirewallRule -DisplayName "Windows Remote Management (HTTPS-In)" -Name "Windows Remote Management (HTTPS-In)" -Profile Any -LocalPort 5986 -Protocol TCP
  winrm set winrm/config/service '@{AllowUnencrypted="true"}'
  New-NetFirewallRule -DisplayName "Windows Remote Management (HTTP-In)" -Name "Windows Remote Management (HTTP-In)" -Profile Any -LocalPort 5985 -Protocol TCP
          PS1
      end

      # PowerShell that initialises and NTFS-formats every raw data disk.
      #
      # @return [String, nil] nil unless +format_data_disks+ is enabled.
      def format_data_disks_powershell_script
        return unless config[:format_data_disks]

        info "Data disks will be initialized and formatted NTFS automatically." unless config[:data_disks].nil?
        config[:format_data_disks_powershell_script] ||
          <<-PS1
  Write-Host "Initializing and formatting raw disks"
  $disks = Get-Disk | where partitionstyle -eq 'raw'
  $letters = New-Object System.Collections.ArrayList
  $letters.AddRange( ('F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z') )
  Function AvailableVolumes() {
  $currentDrives = get-volume
  ForEach ($v in $currentDrives) {
    if ($letters -contains $v.DriveLetter.ToString()) {
        Write-Host "Drive letter $($v.DriveLetter) is taken, moving to next letter"
        $letters.Remove($v.DriveLetter.ToString())
      }
    }
  }
  ForEach ($d in $disks) {
    AvailableVolumes
    $driveLetter = $letters[0]
    Write-Host "Creating volume $($driveLetter)"
    $d | Initialize-Disk -PartitionStyle GPT -PassThru | New-Partition -DriveLetter $driveLetter  -UseMaximumSize
    # Prevent error ' Cannot perform the requested operation while the drive is read only'
    Start-Sleep 1
    Format-Volume -FileSystem NTFS -NewFileSystemLabel "datadisk" -DriveLetter $driveLetter -Confirm:$false
  }
          PS1
      end

      # The full first-boot script handed to a Windows VM as custom data.
      #
      # A Windows VM has exactly one custom data slot, and the driver needs it
      # for the WinRM bootstrap. Any +custom_data+ the user configured has to
      # travel in the same slot, so it is appended here rather than assigned
      # over the top - which is what used to happen, silently discarding it.
      #
      # It runs after WinRM is listening and the data disks are formatted, and
      # before the logoff that ends the first-logon session.
      #
      # @return [String]
      def custom_data_script_windows
        <<-EOH
  #{enable_winrm_powershell_script}
  #{format_data_disks_powershell_script}
  #{custom_data_content}
  logoff
        EOH
      end

      # The ARM +linuxConfiguration+ block that installs an SSH public key and
      # disables password authentication.
      #
      # @param public_key [String] an OpenSSH-format public key.
      # @return [String] JSON.
      def custom_linux_configuration(public_key)
        {
          "disablePasswordAuthentication" => "true",
          "ssh" => {
            "publicKeys" => [
              {
                "path" => "[concat('/home/',parameters('adminUsername'),'/.ssh/authorized_keys')]",
                "keyData" => public_key,
              },
            ],
          },
        }.to_json
      end

      # The ARM +windowsConfiguration+ block that runs the custom data script on
      # first logon.
      #
      # @return [Hash]
      def windows_unattend_content
        {
          additionalUnattendContent: [
            {
              passName: "oobeSystem",
              componentName: "Microsoft-Windows-Shell-Setup",
              settingName: "FirstLogonCommands",
              content: '<FirstLogonCommands><SynchronousCommand><CommandLine>cmd /c "copy C:\\AzureData\\CustomData.bin C:\\Config.ps1"</CommandLine><Description>copy</Description><Order>1</Order></SynchronousCommand><SynchronousCommand><CommandLine>%windir%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe -NoProfile -ExecutionPolicy Bypass -file C:\\Config.ps1</CommandLine><Description>script</Description><Order>2</Order></SynchronousCommand></FirstLogonCommands>',
            },
            {
              passName: "oobeSystem",
              componentName: "Microsoft-Windows-Shell-Setup",
              settingName: "AutoLogon",
              content: "[concat('<AutoLogon><Password><Value>', parameters('adminPassword'), '</Value></Password><Enabled>true</Enabled><LogonCount>1</LogonCount><Username>', parameters('adminUserName'), '</Username></AutoLogon>')]",
            },
          ],
        }
      end

      # Renders the virtual machine ARM template for the current configuration.
      #
      # Uses +internal.erb+ when the instance deploys into a caller-supplied
      # vnet, otherwise +public.erb+.
      #
      # @return [String] the rendered ARM template as JSON.
      def virtual_machine_deployment_template
        data = {
          vm_tags: vm_tag_string(config[:vm_tags]),
          storage_account_type: config[:storage_account_type],
          # A setting written with no value is nil, not "". The templates ask
          # these two whether they are empty, so give them something that can
          # answer.
          image_id: config[:image_id].to_s,
          custom_data: config[:custom_data].to_s,
          os_disk_size_gb: config[:os_disk_size_gb],
          data_disks_for_vm_json:,
          use_ephemeral_osdisk: config[:use_ephemeral_osdisk],
          ssh_key: instance.transport[:ssh_key],
          plan_json:,
          secret_url: config[:secret_url],
          vault_name: config[:vault_name],
          vault_resource_group: config[:vault_resource_group],
          create_nsg: create_nsg?,
          attach_nsg: attach_nsg?,
          nsg_id: config[:nsg_id],
          nsg_rules_json: nsg_rules.to_json,
        }

        if config[:vnet_id].to_s.empty?
          virtual_machine_deployment_template_file("public.erb", data)
        else
          info "Using custom vnet: #{config[:vnet_id]}"
          virtual_machine_deployment_template_file("internal.erb", data.merge(
            vnet_id: config[:vnet_id],
            subnet_ref: subnet_reference,
            public_ip: config[:public_ip],
            public_ip_sku: config[:public_ip_sku]
          ))
        end
      end

      # Resource id of the subnet the network interface attaches to.
      #
      # +subnet_id+ has always held the subnet's *name*, resolved against
      # +vnet_id+. The setting is named like a resource id and sits directly
      # beside +vnet_id+, which really is one, so supplying a full subnet
      # resource id is an easy mistake to make - and it used to be appended to
      # the vnet id, leaving ARM to reject a path that appears nowhere in the
      # user's kitchen.yml. Both spellings are accepted.
      #
      # @return [String]
      def subnet_reference
        subnet = config[:subnet_id].to_s
        return subnet if subnet.start_with?("/subscriptions/")

        "#{config[:vnet_id]}/subnets/#{subnet}"
      end

      # Warns about settings that Azure retirements have made inoperable.
      #
      # @return [void]
      def warn_about_deprecated_config
        DEPRECATED_CONFIG.each do |option, reason|
          next unless config.key?(option)

          warn "The '#{option}' setting is no longer supported and is being ignored. #{reason}"
        end
      end

      # Whether this deployment gets a public IP address.
      #
      # @return [Boolean]
      def public_ip?
        config[:vnet_id].to_s.empty? || !!config[:public_ip]
      end

      # Whether the deployment should create its own network security group.
      #
      # Standard SKU public IPs are closed to inbound traffic unless a security
      # group opens it, so one is generated whenever a public IP is created and
      # the user has not supplied their own group. Instances that live purely
      # inside a caller-supplied vnet are left alone - their subnet may already
      # carry the rules the user wants.
      #
      # @return [Boolean]
      def create_nsg?
        config[:nsg_id].to_s.empty? && public_ip?
      end

      # Whether the network interface references a security group at all.
      #
      # @return [Boolean]
      def attach_nsg?
        create_nsg? || !config[:nsg_id].to_s.empty?
      end

      # Inbound TCP ports the generated security group opens.
      #
      # @return [Array<Integer>] the transport's own port(s) plus +open_ports+.
      def nsg_ports
        (transport_ports + Array(config[:open_ports]).map(&:to_i)).uniq
      end

      # The port(s) the configured transport connects on.
      #
      # The transport already knows which port it will dial, so a +port+ set on
      # it is authoritative: assuming the default instead produced an instance
      # nothing could reach, and left the user repeating the port in
      # +open_ports+ to get in.
      #
      # WinRM keeps both standard ports regardless, because
      # {#enable_winrm_powershell_script} creates both listeners whatever the
      # transport was pointed at.
      #
      # @return [Array<Integer>]
      def transport_ports
        configured = instance.transport[:port].to_i

        if winrm_transport?
          ([5985, 5986] + [configured]).reject(&:zero?).uniq
        elsif configured == 0
          [22]
        else
          [configured]
        end
      end

      # Whether the instance is driven over WinRM.
      #
      # @return [Boolean]
      def winrm_transport?
        instance.transport.name.to_s.casecmp("winrm") == 0
      end

      # ARM security rules for the generated network security group.
      #
      # The source prefix is left wide open, which matches the connectivity a
      # Basic SKU public IP used to give with no security group at all. Narrow
      # it by supplying your own group through +nsg_id+.
      #
      # @return [Array<Hash>]
      def nsg_rules
        nsg_ports.each_with_index.map do |port, index|
          {
            "name" => "allow-tcp-#{port}",
            "properties" => {
              "protocol" => "Tcp",
              "sourcePortRange" => "*",
              "destinationPortRange" => port.to_s,
              "sourceAddressPrefix" => "*",
              "destinationAddressPrefix" => "*",
              "access" => "Allow",
              "priority" => 1000 + index,
              "direction" => "Inbound",
            },
          }
        end
      end

      # Marketplace purchase plan for the image, when one is configured.
      #
      # @return [String, nil] JSON, or nil when no +plan+ is configured.
      def plan_json
        plan_config = config[:plan]
        return nil if plan_config.nil? || plan_config.empty?

        plan = {}
        plan["name"] = plan_config[:name]                    if plan_config[:name]
        plan["product"] = plan_config[:product]              if plan_config[:product]
        plan["promotionCode"] = plan_config[:promotion_code] if plan_config[:promotion_code]
        plan["publisher"] = plan_config[:publisher]          if plan_config[:publisher]

        plan.to_json
      end

      # Renders one of the bundled ERB templates.
      #
      # @param template_file [String] file name within +templates/+.
      # @param data [Hash, nil] values exposed to the template.
      # @return [String] the rendered template.
      def virtual_machine_deployment_template_file(template_file, data = {})
        template = File.read(File.expand_path(File.join(__dir__, "../../../templates", template_file)))
        render_binding = OpenStruct.new(data)
        ERB.new(template, trim_mode: "-").result(render_binding.instance_eval { binding })
      end

      # Base64-encoded custom data for the VM.
      #
      # @return [String, nil] nil when no +custom_data+ is configured.
      def prepared_custom_data
        return nil if config[:custom_data].nil?

        @prepared_custom_data ||= Base64.strict_encode64(custom_data_content)
      end

      # The configured custom data, as content.
      #
      # +custom_data+ may be either the literal content or a path to a file
      # holding it, so this resolves whichever was given.
      #
      # @return [String] empty when no +custom_data+ is configured.
      def custom_data_content
        @custom_data_content ||= if readable_file?(config[:custom_data])
                                   File.read(config[:custom_data])
                                 else
                                   config[:custom_data].to_s
                                 end
      end

      private

      # Whether a string can safely be treated as a path to an existing file.
      #
      # +custom_data+ is frequently a multi-line cloud-init document, which is
      # not a path and which +File.file?+ may reject outright, so screen those
      # out before touching the filesystem.
      #
      # @param path [String]
      # @return [Boolean]
      def readable_file?(path)
        string = path.to_s
        return false if string.empty? || string.include?("\n") || string.include?("\0")

        File.file?(string)
      end

      #
      # Wrapper methods for the Azure API calls to retry the calls when getting timeouts.
      #

      # The resource group body carrying the configured location and tags.
      #
      # @return [Hash]
      def get_resource_group
        { location: config[:location], tags: config[:resource_group_tags] }
      end

      # Runs an Azure API call, retrying on transient connection failures.
      #
      # @param description [String] describes the call, used in retry logging.
      # @yield the API call to run.
      # @return [Object] whatever the block returns.
      # @raise [Azure::TransientError] once the retry budget is exhausted.
      def with_azure_retries(description)
        retries = config[:azure_api_retries]
        begin
          yield
        rescue Azure::TransientError => exception
          send_exception_message(exception, "#{description} #{retries} retries left.")
          raise if retries <= 0

          retries -= 1
          retry
        end
      end

      # Checks whether a resource group exists.
      #
      # @param resource_group_name [String] case-insensitive resource group name.
      # @return [Boolean]
      def resource_group_exists?(resource_group_name)
        with_azure_retries("while checking if resource group '#{resource_group_name}' exists.") do
          arm_client.resource_group_exists?(resource_group_name)
        end
      end

      # Creates or updates a resource group.
      #
      # @param resource_group_name [String] the resource group name.
      # @param resource_group [Hash] with +:location+ and +:tags+.
      # @return [Hash] the resource group as ARM returned it.
      def create_resource_group(resource_group_name, resource_group)
        with_azure_retries("while creating resource group '#{resource_group_name}'.") do
          arm_client.create_or_update_resource_group(resource_group_name,
            location: resource_group[:location], tags: resource_group[:tags])
        end
      end

      # Submits a deployment without waiting for it to complete.
      #
      # @param resource_group [String] the resource group name.
      # @param deployment_name [String] the deployment name.
      # @param deployment [Hash] as built by {#build_deployment}.
      # @return [Hash] the deployment as ARM returned it.
      def create_deployment_async(resource_group, deployment_name, deployment)
        with_azure_retries("while sending deployment creation request for deployment '#{deployment_name}'.") do
          arm_client.create_deployment(resource_group, deployment_name, deployment)
        end
      end

      # Fetches a public IP resource.
      #
      # @param resource_group_name [String] the resource group name.
      # @param public_ip_name [String] the public IP resource name.
      # @return [Hash] the public IP address resource.
      def get_public_ip(resource_group_name, public_ip_name)
        with_azure_retries("while fetching public ip '#{public_ip_name}' for resource group '#{resource_group_name}'.") do
          arm_client.public_ip(resource_group_name, public_ip_name)
        end
      end

      # Fetches a network interface resource.
      #
      # @param resource_group_name [String] the resource group name.
      # @param network_interface_name [String] the NIC name.
      # @return [Hash] the network interface resource.
      def get_network_interface(resource_group_name, network_interface_name)
        with_azure_retries("while fetching network interface '#{network_interface_name}' for resource group '#{resource_group_name}'.") do
          arm_client.network_interface(resource_group_name, network_interface_name)
        end
      end

      # Lists every operation belonging to a deployment.
      #
      # @param resource_group [String] the resource group name.
      # @param deployment_name [String] the deployment name.
      # @return [Array<Hash>]
      def list_deployment_operations(resource_group, deployment_name)
        with_azure_retries("while listing deployment operations for deployment '#{deployment_name}'.") do
          arm_client.deployment_operations(resource_group, deployment_name)
        end
      end

      # Reads a deployment's current provisioning state.
      #
      # @param resource_group [String] the resource group name.
      # @param deployment_name [String] the deployment name.
      # @return [String] e.g. +"Running"+, +"Succeeded"+, +"Failed"+.
      def get_deployment_state(resource_group, deployment_name)
        with_azure_retries("while retrieving state for deployment '#{deployment_name}'.") do
          arm_client.deployment(resource_group, deployment_name).dig("properties", "provisioningState")
        end
      end

      # Requests deletion of a resource group without waiting for it to finish.
      #
      # @param resource_group_name [String] the resource group name.
      # @return [Object] the operation response.
      def delete_resource_group_async(resource_group_name)
        with_azure_retries("while sending resource group deletion request for '#{resource_group_name}'.") do
          arm_client.delete_resource_group(resource_group_name)
        end
      end

      # Logs a human-readable reason for a retryable Azure API failure.
      #
      # @param exception [Exception] the raised error.
      # @param message [String] context describing what was being attempted.
      # @return [void]
      def send_exception_message(exception, message)
        unless exception.is_a?(Azure::TransientError)
          info "Unrecognized exception type."
          return
        end

        info "Could not reach Azure (#{exception.message}) #{message}"
      end
    end
  end
end
