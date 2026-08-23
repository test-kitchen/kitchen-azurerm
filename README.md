# kitchen-azurerm

[![Gem Version](https://badge.fury.io/rb/kitchen-azurerm.svg)](https://badge.fury.io/rb/kitchen-azurerm)
[![Lint, Unit & Integration Tests](https://github.com/test-kitchen/kitchen-azurerm/actions/workflows/lint.yml/badge.svg)](https://github.com/test-kitchen/kitchen-azurerm/actions/workflows/lint.yml)

**kitchen-azurerm** is a driver for the popular test harness [Test Kitchen](http://kitchen.ci) that allows Microsoft Azure resources to be provisioned before testing. This driver talks to the Azure Resource Manager REST API directly, and depends only on the Ruby standard library to do so.

This version has been tested on Windows, macOS, and Ubuntu. If you encounter a problem on your platform, please raise an issue.

## Quick-start

### Installation

This plugin ships in [Cinc Workstation](https://cinc.sh/start/workstation/) out of the box, so there is no need to
install it if you are using Cinc Workstation. The examples below use the `cinc` commands; everything works identically
with Chef Workstation, which also bundles this plugin — see [Using with Chef](#using-with-chef).

If you're not using a Workstation build and need to install the plugin as a gem, run:

```shell
gem install kitchen-azurerm
```

### Configuration

For the driver to interact with the Microsoft Azure Resource Management REST API, you need to configure a Service Principal with Contributor rights for a specific subscription. Using an Organizational (AAD) account and related password is no longer supported. To create a Service Principal and apply the correct permissions, see the [create an Azure service principal with the Azure CLI](https://docs.microsoft.com/en-us/cli/azure/create-an-azure-service-principal-azure-cli?view=azure-cli-latest#create-a-service-principal) and the [Azure CLI](https://azure.microsoft.com/en-us/documentation/articles/xplat-cli-install/) documentation. Make sure you stay within the section titled 'Password-based authentication'.

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

You are now ready to configure kitchen-azurerm to use the credentials from the service principal you created above. You will use four elements from the output:

1. **Subscription ID**: available from the Azure portal
2. **Client ID**: the appId value from the output.
3. **Client Secret/Password**: the password from the output.
4. **Tenant ID**: the tenant from the output.

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

### Authentication methods

The driver picks an authentication method from whatever resolves, in this order:

| Method | Configure with | Use when |
| --- | --- | --- |
| Workload identity federation | `AZURE_FEDERATED_TOKEN_FILE` + `AZURE_CLIENT_ID` + `AZURE_TENANT_ID` | CI — GitHub Actions, GitLab, Azure DevOps, AKS. No secret to store. |
| Service principal | `AZURE_CLIENT_ID` + `AZURE_CLIENT_SECRET` + `AZURE_TENANT_ID`, or the credentials file | A long-lived secret you manage yourself. |
| Managed identity | `AZURE_CLIENT_ID` for a user-assigned identity, `AZURE_USE_MSI=1` for a system-assigned one | Running on an Azure VM or in AKS. |
| Azure CLI | `az login` | Local development. |

Values come from the environment first, then the matching subscription section
of the credentials file.

#### Workload identity federation

This is the method to prefer in CI. Rather than storing a secret, your CI
platform issues a short-lived signed assertion which Azure exchanges for an
access token, so there is no credential in your repository or your CI settings
to leak, rotate, or accidentally print.

Set up a [federated credential](https://learn.microsoft.com/entra/workload-id/workload-identity-federation)
trusting your repository, then in GitHub Actions:

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - uses: azure/login@v2
    with:
      client-id: ${{ secrets.AZURE_CLIENT_ID }}
      tenant-id: ${{ secrets.AZURE_TENANT_ID }}
      subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
  - run: bundle exec kitchen test
```

`azure/login` writes the assertion to a file and exports
`AZURE_FEDERATED_TOKEN_FILE`, `AZURE_CLIENT_ID` and `AZURE_TENANT_ID`, which is
all this driver needs. Nothing in `kitchen.yml` changes.

The assertion is re-read from disk on every token request, so a long
`kitchen test` run keeps working when the platform rotates it.

`AZURE_AUTHORITY_HOST` is honoured if your platform sets it, as AKS does.

#### Managed identity

On an Azure VM or in AKS, set `AZURE_CLIENT_ID` to the user-assigned identity's
client ID, or `AZURE_USE_MSI=1` to use the system-assigned identity. Tokens come
from the instance metadata service; no tenant is required.

After adjusting your ```~/.azure/credentials``` file you will need to adjust your ```kitchen.yml``` file to leverage the azurerm driver. Use the following examples to achieve this, then check your configuration with standard kitchen commands. For example,

```bash
% kitchen list
Instance            Driver   Provisioner  Verifier  Transport  Last Action    Last Error
wsus-windows-2019   Azurerm  ChefZero     Inspec    Winrm      <Not Created>  <None>
wsus-windows-2016   Azurerm  ChefZero     Inspec    Winrm      <Not Created>  <None>
```

### Driver Properties

All options below are set under the `driver:` key in `kitchen.yml`, or per platform under `platforms[].driver:`.

#### Required

| Option | Default | Description |
| --- | --- | --- |
| `subscription_id` | from credentials file / `AZURE_SUBSCRIPTION_ID` | Azure subscription to deploy into. |
| `location` | *none* | Azure region, e.g. `westeurope`. Required. |
| `machine_size` | *none* | VM size, e.g. `Standard_D2s_v3`. Required. |

#### Image

Set one of `image_urn` or `image_id`.

| Option | Default | Description |
| --- | --- | --- |
| `image_urn` | `Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest` | Marketplace image, as `Publisher:Offer:Sku:Version`. See [How to retrieve the image_urn](#how-to-retrieve-the-image_urn). |
| `image_id` | `""` | Resource ID of a private managed image or an Azure Compute Gallery image version. |
| `plan` | *unset* | Purchase plan for a Marketplace image that requires one. A hash accepting `name`, `product`, `publisher`, and `promotion_code`. |

#### Virtual machine

| Option | Default | Description |
| --- | --- | --- |
| `vm_name` | `nil` | Explicit VM name. Generated from `vm_prefix` if unset. |
| `vm_prefix` | `"tk-"` | Prefix for the generated VM name. |
| `vm_tags` | `{}` | Tags applied to the VM. |
| `username` | `"azure"` | Admin username created on the VM. |
| `password` | *generated* | Admin password. A random one is generated if unset. |
| `custom_data` | `""` | Custom data passed to the VM, as a string or a path to a file. |
| `use_fqdn_hostname` | `false` | Connect using the FQDN rather than the IP address. |
| `store_deployment_credentials_in_state` | `true` | Persist the generated credentials in the Test Kitchen state file. |

#### Disks

| Option | Default | Description |
| --- | --- | --- |
| `use_ephemeral_osdisk` | `false` | Use an ephemeral OS disk, which is faster and cheaper but lost on deallocation. |
| `os_disk_size_gb` | *image default* | Size of the OS disk in GB. Must be at least the image's own size. |
| `storage_account_type` | `"StandardSSD_LRS"` | Managed disk type, e.g. `StandardSSD_LRS`, `Premium_LRS`. |
| `data_disks` | `nil` | Array of data disks to attach, each a hash with `lun` and `disk_size_gb`. |
| `format_data_disks` | `false` | Format and mount attached data disks. Windows only. |
| `format_data_disks_powershell_script` | `false` | Custom PowerShell script used to format the data disks. |

All deployments use managed disks. Azure retired unmanaged disks on 31 March 2026.

#### Networking

| Option | Default | Description |
| --- | --- | --- |
| `vnet_id` | `""` | Resource ID of an existing virtual network. Leave unset to create one. |
| `subnet_id` | `""` | Name of the subnet within `vnet_id`. |
| `nic_name` | `""` | Name of an existing network interface to attach. |
| `public_ip` | `false` | Assign a public IP address. Required unless you reach the VM over ExpressRoute or a VPN. |
| `public_ip_sku` | `"Standard"` | Public IP SKU. Azure retired the `Basic` SKU on 30 September 2025. |
| `nsg_id` | `""` | Resource ID of an existing network security group to attach to the network interface. When unset, one is created for you. |
| `open_ports` | `[]` | Extra inbound TCP ports to open, on top of the transport's own port. |

Standard SKU public IPs are closed to inbound traffic unless a network security
group allows it. When the driver creates a public IP and you have not supplied
`nsg_id`, it also creates a security group allowing inbound TCP on the port your
transport uses - 22 for SSH, 5985 and 5986 for WinRM - plus anything in
`open_ports`. Those rules allow any source address, matching the connectivity a
Basic SKU public IP used to provide. To restrict the source, create your own
security group and pass it as `nsg_id`.

#### Retired settings

These settings are still accepted so that an existing `kitchen.yml` keeps
loading, but Azure retirements have made them inoperable. The driver logs a
warning and ignores them.

| Option | Retired because |
| --- | --- |
| `use_managed_disks` | Azure retired unmanaged disks on 31 March 2026. Every deployment now uses managed disks. |
| `image_url` | Deploying from a VHD URL required unmanaged disks. Use `image_id` with a managed image or an Azure Compute Gallery image instead. |
| `os_type` | Only ever applied to `image_url` deployments. |
| `existing_storage_account_blob_url` | OS disks are no longer placed in a storage account you supply. |
| `existing_storage_account_container` | As above. |

#### Resource group

| Option | Default | Description |
| --- | --- | --- |
| `azure_resource_group_name` | derived | Name of the resource group created for the run. |
| `azure_resource_group_prefix` | `"kitchen-"` | Prefix for the generated resource group name. |
| `azure_resource_group_suffix` | `""` | Suffix for the generated resource group name. |
| `explicit_resource_group_name` | `nil` | Deploy into an existing resource group instead of creating one. |
| `resource_group_tags` | `{}` | Tags applied to a resource group the driver creates. |
| `destroy_explicit_resource_group` | `true` | Delete the explicit resource group on destroy. Set to `false` when deploying into a shared group. |
| `destroy_explicit_resource_group_tags` | `true` | Remove the tags the driver added to an explicit resource group on destroy. |
| `destroy_resource_group_contents` | `false` | Delete the resource group's contents rather than the group itself. |

#### Identity

| Option | Default | Description |
| --- | --- | --- |
| `system_assigned_identity` | `false` | Enable a system-assigned managed identity on the VM. |
| `user_assigned_identities` | `[]` | Array of user-assigned managed identity resource IDs. |

#### Key Vault

| Option | Default | Description |
| --- | --- | --- |
| `secret_url` | `""` | URL of a Key Vault certificate to install on the VM. |
| `vault_name` | `""` | Name of the Key Vault holding it. |
| `vault_resource_group` | `""` | Resource group containing the vault. |

#### ARM templates

| Option | Default | Description |
| --- | --- | --- |
| `pre_deployment_template` | `""` | Path to an ARM template deployed before the VM. |
| `pre_deployment_parameters` | `{}` | Parameters for the pre-deployment template. |
| `post_deployment_template` | `""` | Path to an ARM template deployed after the VM. |
| `post_deployment_parameters` | `{}` | Parameters for the post-deployment template. |

#### Environment and behaviour

| Option | Default | Description |
| --- | --- | --- |
| `azure_environment` | `"Azure"` | Cloud to target: `Azure`, `AzureUSGovernment`, `AzureChina`, `AzureGermanCloud`. See [Support for Government and Sovereign Clouds](#support-for-government-and-sovereign-clouds-china-and-germany). |
| `boot_diagnostics_enabled` | `true` | Enable managed boot diagnostics on the VM. |
| `winrm_powershell_script` | `false` | Custom PowerShell script used to configure WinRM. Windows only. |
| `deployment_sleep` | `10` | Seconds to wait between polls of the deployment status. |
| `azure_api_retries` | `5` | Number of times to retry a failed Azure API call. |

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
      image_urn: Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest
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
      image_urn: Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest

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
      image_urn: Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest
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
      image_urn: Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest
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

suites:
  - name: default
    attributes:
```

### kitchen.yml example 7 - deploy VM to existing virtual network/subnet (use for ExpressRoute/VPN scenarios) with a private managed image

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
      image_id: /subscriptions/b6e7eee9-YOUR-GUID-HERE-03ab624df016/resourceGroups/pendrica-infrastructure/providers/Microsoft.Compute/images/Cent7_P4
      vnet_id: /subscriptions/b6e7eee9-YOUR-GUID-HERE-03ab624df016/resourceGroups/pendrica-infrastructure/providers/Microsoft.Network/virtualNetworks/pendrica-arm-vnet
      subnet_id: subnet-10.1.0

suites:
  - name: default
    attributes:
```

### kitchen.yml example 8 - deploy VM to existing virtual network/subnet (use for ExpressRoute/VPN scenarios) with a private managed image, custom data and an extra large os disk

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
      image_id: /subscriptions/b6e7eee9-YOUR-GUID-HERE-03ab624df016/resourceGroups/pendrica-infrastructure/providers/Microsoft.Compute/images/Cent7_P4
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
      image_urn: Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest

suites:
  - name: default
    attributes:
```

Example postdeploy.json to enable MSI extension on VM:

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
      image_urn: Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest
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

### Example kitchen.yml for Azure US Government cloud

```yaml
---
driver:
  name: azurerm
  subscription_id: 'your-azure-subscription-id-here'
  azure_environment: 'AzureUSGovernment'
  location: 'US Gov Iowa'
  machine_size: 'Standard_D2_v2_Promo'

provisioner:
  name: chef_zero

verifier:
  name: inspec

platforms:
- name: ubuntu1604
  driver:
    image_urn: Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest
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

## Using with Chef

This driver is not tied to Cinc. It provisions Azure resources and does not
itself install either distribution — that is the provisioner's job. The examples
above use Cinc Workstation and the `cinc_infra` provisioner; with
[Chef Workstation](https://www.chef.io/downloads/tools/workstation) run `kitchen`
instead of `cinc kitchen` and use `chef_infra` instead of `cinc_infra`:

```yaml
provisioner:
  name: chef_infra

verifier:
  name: inspec
```

No driver configuration changes are needed.

## Contributing

Contributions to the project are welcome via submitting Pull Requests. See
[CONTRIBUTING.md](CONTRIBUTING.md) for development setup, how to run the tests,
and the release process.

## Author

Stuart Preston

## License and Copyright

Copyright 2015-2021, Chef Software, Inc.

```text
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
