# kitchen-azurerm Changelog

## [0.3.1] - 2016-02-29
- Breaking: Linux machines are now created using a temporary sshkey (~/.ssh/id_kitchen) instead of password (@stuartpreston)
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
