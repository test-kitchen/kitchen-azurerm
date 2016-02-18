require 'kitchen'
require 'kitchen/driver/credentials'
require 'securerandom'
require 'azure_mgmt_resources'
require 'azure_mgmt_network'
require 'base64'
require 'sshkey'

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
          adminPassword: state[:password],
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
          resource_management_client.resource_groups.create_or_update(state[:azure_resource_group_name], resource_group).value!
        rescue ::MsRestAzure::AzureOperationError => operation_error
          info operation_error.body['error']
          raise operation_error
        end

        # Execute deployment steps
        begin
          deployment_name = "deploy-#{state[:uuid]}"
          info "Creating Deployment: #{deployment_name}"
          resource_management_client.deployments.create_or_update(state[:azure_resource_group_name], deployment_name, deployment(deployment_parameters)).value!
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

        # Now retrieve the public IP from the resource group:
        network_management_client = ::Azure::ARM::Network::NetworkResourceProviderClient.new(credentials)
        network_management_client.subscription_id = config[:subscription_id]
        result = network_management_client.public_ip_addresses.get(state[:azure_resource_group_name], 'publicip').value!
        info "IP Address is: #{result.body.properties.ip_address} [#{result.body.properties.dns_settings.fqdn}]"
        state[:hostname] = result.body.properties.ip_address
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

        state
      end

      def azure_resource_group_name
        formatted_time = Time.now.utc.strftime '%Y%m%dT%H%M%S'
        "#{config[:azure_resource_group_name]}-#{formatted_time}"
      end

      def template_for_transport_name
        template = JSON.parse(virtual_machine_deployment_template)
        if instance.transport.name.casecmp('winrm') == 0
          encoded_command = Base64.strict_encode64(enable_winrm_powershell_script)
          command = command_to_execute
          template['resources'].select { |h| h['type'] == 'Microsoft.Compute/virtualMachines' }.each do |resource|
            resource['properties']['osProfile']['customData'] = encoded_command
          end
          template['resources'] << JSON.parse(custom_script_extension_template(command))
        end

        if instance.transport.name.casecmp('ssh') == 0
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
        output
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
        failed_operations = resource_management_client.deployment_operations.list(resource_group, deployment_name).value!
        failed_operations.body.value.each do |val|
          resource_code = val.properties.status_code
          fail val.properties.status_message.inspect.to_s if resource_code != 'OK'
        end
      end

      def list_outstanding_deployment_operations(resource_group, deployment_name)
        end_operation_states = 'Failed,Succeeded'
        deployment_operations = resource_management_client.deployment_operations.list(resource_group, deployment_name).value!
        deployment_operations.body.value.each do |val|
          resource_provisioning_state = val.properties.provisioning_state
          resource_name = val.properties.target_resource.resource_name
          resource_type = val.properties.target_resource.resource_type
          end_operation_state_reached = end_operation_states.split(',').include?(resource_provisioning_state)
          unless end_operation_state_reached
            info "Resource #{resource_type} '#{resource_name}' provisioning status is #{resource_provisioning_state}"
          end
        end
      end

      def deployment_state(resource_group, deployment_name)
        deployments = resource_management_client.deployments.get(resource_group, deployment_name).value!
        deployments.body.properties.provisioning_state
      end

      def destroy(state)
        return if state[:server_id].nil?
        credentials = Kitchen::Driver::Credentials.new.azure_credentials_for_subscription(state[:subscription_id])
        resource_management_client = ::Azure::ARM::Resources::ResourceManagementClient.new(credentials, state[:azure_management_url])
        resource_management_client.subscription_id = state[:subscription_id]
        begin
          info "Destroying Resource Group: #{state[:azure_resource_group_name]}"
          resource_management_client.resource_groups.begin_delete(state[:azure_resource_group_name]).value!
          info 'Destroy operation accepted and will continue in the background.'
        rescue ::MsRestAzure::AzureOperationError => operation_error
          info operation_error.body['error']
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

      def command_to_execute
        'copy /y c:\\\\azuredata\\\\customdata.bin c:\\\\azuredata\\\\customdata.ps1 && powershell.exe -ExecutionPolicy Unrestricted -Command \\"start-process powershell.exe -verb runas -argumentlist c:\\\\azuredata\\\\customdata.ps1\\"'
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

      def custom_script_extension_template(command)
        <<-EOH
        {
            "type": "Microsoft.Compute/virtualMachines/extensions",
            "name": "[concat(variables('vmName'),'/','enableWinRM')]",
            "apiVersion": "2015-05-01-preview",
            "location": "[variables('location')]",
            "dependsOn": [
                "[concat('Microsoft.Compute/virtualMachines/',variables('vmName'))]"
            ],
            "properties": {
                "publisher": "Microsoft.Compute",
                "type": "CustomScriptExtension",
                "typeHandlerVersion": "1.4",
                "settings": {
                    "commandToExecute": "#{command}"
                }
            }
        }
        EOH
      end

      def virtual_machine_deployment_template
        <<-EOH
{
    "$schema": "https://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "location": {
            "type": "string",
            "metadata": {
                "description": "The location where the resources will be created."
            }
        },
        "vmSize": {
            "type": "string",
            "metadata": {
                "description": "The size of the VM to be created"
            }
        },
        "newStorageAccountName": {
            "type": "string",
            "metadata": {
                "description": "Unique DNS Name for the Storage Account where the Virtual Machine's disks will be placed."
            }
        },
        "adminUsername": {
            "type": "string",
            "metadata": {
                "description": "User name for the Virtual Machine."
            }
        },
        "adminPassword": {
            "type": "securestring",
            "metadata": {
                "description": "Password for the Virtual Machine."
            }
        },
        "dnsNameForPublicIP": {
            "type": "string",
            "metadata": {
                "description": "Unique DNS Name for the Public IP used to access the Virtual Machine."
            }
        },
        "imagePublisher": {
            "type": "string",
            "defaultValue": "Canonical",
            "metadata": {
                "description": "Publisher for the VM, e.g. Canonical, MicrosoftWindowsServer"
            }
        },
        "imageOffer": {
            "type": "string",
            "defaultValue": "UbuntuServer",
            "metadata": {
                "description": "Offer for the VM, e.g. UbuntuServer, WindowsServer."
            }
        },
        "imageSku": {
            "type": "string",
            "defaultValue": "14.04.3-LTS",
            "metadata": {
                "description": "Sku for the VM, e.g. 14.04.3-LTS"
            }
        },
        "imageVersion": {
            "type": "string",
            "defaultValue": "latest",
            "metadata": {
                "description": "Either a date or latest."
            }
        },
        "vmName": {
            "type": "string",
            "defaultValue": "vm",
            "metadata": {
                "description": "The vm name created inside of the resource group."
            }
        },
        "storageAccountType": {
            "type": "string",
            "defaultValue": "Standard_LRS",
            "metadata": {
                "description": "The type of storage to use (e.g. Standard_LRS or Premium_LRS)."
            }
        },
        "bootDiagnosticsEnabled": {
            "type": "string",
            "defaultValue": "true",
            "metadata": {
                "description": "Whether to enable (true) or disable (false) boot diagnostics. Default: true (requires Standard storage)."
            }
        }
    },
    "variables": {
        "location": "[parameters('location')]",
        "OSDiskName": "osdisk",
        "nicName": "nic",
        "addressPrefix": "10.0.0.0/16",
        "subnetName": "Subnet",
        "subnetPrefix": "10.0.0.0/24",
        "storageAccountType": "[parameters('storageAccountType')]",
        "publicIPAddressName": "publicip",
        "publicIPAddressType": "Dynamic",
        "vmStorageAccountContainerName": "vhds",
        "vmName": "[parameters('vmName')]",
        "vmSize": "[parameters('vmSize')]",
        "virtualNetworkName": "vnet",
        "vnetID": "[resourceId('Microsoft.Network/virtualNetworks',variables('virtualNetworkName'))]",
        "subnetRef": "[concat(variables('vnetID'),'/subnets/',variables('subnetName'))]"
    },
    "resources": [
        {
            "type": "Microsoft.Storage/storageAccounts",
            "name": "[parameters('newStorageAccountName')]",
            "apiVersion": "2015-05-01-preview",
            "location": "[variables('location')]",
            "properties": {
                "accountType": "[variables('storageAccountType')]"
            }
        },
        {
            "apiVersion": "2015-05-01-preview",
            "type": "Microsoft.Network/publicIPAddresses",
            "name": "[variables('publicIPAddressName')]",
            "location": "[variables('location')]",
            "properties": {
                "publicIPAllocationMethod": "[variables('publicIPAddressType')]",
                "dnsSettings": {
                    "domainNameLabel": "[parameters('dnsNameForPublicIP')]"
                }
            }
        },
        {
            "apiVersion": "2015-05-01-preview",
            "type": "Microsoft.Network/virtualNetworks",
            "name": "[variables('virtualNetworkName')]",
            "location": "[variables('location')]",
            "properties": {
                "addressSpace": {
                    "addressPrefixes": [
                        "[variables('addressPrefix')]"
                    ]
                },
                "subnets": [
                    {
                        "name": "[variables('subnetName')]",
                        "properties": {
                            "addressPrefix": "[variables('subnetPrefix')]"
                        }
                    }
                ]
            }
        },
        {
            "apiVersion": "2015-05-01-preview",
            "type": "Microsoft.Network/networkInterfaces",
            "name": "[variables('nicName')]",
            "location": "[variables('location')]",
            "dependsOn": [
                "[concat('Microsoft.Network/publicIPAddresses/', variables('publicIPAddressName'))]",
                "[concat('Microsoft.Network/virtualNetworks/', variables('virtualNetworkName'))]"
            ],
            "properties": {
                "ipConfigurations": [
                    {
                        "name": "ipconfig1",
                        "properties": {
                            "privateIPAllocationMethod": "Dynamic",
                            "publicIPAddress": {
                                "id": "[resourceId('Microsoft.Network/publicIPAddresses',variables('publicIPAddressName'))]"
                            },
                            "subnet": {
                                "id": "[variables('subnetRef')]"
                            }
                        }
                    }
                ]
            }
        },
        {
            "apiVersion": "2015-06-15",
            "type": "Microsoft.Compute/virtualMachines",
            "name": "[variables('vmName')]",
            "location": "[variables('location')]",
            "dependsOn": [
                "[concat('Microsoft.Storage/storageAccounts/', parameters('newStorageAccountName'))]",
                "[concat('Microsoft.Network/networkInterfaces/', variables('nicName'))]"
            ],
            "properties": {
                "hardwareProfile": {
                    "vmSize": "[variables('vmSize')]"
                },
                "osProfile": {
                    "computername": "[variables('vmName')]",
                    "adminUsername": "[parameters('adminUsername')]",
                    "adminPassword": "[parameters('adminPassword')]"
                },
                "storageProfile": {
                    "imageReference": {
                        "publisher": "[parameters('imagePublisher')]",
                        "offer": "[parameters('imageOffer')]",
                        "sku": "[parameters('imageSku')]",
                        "version": "[parameters('imageVersion')]"
                    },
                    "osDisk": {
                        "name": "osdisk",
                        "vhd": {
                            "uri": "[concat('http://',parameters('newStorageAccountName'),'.blob.core.windows.net/',variables('vmStorageAccountContainerName'),'/',variables('OSDiskName'),'.vhd')]"
                        },
                        "caching": "ReadWrite",
                        "createOption": "FromImage"
                    }
                },
                "networkProfile": {
                    "networkInterfaces": [
                        {
                            "id": "[resourceId('Microsoft.Network/networkInterfaces',variables('nicName'))]"
                        }
                    ]
                },
                "diagnosticsProfile": {
                    "bootDiagnostics": {
                        "enabled": "[parameters('bootDiagnosticsEnabled')]",
                        "storageUri": "[concat('http://',parameters('newStorageAccountName'),'.blob.core.windows.net')]"
                    }
                }
            }
        }
    ]
}
        EOH
      end
    end
  end
end
