# kitchen-azurerm

[![Gem Version](https://badge.fury.io/rb/kitchen-azurerm.svg)](https://badge.fury.io/rb/kitchen-azurerm)
![CI](https://github.com/test-kitchen/kitchen-azurerm/workflows/CI/badge.svg?branch=master)

**kitchen-azurerm** is a driver for the popular test harness [Test Kitchen](http://kitchen.ci) that allows Microsoft Azure resources to be provisioned before testing. This driver uses the new Microsoft Azure Resource Management REST API via the [azure-sdk-for-ruby](https://github.com/azure/azure-sdk-for-ruby).

This version has been tested on Windows, macOS, and Ubuntu. If you encounter a problem on your platform, please raise an issue.

## Quick-start

### Installation

This plugin ships in Chef Workstation out of the box so there is no need to install it when using Chef Workstation[https://downloads.chef.io/products/workstation].

If you're not using Chef Workstation and need to install the plugin as a gem run:

```$ gem install kitchen-azurerm```

### Configuration

For the driver to interact with the Microsoft Azure Resource management REST API, a Service Principal needs to be configured with Contributor rights against the specific subscription being targeted. Using an Organizational (AAD) account and related password is no longer supported. To create a Service Principal and apply the correct permissions, you will need to [create an Azure service principal with the Azure CLI](https://docs.microsoft.com/en-us/cli/azure/create-an-azure-service-principal-azure-cli?view=azure-cli-latest#create-a-service-principal) using the [Azure CLI](https://azure.microsoft.com/en-us/documentation/articles/xplat-cli-install/). Make sure you stay within the section titled 'Authenticate service principal with password - Azure CLI'.

If the above is TLDR then try this after `az login` using your target subscription ID and the desired SP name:

```bash
# Create a Service Principal using the desired subscription id from the command above
az ad sp create-for-rbac --name="kitchen-azurerm" --role="Contributor" --scopes="/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

#Output
#
#{
#  "appId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",    <- Also known as the Client ID
#  "displayName": "azure-cli-2018-12-12-14-15-39",
#  "name": "http://azure-cli-2018-12-12-14-15-39",
#  "password": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
#  "tenant": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
#}
```

NOTE: Don't forget to save the values from the output -- most importantly the `password`.

You will also need to ensure you have an active Azure subscription (you can get started [for free](https://azure.microsoft.com/en-us/free/) or use your [MSDN Subscription](https://azure.microsoft.com/en-us/pricing/member-offers/msdn-benefits/)).

You are now ready to configure kitchen-azurerm to use the credentials from the service principal you created above. You will use four elements from the steps in that article:

1. **Subscription ID**: available from the Azure portal
2. **Client ID**: this will be the Application Id from the application in step 2.
3. **Client Secret/Password**: this will be the password you supplied in the command in step 2.
4. **Tenant ID**: use the command detailed in "Manually provide credentials through Azure CLI" step 1 to get the TenantId.

Using a text editor, open or create the file ```~/.azure/credentials``` and add the following section, noting there is one section per Subscription ID. **Make sure you save the file with UTF-8 encoding**

```ruby
[ADD-YOUR-AZURE-SUBSCRIPTION-ID-HERE-IN-SQUARE-BRACKET]
client_id = "your-azure-client-id-here"
client_secret = "your-client-secret-here"
tenant_id = "your-azure-tenant-id-here"
```

If preferred, you may also set the following environment variables, however this would be incompatible with supporting multiple Azure subscriptions.

```ruby
AZURE_CLIENT_ID="your-azure-client-id-here"
AZURE_CLIENT_SECRET="your-client-secret-here"
AZURE_TENANT_ID="your-azure-tenant-id-here"
```

Note that the environment variables, if set, take preference over the values in a configuration file.

After adjusting your ```~/.azure/credentials``` file you will need to adjust your ```kitchen.yml``` file to leverage the azurerm driver. Use the following examples to achieve this, then check your configuration with standard kitchen commands. For example,

```bash
% kitchen list
Instance            Driver   Provisioner  Verifier  Transport  Last Action    Last Error
wsus-windows-2019   Azurerm  ChefZero     Inspec    Winrm      <Not Created>  <None>
wsus-windows-2016   Azurerm  ChefZero     Inspec    Winrm      <Not Created>  <None>
```

### Driver Properties

See the [kitchen.ci kitchen-azurem docs](https://kitchen.ci/docs/drivers/azurerm/) for a complete list of configuration options.

### kitchen.yml example 1 - Linux/Ubuntu

Here's an example ```kitchen.yml``` file that provisions an Ubuntu Server, using Chef Zero as the provisioner and SSH as the transport. Note that if the key does not exist at the specified location, it will be created. Also note that if ```ssh_key``` is supplied, Test Kitchen will use this in preference to any default/configured passwords that are supplied.

```yaml
---
driver:
  name: azurerm
  subscription_id: 'your-azure-subscription-id-here'
  location: 'West Europe'
  machine_size: 'Standard_D1'

transport:
  ssh_key: ~/.ssh/id_kitchen-azurerm

provisioner:
  name: chef_zero

platforms:
  - name: ubuntu-14.04
    driver:
      image_urn: Canonical:UbuntuServer:14.04.4-LTS:latest
      vm_name: trusty-vm

suites:
  - name: default
    attributes:
```

### Concurrent execution

Concurrent execution of create/converge/destroy is supported via the --concurrency parameter. Each machine is created in its own Azure Resource Group so it has no shared lifecycle with the other machines in the test run. To take advantage of parallel execution use the following command:

```kitchen test --concurrency <n>```

Where n is the number of threads to create. Note that any failure (e.g. an AzureOperationError) will cause the whole test to fail, though resources already in creation will continue to be created.

### kitchen.yml example 2 - Windows

Here's a further example ```kitchen.yml``` file that will provision a Windows Server 2019 [smalldisk] instance, using WinRM as the transport. An [ephemeral os disk](https://docs.microsoft.com/en-us/azure/virtual-machines/linux/ephemeral-os-disks) is used. The resource created in Azure will enable itself for remote access at deployment time (it does this by customizing the machine at provisioning time) and tags the Azure Resource Group with metadata using the ```resource_group_tags``` property. Notice that the ```vm_tags``` and ```resource_group_tags``` properties use a simple ```key : value``` structure per line:

```yaml
---
driver:
  name: azurerm
  subscription_id: 'your-subscription-id-here'
  location: 'West Europe'
  machine_size: 'Standard_DS2_v2'

provisioner:
  name: chef_zero

platforms:
  - name: windows2019
    driver:
      image_urn: MicrosoftWindowsServer:WindowsServer:2019-Datacenter-smalldisk:latest
      use_ephemeral_osdisk: true
      resource_group_tags:
        project: 'My Cool Project'
        contact: 'me@somewhere.com'
      vm_tags:
        my_tag: its value
        another_tag: its awesome value
    transport:
      name: winrm
suites:
  - name: default
    attributes:
```

### kitchen.yml example 3 - "pre-deployment" ARM template

The following example introduces the ```pre_deployment_template``` and ```pre_deployment_parameters``` properties in the configuration file.
You can use this capability to execute an ARM template containing Azure resources to provision before the system under test is created.

In the example the ARM template in the file ```predeploy.json``` would be executed with the parameters that are specified under ```pre_deployment_parameters```.
These resources will be created in the same Azure Resource Group as the VM under test, and therefore will be destroyed when you type ```kitchen destroy```.

```yaml
---
driver:
  name: azurerm
  subscription_id: 'your-azure-subscription-id-here'
  location: 'West Europe'
  machine_size: 'Standard_D1'
  pre_deployment_template: predeploy.json
  pre_deployment_parameters:
    test_parameter: 'This is a test.'

transport:
  ssh_key: ~/.ssh/id_kitchen-azurerm

provisioner:
  name: chef_zero

platforms:
  - name: ubuntu-1404
    driver:
      image_urn: Canonical:UbuntuServer:14.04.4-LTS:latest

suites:
  - name: default
    run_list:
      - recipe[kitchen-azurerm-demo::default]
    attributes:
```

Example predeploy.json:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
      "test_parameter": {
        "type": "string",
        "defaultValue": ""
      }
  },
  "variables": {

  },
  "resources": [
      {
        "name": "uniqueinstancenamehere01",
        "type": "Microsoft.Sql/servers",
        "location": "[resourceGroup().location]",
        "apiVersion": "2014-04-01-preview",
        "properties": {
          "version": "12.0",
          "administratorLogin": "azure",
          "administratorLoginPassword": "P2ssw0rd"
        }
      }
  ],
  "outputs": {
      "parameter testing": {
        "type": "string",
        "value": "[parameters('test_parameter')]"
      }
  }
}
```

### kitchen.yml example 4 - deploy VM to existing virtual network/subnet (use for ExpressRoute/VPN scenarios)

The following example introduces the ```vnet_id``` and ```subnet_id``` properties under "driver" in the configuration file. This can be applied at the top level, or per platform.
You can use this capability to create the VM on an existing virtual network and subnet created in a different resource group.

In this case, the public IP address is not used unless ```public_ip``` is set to ```true```

```yaml
---
driver:
  name: azurerm
  subscription_id: 'your-azure-subscription-id-here'
  location: 'West Europe'
  machine_size: 'Standard_D1'

transport:
  ssh_key: ~/.ssh/id_kitchen-azurerm

provisioner:
  name: chef_zero

platforms:
  - name: ubuntu-1404
    driver:
      image_urn: Canonical:UbuntuServer:14.04.4-LTS:latest
      vnet_id: /subscriptions/b6e7eee9-YOUR-GUID-HERE-03ab624df016/resourceGroups/pendrica-infrastructure/providers/Microsoft.Network/virtualNetworks/pendrica-arm-vnet
      subnet_id: subnet-10.1.0

suites:
  - name: default
    attributes:
```

### kitchen.yml example 5 - deploy VM to existing virtual network/subnet with a Standard SKU public IP (use for ExpressRoute/VPN scenarios)

The following example introduces the ```vnet_id``` and ```subnet_id``` properties under "driver" in the configuration file. This can be applied at the top level, or per platform.
You can use this capability to create the VM on an existing virtual network and subnet created in a different resource group.

This enables scenarios that require a Standard SKU public IP resource, for example when a NAT gateway is present on the target subnet.


```yaml
---
driver:
  name: azurerm
  subscription_id: 'your-azure-subscription-id-here'
  location: 'West Europe'
  machine_size: 'Standard_D1'

transport:
  ssh_key: ~/.ssh/id_kitchen-azurerm

provisioner:
  name: chef_zero

platforms:
  - name: ubuntu-1404
    driver:
      image_urn: Canonical:UbuntuServer:14.04.4-LTS:latest
      vnet_id: /subscriptions/b6e7eee9-YOUR-GUID-HERE-03ab624df016/resourceGroups/pendrica-infrastructure/providers/Microsoft.Network/virtualNetworks/pendrica-arm-vnet
      subnet_id: subnet-10.1.0
	  public_ip: true
	  public_ip_sku: Standard

suites:
  - name: default
    attributes:
```

### kitchen.yml example 6 - deploy VM to existing virtual network/subnet (use for ExpressRoute/VPN scenarios) with Private Managed Image

This example is the same as above, but uses a private managed image to provision the vm.

Note: The image must be available first. On deletion the disk and everything is removed.

```yaml
---
driver:
  name: azurerm
  subscription_id: 'your-azure-subscription-id-here'
  location: 'West Europe'
  machine_size: 'Standard_D1'

transport:
  ssh_key: ~/.ssh/id_kitchen-azurerm

provisioner:
  name: chef_zero

platforms:
  - name: ubuntu-1404
    driver:
      image_id: /subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/RESGROUP/providers/Microsoft.Compute/images/IMAGENAME
      vnet_id: /subscriptions/b6e7eee9-YOUR-GUID-HERE-03ab624df016/resourceGroups/pendrica-infrastructure/providers/Microsoft.Network/virtualNetworks/pendrica-arm-vnet
      subnet_id: subnet-10.1.0
      use_managed_disk: true

suites:
  - name: default
    attributes:
```

### kitchen.yml example 7 - deploy VM to existing virtual network/subnet (use for ExpressRoute/VPN scenarios) with Private Classic OS Image

This example a classic Custom VM Image (aka a VHD file) is used. As the Image VHD must be in the same storage account then the disk of the instance, the os disk is created in an existing image account.

Note: When the resource group ís deleted, the os disk is left in the existing storage account blob. You must clean up manually.

This example will:

* use the customized image <https://yourstorageaccount.blob.core.windows.net/system/Microsoft.Compute/Images/images/Cent7_P4-osDisk.170dd1b7-7dc3-4496-b248-f47c49f63965.vhd> (can be built with packer)
* set the disk url of the vm to <https://yourstorageaccount.blob.core.windows.net/vhds/osdisk-kitchen-XXXXX.vhd>
* set the os type to linux

```yaml
---
driver:
  name: azurerm
  subscription_id: 'your-azure-subscription-id-here'
  location: 'West Europe'
  machine_size: 'Standard_D1'

transport:
  ssh_key: ~/.ssh/id_kitchen-azurerm

provisioner:
  name: chef_zero

platforms:
  - name: ubuntu-1404
    driver:
      image_url: https://yourstorageaccount.blob.core.windows.net/system/Microsoft.Compute/Images/images/Cent7_P4-osDisk.170dd1b7-7dc3-4496-b248-f47c49f63965.vhd
      existing_storage_account_blob_url: https://yourstorageaccount.blob.core.windows.net
      os_type: linux
      use_managed_disk: false
      vnet_id: /subscriptions/b6e7eee9-YOUR-GUID-HERE-03ab624df016/resourceGroups/pendrica-infrastructure/providers/Microsoft.Network/virtualNetworks/pendrica-arm-vnet
      subnet_id: subnet-10.1.0

suites:
  - name: default
    attributes:
```

### kitchen.yml example 8 - deploy VM to existing virtual network/subnet (use for ExpressRoute/VPN scenarios) with Private Classic OS Image and providing custom data and extra large os disk

This is the same as above, but uses custom data to customize the instance.

Note: Custom data can be custom data or a file to custom data. Please also note that if you use winrm communication to non-nano windows servers custom data is not supported, as winrm is enabled via custom data.

```yaml
---
driver:
  name: azurerm
  subscription_id: 'your-azure-subscription-id-here'
  location: 'West Europe'
  machine_size: 'Standard_D1'

transport:
  ssh_key: ~/.ssh/id_kitchen-azurerm

provisioner:
  name: chef_zero

platforms:
  - name: ubuntu-1404
    driver:
      image_url: https://yourstorageaccount.blob.core.windows.net/system/Microsoft.Compute/Images/images/Cent7_P4-osDisk.170dd1b7-7dc3-4496-b248-f47c49f63965.vhd
      existing_storage_account_blob_url: https://yourstorageaccount.blob.core.windows.net
      os_type: linux
      use_managed_disk: false
      vnet_id: /subscriptions/b6e7eee9-YOUR-GUID-HERE-03ab624df016/resourceGroups/pendrica-infrastructure/providers/Microsoft.Network/virtualNetworks/pendrica-arm-vnet
      subnet_id: subnet-10.1.0
      os_disk_size_gb: 100
      #custom_data: /tmp/customdata.txt
      custom_data: |
        #cloud-config
        fqdn: myhostname
        preserve_hostname: false
        runcmd:
          - yum install -y telnet

suites:
  - name: default
    attributes:
```

### kitchen.yml example 9 - Windows 2016 VM with additional data disks

This example demonstrates how to add 3 additional Managed data disks to a Windows Server 2016 VM. Not supported with legacy (pre-managed disk) storage accounts.

Note the availability of a `format_data_disks` option (default: `false`). When set to true, a PowerShell script will execute at first boot to initialize and format the disks with an NTFS filesystem. This option does not affect Linux machines.

```yaml
---
driver:
  name: azurerm
  subscription_id: 'your-azure-subscription-id-here'
  location: 'West Europe'
  machine_size: 'Standard_F2s'

provisioner:
  name: chef_zero

platforms:
- name: windows2016-noformat
  driver:
    image_urn: MicrosoftWindowsServer:WindowsServer:2016-Datacenter:latest
    data_disks:
      - lun: 0
        disk_size_gb: 128
      - lun: 1
        disk_size_gb: 128
      - lun: 2
        disk_size_gb: 128
    # format_data_disks: false

suites:
  - name: default
    attributes:
```

### kitchen.yml example 10 - "post-deployment" ARM template with MSI authentication

The following example introduces the ```post_deployment_template``` and ```post_deployment_parameters``` properties in the configuration file.
You can use this capability to execute an ARM template containing Azure resources to provision after the system under test is created.

In the example the ARM template in the file ```postdeploy.json``` would be executed with the parameters that are specified under ```post_deployment_parameters```.
These resources will be created in the same Azure Resource Group as the VM under test, and therefore will be destroyed when you type ```kitchen destroy```.

```yaml
---
driver:
  name: azurerm
  subscription_id: 'your-azure-subscription-id-here'
  location: 'West Europe'
  machine_size: 'Standard_D1'
  post_deployment_template: postdeploy.json
  post_deployment_parameters:
    test_parameter: 'This is a test.'

transport:
  ssh_key: ~/.ssh/id_kitchen-azurerm

provisioner:
  name: chef_zero

platforms:
  - name: ubuntu-1404
    driver:
      image_urn: Canonical:UbuntuServer:14.04.4-LTS:latest

suites:
  - name: default
    attributes:
```

Example postdeploy.json to enable MSI extention on VM:

```json
{
    "$schema": "https://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "vmName": {
            "type": "String"
        },
        "location": {
            "type": "String"
        },
        "msiExtensionName": {
            "type": "String"
        }
    },
    "resources": [
        {
            "type": "Microsoft.Compute/virtualMachines",
            "name": "[parameters('vmName')]",
            "apiVersion": "2017-12-01",
            "location": "[parameters('location')]",
            "identity": {
                "type": "systemAssigned"
            }
        },
        {
            "type": "Microsoft.Compute/virtualMachines/extensions",
            "name": "[concat( parameters('vmName'), '/' , parameters('msiExtensionName') )]",
            "apiVersion": "2017-12-01",
            "location": "[parameters('location')]",
            "properties": {
                "publisher": "Microsoft.ManagedIdentity",
                "type": "[parameters('msiExtensionName')]",
                "typeHandlerVersion": "1.0",
                "autoUpgradeMinorVersion": true,
                "settings": {
                    "port": 50342
                }
            },
            "dependsOn": [
                "[concat('Microsoft.Compute/virtualMachines/', parameters('vmName'))]"
            ]
        }
    ]
}
```

### kitchen.yml example 11 - Enabling Managed Service Identities

This example demonstrates how to enable a System Assigned Identity and User Assigned Identities on a Kitchen VM.
Any combination of System and User assigned identities may be enabled, and multiple User Assigned Identities can be supplied.

See the [Managed identities for Azure resources](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/overview) documentation for more information on using Managed Service Identities.

```yaml
---
driver:
  name: azurerm
  subscription_id: 'your-azure-subscription-id-here'
  location: 'West Europe'
  machine_size: 'Standard_D1'

transport:
  ssh_key: ~/.ssh/id_kitchen-azurerm

provisioner:
  name: chef_zero

platforms:
  - name: ubuntu-1404
    driver:
      image_urn: Canonical:UbuntuServer:14.04.4-LTS:latest
      system_assigned_identity: true
      user_assigned_identities:
        - /subscriptions/4801fa9d-YOUR-GUID-HERE-b265ff49ce21/resourcegroups/test-kitchen-user/providers/Microsoft.ManagedIdentity/userAssignedIdentities/test-kitchen-user

suites:
  - name: default
    attributes:
```

### kitchen.yml example 12 - deploy VM with key vault certificate

This following example introduces ```secret_url```, ```vault_name```, and ```vault_resource_group``` properties under "driver" in the configuration file. You can use this capability to create a VM with a specified key vault certificate.

```yaml
---
driver:
  name: azurerm
  subscription_id: 'your-azure-subscription-id-here'
  location: 'CentralUS'
  machine_size: 'Standard_D2s_v3'
  secret_url: 'https://YOUR-SECRET-PATH'
  vault_name: 'YOUR-VAULT-NAME'
  vault_group_name: 'YOUR-VAULT-GROUP-NAME'
transport:
  name: winrm
  elevated: true
provisioner:
  name: chef_zero
platforms:
  - name: win2012R2-sql2016
    driver:
      image_urn: MicrosoftSQLServer:SQL2016SP2-WS2012R2:SQLDEV:latest

suites:
  - name: default
    attributes:
```

## Support for Government and Sovereign Clouds (China and Germany)

Starting with v0.9.0 this driver has support for Azure Government and Sovereign Clouds via the use of the ```azure_environment``` setting. Valid Azure environments are ```Azure```, ```AzureUSGovernment```, ```AzureChina``` and ```AzureGermanCloud```

Note that the ```use_managed_disks``` option should be set to false until supported by AzureUSGovernment.

### Example kitchen.yml for Azure US Government cloud

```yaml
---
driver:
  name: azurerm
  subscription_id: 'your-azure-subscription-id-here'
  azure_environment: 'AzureUSGovernment'
  location: 'US Gov Iowa'
  machine_size: 'Standard_D2_v2_Promo'
  use_managed_disks: false

provisioner:
  name: chef_zero

verifier:
  name: inspec

platforms:
- name: ubuntu1604
  driver:
    image_urn: Canonical:UbuntuServer:16.04-LTS:latest
  transport:
    ssh_key: ~/.ssh/id_kitchen-azurerm

suites:
  - name: default
```

### How to retrieve the image_urn

You can use the azure (azure-cli) command line tools to interrogate for the Urn. All 4 parts of the Urn must be specified, though the last part can be changed to "latest" to indicate you always wish to provision the latest operating system and patches.

```$ azure vm image list "West Europe" Canonical UbuntuServer```

This will return a list like the following, from which you can derive the Urn.
*this list has been shortened for readability*

```bash
data:    Publisher  Offer         Sku                Version          Location    Urn
data:    ---------  ------------  -----------------  ---------------  ----------  --------------------------------------------------------
data:    Canonical  UbuntuServer  12.04.5-LTS        12.04.201507301  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201507301
data:    Canonical  UbuntuServer  12.04.5-LTS        12.04.201507311  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201507311
data:    Canonical  UbuntuServer  12.04.5-LTS        12.04.201508190  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201508190
data:    Canonical  UbuntuServer  12.04.5-LTS        12.04.201509060  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201509060
data:    Canonical  UbuntuServer  12.04.5-LTS        12.04.201509090  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201509090
data:    Canonical  UbuntuServer  12.10              12.10.201212180  westeurope  Canonical:UbuntuServer:12.10:12.10.201212180
data:    Canonical  UbuntuServer  14.04.3-DAILY-LTS  14.04.201509110  westeurope  Canonical:UbuntuServer:14.04.3-DAILY-LTS:14.04.201509110
data:    Canonical  UbuntuServer  14.04.3-DAILY-LTS  14.04.201509160  westeurope  Canonical:UbuntuServer:14.04.3-DAILY-LTS:14.04.201509160
data:    Canonical  UbuntuServer  14.04.3-DAILY-LTS  14.04.201509220  westeurope  Canonical:UbuntuServer:14.04.3-DAILY-LTS:14.04.201509220
data:    Canonical  UbuntuServer  14.04.3-LTS        14.04.201508050  westeurope  Canonical:UbuntuServer:14.04.3-LTS:14.04.201508050
data:    Canonical  UbuntuServer  14.04.3-LTS        14.04.201509080  westeurope  Canonical:UbuntuServer:14.04.3-LTS:14.04.201509080
data:    Canonical  UbuntuServer  15.04              15.04.201506161  westeurope  Canonical:UbuntuServer:15.04:15.04.201506161
data:    Canonical  UbuntuServer  15.04              15.04.201507070  westeurope  Canonical:UbuntuServer:15.04:15.04.201507070
data:    Canonical  UbuntuServer  15.04              15.04.201507220  westeurope  Canonical:UbuntuServer:15.04:15.04.201507220
data:    Canonical  UbuntuServer  15.04              15.04.201507280  westeurope  Canonical:UbuntuServer:15.04:15.04.201507280
data:    Canonical  UbuntuServer  15.10-DAILY        15.10.201509170  westeurope  Canonical:UbuntuServer:15.10-DAILY:15.10.201509170
data:    Canonical  UbuntuServer  15.10-DAILY        15.10.201509180  westeurope  Canonical:UbuntuServer:15.10-DAILY:15.10.201509180
data:    Canonical  UbuntuServer  15.10-DAILY        15.10.201509190  westeurope  Canonical:UbuntuServer:15.10-DAILY:15.10.201509190
data:    Canonical  UbuntuServer  15.10-DAILY        15.10.201509210  westeurope  Canonical:UbuntuServer:15.10-DAILY:15.10.201509210
data:    Canonical  UbuntuServer  15.10-DAILY        15.10.201509220  westeurope  Canonical:UbuntuServer:15.10-DAILY:15.10.201509220
info:    vm image list command OK
```

## Contributing

Contributions to the project are welcome via submitting Pull Requests.

1. Fork it ( <https://github.com/test-kitchen/kitchen-azurerm/fork> )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Author

Stuart Preston

## License and Copyright

Copyright 2015-2021, Chef Software, Inc.

```
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
