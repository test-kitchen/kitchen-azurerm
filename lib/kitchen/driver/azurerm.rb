require 'kitchen'
require 'kitchen/driver/credentials'
require 'securerandom'
require 'azure_mgmt_resources'
require 'azure_mgmt_network'

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

      def create(state)
        puts 'in kitchen create'
        state[:uuid] = "#{SecureRandom.hex(8)}"
        state[:azure_resource_group_name] = "#{config[:azure_resource_group_name]}-#{state[:uuid]}"
        state[:subscription_id] = config[:subscription_id]
        state[:username] = config[:username]
        state[:password] = config[:password]
        state[:server_id] = "vm#{state[:uuid]}"
        image_publisher, image_offer, image_sku, image_version = config[:image_urn].split(':', 4)
        deployment_parameters = {
          location: config[:location],
          vmSize: config[:machine_size],
          newStorageAccountName: "storage#{state[:uuid]}",
          adminUsername: state[:username],
          adminPassword: state[:password],
          dnsNameForPublicIP: "kitchen-#{state[:uuid]}",
          imagePublisher: image_publisher,
          imageOffer: image_offer,
          imageSku: image_sku,
          imageVersion: image_version
        }

        credentials = Kitchen::Driver::Credentials.new.azure_credentials_for_subscription(config[:subscription_id])
        @resource_management_client = ::Azure::ARM::Resources::ResourceManagementClient.new(credentials)
        @resource_management_client.subscription_id = config[:subscription_id]

        # Create Resource Group
        resource_group = ::Azure::ARM::Resources::Models::ResourceGroup.new
        resource_group.location = config[:location]
        begin
          puts "Creating Resource Group: #{state[:azure_resource_group_name]}"
          resource_management_client.resource_groups.create_or_update(state[:azure_resource_group_name], resource_group).value!
        rescue ::MsRestAzure::AzureOperationError => operation_error
          puts operation_error.body['error']
          raise operation_error
        end

        # Execute deployment steps
        begin
          deployment_name = "deploy-#{state[:uuid]}"
          puts "Creating Deployment: #{deployment_name}"
          resource_management_client.deployments.create_or_update(state[:azure_resource_group_name], deployment_name, deployment(virtual_machine_deployment_template, deployment_parameters)).value!
        rescue ::MsRestAzure::AzureOperationError => operation_error
          puts operation_error.body['error']
          raise operation_error
        end

        # Monitor all operations until completion
        follow_deployment_until_end_state(state[:azure_resource_group_name], deployment_name)

        # Now retrieve the public IP from the resource group:
        network_management_client = ::Azure::ARM::Network::NetworkResourceProviderClient.new(credentials)
        network_management_client.subscription_id = config[:subscription_id]
        result = network_management_client.public_ip_addresses.get(state[:azure_resource_group_name], 'publicip').value!
        puts "IP Address is: #{result.body.properties.ip_address} [#{result.body.properties.dns_settings.fqdn}]"
        state[:hostname] = result.body.properties.ip_address
      end

      def deployment(template, parameters)
        deployment = ::Azure::ARM::Resources::Models::Deployment.new
        deployment.properties = ::Azure::ARM::Resources::Models::DeploymentProperties.new
        deployment.properties.mode = Azure::ARM::Resources::Models::DeploymentMode::Incremental
        deployment.properties.template = JSON.parse(template)
        deployment.properties.parameters = parameters_in_values_format(parameters)
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
        puts "Resource Template deployment reached end state of '#{deployment_provisioning_state}'."
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
            puts "Resource #{resource_type} '#{resource_name}' provisioning status is #{resource_provisioning_state}"
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
        resource_management_client = ::Azure::ARM::Resources::ResourceManagementClient.new(credentials)
        resource_management_client.subscription_id = state[:subscription_id]
        begin
          puts "Destroying Resource Group: #{state[:azure_resource_group_name]}"
          resource_management_client.resource_groups.begin_delete(state[:azure_resource_group_name]).value!
          puts 'Destroy operation accepted and will continue in the background.'
        rescue ::MsRestAzure::AzureOperationError => operation_error
          puts operation_error.body['error']
          raise operation_error
        end
        state.delete(:server_id)
        state.delete(:hostname)
        state.delete(:username)
        state.delete(:password)
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
    }
  },
  "variables": {
    "location": "[parameters('location')]",
    "OSDiskName": "osdisk",
    "nicName": "nic",
    "addressPrefix": "10.0.0.0/16",
    "subnetName": "Subnet",
    "subnetPrefix": "10.0.0.0/24",
    "storageAccountType": "Standard_LRS",
    "publicIPAddressName": "publicip",
    "publicIPAddressType": "Dynamic",
    "vmStorageAccountContainerName": "vhds",
    "vmName": "vm",
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
             "enabled": "false",
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
