# kitchen-azurerm

**kitchen-azurerm** is a driver for the popular test harness [Test Kitchen](http://kitchen.ci) that allows Microsoft Azure resources to be provisioned prior to testing. This driver uses the new Microsoft Azure Resource Management REST API via the [azure-sdk-for-ruby](https://github.com/azure/azure-sdk-for-ruby).

[![Gem Version](https://badge.fury.io/rb/kitchen-azurerm.svg)](http://badge.fury.io/rb/kitchen-azurerm)

This version has been tested on Windows only, and may not work on OSX/Linux. 

## Known issues
- WinRM support is not complete, Windows machines will not converge. They will provision (and destroy) correctly, however.
- Azure SDK for Ruby has blocking issues on OSX/Linux environments, this is being tracked here: (https://github.com/Azure/azure-sdk-for-ruby/pull/282) 

## Quick-start
### Installation
This plugin is distributed as a Ruby Gem. To install it, run:

```$ gem install kitchen-azurerm```

Note if you are running the ChefDK you may need to prefix the command with chef, i.e. ```$ chef gem install kitchen-azurerm```

### Configuration

For the driver to interact with the Microsoft Azure Resource management REST API, a Service Principal needs to be configured with Owner rights against the specific subscription being targeted.  Using an Organizational (AAD) account and related password is no longer supported.  To create a Service Principal and apply the correct permissions, follow the instructions in the article: [Authenticating a service principal with Azure Resource Manager](https://azure.microsoft.com/en-us/documentation/articles/resource-group-authenticate-service-principal/#authenticate-service-principal-with-password---azure-cli)   

You will essentially need 4 parameters from the above article to configure kitchen-azurerm: **Subscription ID**, **Client ID**, **Client Secret/Password** and **Tenant ID**.  These can be easily obtained using the azure-cli tools (v0.9.8 or higher) on any platform.

Using a text editor, open or create the file ```~/.azure/credentials``` and add the following section, noting there is one section per Subscription ID.

```ruby
[abcd1234-YOUR-GUID-HERE-abcdef123456]
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

Here's an example ```.kitchen.yml``` file that provisions 3 different types of Ubuntu Server, using Chef Zero as the provisioner and SSH as the transport.

```yml
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
  - name: ubuntu-12.04
    driver_config:
      image_urn: Canonical:UbuntuServer:12.04.5-LTS:latest
  - name: ubuntu-14.04
    driver_config:
      image_urn: Canonical:UbuntuServer:14.04.3-LTS:latest
  - name: ubuntu-15.04
    driver_config:
      image_urn: Canonical:UbuntuServer:15.04:latest

suites:
  - name: default
    run_list:
      - recipe[kitchentesting::default]
    attributes:
```

### Parallel execution
Parallel execution of create/converge/destroy is supported via the --parallel parameter.

### .kitchen.yml example 2 - Windows

```kitchen test --parallel```

Here's a further example ```.kitchen.yml``` file that will provision a Windows Server 2012 R2 instance, using WinRM as the transport:

```yml
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

suites:
  - name: default
    run_list:
      - recipe[kitchentesting::default]
    attributes:
```

### How to retrieve the image_urn
You can use the azure (azure-cli) command line tools to interrogate for the Urn. All 4 parts of the Urn must be specified, though the last part can be changed to "latest" to indicate you always wish to provision the latest operating system and patches.

```$ azure vm image list "West Europe" Canonical UbuntuServer```

This will return a list like the following, from which you can derive the Urn.

```
data:    Publisher  Offer         Sku                OS         Version          Location    Urn
data:    ---------  ------------  -----------------  ---------  ---------------  ----------  --------------------------------------------------------
data:    Canonical  UbuntuServer  12.04.2-LTS        undefined  12.04.201302250  westeurope  Canonical:UbuntuServer:12.04.2-LTS:12.04.201302250
data:    Canonical  UbuntuServer  12.04.2-LTS        undefined  12.04.201303250  westeurope  Canonical:UbuntuServer:12.04.2-LTS:12.04.201303250
data:    Canonical  UbuntuServer  12.04.2-LTS        undefined  12.04.201304150  westeurope  Canonical:UbuntuServer:12.04.2-LTS:12.04.201304150
data:    Canonical  UbuntuServer  12.04.2-LTS        undefined  12.04.201305160  westeurope  Canonical:UbuntuServer:12.04.2-LTS:12.04.201305160
data:    Canonical  UbuntuServer  12.04.2-LTS        undefined  12.04.201305270  westeurope  Canonical:UbuntuServer:12.04.2-LTS:12.04.201305270
data:    Canonical  UbuntuServer  12.04.2-LTS        undefined  12.04.201306030  westeurope  Canonical:UbuntuServer:12.04.2-LTS:12.04.201306030
data:    Canonical  UbuntuServer  12.04.2-LTS        undefined  12.04.201306240  westeurope  Canonical:UbuntuServer:12.04.2-LTS:12.04.201306240
data:    Canonical  UbuntuServer  12.04.3-LTS        undefined  12.04.201308270  westeurope  Canonical:UbuntuServer:12.04.3-LTS:12.04.201308270
data:    Canonical  UbuntuServer  12.04.3-LTS        undefined  12.04.201309090  westeurope  Canonical:UbuntuServer:12.04.3-LTS:12.04.201309090
data:    Canonical  UbuntuServer  12.04.3-LTS        undefined  12.04.201309161  westeurope  Canonical:UbuntuServer:12.04.3-LTS:12.04.201309161
data:    Canonical  UbuntuServer  12.04.3-LTS        undefined  12.04.201310030  westeurope  Canonical:UbuntuServer:12.04.3-LTS:12.04.201310030
data:    Canonical  UbuntuServer  12.04.3-LTS        undefined  12.04.201310240  westeurope  Canonical:UbuntuServer:12.04.3-LTS:12.04.201310240
data:    Canonical  UbuntuServer  12.04.3-LTS        undefined  12.04.201311110  westeurope  Canonical:UbuntuServer:12.04.3-LTS:12.04.201311110
data:    Canonical  UbuntuServer  12.04.3-LTS        undefined  12.04.201311140  westeurope  Canonical:UbuntuServer:12.04.3-LTS:12.04.201311140
data:    Canonical  UbuntuServer  12.04.3-LTS        undefined  12.04.201312050  westeurope  Canonical:UbuntuServer:12.04.3-LTS:12.04.201312050
data:    Canonical  UbuntuServer  12.04.3-LTS        undefined  12.04.201401270  westeurope  Canonical:UbuntuServer:12.04.3-LTS:12.04.201401270
data:    Canonical  UbuntuServer  12.04.3-LTS        undefined  12.04.201401300  westeurope  Canonical:UbuntuServer:12.04.3-LTS:12.04.201401300
data:    Canonical  UbuntuServer  12.04.4-LTS        undefined  12.04.201402270  westeurope  Canonical:UbuntuServer:12.04.4-LTS:12.04.201402270
data:    Canonical  UbuntuServer  12.04.4-LTS        undefined  12.04.201404080  westeurope  Canonical:UbuntuServer:12.04.4-LTS:12.04.201404080
data:    Canonical  UbuntuServer  12.04.4-LTS        undefined  12.04.201404280  westeurope  Canonical:UbuntuServer:12.04.4-LTS:12.04.201404280
data:    Canonical  UbuntuServer  12.04.4-LTS        undefined  12.04.201405140  westeurope  Canonical:UbuntuServer:12.04.4-LTS:12.04.201405140
data:    Canonical  UbuntuServer  12.04.4-LTS        undefined  12.04.201406060  westeurope  Canonical:UbuntuServer:12.04.4-LTS:12.04.201406060
data:    Canonical  UbuntuServer  12.04.4-LTS        undefined  12.04.201406190  westeurope  Canonical:UbuntuServer:12.04.4-LTS:12.04.201406190
data:    Canonical  UbuntuServer  12.04.4-LTS        undefined  12.04.201407020  westeurope  Canonical:UbuntuServer:12.04.4-LTS:12.04.201407020
data:    Canonical  UbuntuServer  12.04.4-LTS        undefined  12.04.201407170  westeurope  Canonical:UbuntuServer:12.04.4-LTS:12.04.201407170
data:    Canonical  UbuntuServer  12.04.5-DAILY-LTS  undefined  12.04.201508180  westeurope  Canonical:UbuntuServer:12.04.5-DAILY-LTS:12.04.201508180
data:    Canonical  UbuntuServer  12.04.5-DAILY-LTS  undefined  12.04.201508190  westeurope  Canonical:UbuntuServer:12.04.5-DAILY-LTS:12.04.201508190
data:    Canonical  UbuntuServer  12.04.5-DAILY-LTS  undefined  12.04.201508313  westeurope  Canonical:UbuntuServer:12.04.5-DAILY-LTS:12.04.201508313
data:    Canonical  UbuntuServer  12.04.5-DAILY-LTS  undefined  12.04.201509020  westeurope  Canonical:UbuntuServer:12.04.5-DAILY-LTS:12.04.201509020
data:    Canonical  UbuntuServer  12.04.5-DAILY-LTS  undefined  12.04.201509040  westeurope  Canonical:UbuntuServer:12.04.5-DAILY-LTS:12.04.201509040
data:    Canonical  UbuntuServer  12.04.5-DAILY-LTS  undefined  12.04.201509050  westeurope  Canonical:UbuntuServer:12.04.5-DAILY-LTS:12.04.201509050
data:    Canonical  UbuntuServer  12.04.5-DAILY-LTS  undefined  12.04.201509060  westeurope  Canonical:UbuntuServer:12.04.5-DAILY-LTS:12.04.201509060
data:    Canonical  UbuntuServer  12.04.5-DAILY-LTS  undefined  12.04.201509090  westeurope  Canonical:UbuntuServer:12.04.5-DAILY-LTS:12.04.201509090
data:    Canonical  UbuntuServer  12.04.5-DAILY-LTS  undefined  12.04.201509100  westeurope  Canonical:UbuntuServer:12.04.5-DAILY-LTS:12.04.201509100
data:    Canonical  UbuntuServer  12.04.5-DAILY-LTS  undefined  12.04.201509170  westeurope  Canonical:UbuntuServer:12.04.5-DAILY-LTS:12.04.201509170
data:    Canonical  UbuntuServer  12.04.5-LTS        undefined  12.04.201408060  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201408060
data:    Canonical  UbuntuServer  12.04.5-LTS        undefined  12.04.201408292  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201408292
data:    Canonical  UbuntuServer  12.04.5-LTS        undefined  12.04.201409092  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201409092
data:    Canonical  UbuntuServer  12.04.5-LTS        undefined  12.04.201409231  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201409231
data:    Canonical  UbuntuServer  12.04.5-LTS        undefined  12.04.201409244  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201409244
data:    Canonical  UbuntuServer  12.04.5-LTS        undefined  12.04.201409251  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201409251
data:    Canonical  UbuntuServer  12.04.5-LTS        undefined  12.04.201409252  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201409252
data:    Canonical  UbuntuServer  12.04.5-LTS        undefined  12.04.201409270  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201409270
data:    Canonical  UbuntuServer  12.04.5-LTS        undefined  12.04.201501190  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201501190
data:    Canonical  UbuntuServer  12.04.5-LTS        undefined  12.04.201501270  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201501270
data:    Canonical  UbuntuServer  12.04.5-LTS        undefined  12.04.201502040  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201502040
data:    Canonical  UbuntuServer  12.04.5-LTS        undefined  12.04.201503090  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201503090
data:    Canonical  UbuntuServer  12.04.5-LTS        undefined  12.04.201504010  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201504010
data:    Canonical  UbuntuServer  12.04.5-LTS        undefined  12.04.201504130  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201504130
data:    Canonical  UbuntuServer  12.04.5-LTS        undefined  12.04.201505120  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201505120
data:    Canonical  UbuntuServer  12.04.5-LTS        undefined  12.04.201505221  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201505221
data:    Canonical  UbuntuServer  12.04.5-LTS        undefined  12.04.201506100  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201506100
data:    Canonical  UbuntuServer  12.04.5-LTS        undefined  12.04.201506150  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201506150
data:    Canonical  UbuntuServer  12.04.5-LTS        undefined  12.04.201506160  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201506160
data:    Canonical  UbuntuServer  12.04.5-LTS        undefined  12.04.201507070  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201507070
data:    Canonical  UbuntuServer  12.04.5-LTS        undefined  12.04.201507280  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201507280
data:    Canonical  UbuntuServer  12.04.5-LTS        undefined  12.04.201507301  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201507301
data:    Canonical  UbuntuServer  12.04.5-LTS        undefined  12.04.201507311  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201507311
data:    Canonical  UbuntuServer  12.04.5-LTS        undefined  12.04.201508190  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201508190
data:    Canonical  UbuntuServer  12.04.5-LTS        undefined  12.04.201509060  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201509060
data:    Canonical  UbuntuServer  12.04.5-LTS        undefined  12.04.201509090  westeurope  Canonical:UbuntuServer:12.04.5-LTS:12.04.201509090
data:    Canonical  UbuntuServer  12.10              undefined  12.10.201212180  westeurope  Canonical:UbuntuServer:12.10:12.10.201212180
data:    Canonical  UbuntuServer  14.04.0-LTS        undefined  14.04.201404140  westeurope  Canonical:UbuntuServer:14.04.0-LTS:14.04.201404140
data:    Canonical  UbuntuServer  14.04.0-LTS        undefined  14.04.201404142  westeurope  Canonical:UbuntuServer:14.04.0-LTS:14.04.201404142
data:    Canonical  UbuntuServer  14.04.0-LTS        undefined  14.04.201404161  westeurope  Canonical:UbuntuServer:14.04.0-LTS:14.04.201404161
data:    Canonical  UbuntuServer  14.04.0-LTS        undefined  14.04.201405280  westeurope  Canonical:UbuntuServer:14.04.0-LTS:14.04.201405280
data:    Canonical  UbuntuServer  14.04.0-LTS        undefined  14.04.201406061  westeurope  Canonical:UbuntuServer:14.04.0-LTS:14.04.201406061
data:    Canonical  UbuntuServer  14.04.0-LTS        undefined  14.04.201406181  westeurope  Canonical:UbuntuServer:14.04.0-LTS:14.04.201406181
data:    Canonical  UbuntuServer  14.04.0-LTS        undefined  14.04.201407240  westeurope  Canonical:UbuntuServer:14.04.0-LTS:14.04.201407240
data:    Canonical  UbuntuServer  14.04.1-LTS        undefined  14.04.201409090  westeurope  Canonical:UbuntuServer:14.04.1-LTS:14.04.201409090
data:    Canonical  UbuntuServer  14.04.1-LTS        undefined  14.04.201409240  westeurope  Canonical:UbuntuServer:14.04.1-LTS:14.04.201409240
data:    Canonical  UbuntuServer  14.04.1-LTS        undefined  14.04.201409260  westeurope  Canonical:UbuntuServer:14.04.1-LTS:14.04.201409260
data:    Canonical  UbuntuServer  14.04.1-LTS        undefined  14.04.201409270  westeurope  Canonical:UbuntuServer:14.04.1-LTS:14.04.201409270
data:    Canonical  UbuntuServer  14.04.1-LTS        undefined  14.04.201411250  westeurope  Canonical:UbuntuServer:14.04.1-LTS:14.04.201411250
data:    Canonical  UbuntuServer  14.04.1-LTS        undefined  14.04.201501230  westeurope  Canonical:UbuntuServer:14.04.1-LTS:14.04.201501230
data:    Canonical  UbuntuServer  14.04.2-LTS        undefined  14.04.201503090  westeurope  Canonical:UbuntuServer:14.04.2-LTS:14.04.201503090
data:    Canonical  UbuntuServer  14.04.2-LTS        undefined  14.04.201505060  westeurope  Canonical:UbuntuServer:14.04.2-LTS:14.04.201505060
data:    Canonical  UbuntuServer  14.04.2-LTS        undefined  14.04.201506100  westeurope  Canonical:UbuntuServer:14.04.2-LTS:14.04.201506100
data:    Canonical  UbuntuServer  14.04.2-LTS        undefined  14.04.201507060  westeurope  Canonical:UbuntuServer:14.04.2-LTS:14.04.201507060
data:    Canonical  UbuntuServer  14.04.3-DAILY-LTS  undefined  14.04.201509020  westeurope  Canonical:UbuntuServer:14.04.3-DAILY-LTS:14.04.201509020
data:    Canonical  UbuntuServer  14.04.3-DAILY-LTS  undefined  14.04.201509030  westeurope  Canonical:UbuntuServer:14.04.3-DAILY-LTS:14.04.201509030
data:    Canonical  UbuntuServer  14.04.3-DAILY-LTS  undefined  14.04.201509040  westeurope  Canonical:UbuntuServer:14.04.3-DAILY-LTS:14.04.201509040
data:    Canonical  UbuntuServer  14.04.3-DAILY-LTS  undefined  14.04.201509050  westeurope  Canonical:UbuntuServer:14.04.3-DAILY-LTS:14.04.201509050
data:    Canonical  UbuntuServer  14.04.3-DAILY-LTS  undefined  14.04.201509070  westeurope  Canonical:UbuntuServer:14.04.3-DAILY-LTS:14.04.201509070
data:    Canonical  UbuntuServer  14.04.3-DAILY-LTS  undefined  14.04.201509080  westeurope  Canonical:UbuntuServer:14.04.3-DAILY-LTS:14.04.201509080
data:    Canonical  UbuntuServer  14.04.3-DAILY-LTS  undefined  14.04.201509091  westeurope  Canonical:UbuntuServer:14.04.3-DAILY-LTS:14.04.201509091
data:    Canonical  UbuntuServer  14.04.3-DAILY-LTS  undefined  14.04.201509110  westeurope  Canonical:UbuntuServer:14.04.3-DAILY-LTS:14.04.201509110
data:    Canonical  UbuntuServer  14.04.3-DAILY-LTS  undefined  14.04.201509160  westeurope  Canonical:UbuntuServer:14.04.3-DAILY-LTS:14.04.201509160
data:    Canonical  UbuntuServer  14.04.3-DAILY-LTS  undefined  14.04.201509220  westeurope  Canonical:UbuntuServer:14.04.3-DAILY-LTS:14.04.201509220
data:    Canonical  UbuntuServer  14.04.3-LTS        undefined  14.04.201508050  westeurope  Canonical:UbuntuServer:14.04.3-LTS:14.04.201508050
data:    Canonical  UbuntuServer  14.04.3-LTS        undefined  14.04.201509080  westeurope  Canonical:UbuntuServer:14.04.3-LTS:14.04.201509080
data:    Canonical  UbuntuServer  15.04              undefined  15.04.201504171  westeurope  Canonical:UbuntuServer:15.04:15.04.201504171
data:    Canonical  UbuntuServer  15.04              undefined  15.04.201504201  westeurope  Canonical:UbuntuServer:15.04:15.04.201504201
data:    Canonical  UbuntuServer  15.04              undefined  15.04.201504210  westeurope  Canonical:UbuntuServer:15.04:15.04.201504210
data:    Canonical  UbuntuServer  15.04              undefined  15.04.201504211  westeurope  Canonical:UbuntuServer:15.04:15.04.201504211
data:    Canonical  UbuntuServer  15.04              undefined  15.04.201504220  westeurope  Canonical:UbuntuServer:15.04:15.04.201504220
data:    Canonical  UbuntuServer  15.04              undefined  15.04.201505130  westeurope  Canonical:UbuntuServer:15.04:15.04.201505130
data:    Canonical  UbuntuServer  15.04              undefined  15.04.201505131  westeurope  Canonical:UbuntuServer:15.04:15.04.201505131
data:    Canonical  UbuntuServer  15.04              undefined  15.04.201505281  westeurope  Canonical:UbuntuServer:15.04:15.04.201505281
data:    Canonical  UbuntuServer  15.04              undefined  15.04.201506110  westeurope  Canonical:UbuntuServer:15.04:15.04.201506110
data:    Canonical  UbuntuServer  15.04              undefined  15.04.201506161  westeurope  Canonical:UbuntuServer:15.04:15.04.201506161
data:    Canonical  UbuntuServer  15.04              undefined  15.04.201507070  westeurope  Canonical:UbuntuServer:15.04:15.04.201507070
data:    Canonical  UbuntuServer  15.04              undefined  15.04.201507220  westeurope  Canonical:UbuntuServer:15.04:15.04.201507220
data:    Canonical  UbuntuServer  15.04              undefined  15.04.201507280  westeurope  Canonical:UbuntuServer:15.04:15.04.201507280
data:    Canonical  UbuntuServer  15.04              undefined  15.04.201507290  westeurope  Canonical:UbuntuServer:15.04:15.04.201507290
data:    Canonical  UbuntuServer  15.04              undefined  15.04.201508180  westeurope  Canonical:UbuntuServer:15.04:15.04.201508180
data:    Canonical  UbuntuServer  15.04              undefined  15.04.201509090  westeurope  Canonical:UbuntuServer:15.04:15.04.201509090
data:    Canonical  UbuntuServer  15.04              undefined  15.04.201509100  westeurope  Canonical:UbuntuServer:15.04:15.04.201509100
data:    Canonical  UbuntuServer  15.04-beta         undefined  15.04.201502245  westeurope  Canonical:UbuntuServer:15.04-beta:15.04.201502245
data:    Canonical  UbuntuServer  15.04-beta         undefined  15.04.201503250  westeurope  Canonical:UbuntuServer:15.04-beta:15.04.201503250
data:    Canonical  UbuntuServer  15.04-DAILY        undefined  15.04.201508210  westeurope  Canonical:UbuntuServer:15.04-DAILY:15.04.201508210
data:    Canonical  UbuntuServer  15.04-DAILY        undefined  15.04.201508283  westeurope  Canonical:UbuntuServer:15.04-DAILY:15.04.201508283
data:    Canonical  UbuntuServer  15.04-DAILY        undefined  15.04.201509010  westeurope  Canonical:UbuntuServer:15.04-DAILY:15.04.201509010
data:    Canonical  UbuntuServer  15.04-DAILY        undefined  15.04.201509020  westeurope  Canonical:UbuntuServer:15.04-DAILY:15.04.201509020
data:    Canonical  UbuntuServer  15.04-DAILY        undefined  15.04.201509030  westeurope  Canonical:UbuntuServer:15.04-DAILY:15.04.201509030
data:    Canonical  UbuntuServer  15.04-DAILY        undefined  15.04.201509090  westeurope  Canonical:UbuntuServer:15.04-DAILY:15.04.201509090
data:    Canonical  UbuntuServer  15.04-DAILY        undefined  15.04.201509100  westeurope  Canonical:UbuntuServer:15.04-DAILY:15.04.201509100
data:    Canonical  UbuntuServer  15.04-DAILY        undefined  15.04.201509110  westeurope  Canonical:UbuntuServer:15.04-DAILY:15.04.201509110
data:    Canonical  UbuntuServer  15.04-DAILY        undefined  15.04.201509111  westeurope  Canonical:UbuntuServer:15.04-DAILY:15.04.201509111
data:    Canonical  UbuntuServer  15.04-DAILY        undefined  15.04.201509170  westeurope  Canonical:UbuntuServer:15.04-DAILY:15.04.201509170
data:    Canonical  UbuntuServer  15.10-alpha        undefined  15.10.201506240  westeurope  Canonical:UbuntuServer:15.10-alpha:15.10.201506240
data:    Canonical  UbuntuServer  15.10-alpha        undefined  15.10.201507281  westeurope  Canonical:UbuntuServer:15.10-alpha:15.10.201507281
data:    Canonical  UbuntuServer  15.10-beta         undefined  15.10.201508250  westeurope  Canonical:UbuntuServer:15.10-beta:15.10.201508250
data:    Canonical  UbuntuServer  15.10-DAILY        undefined  15.10.201509120  westeurope  Canonical:UbuntuServer:15.10-DAILY:15.10.201509120
data:    Canonical  UbuntuServer  15.10-DAILY        undefined  15.10.201509130  westeurope  Canonical:UbuntuServer:15.10-DAILY:15.10.201509130
data:    Canonical  UbuntuServer  15.10-DAILY        undefined  15.10.201509140  westeurope  Canonical:UbuntuServer:15.10-DAILY:15.10.201509140
data:    Canonical  UbuntuServer  15.10-DAILY        undefined  15.10.201509150  westeurope  Canonical:UbuntuServer:15.10-DAILY:15.10.201509150
data:    Canonical  UbuntuServer  15.10-DAILY        undefined  15.10.201509160  westeurope  Canonical:UbuntuServer:15.10-DAILY:15.10.201509160
data:    Canonical  UbuntuServer  15.10-DAILY        undefined  15.10.201509170  westeurope  Canonical:UbuntuServer:15.10-DAILY:15.10.201509170
data:    Canonical  UbuntuServer  15.10-DAILY        undefined  15.10.201509180  westeurope  Canonical:UbuntuServer:15.10-DAILY:15.10.201509180
data:    Canonical  UbuntuServer  15.10-DAILY        undefined  15.10.201509190  westeurope  Canonical:UbuntuServer:15.10-DAILY:15.10.201509190
data:    Canonical  UbuntuServer  15.10-DAILY        undefined  15.10.201509210  westeurope  Canonical:UbuntuServer:15.10-DAILY:15.10.201509210
data:    Canonical  UbuntuServer  15.10-DAILY        undefined  15.10.201509220  westeurope  Canonical:UbuntuServer:15.10-DAILY:15.10.201509220
info:    vm image list command OK
```

### Additional information/notes
- driver_config also takes a username and password parameter, the defaults if these are not specified are "azure" and "P2ssw0rd" respectively.

## Contributing

Contributions to the project are welcome via submitting Pull Requests.

1. Fork it ( https://github.com/pendrica/kitchen-azurerm/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
