require "kitchen"

autoload :MsRestAzure, "ms_rest_azure"
require_relative "azure_credentials"
require "securerandom" unless defined?(SecureRandom)
module Azure
  autoload :Resources, "azure_mgmt_resources"
  autoload :Network, "azure_mgmt_network"
end
require "base64" unless defined?(Base64)
autoload :SSHKey, "sshkey"
require "fileutils" unless defined?(FileUtils)
require "erb" unless defined?(Erb)
require "ostruct" unless defined?(OpenStruct)
require "json" unless defined?(JSON)
autoload :Faraday, "faraday"

module Kitchen
  module Driver
    #
    # Azurerm
    # Create a new resource group object and set the location and tags attributes then return it.
    #
    # @return [::Azure::Resources::Profiles::Latest::Mgmt::Models::ResourceGroup] A new resource group object.
    class Azurerm < Kitchen::Driver::Base
      attr_accessor :resource_management_client
      attr_accessor :network_management_client

      kitchen_driver_api_version 2

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

      default_config(:image_urn) do |_config|
        "Canonical:UbuntuServer:14.04.3-LTS:latest"
      end

      default_config(:image_url) do |_config|
        ""
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

      default_config(:os_type) do |_config|
        "linux"
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

      default_config(:storage_account_type) do |_config|
        "Standard_LRS"
      end

      default_config(:existing_storage_account_blob_url) do |_config|
        ""
      end

      default_config(:existing_storage_account_container) do |_config|
        "vhds"
      end

      default_config(:boot_diagnostics_enabled) do |_config|
        "true"
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

      default_config(:use_managed_disks) do |_config|
        true
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

      default_config(:public_ip_sku) do |_config|
        "Basic"
      end

      default_config(:azure_api_retries) do |_config|
        5
      end

      default_config(:use_fqdn_hostname) do |_config|
        false
      end

      def create(state)
        state = validate_state(state)
        deployment_parameters = {
          location: config[:location],
          vmSize: config[:machine_size],
          storageAccountType: config[:storage_account_type],
          bootDiagnosticsEnabled: config[:boot_diagnostics_enabled],
          newStorageAccountName: "storage#{state[:uuid]}",
          adminUsername: config[:username],
          dnsNameForPublicIP: "kitchen-#{state[:uuid]}",
          vmName: state[:vm_name],
          systemAssignedIdentity: config[:system_assigned_identity],
          userAssignedIdentities: config[:user_assigned_identities].map { |identity| [identity, {}] }.to_h,
          secretUrl: config[:secret_url],
          vaultName: config[:vault_name],
          vaultResourceGroup: config[:vault_resource_group],
        }

        if instance.transport[:ssh_key].nil?
          deployment_parameters[:adminPassword] = config[:password]
        end

        deployment_parameters[:publicIPSKU] = config[:public_ip_sku]

        if config[:public_ip_sku] == "Standard"
          deployment_parameters[:publicIPAddressType] = "Static"
        end

        if config[:subscription_id].to_s == ""
          raise "A subscription_id config value was not detected and kitchen-azurerm cannot continue. Please check your kitchen.yml configuration. Exiting."
        end

        if config[:nic_name].to_s == ""
          vmnic = "nic-#{state[:vm_name]}"
        else
          vmnic = config[:nic_name]
        end
        deployment_parameters["nicName"] = vmnic.to_s

        if config[:custom_data].to_s != ""
          deployment_parameters["customData"] = prepared_custom_data
        end
        # When deploying in a shared storage account, we needs to add
        # a unique suffix to support multiple kitchen instances
        if config[:existing_storage_account_blob_url].to_s != ""
          deployment_parameters["osDiskNameSuffix"] = "-#{state[:azure_resource_group_name]}"
        end
        if config[:existing_storage_account_blob_url].to_s != ""
          deployment_parameters["existingStorageAccountBlobURL"] = config[:existing_storage_account_blob_url]
        end
        if config[:existing_storage_account_container].to_s != ""
          deployment_parameters["existingStorageAccountBlobContainer"] = config[:existing_storage_account_container]
        end
        if config[:os_disk_size_gb].to_s != ""
          deployment_parameters["osDiskSizeGb"] = config[:os_disk_size_gb]
        end

        # The three deployment modes
        #  a) Private Image: Managed VM Image (by id)
        #  b) Private Image: Using a VHD URL (note: we must use existing_storage_account_blob_url due to azure limitations)
        #  c) Public Image: Using a marketplace image (urn)
        if config[:image_id].to_s != ""
          deployment_parameters["imageId"] = config[:image_id]
        elsif config[:image_url].to_s != ""
          deployment_parameters["imageUrl"] = config[:image_url]
          deployment_parameters["osType"] = config[:os_type]
        else
          image_publisher, image_offer, image_sku, image_version = config[:image_urn].split(":", 4)
          deployment_parameters["imagePublisher"] = image_publisher
          deployment_parameters["imageOffer"] = image_offer
          deployment_parameters["imageSku"] = image_sku
          deployment_parameters["imageVersion"] = image_version
        end

        options = Kitchen::Driver::AzureCredentials.new(subscription_id: config[:subscription_id],
                                                        environment: config[:azure_environment]).azure_options

        debug "Azure environment: #{config[:azure_environment]}"
        @resource_management_client = ::Azure::Resources::Profiles::Latest::Mgmt::Client.new(options)

        # Create Resource Group
        begin
          info "Creating Resource Group: #{state[:azure_resource_group_name]}"
          create_resource_group(state[:azure_resource_group_name], get_resource_group)
        rescue ::MsRestAzure::AzureOperationError => operation_error
          error operation_error.body
          raise operation_error
        end

        # Execute deployment steps
        begin
          if File.file?(config[:pre_deployment_template])
            pre_deployment_name = "pre-deploy-#{state[:uuid]}"
            info "Creating deployment: #{pre_deployment_name}"
            create_deployment_async(state[:azure_resource_group_name], pre_deployment_name, pre_deployment(config[:pre_deployment_template], config[:pre_deployment_parameters])).value!
            follow_deployment_until_end_state(state[:azure_resource_group_name], pre_deployment_name)
          end
          deployment_name = "deploy-#{state[:uuid]}"
          info "Creating deployment: #{deployment_name}"
          create_deployment_async(state[:azure_resource_group_name], deployment_name, deployment(deployment_parameters)).value!
          follow_deployment_until_end_state(state[:azure_resource_group_name], deployment_name)

          if config[:store_deployment_credentials_in_state] == true
            state[:username] = deployment_parameters[:adminUsername] unless existing_state_value?(state, :username)
            state[:password] = deployment_parameters[:adminPassword] unless existing_state_value?(state, :password) && instance.transport[:ssh_key].nil?
          end

          if File.file?(config[:post_deployment_template])
            post_deployment_name = "post-deploy-#{state[:uuid]}"
            info "Creating deployment: #{post_deployment_name}"
            create_deployment_async(state[:azure_resource_group_name], post_deployment_name, post_deployment(config[:post_deployment_template], config[:post_deployment_parameters])).value!
            follow_deployment_until_end_state(state[:azure_resource_group_name], post_deployment_name)
          end
        rescue ::MsRestAzure::AzureOperationError => operation_error
          rest_error = operation_error.body["error"]
          deployment_active = rest_error["code"] == "DeploymentActive"
          if deployment_active
            info "Deployment for resource group #{state[:azure_resource_group_name]} is ongoing."
            info "If you need to change the deployment template you'll need to rerun `kitchen create` for this instance."
          else
            info rest_error
            raise operation_error
          end
        end

        @network_management_client = ::Azure::Network::Profiles::Latest::Mgmt::Client.new(options)

        if config[:vnet_id] == "" || config[:public_ip]
          # Retrieve the public IP from the resource group:
          result = get_public_ip(state[:azure_resource_group_name], "publicip")
          info "IP Address is: #{result.ip_address} [#{result.dns_settings.fqdn}]"
          state[:hostname] = result.ip_address
          if config[:use_fqdn_hostname]
            info "Using FQDN to communicate instead of IP"
            state[:hostname] = result.dns_settings.fqdn
          end
        else
          # Retrieve the internal IP from the resource group:
          result = get_network_interface(state[:azure_resource_group_name], vmnic.to_s)
          info "IP Address is: #{result.ip_configurations[0].private_ipaddress}"
          state[:hostname] = result.ip_configurations[0].private_ipaddress
        end
      end

      # Return a True of False if the state is already stored for a particular property.
      #
      # @param [Hash] Hash of existing state values.
      # @param [String] A property to check
      # @return [Boolean]
      def existing_state_value?(state, property)
        state.key?(property) && !state[property].nil?
      end

      # Leverage existing state values or bring state into existence from a configuration file.
      #
      # @param [Hash] Existing Hash of state values.
      # @return [Hash] Updated Hash of state values.
      def validate_state(state = {})
        state[:uuid] = SecureRandom.hex(8) unless existing_state_value?(state, :uuid)
        state[:vm_name] = config[:vm_name] || "tk-#{state[:uuid][0..11]}" unless existing_state_value?(state, :vm_name)
        state[:server_id] = "vm#{state[:uuid]}" unless existing_state_value?(state, :server_id)
        state[:azure_resource_group_name] = azure_resource_group_name unless existing_state_value?(state, :azure_resource_group_name)
        %i{subscription_id azure_environment use_managed_disks}.each do |config_element|
          state[config_element] = config[config_element] unless existing_state_value?(state, config_element)
        end
        state.delete(:password) unless instance.transport[:ssh_key].nil?
        state
      end

      def azure_resource_group_name
        formatted_time = Time.now.utc.strftime "%Y%m%dT%H%M%S"
        return "#{config[:azure_resource_group_prefix]}#{config[:azure_resource_group_name]}-#{formatted_time}#{config[:azure_resource_group_suffix]}" unless config[:explicit_resource_group_name]

        config[:explicit_resource_group_name]
      end

      def data_disks_for_vm_json
        return nil if config[:data_disks].nil?

        disks = []

        if config[:use_managed_disks]
          config[:data_disks].each do |data_disk|
            disks << { name: "datadisk#{data_disk[:lun]}", lun: data_disk[:lun], diskSizeGB: data_disk[:disk_size_gb], createOption: "Empty" }
          end
          debug "Additional disks being added to configuration: #{disks.inspect}"
        else
          warn 'Data disks are only supported when used with the "use_managed_disks" option. No additional disks were added to the configuration.'
        end
        disks.to_json
      end

      def template_for_transport_name
        template = JSON.parse(virtual_machine_deployment_template)
        if instance.transport.name.casecmp("winrm") == 0
          if instance.platform.name.index("nano").nil?
            info "Adding WinRM configuration to provisioning profile."
            encoded_command = Base64.strict_encode64(custom_data_script_windows)
            template["resources"].select { |h| h["type"] == "Microsoft.Compute/virtualMachines" }.each do |resource|
              resource["properties"]["osProfile"]["customData"] = encoded_command
              resource["properties"]["osProfile"]["windowsConfiguration"] = windows_unattend_content
            end
          end
        end

        unless instance.transport[:ssh_key].nil?
          info "Adding public key from #{File.expand_path(instance.transport[:ssh_key])}.pub to the deployment."
          public_key = public_key_for_deployment(File.expand_path(instance.transport[:ssh_key]))
          template["resources"].select { |h| h["type"] == "Microsoft.Compute/virtualMachines" }.each do |resource|
            resource["properties"]["osProfile"]["linuxConfiguration"] = JSON.parse(custom_linux_configuration(public_key))
          end
        end
        template.to_json
      end

      def public_key_for_deployment(private_key_filename)
        if File.file?(private_key_filename) == false
          k = SSHKey.generate

          ::FileUtils.mkdir_p(File.dirname(private_key_filename))

          private_key_file = File.new(private_key_filename, "w")
          private_key_file.syswrite(k.private_key)
          private_key_file.chmod(0600)
          private_key_file.close

          public_key_file = File.new("#{private_key_filename}.pub", "w")
          public_key_file.syswrite(k.ssh_public_key)
          public_key_file.chmod(0600)
          public_key_file.close

          output = k.ssh_public_key
        else
          output = if instance.transport[:ssh_public_key].nil?
                     File.read("#{private_key_filename}.pub")
                   else
                     File.read(instance.transport[:ssh_public_key])
                   end
        end
        output.strip
      end

      def pre_deployment(pre_deployment_template_filename, pre_deployment_parameters)
        pre_deployment_template = ::File.read(pre_deployment_template_filename)
        pre_deployment = ::Azure::Resources::Profiles::Latest::Mgmt::Models::Deployment.new
        pre_deployment.properties = ::Azure::Resources::Profiles::Latest::Mgmt::Models::DeploymentProperties.new
        pre_deployment.properties.mode = ::Azure::Resources::Profiles::Latest::Mgmt::Models::DeploymentMode::Incremental
        pre_deployment.properties.template = JSON.parse(pre_deployment_template)
        pre_deployment.properties.parameters = parameters_in_values_format(pre_deployment_parameters)
        debug(pre_deployment.properties.template)
        pre_deployment
      end

      def deployment(parameters)
        template = template_for_transport_name
        deployment = ::Azure::Resources::Profiles::Latest::Mgmt::Models::Deployment.new
        deployment.properties = ::Azure::Resources::Profiles::Latest::Mgmt::Models::DeploymentProperties.new
        deployment.properties.mode = ::Azure::Resources::Profiles::Latest::Mgmt::Models::DeploymentMode::Incremental
        deployment.properties.template = JSON.parse(template)
        deployment.properties.parameters = parameters_in_values_format(parameters)
        debug(JSON.pretty_generate(deployment.properties.template))
        deployment
      end

      def post_deployment(post_deployment_template_filename, post_deployment_parameters)
        post_deployment_template = ::File.read(post_deployment_template_filename)
        post_deployment = ::Azure::Resources::Profiles::Latest::Mgmt::Models::Deployment.new
        post_deployment.properties = ::Azure::Resources::Profiles::Latest::Mgmt::Models::DeploymentProperties.new
        post_deployment.properties.mode = ::Azure::Resources::Profiles::Latest::Mgmt::Models::DeploymentMode::Incremental
        post_deployment.properties.template = JSON.parse(post_deployment_template)
        post_deployment.properties.parameters = parameters_in_values_format(post_deployment_parameters)
        debug(post_deployment.properties.template)
        post_deployment
      end

      def empty_deployment
        template = virtual_machine_deployment_template_file("empty.erb", nil)
        empty_deployment = ::Azure::Resources::Profiles::Latest::Mgmt::Models::Deployment.new
        empty_deployment.properties = ::Azure::Resources::Profiles::Latest::Mgmt::Models::DeploymentProperties.new
        empty_deployment.properties.mode = ::Azure::Resources::Profiles::Latest::Mgmt::Models::DeploymentMode::Complete
        empty_deployment.properties.template = JSON.parse(template)
        debug(JSON.pretty_generate(empty_deployment.properties.template))
        empty_deployment
      end

      def vm_tag_string(vm_tags_in)
        tag_string = ""
        unless vm_tags_in.empty?
          tag_array = vm_tags_in.map do |key, value|
            "\"#{key}\": \"#{value}\",\n"
          end
          # Strip punctuation from last item
          tag_array[-1] = tag_array[-1][0..-3]
          tag_string = tag_array.join
        end
        tag_string
      end

      def parameters_in_values_format(parameters_in)
        parameters = parameters_in.map do |key, value|
          { key.to_sym => { "value" => value } }
        end
        parameters.reduce(:merge!)
      end

      def follow_deployment_until_end_state(resource_group, deployment_name)
        end_provisioning_states = "Canceled,Failed,Deleted,Succeeded"
        end_provisioning_state_reached = false
        until end_provisioning_state_reached
          list_outstanding_deployment_operations(resource_group, deployment_name)
          sleep config[:deployment_sleep]
          deployment_provisioning_state = get_deployment_state(resource_group, deployment_name)
          end_provisioning_state_reached = end_provisioning_states.split(",").include?(deployment_provisioning_state)
        end
        info "Resource Template deployment reached end state of '#{deployment_provisioning_state}'."
        show_failed_operations(resource_group, deployment_name) if deployment_provisioning_state == "Failed"
      end

      def show_failed_operations(resource_group, deployment_name)
        failed_operations = list_deployment_operations(resource_group, deployment_name)
        failed_operations.each do |val|
          resource_code = val.properties.status_code
          raise val.properties.status_message.inspect.to_s if resource_code != "OK"
        end
      end

      def list_outstanding_deployment_operations(resource_group, deployment_name)
        end_operation_states = "Failed,Succeeded"
        deployment_operations = list_deployment_operations(resource_group, deployment_name)
        deployment_operations.each do |val|
          resource_provisioning_state = val.properties.provisioning_state
          unless val.properties.target_resource.nil?
            resource_name = val.properties.target_resource.resource_name
            resource_type = val.properties.target_resource.resource_type
          end
          end_operation_state_reached = end_operation_states.split(",").include?(resource_provisioning_state)
          unless end_operation_state_reached
            info "Resource #{resource_type} '#{resource_name}' provisioning status is #{resource_provisioning_state}"
          end
        end
      end

      def destroy(state)
        # TODO: We have some not so fun state issues we need to clean up
        state[:azure_environment] = config[:azure_environment] unless state[:azure_environment]
        state[:subscription_id] = config[:subscription_id] unless state[:subscription_id]

        # Setup our authentication components for the SDK
        options = Kitchen::Driver::AzureCredentials.new(subscription_id: state[:subscription_id],
          environment: state[:azure_environment]).azure_options
        @resource_management_client = ::Azure::Resources::Profiles::Latest::Mgmt::Client.new(options)

        # If we don't have any instances, let's check to see if the user wants to delete a resource group and if so let's delete!
        if state[:server_id].nil? && state[:azure_resource_group_name].nil? && !config[:explicit_resource_group_name].nil? && config[:destroy_explicit_resource_group]
          if resource_group_exists?(config[:explicit_resource_group_name])
            info "This instance doesn't exist but you asked to delete the resource group."
            begin
              info "Destroying Resource Group: #{config[:explicit_resource_group_name]}"
              delete_resource_group_async(config[:explicit_resource_group_name])
              info "Destroy operation accepted and will continue in the background."
              return
            rescue ::MsRestAzure::AzureOperationError => operation_error
              error operation_error.body
              raise operation_error
            end
          end
        end

        # Our working environment
        info "Azure environment: #{state[:azure_environment]}"

        # Skip if we don't have any instances
        return if state[:server_id].nil?

        # Destroy resource group contents
        if config[:destroy_resource_group_contents] == true
          info "Destroying individual resources within the Resource Group."
          empty_deployment_name = "empty-deploy-#{state[:uuid]}"
          begin
            info "Creating deployment: #{empty_deployment_name}"
            create_deployment_async(state[:azure_resource_group_name], empty_deployment_name, empty_deployment).value!
            follow_deployment_until_end_state(state[:azure_resource_group_name], empty_deployment_name)

            # NOTE: We are using the internal wrapper function create_resource_group() which wraps the API
            # method of create_or_update()
            begin
              # Maintain tags on the resource group
              create_resource_group(state[:azure_resource_group_name], get_resource_group) unless config[:destroy_explicit_resource_group_tags] == true
              warn 'The "destroy_explicit_resource_group_tags" setting value is set to "false". The tags on the resource group will NOT be removed.' unless config[:destroy_explicit_resource_group_tags] == true
              # Corner case where we want to use kitchen to remove the tags
              resource_group = get_resource_group
              resource_group.tags = {}
              create_resource_group(state[:azure_resource_group_name], resource_group) unless config[:destroy_explicit_resource_group_tags] == false
              warn 'The "destroy_explicit_resource_group_tags" setting value is set to "true". The tags on the resource group will be removed.' unless config[:destroy_explicit_resource_group_tags] == false
            rescue ::MsRestAzure::AzureOperationError => operation_error
              error operation_error.body
              raise operation_error
            end

          rescue ::MsRestAzure::AzureOperationError => operation_error
            error operation_error.body
            raise operation_error
          end
        end

        # Do not remove the explicitly named resource group
        if config[:destroy_explicit_resource_group] == false && !config[:explicit_resource_group_name].nil?
          warn 'The "destroy_explicit_resource_group" setting value is set to "false". The resource group will not be deleted.'
          warn 'Remember to manually destroy resources, or set "destroy_resource_group_contents: true" to save costs!' unless config[:destroy_resource_group_contents] == true
          return state
        end

        # Destroy the world
        begin
          info "Destroying Resource Group: #{state[:azure_resource_group_name]}"
          delete_resource_group_async(state[:azure_resource_group_name])
          info "Destroy operation accepted and will continue in the background."
          # Remove resource group name from driver state
          state.delete(:azure_resource_group_name)
        rescue ::MsRestAzure::AzureOperationError => operation_error
          error operation_error.body
          raise operation_error
        end

        # Clear state of components
        state.delete(:server_id)
        state.delete(:hostname)
        state.delete(:username)
        state.delete(:password)
      end

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

      def custom_data_script_windows
        <<-EOH
  #{enable_winrm_powershell_script}
  #{format_data_disks_powershell_script}
  logoff
        EOH
      end

      def custom_linux_configuration(public_key)
        <<-EOH
        {
          "disablePasswordAuthentication": "true",
          "ssh": {
            "publicKeys": [
              {
                "path": "[concat('/home/',parameters('adminUsername'),'/.ssh/authorized_keys')]",
                "keyData": "#{public_key}"
              }
            ]
          }
        }
        EOH
      end

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

      def virtual_machine_deployment_template
        if config[:vnet_id] == ""
          virtual_machine_deployment_template_file("public.erb", vm_tags: vm_tag_string(config[:vm_tags]), use_managed_disks: config[:use_managed_disks], image_url: config[:image_url], storage_account_type: config[:storage_account_type], existing_storage_account_blob_url: config[:existing_storage_account_blob_url], image_id: config[:image_id], existing_storage_account_container: config[:existing_storage_account_container], custom_data: config[:custom_data], os_disk_size_gb: config[:os_disk_size_gb], data_disks_for_vm_json: data_disks_for_vm_json, use_ephemeral_osdisk: config[:use_ephemeral_osdisk], ssh_key: instance.transport[:ssh_key], plan_json: plan_json)
        else
          info "Using custom vnet: #{config[:vnet_id]}"
          virtual_machine_deployment_template_file("internal.erb", vnet_id: config[:vnet_id], subnet_id: config[:subnet_id], public_ip: config[:public_ip], vm_tags: vm_tag_string(config[:vm_tags]), use_managed_disks: config[:use_managed_disks], image_url: config[:image_url], storage_account_type: config[:storage_account_type], existing_storage_account_blob_url: config[:existing_storage_account_blob_url], image_id: config[:image_id], existing_storage_account_container: config[:existing_storage_account_container], custom_data: config[:custom_data], os_disk_size_gb: config[:os_disk_size_gb], data_disks_for_vm_json: data_disks_for_vm_json, use_ephemeral_osdisk: config[:use_ephemeral_osdisk], ssh_key: instance.transport[:ssh_key], public_ip_sku: config[:public_ip_sku], plan_json: plan_json)
        end
      end

      def plan_json
        return nil if config[:plan].empty?

        plan = {}
        plan["name"] = config[:plan][:name]                    if config[:plan][:name]
        plan["product"] = config[:plan][:product]              if config[:plan][:product]
        plan["promotionCode"] = config[:plan][:promotion_code] if config[:plan][:promotion_code]
        plan["publisher"] = config[:plan][:publisher]          if config[:plan][:publisher]

        plan.to_json
      end

      def virtual_machine_deployment_template_file(template_file, data = {})
        template = File.read(File.expand_path(File.join(__dir__, "../../../templates", template_file)))
        render_binding = OpenStruct.new(data)
        ERB.new(template, trim_mode: "-").result(render_binding.instance_eval { binding })
      end

      def resource_manager_endpoint_url(azure_environment)
        case azure_environment.downcase
        when "azureusgovernment"
          MsRestAzure::AzureEnvironments::AzureUSGovernment.resource_manager_endpoint_url
        when "azurechina"
          MsRestAzure::AzureEnvironments::AzureChinaCloud.resource_manager_endpoint_url
        when "azuregermancloud"
          MsRestAzure::AzureEnvironments::AzureGermanCloud.resource_manager_endpoint_url
        when "azure"
          MsRestAzure::AzureEnvironments::AzureCloud.resource_manager_endpoint_url
        end
      end

      def prepared_custom_data
        # If user_data is a file reference, lets read it as such
        return nil if config[:custom_data].nil?

        @custom_data ||= if File.file?(config[:custom_data])
                           Base64.strict_encode64(File.read(config[:custom_data]))
                         else
                           Base64.strict_encode64(config[:custom_data])
                         end
      end

      private

      #
      # Wrapper methods for the Azure API calls to retry the calls when getting timeouts.
      #

      # Create a new resource group object and set the location and tags attributes then return it.
      #
      # @return [::Azure::Resources::Profiles::Latest::Mgmt::Models::ResourceGroup] A new resource group object.
      def get_resource_group
        resource_group = ::Azure::Resources::Profiles::Latest::Mgmt::Models::ResourceGroup.new
        resource_group.location = config[:location]
        resource_group.tags = config[:resource_group_tags]
        resource_group
      end

      # Checks whether a resource group exists.
      #
      # @param resource_group_name [String] The name of the resource group to check.
      # The name is case insensitive.
      #
      # @return [Boolean] operation results.
      #
      def resource_group_exists?(resource_group_name)
        retries = config[:azure_api_retries]
        begin
          resource_management_client.resource_groups.check_existence(resource_group_name)
        rescue Faraday::TimeoutError, Faraday::ClientError => exception
          send_exception_message(exception, "while checking if resource group '#{resource_group_name}' exists. #{retries} retries left.")
          raise if retries == 0

          retries -= 1
          retry
        end
      end

      def create_resource_group(resource_group_name, resource_group)
        retries = config[:azure_api_retries]
        begin
          resource_management_client.resource_groups.create_or_update(resource_group_name, resource_group)
        rescue Faraday::TimeoutError, Faraday::ClientError => exception
          send_exception_message(exception, "while creating resource group '#{resource_group_name}'. #{retries} retries left.")
          raise if retries == 0

          retries -= 1
          retry
        end
      end

      def create_deployment_async(resource_group, deployment_name, deployment)
        retries = config[:azure_api_retries]
        begin
          resource_management_client.deployments.begin_create_or_update_async(resource_group, deployment_name, deployment)
        rescue Faraday::TimeoutError, Faraday::ClientError => exception
          send_exception_message(exception, "while sending deployment creation request for deployment '#{deployment_name}'. #{retries} retries left.")
          raise if retries == 0

          retries -= 1
          retry
        end
      end

      def get_public_ip(resource_group_name, public_ip_name)
        retries = config[:azure_api_retries]
        begin
          network_management_client.public_ipaddresses.get(resource_group_name, public_ip_name)
        rescue Faraday::TimeoutError, Faraday::ClientError => exception
          send_exception_message(exception, "while fetching public ip '#{public_ip_name}' for resource group '#{resource_group_name}'. #{retries} retries left.")
          raise if retries == 0

          retries -= 1
          retry
        end
      end

      def get_network_interface(resource_group_name, network_interface_name)
        retries = config[:azure_api_retries]
        begin
          network_interfaces = ::Azure::Network::Profiles::Latest::Mgmt::NetworkInterfaces.new(network_management_client)
          network_interfaces.get(resource_group_name, network_interface_name)
        rescue Faraday::TimeoutError, Faraday::ClientError => exception
          send_exception_message(exception, "while fetching network interface '#{network_interface_name}' for resource group '#{resource_group_name}'. #{retries} retries left.")
          raise if retries == 0

          retries -= 1
          retry
        end
      end

      def list_deployment_operations(resource_group, deployment_name)
        retries = config[:azure_api_retries]
        begin
          resource_management_client.deployment_operations.list(resource_group, deployment_name)
        rescue Faraday::TimeoutError, Faraday::ClientError => exception
          send_exception_message(exception, "while listing deployment operations for deployment '#{deployment_name}'. #{retries} retries left.")
          raise if retries == 0

          retries -= 1
          retry
        end
      end

      def get_deployment_state(resource_group, deployment_name)
        retries = config[:azure_api_retries]
        begin
          deployments = resource_management_client.deployments.get(resource_group, deployment_name)
          deployments.properties.provisioning_state
        rescue Faraday::TimeoutError, Faraday::ClientError => exception
          send_exception_message(exception, "while retrieving state for deployment '#{deployment_name}'. #{retries} retries left.")
          raise if retries == 0

          retries -= 1
          retry
        end
      end

      def delete_resource_group_async(resource_group_name)
        retries = config[:azure_api_retries]
        begin
          resource_management_client.resource_groups.begin_delete(resource_group_name)
        rescue Faraday::TimeoutError, Faraday::ClientError => exception
          send_exception_message(exception, "while sending resource group deletion request for '#{resource_group_name}'. #{retries} retries left.")
          raise if retries == 0

          retries -= 1
          retry
        end
      end

      def send_exception_message(exception, message)
        if exception.is_a?(Faraday::TimeoutError)
          header = "Timed out"
        elsif exception.is_a?(Faraday::ClientError)
          header = "Connection reset by peer"
        else
          # Unhandled exception, return early
          info "Unrecognized exception type."
          return
        end
        info "#{header} #{message}"
      end
    end
  end
end
