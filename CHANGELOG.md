# kitchen-azurerm Changelog

## [0.15.0] - 2019-11-29
- Enable WinRM HTTP listener by default [PR #121](https://github.com/test-kitchen/kitchen-azurerm/pull/121) (@sean-nixon)
- Default subscription_id to AZURE_SUBSCRIPTION_ID environment variable if not supplied[df79c787fa299cb6eff4a2fd7807fe28ce2bc725](https://github.com/test-kitchen/kitchen-azurerm/commit/df79c787fa299cb6eff4a2fd7807fe28ce2bc725) (@stuartpreston)
- Allow nic name to be passed in as a parameter [PR #112](https://github.com/test-kitchen/kitchen-azurerm/pull/112) (@libertymutual)
- Support for creating VM with Azure KeyVault certificate [PR #120](https://github.com/test-kitchen/kitchen-azurerm/pull/120) (@javgallegos)

## [0.14.9] - 2019-07-30
- Support [Ephemeral OS Disk](https://azure.microsoft.com/en-us/updates/azure-ephemeral-os-disk-now-generally-available/),  (@stuartpreston)

## [0.14.8] - 2018-12-30
- Support [Azure Managed Identities](https://github.com/test-kitchen/kitchen-azurerm#kitchenyml-example-10---enabling-managed-service-identities), [PR #106](https://github.com/test-kitchen/kitchen-azurerm/pull/105) (@zanecodes)
- Apply vm_tags to all resources in resource group [PR #105](https://github.com/test-kitchen/kitchen-azurerm/pull/105) (@josh-hetland)

## [0.14.7] - 2018-12-18
- Updating Azure SDK dependencies, [PR #104](https://github.com/test-kitchen/kitchen-azurerm/pull/104) (@stuartpreston)

## [0.14.6] - 2018-12-11
- Support tags at Resource Group level, [PR #102](https://github.com/test-kitchen/kitchen-azurerm/pull/102) (@pgryzan-chefio)
- Pin azure_mgmt_resources to 0.18.0 to avoid issue retrieving IP address of node during kitchen create [#99](https://github.com/test-kitchen/kitchen-azurerm/issues/99) (@stuartpreston)

## [0.14.5] - 2018-09-30
- Support Shared Image Gallery (preview Azure feature) (@zanecodes)

## [0.14.4] - 2018-08-10
- Adding capability to execute ARM template after VM deployment, ```post_deployment_template``` and ```post_deployment_parameters``` added (@sebastiankasprzak)

## [0.14.3] - 2018-07-16
- Add `destroy_resource_group_contents` (default: false) property to allow contents of Azure Resource Group to be deleted rather than entire Resource Group, fixes [#90](https://github.com/test-kitchen/kitchen-azurerm/issues/85)

## [0.14.2] - 2018-07-09
- Add `destroy_explicit_resource_group` (default: false) property to allow reuse of specific Azure RG, fixes [#85](https://github.com/test-kitchen/kitchen-azurerm/issues/85)

## [0.14.1] - 2018-05-10
- Support for soverign clouds with latest Azure SDK for Ruby, fixes [#79](https://github.com/test-kitchen/kitchen-azurerm/issues/79)
- Raise error when subscription_id is not available, fixes [#74](https://github.com/test-kitchen/kitchen-azurerm/issues/74)

## [0.14.0] - 2018-04-10
- Update Azure SDK to latest version, upgrade to latest build tools

## [0.13.0] - 2017-12-26
- Switch to new Microsoft telemetry system [#73](https://github.com/test-kitchen/kitchen-azurerm/issues/73)

## [0.12.4] - 2017-11-17
- Adding `explicit_resource_group_name` property to driver configuration

## [0.12.3] - 2017-10-18
- Pinning to version 0.14.0 of Microsoft Azure SDK for Ruby, avoid namespace changes

## [0.12.2] - 2017-09-20
- Fix issue with location of data_disks in internal.erb [#67](https://github.com/test-kitchen/kitchen-azurerm/pull/67https://github.com/test-kitchen/kitchen-azurerm/pull/67) (@ehanlon)

## [0.12.1] - 2017-09-10
- Fix for undefined local variable when using pre_deployment_template [#65](https://github.com/test-kitchen/kitchen-azurerm/issue/65)

## [0.12.0] - 2017-09-01
- Additional managed disks can be specified in configuration and left unformatted or formatted on Windows(@stuartpreston)
- Added `azure_resource_group_prefix` and `azure_resource_group_suffix` parameter (@stuartpreston)

## [0.11.0] - 2017-07-20
- Pin to latest ARM SDK and constants [#59](https://github.com/test-kitchen/kitchen-azurerm/pull/59) (@smurawski)

## [0.10.0] - 2017-07-03
- Support for custom images (@elconas)
- Support for custom-data (Linux only) (@elconas)
- Support for custom OS sizes (@elconas)

## [0.9.1] - 2017-05-25
- Support for Managed Disks enabled by default (@stuartpreston)
- Add ```use_managed_disks``` driver_config parameter (@stuartpreston)

## [0.9.0] - 2017-04-28
- Support for AzureUSGovernment, AzureChina and AzureGermanCloud environments
- Add ```azure_environment``` driver_config parameter (@stuartpreston)

## [0.8.1] - 2017-02-28
- Adding provider identifier tag to all created resources (@stuartpreston)

## [0.8.0] - 2017-01-16
- [Unattend.xml used instead of Custom Script Extension to inject WinRM configuration/AKA support proxy server configurations](https://github.com/pendrica/kitchen-azurerm/pull/44) (@hbuckle)
- [Public IP addresses can now be used to connect even if the VM is connected to an existing subnet](https://github.com/pendrica/kitchen-azurerm/pull/42) (@vlesierse)
- [Resource Tags can now be applied to the created VMsPR](https://github.com/pendrica/kitchen-azurerm/pull/38)  (@liamkirwan)

## [0.7.2] - 2016-11-03
- Bug: When repeating a completed deployment, deployment would fail with a nil error on resource_name (@stuartpreston)

## [0.7.1] - 2016-09-17
- Bug: WinRM is not enabled where the platform name does not contain 'nano' (@stuartpreston)

## [0.7.0] - 2016-09-15
- Support creation of Windows Nano Server (ignoring automatic WinRM setting application) (@stuartpreston)

## [0.6.0] - 2016-08-22
- Supports latest autogenerated resources from Azure SDK for Ruby (0.5.0) (@stuartpreston)
- Removes unnecessary direct depdendencies on older ms_rest libraries (@stuartpreston)
- ssh_key will be used in preference to password if both are supplied (@stuartpreston) 

## [0.5.0] - 2016-08-07
- Adding support for internal (e.g. ExpressRoute/VPN) access to created VM (@stuartpreston)

## [0.4.1] - 2016-07-01
- Adding explicit depdendency on concurrent-ruby gem (@stuartpreston)

## [0.4.0] - 2016-06-26
- Adding capability to execute ARM template prior to VM deployment, ```pre_deployment_template``` and ```pre_deployment_parameters``` added (@stuartpreston)

## [0.3.6] - 2016-05-10
- Remove version pin on inifile gem dependency, compatible with newer ChefDK (@stuartpreston)

## [0.3.5] - 2016-03-21
- Remove transport name restriction on SSH key upload (allow rsync support) (@stuartpreston)
- Support SSH public keys with newlines as generated by ssh-keygen (@stuartpreston) 

## [0.3.4] - 2016-03-19
- Additional diagnostics when Azure Resource Group fails to create successfully (@stuartpreston)

## [0.3.3] - 2016-03-07
- Pinning ms_rest_azure dependencies to avoid errors when using latest ms_rest_azure library (@stuartpreston)

## [0.3.2] - 2016-03-07
- Breaking: Linux machines are now created using a temporary sshkey (~/.ssh/id_kitchen-azurerm) instead of password (@stuartpreston)
- Real error message shown if credentials are incorrect (@stuartpreston)

## [0.2.4] - 2016-01-26
- Support Premium Storage and Boot Diagnostics (@stuartpreston)
- If deployment fails, show the message from the failing operation (@stuartpreston)
- Updated Windows 2008 R2 example (@stuartpreston)

## [0.2.3] - 2015-12-17
- ```kitchen create``` can now be executed multiple times, updating an existing deployment if an error occurs (@smurawski)

## [0.2.2] - 2015-12-10
- Add an option for users to specify a custom script for WinRM (support Windows 2008 R2) (@andrewelizondo)
- Add azure_management_url parameter for Azure Stack support (@andrewelizondo)

## [0.2.1] - 2015-10-06
- Pointing to updated Azure SDK for Ruby, supports Linux

## [0.2.0] - 2015-09-29
- Logs should be sent to info, not stdout (@stuartpreston)
- Added WinRM support, enables WinRM and WinRM/s and configures server for Basic/Negotiate authentication (@stuartpreston) 
- Store server_id earlier so it can be retrieved if resources fail to create in Azure (@stuartpreston)

## [0.1.3] - 2015-09-23
- Support *nix by changing the driver name to lowercase 'azurerm', remove Chef references (@gadgetmg)

## [0.1.2] - 2015-09-23
- Initial release, supports provision of all public image types in Azure (@stuartpreston)
