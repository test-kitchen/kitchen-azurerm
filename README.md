# kitchen-azurerm

[![Gem Version](https://img.shields.io/gem/v/kitchen-azurerm.svg)](https://rubygems.org/gems/kitchen-azurerm)
[![Lint, Unit & Integration Tests](https://github.com/test-kitchen/kitchen-azurerm/actions/workflows/lint.yml/badge.svg)](https://github.com/test-kitchen/kitchen-azurerm/actions/workflows/lint.yml)

A [Test Kitchen](https://kitchen.ci/) driver for Microsoft Azure.

Test Kitchen builds a throwaway machine, converges your configuration code on
it, runs your tests, and destroys it. This driver makes that throwaway machine
an Azure virtual machine, so you can test against the same platform you deploy
to. It talks to the Azure Resource Manager REST API directly and depends only
on the Ruby standard library to do so.

Tested on Windows, macOS, and Linux. If you hit a problem on your platform,
please raise an issue.

> This documentation uses [Cinc Workstation](https://cinc.sh/) and the `cinc`
> commands throughout. Everything here works identically with Chef Workstation —
> see [Using with Chef](#using-with-chef).

---

## Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Authentication](#authentication)
- [Configuration reference](#configuration-reference)
- [Common setups](#common-setups)
- [Finding an image URN](#finding-an-image-urn)
- [Troubleshooting](#troubleshooting)
- [Using with Chef](#using-with-chef)
- [Contributing](#contributing)
- [License and Copyright](#license-and-copyright)

---

## Requirements

- Ruby 3.1 or newer (already satisfied if you use Cinc Workstation)
- An active Azure subscription — you can [start for free](https://azure.microsoft.com/en-us/free/)
  or use an [MSDN subscription](https://azure.microsoft.com/en-us/pricing/member-offers/msdn-benefits/)
- A way to authenticate to it, with rights to create resources. A service
  principal with the Contributor role is the usual choice; see
  [Authentication](#authentication) for the alternatives.

The [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) is not
required at run time, but the quick start uses it to create the service
principal and to look up images.

## Installation

This driver ships with [Cinc
Workstation](https://cinc.sh/start/workstation/), which is the simplest way to
get Test Kitchen and its plugins in one package. It also ships with [Chef
Workstation](https://www.chef.io/downloads/tools/workstation).

To install it yourself, add it to your `Gemfile`:

```ruby
gem "kitchen-azurerm"
```

then `bundle install`. Or install the gem directly:

```shell
gem install kitchen-azurerm
```

## Quick start

### 1. Create a service principal

The driver needs an identity with Contributor rights on the subscription you
want to deploy into. After `az login`:

```bash
az ad sp create-for-rbac --name "kitchen-azurerm" \
  --role "Contributor" \
  --scopes "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

which prints:

```json
{
  "appId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "displayName": "kitchen-azurerm",
  "password": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "tenant": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

**Save the `password` now** — Azure will not show it again. You need four
values: the subscription ID, `appId` (the client ID), `password` (the client
secret), and `tenant`.

> Organizational (Entra ID) account and password authentication is no longer
> supported. If you are setting this up for CI, prefer [workload identity
> federation](#workload-identity-federation) and skip the secret entirely.

### 2. Store the credentials

Create `~/.azure/credentials`, with one section per subscription ID. **Save it
as UTF-8.**

```ini
[your-azure-subscription-id-here]
client_id = "your-azure-client-id-here"
client_secret = "your-client-secret-here"
tenant_id = "your-azure-tenant-id-here"
```

Or use environment variables, which take precedence over the file but cannot
describe more than one subscription:

```bash
export AZURE_CLIENT_ID="your-azure-client-id-here"
export AZURE_CLIENT_SECRET="your-client-secret-here"
export AZURE_TENANT_ID="your-azure-tenant-id-here"
```

### 3. Write your `kitchen.yml`

```yaml
---
driver:
  name: azurerm
  subscription_id: <%= ENV["AZURE_SUBSCRIPTION_ID"] %>
  location: westeurope
  machine_size: Standard_D2s_v3

transport:
  ssh_key: ~/.ssh/id_kitchen-azurerm

provisioner:
  name: cinc_infra

verifier:
  name: cinc_auditor

platforms:
  - name: ubuntu-22.04

suites:
  - name: default
```

If the SSH key does not exist at the path you give, Test Kitchen creates it.
When `ssh_key` is set, Test Kitchen uses it in preference to any password.

### 4. Run it

```bash
cinc kitchen test
```

Or step through it:

```bash
cinc kitchen create    # deploy the resource group and VM
cinc kitchen converge  # apply your configuration
cinc kitchen verify    # run your tests
cinc kitchen destroy   # delete the resource group
```

`cinc kitchen list` shows what is configured and what state it is in:

```text
Instance            Driver   Provisioner  Verifier     Transport  Last Action    Last Error
default-ubuntu-2204 Azurerm  CincInfra    CincAuditor  Ssh        <Not Created>  <None>
```

## Authentication

The driver picks an authentication method from whatever resolves, in this
order:

| Method | Configure with | Use when |
| --- | --- | --- |
| Workload identity federation | `AZURE_FEDERATED_TOKEN_FILE` + `AZURE_CLIENT_ID` + `AZURE_TENANT_ID` | CI — GitHub Actions, GitLab, Azure DevOps, AKS. No secret to store. |
| Service principal | `AZURE_CLIENT_ID` + `AZURE_CLIENT_SECRET` + `AZURE_TENANT_ID`, or the credentials file | A long-lived secret you manage yourself. |
| Managed identity | `AZURE_CLIENT_ID` for a user-assigned identity, `AZURE_USE_MSI=1` for a system-assigned one | Running on an Azure VM or in AKS. |
| Azure CLI | `az login` | Local development. |

Values come from the environment first, then the matching subscription section
of the credentials file.

### Workload identity federation

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

### Managed identity

On an Azure VM or in AKS, set `AZURE_CLIENT_ID` to the user-assigned identity's
client ID, or `AZURE_USE_MSI=1` to use the system-assigned identity. Tokens come
from the instance metadata service; no tenant is required.

## Configuration reference

All options below are set under the `driver:` key in `kitchen.yml`, or per platform under `platforms[].driver:`.

### Required

| Option | Default | Description |
| --- | --- | --- |
| `subscription_id` | from credentials file / `AZURE_SUBSCRIPTION_ID` | Azure subscription to deploy into. |
| `location` | *none* | Azure region, e.g. `westeurope`. Required. |
| `machine_size` | *none* | VM size, e.g. `Standard_D2s_v3`. Required. |

### Image

Set one of `image_urn` or `image_id`.

| Option | Default | Description |
| --- | --- | --- |
| `image_urn` | `Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest` | Marketplace image, as `Publisher:Offer:Sku:Version`. See [Finding an image URN](#finding-an-image-urn). |
| `image_id` | `""` | Resource ID of a private managed image or an Azure Compute Gallery image version. |
| `plan` | *unset* | Purchase plan for a Marketplace image that requires one. A hash accepting `name`, `product`, `publisher`, and `promotion_code`. |

### Virtual machine

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

### Disks

| Option | Default | Description |
| --- | --- | --- |
| `use_ephemeral_osdisk` | `false` | Use an ephemeral OS disk, which is faster and cheaper but lost on deallocation. |
| `os_disk_size_gb` | *image default* | Size of the OS disk in GB. Must be at least the image's own size. |
| `storage_account_type` | `"StandardSSD_LRS"` | Managed disk type, e.g. `StandardSSD_LRS`, `Premium_LRS`. |
| `data_disks` | `nil` | Array of data disks to attach, each a hash with `lun` and `disk_size_gb`. |
| `format_data_disks` | `false` | Format and mount attached data disks. Windows only. |
| `format_data_disks_powershell_script` | `false` | Custom PowerShell script used to format the data disks. |

All deployments use managed disks. Azure retired unmanaged disks on 31 March 2026.

### Networking

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

### Resource group

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

### Identity

| Option | Default | Description |
| --- | --- | --- |
| `system_assigned_identity` | `false` | Enable a system-assigned managed identity on the VM. |
| `user_assigned_identities` | `[]` | Array of user-assigned managed identity resource IDs. |

### Key Vault

| Option | Default | Description |
| --- | --- | --- |
| `secret_url` | `""` | URL of a Key Vault certificate to install on the VM. |
| `vault_name` | `""` | Name of the Key Vault holding it. |
| `vault_resource_group` | `""` | Resource group containing the vault. |

### ARM templates

| Option | Default | Description |
| --- | --- | --- |
| `pre_deployment_template` | `""` | Path to an ARM template deployed before the VM. |
| `pre_deployment_parameters` | `{}` | Parameters for the pre-deployment template. |
| `post_deployment_template` | `""` | Path to an ARM template deployed after the VM. |
| `post_deployment_parameters` | `{}` | Parameters for the post-deployment template. |

### Environment and behaviour

| Option | Default | Description |
| --- | --- | --- |
| `azure_environment` | `"Azure"` | Cloud to target: `Azure`, `AzureUSGovernment`, `AzureChina`, `AzureGermanCloud`. See [Government and sovereign clouds](#government-and-sovereign-clouds). |
| `boot_diagnostics_enabled` | `true` | Enable managed boot diagnostics on the VM. |
| `winrm_powershell_script` | `false` | Custom PowerShell script used to configure WinRM. Windows only. |
| `deployment_sleep` | `10` | Seconds to wait between polls of the deployment status. |
| `azure_api_retries` | `5` | Number of times to retry a failed Azure API call. |

### Retired settings

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

## Common setups

Each of these shows only the parts that matter — combine them with the quick
start's `kitchen.yml` as needed. Any `driver:` setting can be given at the top
level or per platform under `platforms[].driver:`.

### Windows over WinRM

The VM enables itself for remote access at deployment time. This example also
uses an [ephemeral OS
disk](https://learn.microsoft.com/azure/virtual-machines/ephemeral-os-disks),
which is faster and cheaper but lost when the VM is deallocated, and tags both
the VM and its resource group.

```yaml
---
driver:
  name: azurerm
  subscription_id: <%= ENV["AZURE_SUBSCRIPTION_ID"] %>
  location: westeurope
  machine_size: Standard_DS2_v2

provisioner:
  name: cinc_infra

verifier:
  name: cinc_auditor

platforms:
  - name: windows-2022
    driver:
      image_urn: MicrosoftWindowsServer:WindowsServer:2022-Datacenter-smalldisk:latest
      use_ephemeral_osdisk: true
      resource_group_tags:
        project: My Cool Project
        contact: me@somewhere.com
      vm_tags:
        my_tag: its value
        another_tag: its awesome value
    transport:
      name: winrm

suites:
  - name: default
```

### Running instances concurrently

Each machine is created in its own Azure resource group, so instances share no
lifecycle and can be built in parallel:

```bash
cinc kitchen test --concurrency 4
```

Any failure fails the whole run, though resources already being created will
finish being created.

### Deploying into an existing virtual network

Set `vnet_id` and `subnet_id` to place the VM on a network that already exists,
possibly in a different resource group. This is the usual setup when you reach
the VM over ExpressRoute or a VPN rather than a public address.

```yaml
platforms:
  - name: ubuntu-22.04
    driver:
      image_urn: Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest
      vnet_id: /subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/my-infrastructure/providers/Microsoft.Network/virtualNetworks/my-vnet
      subnet_id: my-subnet
```

No public IP address is assigned unless you also set `public_ip: true`. When
the subnet sits behind a NAT gateway, or otherwise needs a Standard SKU
address, add:

```yaml
      public_ip: true
      public_ip_sku: Standard
```

Standard SKU public IPs are closed to inbound traffic unless a network security
group allows it — see the note under [Networking](#networking).

### Using a private image

Set `image_id` to the resource ID of a managed image or an Azure Compute
Gallery image version, in place of `image_urn`. The image must already exist.

```yaml
platforms:
  - name: my-custom-image
    driver:
      image_id: /subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/my-images/providers/Microsoft.Compute/images/my-image
```

Everything created for the run, including the OS disk, is removed on
`kitchen destroy`.

> Deploying from a VHD URL in a storage account is no longer supported. Azure
> retired unmanaged disks on 31 March 2026 — see [Retired
> settings](#retired-settings).

### Custom data and a larger OS disk

`custom_data` takes either a string or a path to a file, and `os_disk_size_gb`
grows the OS disk beyond the image's own size.

```yaml
platforms:
  - name: ubuntu-22.04
    driver:
      image_urn: Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest
      custom_data: cloud-init.txt
      os_disk_size_gb: 128
```

> Custom data is how WinRM gets enabled on non-Nano Windows images, so setting
> `custom_data` yourself is not supported when using the WinRM transport.

### Attaching data disks

Each entry needs a `lun` and a `disk_size_gb`:

```yaml
platforms:
  - name: windows-2022
    driver:
      image_urn: MicrosoftWindowsServer:WindowsServer:2022-Datacenter:latest
      data_disks:
        - lun: 0
          disk_size_gb: 128
        - lun: 1
          disk_size_gb: 128
        - lun: 2
          disk_size_gb: 128
      format_data_disks: true
```

`format_data_disks` runs a PowerShell script at first boot to initialize and
format the disks as NTFS. It has no effect on Linux.

### Managed identities

Any combination of system-assigned and user-assigned identities can be enabled,
and multiple user-assigned identities can be supplied. See the [managed
identities
documentation](https://learn.microsoft.com/entra/identity/managed-identities-azure-resources/overview).

```yaml
platforms:
  - name: ubuntu-22.04
    driver:
      image_urn: Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest
      system_assigned_identity: true
      user_assigned_identities:
        - /subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourcegroups/test-kitchen-user/providers/Microsoft.ManagedIdentity/userAssignedIdentities/test-kitchen-user
```

### Installing a Key Vault certificate

```yaml
driver:
  name: azurerm
  subscription_id: <%= ENV["AZURE_SUBSCRIPTION_ID"] %>
  location: centralus
  machine_size: Standard_D2s_v3
  secret_url: https://YOUR-VAULT.vault.azure.net/secrets/YOUR-SECRET/YOUR-VERSION
  vault_name: YOUR-VAULT-NAME
  vault_resource_group: YOUR-VAULT-RESOURCE-GROUP

transport:
  name: winrm
  elevated: true

provisioner:
  name: cinc_infra

platforms:
  - name: windows-2022
    driver:
      image_urn: MicrosoftWindowsServer:WindowsServer:2022-Datacenter:latest

suites:
  - name: default
```

### ARM templates before and after the VM

`pre_deployment_template` runs an ARM template before the system under test is
created; `post_deployment_template` runs one after. Both deploy into the same
resource group as the VM, so both are torn down by `kitchen destroy`.

```yaml
driver:
  name: azurerm
  subscription_id: <%= ENV["AZURE_SUBSCRIPTION_ID"] %>
  location: westeurope
  machine_size: Standard_D2s_v3
  pre_deployment_template: predeploy.json
  pre_deployment_parameters:
    test_parameter: This is a test.
  post_deployment_template: postdeploy.json
  post_deployment_parameters:
    test_parameter: This is a test.
```

A minimal `predeploy.json`:

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
  "variables": {},
  "resources": [],
  "outputs": {
    "parameter testing": {
      "type": "string",
      "value": "[parameters('test_parameter')]"
    }
  }
}
```

A post-deployment template runs against the VM that was just created, so it can
reference it — for example to attach an extension. Use the `vmName` the driver
reports, and declare the dependency:

```json
"dependsOn": [
  "[concat('Microsoft.Compute/virtualMachines/', parameters('vmName'))]"
]
```

### Government and sovereign clouds

Set `azure_environment` to target a cloud other than global Azure. Valid values
are `Azure`, `AzureUSGovernment`, `AzureChina`, and `AzureGermanCloud`.

```yaml
---
driver:
  name: azurerm
  subscription_id: <%= ENV["AZURE_SUBSCRIPTION_ID"] %>
  azure_environment: AzureUSGovernment
  location: usgoviowa
  machine_size: Standard_D2_v2

provisioner:
  name: cinc_infra

verifier:
  name: cinc_auditor

platforms:
  - name: ubuntu-22.04
    driver:
      image_urn: Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest
    transport:
      ssh_key: ~/.ssh/id_kitchen-azurerm

suites:
  - name: default
```

## Finding an image URN

An `image_urn` has four parts — `Publisher:Offer:Sku:Version`. All four must be
given, though the last can be `latest` to always take the newest version.

List the offers a publisher has in your region:

```bash
az vm image list --location westeurope --publisher Canonical \
  --all --output table
```

```text
Architecture  Offer                            Publisher  Sku               Version         Urn
------------  -------------------------------  ---------  ----------------  --------------  ----------------------------------------------------------------------------
x64           0001-com-ubuntu-server-jammy     Canonical  22_04-lts-gen2    22.04.202401161 Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:22.04.202401161
x64           0001-com-ubuntu-server-noble     Canonical  24_04-lts-gen2    24.04.202404230 Canonical:0001-com-ubuntu-server-noble:24_04-lts-gen2:24.04.202404230
```

Take the `Urn` column and replace the version with `latest` if you want the
newest each run. Drop `--all` for a much shorter list of current images, and
add `--offer` to narrow further.

## Troubleshooting

**`kitchen create` fails immediately with an authentication error.**
Check which method is actually being picked — see [Authentication](#authentication).
The environment wins over `~/.azure/credentials`, so a stale `AZURE_CLIENT_ID`
exported in your shell will silently override the file. Confirm the service
principal still has Contributor on the subscription in `subscription_id`.

**The credentials file is ignored.**
It must be saved as UTF-8, and the section header is the bare subscription ID
in square brackets, with no quotes.

**The deployment succeeds but Test Kitchen cannot connect.**
Almost always the network. If you set `public_ip: false`, you need
ExpressRoute, a VPN, or a jump host to reach the VM at all. If you have a
public IP, remember Standard SKU addresses are closed by default: the driver
creates a security group opening your transport's port only when it creates the
public IP *and* you have not supplied `nsg_id`. Supply `open_ports` for anything
extra.

**`The requested size for resource is currently not available in location`.**
The `machine_size` is not offered in that region, or your subscription has no
quota for it. `az vm list-skus --location westeurope --size Standard_D --output table`
shows what is available.

**A Key Vault certificate is not installed and no error is raised.**
Check the option name. It is `vault_resource_group` — `vault_group_name` is not
a real setting and is silently ignored.

**An option in my `kitchen.yml` has no effect.**
Check it against [Retired settings](#retired-settings). Those are still accepted
so old configuration keeps loading, but the driver logs a warning and ignores
them.

**Resources are left behind after a failed run.**
A `kitchen test` that fails partway can leave the resource group in place.
`cinc kitchen destroy` removes it. If you deployed into an existing group with
`explicit_resource_group_name` and `destroy_explicit_resource_group: false`,
nothing is deleted by design — clean up in the portal.

## Using with Chef

This driver is not tied to Cinc. It provisions Azure resources and does not
itself install either distribution — that is the provisioner's job. The
examples above use Cinc Workstation and the `cinc_infra` provisioner; with
[Chef Workstation](https://www.chef.io/downloads/tools/workstation) run
`kitchen` instead of `cinc kitchen`, and substitute the plugin names:

| Cinc | Chef |
| --- | --- |
| `cinc kitchen test` | `kitchen test` |
| `cinc_infra` provisioner | `chef_infra` provisioner |
| `cinc_auditor` verifier | `inspec` verifier |

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
