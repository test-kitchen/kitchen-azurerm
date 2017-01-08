require 'kitchen'
require 'kitchen/driver/credentials'
require 'securerandom'
require 'azure_mgmt_resources'
require 'azure_mgmt_network'
require 'base64'
require 'sshkey'
require 'fileutils'
require 'erb'

module Kitchen
  module Driver
    #
    # Azurerm
    #
    class Azurerm < Kitchen::Driver::Base
      attr_accessor :resource_management_client

      default_config(:azure_resource_group_name) do |config|
        "kitchen-#{config.instance.name}"
      end

      default_config(:image_urn) do |_config|
        'Canonical:UbuntuServer:14.04.3-LTS:latest'
      end

      default_config(:username) do |_config|
        'azure'
      end

      default_config(:password) do |_config|
        'P2ssw0rd'
      end

      default_config(:vm_name) do |_config|
        'vm'
      end

      default_config(:vnet_id) do |_config|
        ''
      end

      default_config(:subnet_id) do |_config|
        ''
      end

      default_config(:storage_account_type) do |_config|
        'Standard_LRS'
      end

      default_config(:boot_diagnostics_enabled) do |_config|
        'true'
      end

      default_config(:winrm_powershell_script) do |_config|
        false
      end

      default_config(:azure_management_url) do |_config|
        'https://management.azure.com'
      end

      default_config(:pre_deployment_template) do |_config|
        ''
      end

      default_config(:pre_deployment_parameters) do |_config|
        {}
      end

      default_config(:vm_tags) do |_config|
        {}
      end

      default_config(:public_ip) do |_config|
        false
      end

      def create(state)
        state = validate_state(state)
        image_publisher, image_offer, image_sku, image_version = config[:image_urn].split(':', 4)
        deployment_parameters = {
          location: config[:location],
          vmSize: config[:machine_size],
          storageAccountType: config[:storage_account_type],
          bootDiagnosticsEnabled: config[:boot_diagnostics_enabled],
          newStorageAccountName: "storage#{state[:uuid]}",
          adminUsername: state[:username],
          adminPassword: state[:password] || 'P2ssw0rd',
          dnsNameForPublicIP: "kitchen-#{state[:uuid]}",
          imagePublisher: image_publisher,
          imageOffer: image_offer,
          imageSku: image_sku,
          imageVersion: image_version,
          vmName: state[:vm_name]
        }

        credentials = Kitchen::Driver::Credentials.new.azure_credentials_for_subscription(config[:subscription_id])
        @resource_management_client = ::Azure::ARM::Resources::ResourceManagementClient.new(credentials)
        @resource_management_client.subscription_id = config[:subscription_id]

        # Create Resource Group
        resource_group = ::Azure::ARM::Resources::Models::ResourceGroup.new
        resource_group.location = config[:location]
        begin
          info "Creating Resource Group: #{state[:azure_resource_group_name]}"
          resource_management_client.resource_groups.create_or_update(state[:azure_resource_group_name], resource_group)
        rescue ::MsRestAzure::AzureOperationError => operation_error
          error operation_error.body
          raise operation_error
        end

        # Execute deployment steps
        begin
          if File.file?(config[:pre_deployment_template])
            pre_deployment_name = "pre-deploy-#{state[:uuid]}"
            info "Creating deployment: #{pre_deployment_name}"
            resource_management_client.deployments.begin_create_or_update_async(state[:azure_resource_group_name], pre_deployment_name, pre_deployment(config[:pre_deployment_template], config[:pre_deployment_parameters])).value!
            follow_deployment_until_end_state(state[:azure_resource_group_name], pre_deployment_name)
          end
          deployment_name = "deploy-#{state[:uuid]}"
          info "Creating deployment: #{deployment_name}"
          resource_management_client.deployments.begin_create_or_update_async(state[:azure_resource_group_name], deployment_name, deployment(deployment_parameters)).value!
        rescue ::MsRestAzure::AzureOperationError => operation_error
          rest_error = operation_error.body['error']
          deployment_active = rest_error['code'] == 'DeploymentActive'
          if deployment_active
            info "Deployment for resource group #{state[:azure_resource_group_name]} is ongoing."
            info "If you need to change the deployment template you'll need to rerun `kitchen create` for this instance."
          else
            info rest_error
            raise operation_error
          end
        end

        # Monitor all operations until completion
        follow_deployment_until_end_state(state[:azure_resource_group_name], deployment_name)

        if config[:vnet_id] == '' || config[:public_ip]
          # Retrieve the public IP from the resource group:
          network_management_client = ::Azure::ARM::Network::NetworkManagementClient.new(credentials)
          network_management_client.subscription_id = config[:subscription_id]
          result = network_management_client.public_ipaddresses.get(state[:azure_resource_group_name], 'publicip')
          info "IP Address is: #{result.ip_address} [#{result.dns_settings.fqdn}]"
          state[:hostname] = result.ip_address
        else
          # Retrieve the internal IP from the resource group:
          network_management_client = ::Azure::ARM::Network::NetworkManagementClient.new(credentials)
          network_management_client.subscription_id = config[:subscription_id]
          network_interfaces = ::Azure::ARM::Network::NetworkInterfaces.new(network_management_client)
          result = network_interfaces.get(state[:azure_resource_group_name], 'nic')
          info "IP Address is: #{result.ip_configurations[0].private_ipaddress}"
          state[:hostname] = result.ip_configurations[0].private_ipaddress
        end
      end

      def existing_state_value?(state, property)
        state.key?(property) && !state[property].nil?
      end

      def validate_state(state = {})
        state[:uuid] = SecureRandom.hex(8) unless existing_state_value?(state, :uuid)
        state[:server_id] = "vm#{state[:uuid]}" unless existing_state_value?(state, :server_id)
        state[:azure_resource_group_name] = azure_resource_group_name unless existing_state_value?(state, :azure_resource_group_name)
        [:subscription_id, :username, :password, :vm_name, :azure_management_url].each do |config_element|
          state[config_element] = config[config_element] unless existing_state_value?(state, config_element)
        end
        state.delete(:password) unless instance.transport[:ssh_key].nil?
        state
      end

      def azure_resource_group_name
        formatted_time = Time.now.utc.strftime '%Y%m%dT%H%M%S'
        "#{config[:azure_resource_group_name]}-#{formatted_time}"
      end

      def template_for_transport_name
        template = JSON.parse(virtual_machine_deployment_template)
        if instance.transport.name.casecmp('winrm').zero?
          if instance.platform.name.index('nano').nil?
            info 'Adding WinRM configuration to provisioning profile.'
            encoded_command = Base64.strict_encode64(enable_winrm_powershell_script)
            command = command_to_execute
            template['resources'].select { |h| h['type'] == 'Microsoft.Compute/virtualMachines' }.each do |resource|
              resource['properties']['osProfile']['customData'] = encoded_command
              resource['properties']['osProfile']['windowsConfiguration'] = windows_unattend_content
            end
          end
        end

        unless instance.transport[:ssh_key].nil?
          info "Adding public key from #{File.expand_path(instance.transport[:ssh_key])}.pub to the deployment."
          public_key = public_key_for_deployment(File.expand_path(instance.transport[:ssh_key]))
          template['resources'].select { |h| h['type'] == 'Microsoft.Compute/virtualMachines' }.each do |resource|
            resource['properties']['osProfile']['linuxConfiguration'] = JSON.parse(custom_linux_configuration(public_key))
          end
        end
        template.to_json
      end

      def public_key_for_deployment(private_key_filename)
        if File.file?(private_key_filename) == false
          k = SSHKey.generate

          ::FileUtils.mkdir_p(File.dirname(private_key_filename))

          private_key_file = File.new(private_key_filename, 'w')
          private_key_file.syswrite(k.private_key)
          private_key_file.chmod(0600)
          private_key_file.close

          public_key_file = File.new("#{private_key_filename}.pub", 'w')
          public_key_file.syswrite(k.ssh_public_key)
          public_key_file.chmod(0600)
          public_key_file.close

          output = k.ssh_public_key
        else
          output = File.read("#{private_key_filename}.pub")
        end
        output.strip
      end

      def pre_deployment(pre_deployment_template_filename, pre_deployment_parameters)
        pre_deployment_template = ::File.read(pre_deployment_template_filename)
        pre_deployment = ::Azure::ARM::Resources::Models::Deployment.new
        pre_deployment.properties = ::Azure::ARM::Resources::Models::DeploymentProperties.new
        pre_deployment.properties.mode = Azure::ARM::Resources::Models::DeploymentMode::Incremental
        pre_deployment.properties.template = JSON.parse(pre_deployment_template)
        pre_deployment.properties.parameters = parameters_in_values_format(pre_deployment_parameters)
        debug(pre_deployment.properties.template)
        pre_deployment
      end

      def deployment(parameters)
        template = template_for_transport_name
        deployment = ::Azure::ARM::Resources::Models::Deployment.new
        deployment.properties = ::Azure::ARM::Resources::Models::DeploymentProperties.new
        deployment.properties.mode = Azure::ARM::Resources::Models::DeploymentMode::Incremental
        deployment.properties.template = JSON.parse(template)
        deployment.properties.parameters = parameters_in_values_format(parameters)
        debug(deployment.properties.template)
        deployment
      end

      def vm_tag_string(vm_tags_in)
        tag_string = ''
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
          { key.to_sym => { 'value' => value } }
        end
        parameters.reduce(:merge!)
      end

      def follow_deployment_until_end_state(resource_group, deployment_name)
        end_provisioning_states = 'Canceled,Failed,Deleted,Succeeded'
        end_provisioning_state_reached = false
        until end_provisioning_state_reached
          list_outstanding_deployment_operations(resource_group, deployment_name)
          sleep 10
          deployment_provisioning_state = deployment_state(resource_group, deployment_name)
          end_provisioning_state_reached = end_provisioning_states.split(',').include?(deployment_provisioning_state)
        end
        info "Resource Template deployment reached end state of '#{deployment_provisioning_state}'."
        show_failed_operations(resource_group, deployment_name) if deployment_provisioning_state == 'Failed'
      end

      def show_failed_operations(resource_group, deployment_name)
        failed_operations = resource_management_client.deployment_operations.list(resource_group, deployment_name)
        failed_operations.each do |val|
          resource_code = val.properties.status_code
          raise val.properties.status_message.inspect.to_s if resource_code != 'OK'
        end
      end

      def list_outstanding_deployment_operations(resource_group, deployment_name)
        end_operation_states = 'Failed,Succeeded'
        deployment_operations = resource_management_client.deployment_operations.list(resource_group, deployment_name)
        deployment_operations.each do |val|
          resource_provisioning_state = val.properties.provisioning_state
          unless val.properties.target_resource.nil?
            resource_name = val.properties.target_resource.resource_name
            resource_type = val.properties.target_resource.resource_type
          end
          end_operation_state_reached = end_operation_states.split(',').include?(resource_provisioning_state)
          unless end_operation_state_reached
            info "Resource #{resource_type} '#{resource_name}' provisioning status is #{resource_provisioning_state}"
          end
        end
      end

      def deployment_state(resource_group, deployment_name)
        deployments = resource_management_client.deployments.get(resource_group, deployment_name)
        deployments.properties.provisioning_state
      end

      def destroy(state)
        return if state[:server_id].nil?
        credentials = Kitchen::Driver::Credentials.new.azure_credentials_for_subscription(state[:subscription_id])
        resource_management_client = ::Azure::ARM::Resources::ResourceManagementClient.new(credentials, state[:azure_management_url])
        resource_management_client.subscription_id = state[:subscription_id]
        begin
          info "Destroying Resource Group: #{state[:azure_resource_group_name]}"
          resource_management_client.resource_groups.begin_delete(state[:azure_resource_group_name])
          info 'Destroy operation accepted and will continue in the background.'
        rescue ::MsRestAzure::AzureOperationError => operation_error
          error operation_error.body
          raise operation_error
        end
        state.delete(:server_id)
        state.delete(:hostname)
        state.delete(:username)
        state.delete(:password)
      end

      def enable_winrm_powershell_script
        config[:winrm_powershell_script] || <<-PS1
$cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\\LocalMachine\\My
$config = '@{CertificateThumbprint="' + $cert.Thumbprint + '"}'
winrm create winrm/config/listener?Address=*+Transport=HTTPS $config
winrm set winrm/config/service/auth '@{Basic="true";Kerberos="false";Negotiate="true";Certificate="false";CredSSP="true"}'
New-NetFirewallRule -DisplayName "Windows Remote Management (HTTPS-In)" -Name "Windows Remote Management (HTTPS-In)" -Profile Any -LocalPort 5986 -Protocol TCP
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
New-NetFirewallRule -DisplayName "Windows Remote Management (HTTP-In)" -Name "Windows Remote Management (HTTP-In)" -Profile Any -LocalPort 5985 -Protocol TCP
        PS1
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
        template = File.read(File.expand_path(File.join(__dir__, '../../../templates', 'windows.json')))
        JSON.parse(template)
      end

      def virtual_machine_deployment_template
        if config[:vnet_id] == ''
          virtual_machine_deployment_template_file('public.erb', vm_tags: vm_tag_string(config[:vm_tags]))
        else
          info "Using custom vnet: #{config[:vnet_id]}"
          virtual_machine_deployment_template_file('internal.erb', vnet_id: config[:vnet_id], subnet_id: config[:subnet_id], public_ip: config[:public_ip], vm_tags: vm_tag_string(config[:vm_tags]))
        end
      end

      def virtual_machine_deployment_template_file(template_file, data = {})
        template = File.read(File.expand_path(File.join(__dir__, '../../../templates', template_file)))
        render_binding = binding
        data.each { |key, value| render_binding.local_variable_set(key.to_sym, value) }
        ERB.new(template, nil, '-').result(render_binding)
      end
    end
  end
end
