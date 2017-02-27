# kitchen-azurerm

**kitchen-azurerm** is a driver for the popular test harness [Test Kitchen](http://kitchen.ci) that allows Microsoft Azure resources to be provisioned prior to testing. This driver uses the new Microsoft Azure Resource Management REST API via the [azure-sdk-for-ruby](https://github.com/azure/azure-sdk-for-ruby).

[![Gem Version](https://badge.fury.io/rb/kitchen-azurerm.svg)](http://badge.fury.io/rb/kitchen-azurerm) [![Build Status](https://travis-ci.org/test-kitchen/kitchen-azurerm.svg)](https://travis-ci.org/test-kitchen/kitchen-azurerm)

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

driver_config:
  subscription_id: '4801fa9d-YOUR-GUID-HERE-b265ff49ce21'
  location: 'West Europe'
  machine_size: 'Standard_D1'

transport:
  ssh_key: ~/.ssh/id_kitchen-azurerm

provisioner:
  name: chef_zero

platforms:
  - name: ubuntu-14.04
    driver_config:
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

Here's a further example ```.kitchen.yml``` file that will provision a Windows Server 2012 R2 instance as well as a Windows Server 2008 R2 instance, using WinRM as the transport. The resource created in Azure will enable itself for remote access at deployment time:

**Note: Test Kitchen currently uses WinRM over HTTP rather than HTTPS. This means the temporary machine credentials traverse the internet in the clear. This will be changed once Test Kitchen fully supports WinRM over a secure channel.**

```yaml
---
driver:
  name: azurerm

driver_config:
  subscription_id: '4801fa9d-YOUR-GUID-HERE-b265ff49ce21'
  location: 'West Europe'
  machine_size: 'Standard_D1'

provisioner:
  name: chef_zero

platforms:
  - name: windows2012-r2
    driver_config:
      image_urn: MicrosoftWindowsServer:WindowsServer:2012-R2-Datacenter:latest
    transport:
      name: winrm
  - name: windows2008-r2
    driver_config:
      image_urn: MicrosoftWindowsServer:WindowsServer:2008-R2-SP1:latest
      winrm_powershell_script: |-
        winrm quickconfig -q
        winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="512"}'
        winrm set winrm/config '@{MaxTimeoutms="1800000"}'
        winrm set winrm/config/service '@{AllowUnencrypted="true"}'
        winrm set winrm/config/service/auth '@{Basic="true"}'
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

driver_config:
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
    driver_config:
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

The following example introduces the ```vnet_id``` and ```subnet_id``` properties under driver_config in the configuration file.  This can be applied at the top level, or per platform.
You can use this capability to create the VM on an existing virtual network and subnet created in a different resource group.

In this case, the public IP address is not used unless ```public_ip``` is set to ```true```


```yaml
---
driver:
  name: azurerm

driver_config:
  subscription_id: '4801fa9d-YOUR-GUID-HERE-b265ff49ce21'
  location: 'West Europe'
  machine_size: 'Standard_D1'

transport:
  ssh_key: ~/.ssh/id_kitchen-azurerm

provisioner:
  name: chef_zero

platforms:
  - name: ubuntu-1404
    driver_config:
      image_urn: Canonical:UbuntuServer:14.04.4-LTS:latest
      vnet_id: /subscriptions/b6e7eee9-YOUR-GUID-HERE-03ab624df016/resourceGroups/pendrica-infrastructure/providers/Microsoft.Network/virtualNetworks/pendrica-arm-vnet
      subnet_id: subnet-10.1.0

suites:
  - name: default
    run_list:
      - recipe[kitchen-azurerm-demo::default]
    attributes:
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
- Note that the ```driver_config``` section also takes a ```username``` and ```password``` parameter, the defaults if these are not specified are "azure" and "P2ssw0rd" respectively.
- The ```storage_account_type``` parameter defaults to 'Standard_LRS' and allows you to switch to premium storage (e.g. 'Premium_LRS')
- The ```enable_boot_diagnostics``` parameter defaults to 'true' and allows you to switch off boot diagnostics in case you are using premium storage.
- The optional ```vm_tags``` parameter allows you to define key:value pairs to tag VMs with on creation.

## Contributing

Contributions to the project are welcome via submitting Pull Requests.

1. Fork it ( https://github.com/test-kitchen/kitchen-azurerm/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
