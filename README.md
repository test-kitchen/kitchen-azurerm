# kitchen-azurerm

[![Gem Version](https://badge.fury.io/rb/kitchen-azurerm.svg)](http://badge.fury.io/rb/kitchen-azurerm) [![Build Status](https://travis-ci.org/test-kitchen/kitchen-azurerm.svg)](https://travis-ci.org/test-kitchen/kitchen-azurerm)

**kitchen-azurerm** is a driver for the popular test harness [Test Kitchen](http://kitchen.ci) that allows Microsoft Azure resources to be provisioned prior to testing. This driver uses the new Microsoft Azure Resource Management REST API via the [azure-sdk-for-ruby](https://github.com/azure/azure-sdk-for-ruby).

This version has been tested on Windows, OS/X and Ubuntu. If you encounter a problem on your platform, please raise an issue.

## Quick-start

### Installation

This plugin is distributed as a [Ruby Gem](https://rubygems.org/gems/kitchen-azurerm). To install it, run:

```$ gem install kitchen-azurerm```

Note if you are running the ChefDK you may need to prefix the command with chef, i.e. ```$ chef gem install kitchen-azurerm```

### Configuration

For the driver to interact with the Microsoft Azure Resource management REST API, a Service Principal needs to be configured with Contributor rights against the specific subscription being targeted.  Using an Organizational (AAD) account and related password is no longer supported.  To create a Service Principal and apply the correct permissions, you will need to [create and authenticate a service principal](https://azure.microsoft.com/en-us/documentation/articles/resource-group-authenticate-service-principal/#authenticate-service-principal-with-password---azure-cli) using the [Azure CLI](https://azure.microsoft.com/en-us/documentation/articles/xplat-cli-install/). Make sure you stay within the section titled 'Authenticate service principal with password - Azure CLI'.

You will also need to ensure you have an active Azure subscription (you can get started [for free](https://azure.microsoft.com/en-us/free/) or use your [MSDN Subscription](https://azure.microsoft.com/en-us/pricing/member-offers/msdn-benefits/)).

You are now ready to configure kitchen-azurerm to use the credentials from the service principal you created above. You will use four elements from the steps in that article:

1. **Subscription ID**: available from the Azure portal
2. **Client ID**: this will be the Application Id from the application in step 2.
3. **Client Secret/Password**: this will be the password you supplied in the command in step 2.
4. **Tenant ID**: use the command detailed in "Manually provide credentials through Azure CLI" step 1 to get the TenantId.

Using a text editor, open or create the file ```~/.azure/credentials``` and add the following section, noting there is one section per Subscription ID.  **Make sure you save the file with UTF-8 encoding**

```ruby
[abcd1234-YOUR-SUBSCRIPTION-ID-HERE-abcdef123456]
client_id = "48b9bba3-YOUR-GUID-HERE-90f0b68ce8ba"
client_secret = "your-client-secret-here"
tenant_id = "9c117323-YOUR-GUID-HERE-9ee430723ba3"
```

If preferred, you may also set the following environment variables, however this would be incompatible with supporting multiple Azure subscriptions.

```ruby
AZURE_CLIENT_ID="48b9bba3-YOUR-GUID-HERE-90f0b68ce8ba"
AZURE_CLIENT_SECRET="your-client-secret-here"
AZURE_TENANT_ID="9c117323-YOUR-GUID-HERE-9ee430723ba3"
```

Note that the environment variables, if set, take preference over the values in a configuration file.

### .kitchen.yml example 1 - Linux/Ubuntu

Here's an example ```.kitchen.yml``` file that provisions an Ubuntu Server, using Chef Zero as the provisioner and SSH as the transport. Note that if the key does not exist at the specified location, it will be created. Also note that if ```ssh_key``` is supplied, Test Kitchen will use this in preference to any default/configured passwords that are supplied.

```yaml
---
driver:
  name: azurerm
  subscription_id: '4801fa9d-YOUR-GUID-HERE-b265ff49ce21'
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
      vm_tags:
        ostype: linux
        distro: ubuntu

suites:
  - name: default
    run_list:
      - recipe[kitchentesting::default]
    attributes:
```

### Concurrent execution
Concurrent execution of create/converge/destroy is supported via the --concurrency parameter. Each machine is created in it's own Azure Resource Group so has no shared lifecycle with the other machines in the test run. To take advantage of parallel execution use the following command:

```kitchen test --concurrency <n>```

Where <n> is the number of threads to create. Note that any failure (e.g. an AzureOperationError) will cause the whole test to fail, though resources already in creation will continue to be created.

### .kitchen.yml example 2 - Windows

Here's a further example ```.kitchen.yml``` file that will provision a Windows Server 2012 R2 instance, using WinRM as the transport. The resource created in Azure will enable itself for remote access at deployment time (it does this by customizing the machine at provisioning time):

```yaml
---
driver:
  name: azurerm
  subscription_id: '4801fa9d-YOUR-GUID-HERE-b265ff49ce21'
  location: 'West Europe'
  machine_size: 'Standard_D1'

provisioner:
  name: chef_zero

platforms:
  - name: windows2012-r2
    driver:
      image_urn: MicrosoftWindowsServer:WindowsServer:2012-R2-Datacenter:latest
    transport:
      name: winrm
suites:
  - name: default
    run_list:
      - recipe[kitchentesting::default]
    attributes:
```

### .kitchen.yml example 3 - "pre-deployment" ARM template

The following example introduces the ```pre_deployment_template``` and ```pre_deployment_parameters``` properties in the configuration file.
You can use this capability to execute an ARM template containing Azure resources to provision before the system under test is created.  

In the example the ARM template in the file ```predeploy.json``` would be executed with the parameters that are specified under ```pre_deployment_parameters```.  
These resources will be created in the same Azure Resource Group as the VM under test, and therefore will be destroyed when you type ```kitchen destroy```.

```yaml
---
driver:
  name: azurerm
  subscription_id: '4801fa9d-YOUR-GUID-HERE-b265ff49ce21'
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

### .kitchen.yml example 4 - deploy VM to existing virtual network/subnet (use for ExpressRoute/VPN scenarios)

The following example introduces the ```vnet_id``` and ```subnet_id``` properties under "driver" in the configuration file.  This can be applied at the top level, or per platform.
You can use this capability to create the VM on an existing virtual network and subnet created in a different resource group.

In this case, the public IP address is not used unless ```public_ip``` is set to ```true```


```yaml
---
driver:
  name: azurerm
  subscription_id: '4801fa9d-YOUR-GUID-HERE-b265ff49ce21'
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
    run_list:
      - recipe[kitchen-azurerm-demo::default]
    attributes:
```

### .kitchen.yml example 5 - deploy VM to existing virtual network/subnet (use for ExpressRoute/VPN scenarios) with Private Managed Image

This example is the same as above, but uses a private managed image to provision the vm. 

Note: The image must be available first. On deletion the disk and everything is removed.

```yaml
---
driver:
  name: azurerm
  subscription_id: '4801fa9d-YOUR-GUID-HERE-b265ff49ce21'
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
    run_list:
      - recipe[kitchen-azurerm-demo::default]
    attributes:
```

### .kitchen.yml example 6 - deploy VM to existing virtual network/subnet (use for ExpressRoute/VPN scenarios) with Private Classic OS Image

This example a classic Custom VM Image (aka a VHD file) is used. As the Image VHD must be in the same storage account then the disk of the instance, the os disk is created in an existing image account. 

Note: When the resource group ís deleted, the os disk is left in the extsing storage account blob. You must cleanup manually.

This example will: 

* use the customized image https://yourstorageaccount.blob.core.windows.net/system/Microsoft.Compute/Images/images/Cent7_P4-osDisk.170dd1b7-7dc3-4496-b248-f47c49f63965.vhd (can be built with packer)
* set the disk url of the vm to https://yourstorageaccount.blob.core.windows.net/vhds/osdisk-kitchen-XXXXX.vhd
* set the os type to linux


```yaml
---
driver:
  name: azurerm
  subscription_id: '4801fa9d-YOUR-GUID-HERE-b265ff49ce21'
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
    run_list:
      - recipe[kitchen-azurerm-demo::default]
    attributes:
```

### .kitchen.yml example 7 - deploy VM to existing virtual network/subnet (use for ExpressRoute/VPN scenarios) with Private Classic OS Image and providing custom data and extra large os disk

This is the same as above, but uses custom data to customize the instance.

Note: Custom data can be custom data or a file to custom data. Please also note that if you use winrm communication to non-nano windows servers custom data is not supported, as winrm is enabled via custom data.


```yaml
---
driver:
  name: azurerm
  subscription_id: '4801fa9d-YOUR-GUID-HERE-b265ff49ce21'
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
    run_list:
      - recipe[kitchen-azurerm-demo::default]
    attributes:
```

### .kitchen.yml example 8 - Windows 2016 VM with additional data disks:

This example demonstrates how to add 3 additional Managed data disks to a Windows Server 2016 VM. Not supported with legacy (pre-managed disk) storage accounts.

Note the availability of a `format_data_disks` option (default: `false`).  When set to true, a PowerShell script will execute at first boot to initialize and format the disks with an NTFS filesystem.  This option has no effect on Linux machines.

```yaml
---
driver:
  name: azurerm
  subscription_id: '4801fa9d-YOUR-GUID-HERE-b265ff49ce21'
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
    run_list:
      - recipe[kitchentesting::default]
    attributes:
```

## Support for Government and Sovereign Clouds (China and Germany)

Starting with v0.9.0 this driver has support for Azure Government and Sovereign Clouds via the use of the ```azure_environment``` setting.  Valid Azure environments are ```Azure```, ```AzureUSGovernment```, ```AzureChina``` and ```AzureGermanCloud```

Note that the ```use_managed_disks``` option should be set to false until supported by AzureUSGovernment.

### Example .kitchen.yml for Azure US Government cloud

```yaml
---
driver:
  name: azurerm
  subscription_id: 'abcdabcd-YOUR-GUID-HERE-abcdabcdabcd'
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
    run_list:
      - recipe[vmtesting::default]
```

### How to retrieve the image_urn
You can use the azure (azure-cli) command line tools to interrogate for the Urn. All 4 parts of the Urn must be specified, though the last part can be changed to "latest" to indicate you always wish to provision the latest operating system and patches.

```$ azure vm image list "West Europe" Canonical UbuntuServer```

This will return a list like the following, from which you can derive the Urn.
*this list has been shortened for readability*

```
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

### Additional parameters:
- Note that the ```driver``` section also takes a ```username``` and ```password``` parameter, the defaults if these are not specified are "azure" and "P2ssw0rd" respectively.
- The ```storage_account_type``` parameter defaults to 'Standard_LRS' and allows you to switch to premium storage (e.g. 'Premium_LRS')
- The ```enable_boot_diagnostics``` parameter defaults to 'true' and allows you to switch off boot diagnostics in case you are using premium storage.
- The optional ```vm_tags``` parameter allows you to define key:value pairs to tag VMs with on creation.
- Managed disks are now enabled by default, to use the Storage account set ```use_managed_disks``` (default: true).
- The ```image_url``` (unmanaged disks only) parameter can be used to specify a custom vhd (This VHD must be in the same storage account as the disks of the VM, therefore ```existing_storage_account_blob_url``` must also be set and ```use_managed_disks``` must be set to false)
- The ```image_id``` (managed disks only) parameter can be used to specify an image by id (managed disk). This works only with managed disks.
- The ```existing_storage_account_blob_url``` can be specified to specify an url to an existing storage account (needed for ```image_url```)
- The ```custom_data``` parameter can be used to specify custom data to provide to the instance. This can be a file or the data itself. This module handles base64 encoding for you.
- The ```os_disk_size_gb``` parameter can be used to specify a custom os disk size.
- The ```azure_resource_group_prefix``` and ```azure_resource_group_suffix``` can be used to further disambiguate Azure resource group names created by the driver.
- The ```explicit_resource_group_name``` parameters can be used in scenarios where you are provided a pre-created Resource Group.  Example usage: ```explicit_resource_group_name: kitchen-<%= ENV["USERNAME"] %>```

## Contributing

Contributions to the project are welcome via submitting Pull Requests.

1. Fork it ( https://github.com/test-kitchen/kitchen-azurerm/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
