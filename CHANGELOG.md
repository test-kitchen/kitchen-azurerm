# kitchen-azurerm Changelog


This CHANGELOG is maintained by the [release-please-action](google-github-actions/release-please-action)

## Unreleased

## [2.1.2](https://github.com/test-kitchen/kitchen-azurerm/compare/v2.1.1...v2.1.2) (2026-08-23)


### Bug Fixes

* keep generated resource group names within Azure's limit ([#339](https://github.com/test-kitchen/kitchen-azurerm/issues/339)) ([9d55e74](https://github.com/test-kitchen/kitchen-azurerm/commit/9d55e74f0541d441500336a100db6f3c77958744))
* never send instance metadata requests through a proxy ([#338](https://github.com/test-kitchen/kitchen-azurerm/issues/338)) ([7cad34b](https://github.com/test-kitchen/kitchen-azurerm/commit/7cad34bd6e2ac733616f17de750b96b59c81a0ba))
* open the port the transport actually connects on ([#337](https://github.com/test-kitchen/kitchen-azurerm/issues/337)) ([52771e0](https://github.com/test-kitchen/kitchen-azurerm/commit/52771e026eeff66c611ca9c66875265a303c4385))
* stop discarding custom_data on Windows instances ([#336](https://github.com/test-kitchen/kitchen-azurerm/issues/336)) ([96046e7](https://github.com/test-kitchen/kitchen-azurerm/commit/96046e7e528daeca8ad44722b69c588742c7752e))

## [2.1.1](https://github.com/test-kitchen/kitchen-azurerm/compare/v2.1.0...v2.1.1) (2026-08-23)


### Bug Fixes

* accept a full resource id for subnet_id ([#330](https://github.com/test-kitchen/kitchen-azurerm/issues/330)) ([2ff0e75](https://github.com/test-kitchen/kitchen-azurerm/commit/2ff0e75875fd889558f3d517bc6dd57f2414fed8))
* fail the run when a deployment does not succeed ([#332](https://github.com/test-kitchen/kitchen-azurerm/issues/332)) ([292cdee](https://github.com/test-kitchen/kitchen-azurerm/commit/292cdee9be646ead84ea6cd23deec0a57bb60d24))
* keep a generated vm_name from ending on its prefix separator ([#333](https://github.com/test-kitchen/kitchen-azurerm/issues/333)) ([e0e880b](https://github.com/test-kitchen/kitchen-azurerm/commit/e0e880b1a755b405350137f3447c44409acee0a6))
* only warn about Azure credentials when something is actually wrong ([#329](https://github.com/test-kitchen/kitchen-azurerm/issues/329)) ([98bca8d](https://github.com/test-kitchen/kitchen-azurerm/commit/98bca8d855acefc8db3565e36a08e6dd537ffd1b))
* wait for an in-flight deployment instead of abandoning create ([#331](https://github.com/test-kitchen/kitchen-azurerm/issues/331)) ([eb690b3](https://github.com/test-kitchen/kitchen-azurerm/commit/eb690b3f0e199c843401069b7eb938fd885cd419))

## [2.1.0](https://github.com/test-kitchen/kitchen-azurerm/compare/v2.0.0...v2.1.0) (2026-08-23)

### Features

* add workload identity federation, and fix managed identity selection ([#325](https://github.com/test-kitchen/kitchen-azurerm/issues/325)) ([5e36643](https://github.com/test-kitchen/kitchen-azurerm/commit/5e36643e4bb5a2509d4a3d790e18202e87954643))

### Other Changes

* Remove dependabot config in favor of renovate ([#324](https://github.com/test-kitchen/kitchen-azurerm/pull/324)) ([0debe20](https://github.com/test-kitchen/kitchen-azurerm/commit/0debe20))

## [2.0.0](https://github.com/test-kitchen/kitchen-azurerm/compare/v1.14.0...v2.0.0) (2026-08-23)

### ⚠ BREAKING CHANGES

* AzureCredentials#azure_options is replaced by #arm_client and #token_provider, and the driver exposes #arm_client in place of #resource_management_client and #network_management_client. Rescuing MsRestAzure2::AzureOperationError must become Kitchen::Driver::Azure::OperationError.
* `use_managed_disks`, `image_url`, `os_type`, `existing_storage_account_blob_url` and `existing_storage_account_container` are retired. They still parse, so an existing kitchen.yml keeps loading, but the driver warns and ignores them. Defaults for `public_ip_sku`, `storage_account_type` and `boot_diagnostics_enabled` have changed.

### Features

* modernize for current Azure, replacing retired defaults and features ([#321](https://github.com/test-kitchen/kitchen-azurerm/issues/321)) ([8459942](https://github.com/test-kitchen/kitchen-azurerm/commit/8459942cd573f77a4141947328d98b9e8bdf523c))
* replace the retired Azure SDK with a direct ARM REST client ([#323](https://github.com/test-kitchen/kitchen-azurerm/issues/323)) ([23b8975](https://github.com/test-kitchen/kitchen-azurerm/commit/23b897563f35d27eb9d53f179ce63d7905ef1412))

### Other Changes

* Docs: document every driver option and split contributor docs ([#320](https://github.com/test-kitchen/kitchen-azurerm/pull/320)) ([d5d881d](https://github.com/test-kitchen/kitchen-azurerm/commit/d5d881d))

## [1.14.0](https://github.com/test-kitchen/kitchen-azurerm/compare/v1.13.6...v1.14.0) (2026-08-22)

### Features

* rewrite unit test suite and fix bugs it uncovered ([#317](https://github.com/test-kitchen/kitchen-azurerm/issues/317)) ([2461e02](https://github.com/test-kitchen/kitchen-azurerm/commit/2461e029da64dadcba90565d796f3ebd9b6a4ad8))

### Other Changes

* Fix typos ([#314](https://github.com/test-kitchen/kitchen-azurerm/pull/314)) ([5fbed05](https://github.com/test-kitchen/kitchen-azurerm/commit/5fbed05))
* Fix malformed YARD tags ([#315](https://github.com/test-kitchen/kitchen-azurerm/pull/315)) ([b8b41c5](https://github.com/test-kitchen/kitchen-azurerm/commit/b8b41c5))
* Require Ruby 3.1+ and modernize CI ([#316](https://github.com/test-kitchen/kitchen-azurerm/pull/316)) ([d46a1e7](https://github.com/test-kitchen/kitchen-azurerm/commit/d46a1e7))
* chore(deps): bump actions/checkout from 6 to 7 ([#313](https://github.com/test-kitchen/kitchen-azurerm/pull/313)) ([53572ac](https://github.com/test-kitchen/kitchen-azurerm/commit/53572ac))
* chore(deps): update actions/checkout action to v7 - autoclosed ([#312](https://github.com/test-kitchen/kitchen-azurerm/pull/312)) ([3be4782](https://github.com/test-kitchen/kitchen-azurerm/commit/3be4782))
* chore(deps): bump googleapis/release-please-action from 4 to 5 ([#311](https://github.com/test-kitchen/kitchen-azurerm/pull/311)) ([e1b664e](https://github.com/test-kitchen/kitchen-azurerm/commit/e1b664e))

## [1.13.6](https://github.com/test-kitchen/kitchen-azurerm/compare/v1.13.5...v1.13.6) (2026-02-19)

### Bug Fixes

* revert to required ruby 3.1 or greater ([#308](https://github.com/test-kitchen/kitchen-azurerm/issues/308)) ([1b2d9ae](https://github.com/test-kitchen/kitchen-azurerm/commit/1b2d9ae3c167ac5b4e7f3afed40086b85793e168))

## [1.13.5](https://github.com/test-kitchen/kitchen-azurerm/compare/v1.13.4...v1.13.5) (2026-01-23)

### Bug Fixes

* azure dep restrictions ([#306](https://github.com/test-kitchen/kitchen-azurerm/issues/306)) ([bd0eb54](https://github.com/test-kitchen/kitchen-azurerm/commit/bd0eb54507d30eae1e9481ca514bd3984259d594))

## [1.13.4](https://github.com/test-kitchen/kitchen-azurerm/compare/v1.13.3...v1.13.4) (2026-01-22)

### Bug Fixes

* bump tk dep to allow tk 4 ([#304](https://github.com/test-kitchen/kitchen-azurerm/issues/304)) ([718d030](https://github.com/test-kitchen/kitchen-azurerm/commit/718d03029d30f66dc6ff251c4c7663fa60b58bfb))

### Other Changes

* chore(deps): update azure_mgmt_resources2 requirement from ~&gt; 1.0.1, &gt;= 1.0.1 to &gt;= 1.0.1, &lt; 1.2.0 ([#300](https://github.com/test-kitchen/kitchen-azurerm/pull/300)) ([b415c44](https://github.com/test-kitchen/kitchen-azurerm/commit/b415c44))
* chore(deps): update azure_mgmt_network2 requirement from ~&gt; 1.0.1, &gt;= 1.0.1 to &gt;= 1.0.1, &lt; 1.2.0 ([#301](https://github.com/test-kitchen/kitchen-azurerm/pull/301)) ([179ea4c](https://github.com/test-kitchen/kitchen-azurerm/commit/179ea4c))
* chore(deps): update actions/checkout action to v6 - autoclosed ([#302](https://github.com/test-kitchen/kitchen-azurerm/pull/302)) ([06686b7](https://github.com/test-kitchen/kitchen-azurerm/commit/06686b7))

## [1.13.3](https://github.com/test-kitchen/kitchen-azurerm/compare/v1.13.2...v1.13.3) (2025-08-15)

### Bug Fixes

* Require Ruby 3.2 ([#294](https://github.com/test-kitchen/kitchen-azurerm/issues/294)) ([a21cdcf](https://github.com/test-kitchen/kitchen-azurerm/commit/a21cdcf373c503bc27c014eaf58090d721a14857))

### Other Changes

* Update cookstyle requirement from 7.32.8 to 8.2.1 ([#287](https://github.com/test-kitchen/kitchen-azurerm/pull/287)) ([c79ae38](https://github.com/test-kitchen/kitchen-azurerm/commit/c79ae38))
* Update badges + CI files ([#288](https://github.com/test-kitchen/kitchen-azurerm/pull/288)) ([e5611d4](https://github.com/test-kitchen/kitchen-azurerm/commit/e5611d4))
* chore(deps): update dependency cookstyle to v8.3.0 ([#289](https://github.com/test-kitchen/kitchen-azurerm/pull/289)) ([9405598](https://github.com/test-kitchen/kitchen-azurerm/commit/9405598))
* Bump actions/checkout from 4 to 5 ([#292](https://github.com/test-kitchen/kitchen-azurerm/pull/292)) ([f20140a](https://github.com/test-kitchen/kitchen-azurerm/commit/f20140a))
* Update cookstyle requirement from 8.3.0 to 8.4.0 ([#293](https://github.com/test-kitchen/kitchen-azurerm/pull/293)) ([42dd34b](https://github.com/test-kitchen/kitchen-azurerm/commit/42dd34b))

## [1.13.2](https://github.com/test-kitchen/kitchen-azurerm/compare/v1.13.1...v1.13.2) (2025-03-03)

### Bug Fixes

* Require Ruby 3.1 + lint with cookstyle ([#278](https://github.com/test-kitchen/kitchen-azurerm/issues/278)) ([b9bba1b](https://github.com/test-kitchen/kitchen-azurerm/commit/b9bba1b85c115272456f1d28926bba263aa6ef48))

### Other Changes

* chore(deps): update dependency rspec-its to v2 ([#277](https://github.com/test-kitchen/kitchen-azurerm/pull/277)) ([7540992](https://github.com/test-kitchen/kitchen-azurerm/commit/7540992))
* Update sshkey requirement from &gt;= 1.0.0, &lt; 3 to &gt;= 1.0.0, &lt; 4 ([#280](https://github.com/test-kitchen/kitchen-azurerm/pull/280)) ([c30dc08](https://github.com/test-kitchen/kitchen-azurerm/commit/c30dc08))

## [1.13.1](https://github.com/test-kitchen/kitchen-azurerm/compare/v1.13.0...v1.13.1) (2024-06-21)

### Bug Fixes

* release please configs ([#273](https://github.com/test-kitchen/kitchen-azurerm/issues/273)) ([8633756](https://github.com/test-kitchen/kitchen-azurerm/commit/8633756a593dc68087e1a6bb6905e88330bf1e54))

### Other Changes

* chore(deps): update dependency chefstyle to v2.2.3 ([#268](https://github.com/test-kitchen/kitchen-azurerm/pull/268)) ([c25295b](https://github.com/test-kitchen/kitchen-azurerm/commit/c25295b))

## [1.13.0](https://github.com/test-kitchen/kitchen-azurerm/compare/v1.12.0...v1.13.0) (2023-11-27)

### Features

* add configurable vm prefix ([#264](https://github.com/test-kitchen/kitchen-azurerm/issues/264)) ([4b09973](https://github.com/test-kitchen/kitchen-azurerm/commit/4b099731f1132739aaaf203cc417d254feb6862e))
* Update workflows and run Chefstyle over the code base ([#267](https://github.com/test-kitchen/kitchen-azurerm/issues/267)) ([869ee8c](https://github.com/test-kitchen/kitchen-azurerm/commit/869ee8c5af9cf9c77786090c6b3dc1733b50b90d))

### [1.12.0](https://github.com/test-kitchen/kitchen-azurerm/compare/v1.11.0...v1.11.1) (2023-05-08)

### Features

* Azure sdk namespace updates ([#258](https://github.com/test-kitchen/kitchen-azurerm/issues/258)) ([d3041f1](https://github.com/test-kitchen/kitchen-azurerm/commit/d3041f19dd68e4c3ea00631e9fa5d3a63ea92a76))

### [1.11.0](http3://g11hub.com/test-kitchen/kitchen-azurerm/compare/v1.10.6...v1.11.0) (2023-04-11)

### Features

* Replaced the deprecated azure SDK gems with separately maintained version twos. ([#238](https://github.com/test-kitchen/kitchen-azurerm/issues/238)) ([c6da371](https://github.com/test-kitchen/kitchen-azurerm/commit/c6da371443912b9d689e445f3f714d5cae6dd3a0))


### [1.10.7](https://github.com/test-kitchen/kitchen-azurerm/compare/v1.10.6...v1.10.7) (2022-04-20)


### Features

* Add release please releaser ([#238](https://github.com/test-kitchen/kitchen-azurerm/issues/238)) ([32cf4b8](https://github.com/test-kitchen/kitchen-azurerm/commit/32cf4b84a1a864d6f5272bd53b438d74bc141339))


### Bug Fixes

* Add PR template, release, publsh and unit workflows ([#242](https://github.com/test-kitchen/kitchen-azurerm/issues/242)) ([56b31cc](https://github.com/test-kitchen/kitchen-azurerm/commit/56b31ccc38bc53f997e35323ce5ef13e5ef61803))
* AZURERM_VERSION ([38b9475](https://github.com/test-kitchen/kitchen-azurerm/commit/38b9475da1ad421ea7ce927463c8a9e20761a56f))
* publish workflow ([#247](https://github.com/test-kitchen/kitchen-azurerm/issues/247)) ([a68d380](https://github.com/test-kitchen/kitchen-azurerm/commit/a68d380bd44e7e4de7abb177034ba4109880dcef))
* switch to reusable GitHub workflows ([#244](https://github.com/test-kitchen/kitchen-azurerm/issues/244)) ([0abd514](https://github.com/test-kitchen/kitchen-azurerm/commit/0abd514aeb8c588409422be0c71d10cff82a8ebe))

### [1.10.5](https://github.com/test-kitchen/kitchen-azurerm/compare/v1.10.4...v1.10.5) (2022-04-13)

### Features


### Bug Fixes


### [1.10.4](https://github.com/test-kitchen/kitchen-azurerm/compare/v1.10.3...v1.10.4) (2022-04-04)

### Bug Fixes


### [1.10.3](https://github.com/test-kitchen/kitchen-azurerm/compare/v1.10.2...v1.10.3) (2022-04-04)

### Features

## [1.12.0](https://github.com/test-kitchen/kitchen-azurerm/compare/v1.11.0...v1.12.0) (2023-05-09)

* Feat: Azure sdk namespace updates ([#258](https://github.com/test-kitchen/kitchen-azurerm/pull/258)) ([d3041f1](https://github.com/test-kitchen/kitchen-azurerm/commit/d3041f1))

## [1.11.0](https://github.com/test-kitchen/kitchen-azurerm/compare/v1.10.7...v1.11.0) (2023-04-11)

* fix indentation in readme.md ([#249](https://github.com/test-kitchen/kitchen-azurerm/pull/249)) ([2809d52](https://github.com/test-kitchen/kitchen-azurerm/commit/2809d52))
* Test workflow ([#250](https://github.com/test-kitchen/kitchen-azurerm/pull/250)) ([dccff8b](https://github.com/test-kitchen/kitchen-azurerm/commit/dccff8b))
* Updated the azure gems to the forked gems ([#254](https://github.com/test-kitchen/kitchen-azurerm/pull/254)) ([c6da371](https://github.com/test-kitchen/kitchen-azurerm/commit/c6da371))

* Fix: switch to reusable GitHub workflows ([#244](https://github.com/test-kitchen/kitchen-azurerm/pull/244)) ([0abd514](https://github.com/test-kitchen/kitchen-azurerm/commit/0abd514))
* Revert "chore(main): release 1.10.6" ([#246](https://github.com/test-kitchen/kitchen-azurerm/pull/246)) ([4cfac64](https://github.com/test-kitchen/kitchen-azurerm/commit/4cfac64))
* Fix: publish workflow ([#247](https://github.com/test-kitchen/kitchen-azurerm/pull/247)) ([a68d380](https://github.com/test-kitchen/kitchen-azurerm/commit/a68d380))
* Allow multiple blank lines ([ebd96eb](https://github.com/test-kitchen/kitchen-azurerm/commit/ebd96eb))

## [1.10.5](https://github.com/test-kitchen/kitchen-azurerm/compare/v1.10.3...v1.10.5) (2022-04-13)

* fix: AZURERM_VERSION ([38b9475](https://github.com/test-kitchen/kitchen-azurerm/commit/38b9475))
* chore: Add "type of change" guidance to Pull Request template Also fixes the markdown on templates ([236f61d](https://github.com/test-kitchen/kitchen-azurerm/commit/236f61d))
* Fix please-release version file param ([1b2b5ce](https://github.com/test-kitchen/kitchen-azurerm/commit/1b2b5ce))
* Fix version file to match currently published version ([4ff19a2](https://github.com/test-kitchen/kitchen-azurerm/commit/4ff19a2))
* Add PR template, release, publish and unit workflows ([#242](https://github.com/test-kitchen/kitchen-azurerm/pull/242)) ([56b31cc](https://github.com/test-kitchen/kitchen-azurerm/commit/56b31cc))

* FEAT: Add release please releaser ([#238](https://github.com/test-kitchen/kitchen-azurerm/pull/238)) ([32cf4b8](https://github.com/test-kitchen/kitchen-azurerm/commit/32cf4b8))

## [1.10.2] - 2022-04-04

* move warning about missing credentials into debug by @jasonwbarnett in <https://github.com/test-kitchen/kitchen-azurerm/pull/235>
* Deprecation/positional arguments by @damacus in <https://github.com/test-kitchen/kitchen-azurerm/pull/236>
* Publish gem to GitHub by @damacus in <https://github.com/test-kitchen/kitchen-azurerm/pull/237>

* prep for v1.10.2 release ([8e59c53](https://github.com/test-kitchen/kitchen-azurerm/commit/8e59c53))

## [1.10.1] - 2022-03-10

* Rollback #228 by [@jasonwbarnett](https://github.com/jasonwbarnett) in #234

* Prep for 1.10.1 release ([136f819](https://github.com/test-kitchen/kitchen-azurerm/commit/136f819))

## [1.10.0] - 2022-02.28

* Add a new `store_deployment_credentials_in_state` configuration option to skip storing sensitive data in the state [@jasonwbarnett](https://github.com/jasonwbarnett)

* include ruby 3.1 in ci ([#229](https://github.com/test-kitchen/kitchen-azurerm/pull/229)) ([11629b6](https://github.com/test-kitchen/kitchen-azurerm/commit/11629b6))
* Update chefstyle requirement from 2.2.1 to 2.2.2 ([#230](https://github.com/test-kitchen/kitchen-azurerm/pull/230)) ([3217e07](https://github.com/test-kitchen/kitchen-azurerm/commit/3217e07))
* only store deployment credentials if specified ([#231](https://github.com/test-kitchen/kitchen-azurerm/pull/231)) ([d018cc4](https://github.com/test-kitchen/kitchen-azurerm/commit/d018cc4))

## [1.9.0] - 2022-02.04

* Support setting the VM availability zone with a new `zone` config. [@pkazi](https://github.com/pkazi)
* Drop support for EOL Ruby 2.5

* Update chefstyle requirement from 2.0.7 to 2.0.9 ([#215](https://github.com/test-kitchen/kitchen-azurerm/pull/215)) ([d90b42d](https://github.com/test-kitchen/kitchen-azurerm/commit/d90b42d))
* Update README.md ([888649b](https://github.com/test-kitchen/kitchen-azurerm/commit/888649b))
* Update chefstyle requirement from 2.0.9 to 2.1.0 ([#216](https://github.com/test-kitchen/kitchen-azurerm/pull/216)) ([70764b4](https://github.com/test-kitchen/kitchen-azurerm/commit/70764b4))
* Update chefstyle requirement from 2.1.0 to 2.1.3 ([#220](https://github.com/test-kitchen/kitchen-azurerm/pull/220)) ([ea866a8](https://github.com/test-kitchen/kitchen-azurerm/commit/ea866a8))
* Update chefstyle requirement from 2.1.3 to 2.2.0 ([#225](https://github.com/test-kitchen/kitchen-azurerm/pull/225)) ([0cb9d64](https://github.com/test-kitchen/kitchen-azurerm/commit/0cb9d64))
* update readme ([#223](https://github.com/test-kitchen/kitchen-azurerm/pull/223)) ([08b52f7](https://github.com/test-kitchen/kitchen-azurerm/commit/08b52f7))
* Update chefstyle requirement from 2.2.0 to 2.2.1 ([#226](https://github.com/test-kitchen/kitchen-azurerm/pull/226)) ([ad38efd](https://github.com/test-kitchen/kitchen-azurerm/commit/ad38efd))
* Use chefstyle linting ([#227](https://github.com/test-kitchen/kitchen-azurerm/pull/227)) ([509424c](https://github.com/test-kitchen/kitchen-azurerm/commit/509424c))
* Support vm availability zone ([#228](https://github.com/test-kitchen/kitchen-azurerm/pull/228)) ([477b739](https://github.com/test-kitchen/kitchen-azurerm/commit/477b739))
* Drop Ruby 2.5 support and release 1.9 ([6d7d1f9](https://github.com/test-kitchen/kitchen-azurerm/commit/6d7d1f9))

## [1.8.0] - 2021-08.27

* Increase max OS volume size from 1023 to 2048 [@jasonwbarnett](https://github.com/jasonwbarnett)

* Update chefstyle requirement from 2.0.5 to 2.0.7 ([#209](https://github.com/test-kitchen/kitchen-azurerm/pull/209)) ([546a565](https://github.com/test-kitchen/kitchen-azurerm/commit/546a565))
* Don't ship the readme with the gemfile ([d8a4842](https://github.com/test-kitchen/kitchen-azurerm/commit/d8a4842))

## [1.7.0] - 2021-07.02

* Support Test Kitchen 3.0

* Update chefstyle requirement from 1.7.2 to 1.7.5 ([#201](https://github.com/test-kitchen/kitchen-azurerm/pull/201)) ([c76a481](https://github.com/test-kitchen/kitchen-azurerm/commit/c76a481))
* Upgrade to GitHub-native Dependabot ([#202](https://github.com/test-kitchen/kitchen-azurerm/pull/202)) ([8be8662](https://github.com/test-kitchen/kitchen-azurerm/commit/8be8662))
* Update chefstyle requirement from 1.7.5 to 2.0.4 ([#204](https://github.com/test-kitchen/kitchen-azurerm/pull/204)) ([0a2ac7a](https://github.com/test-kitchen/kitchen-azurerm/commit/0a2ac7a))
* Update chefstyle requirement from 2.0.4 to 2.0.5 ([#205](https://github.com/test-kitchen/kitchen-azurerm/pull/205)) ([a151e35](https://github.com/test-kitchen/kitchen-azurerm/commit/a151e35))

## [1.6.0] - 2021-03.19

* The default VM name has been changed from `vm` to `tk-RANDOMVALUE` to avoid name conflicts and make it easier to find systems in the portal [@jasonwbarnett](https://github.com/jasonwbarnett)

* Update chefstyle requirement from 1.7.1 to 1.7.2 ([#198](https://github.com/test-kitchen/kitchen-azurerm/pull/198)) ([39c4067](https://github.com/test-kitchen/kitchen-azurerm/commit/39c4067))
* Default to randomly generated vm name instead of just 'vm' ([#199](https://github.com/test-kitchen/kitchen-azurerm/pull/199)) ([7db6d6d](https://github.com/test-kitchen/kitchen-azurerm/commit/7db6d6d))

## [1.5.3] - 2021-02-24

* Additional fixes for `public_ip_sku` to update the default behavior to match pre-1.5.0 behavior [@collinmcneese](https://github.com/collinmcneese)

* public_ip_sku fixes for default/existing behavior ([#197](https://github.com/test-kitchen/kitchen-azurerm/pull/197)) ([2f83c3b](https://github.com/test-kitchen/kitchen-azurerm/commit/2f83c3b))

## [1.5.2] - 2021-02-18

* Fix using `storage_account_type` config option to set data disk storage types - [@reasland](https://github.com/reasland)

* Fixing data disk storage type ([#195](https://github.com/test-kitchen/kitchen-azurerm/pull/195)) ([e5c3604](https://github.com/test-kitchen/kitchen-azurerm/commit/e5c3604))

## [1.5.1] - 2021-02-18

* Populate publicIPSKU in template only if provided by kitchen config [@collinmcneese](https://github.com/collinmcneese)

* Update CHANGELOG.md ([461c936](https://github.com/test-kitchen/kitchen-azurerm/commit/461c936))
* Update chefstyle requirement from 1.6.2 to 1.7.1 ([#191](https://github.com/test-kitchen/kitchen-azurerm/pull/191)) ([c5acff1](https://github.com/test-kitchen/kitchen-azurerm/commit/c5acff1))
* Populates publicIPSKU in template only if provided by kitchen config ([#194](https://github.com/test-kitchen/kitchen-azurerm/pull/194)) ([a1d46dc](https://github.com/test-kitchen/kitchen-azurerm/commit/a1d46dc))

## [1.5.0] - 2021-02-11

* Add support for setting the public IP SkU with a new `public_ip_sku` configuration option within the `subnet` config. Thanks [@simonjefford](https://github.com/simonjefford)

* Update chefstyle requirement from = 1.4.2 to = 1.4.3 ([#174](https://github.com/test-kitchen/kitchen-azurerm/pull/174)) ([b2b8099](https://github.com/test-kitchen/kitchen-azurerm/commit/b2b8099))
* Update chefstyle requirement from = 1.4.3 to = 1.4.4 ([#175](https://github.com/test-kitchen/kitchen-azurerm/pull/175)) ([07cb2b6](https://github.com/test-kitchen/kitchen-azurerm/commit/07cb2b6))
* Update chefstyle requirement from = 1.4.4 to = 1.4.5 ([#176](https://github.com/test-kitchen/kitchen-azurerm/pull/176)) ([e60b9c2](https://github.com/test-kitchen/kitchen-azurerm/commit/e60b9c2))
* Update chefstyle requirement from = 1.4.5 to = 1.5.0 ([#177](https://github.com/test-kitchen/kitchen-azurerm/pull/177)) ([bd02f8c](https://github.com/test-kitchen/kitchen-azurerm/commit/bd02f8c))
* Update chefstyle requirement from = 1.5.0 to = 1.5.1 ([#178](https://github.com/test-kitchen/kitchen-azurerm/pull/178)) ([69b21ed](https://github.com/test-kitchen/kitchen-azurerm/commit/69b21ed))
* Update chefstyle requirement from = 1.5.1 to = 1.5.2 ([#179](https://github.com/test-kitchen/kitchen-azurerm/pull/179)) ([81bbfd6](https://github.com/test-kitchen/kitchen-azurerm/commit/81bbfd6))
* Update chefstyle requirement from = 1.5.2 to = 1.5.8 ([#182](https://github.com/test-kitchen/kitchen-azurerm/pull/182)) ([cfc7c14](https://github.com/test-kitchen/kitchen-azurerm/commit/cfc7c14))
* Update chefstyle requirement from = 1.5.8 to = 1.5.9 ([#183](https://github.com/test-kitchen/kitchen-azurerm/pull/183)) ([abc5750](https://github.com/test-kitchen/kitchen-azurerm/commit/abc5750))
* Update Github Actions to cache gems + test Ruby 3 ([#184](https://github.com/test-kitchen/kitchen-azurerm/pull/184)) ([56de658](https://github.com/test-kitchen/kitchen-azurerm/commit/56de658))
* Misc testing updates + Require Ruby 2.5+ ([#186](https://github.com/test-kitchen/kitchen-azurerm/pull/186)) ([5cd97d8](https://github.com/test-kitchen/kitchen-azurerm/commit/5cd97d8))
* Fix minor gemfile typo ([1d12c7d](https://github.com/test-kitchen/kitchen-azurerm/commit/1d12c7d))
* Update chefstyle requirement from =1.5.9 to 1.6.1 ([#189](https://github.com/test-kitchen/kitchen-azurerm/pull/189)) ([dcc12bb](https://github.com/test-kitchen/kitchen-azurerm/commit/dcc12bb))
* Update chefstyle requirement from 1.6.1 to 1.6.2 ([#190](https://github.com/test-kitchen/kitchen-azurerm/pull/190)) ([d6ff72d](https://github.com/test-kitchen/kitchen-azurerm/commit/d6ff72d))

## [1.4.0] - 2020-09-29

* Resolved an issue where VM state was persisted before VM is provisioned
* Added linting and unit testing for each pull request via GitHub Actions
* Resolved issues where resource groups where not being destroyed
* Set 'az login' the default authentication mechanism
* Added new `use_fqdn_hostname` config option to set Test Kitchen to communicate using the instance's FQDN
* Resolved an issue where username was not being added to Test Kitchen's state

* updating rakefile to include rspec tests, fixed failing rspec test ([#162](https://github.com/test-kitchen/kitchen-azurerm/pull/162)) ([a989fbc](https://github.com/test-kitchen/kitchen-azurerm/commit/a989fbc))
* Update chefstyle requirement from = 1.2.1 to = 1.4.0 ([#163](https://github.com/test-kitchen/kitchen-azurerm/pull/163)) ([9e04af7](https://github.com/test-kitchen/kitchen-azurerm/commit/9e04af7))
* Apply patch from @zanecodes. Thank you. ([#155](https://github.com/test-kitchen/kitchen-azurerm/pull/155)) ([b8cd679](https://github.com/test-kitchen/kitchen-azurerm/commit/b8cd679))
* Fixes Issue #153. Fixed state bugs. Cleaned up code for Issue #149. ([#154](https://github.com/test-kitchen/kitchen-azurerm/pull/154)) ([a0571c1](https://github.com/test-kitchen/kitchen-azurerm/commit/a0571c1))
* Make 'az login' the default authentication mechanism ([#160](https://github.com/test-kitchen/kitchen-azurerm/pull/160)) ([1890441](https://github.com/test-kitchen/kitchen-azurerm/commit/1890441))
* Fix requires for code to function. Thank you @ElementalDev. Fixes #165. ([#166](https://github.com/test-kitchen/kitchen-azurerm/pull/166)) ([d105ee4](https://github.com/test-kitchen/kitchen-azurerm/commit/d105ee4))
* autoload ms_rest and ms_rest_azure ([#169](https://github.com/test-kitchen/kitchen-azurerm/pull/169)) ([a93b64e](https://github.com/test-kitchen/kitchen-azurerm/commit/a93b64e))
* Adding FQDN communication option ([#168](https://github.com/test-kitchen/kitchen-azurerm/pull/168)) ([f22020b](https://github.com/test-kitchen/kitchen-azurerm/commit/f22020b))
* Added tests for username and fixes username issue ([#171](https://github.com/test-kitchen/kitchen-azurerm/pull/171)) ([0f6c355](https://github.com/test-kitchen/kitchen-azurerm/commit/0f6c355))
* Update chefstyle requirement from = 1.4.0 to = 1.4.2 ([#172](https://github.com/test-kitchen/kitchen-azurerm/pull/172)) ([f5e5d8a](https://github.com/test-kitchen/kitchen-azurerm/commit/f5e5d8a))

## [1.3.0] - 2020-09-09

* Improve performance by loading dependencies only when we need them (@mwrock)

* autoload expensive gems ([#158](https://github.com/test-kitchen/kitchen-azurerm/pull/158)) ([b57e727](https://github.com/test-kitchen/kitchen-azurerm/commit/b57e727))

## [1.2.0] - 2020-08-20

* Add support for deletion or preservation of resource group tags with a new `destroy_explicit_resource_group_tags` config that defaults to `true` (@StylusEaterChef)
* Optimize our requires to make load the gem a tiny bit faster (@tas50)

* Pin chefstyle so dependabot can bump it ([2d2bc1d](https://github.com/test-kitchen/kitchen-azurerm/commit/2d2bc1d))
* Update ignore and add some docs to the code as requested by @tas50. ([#151](https://github.com/test-kitchen/kitchen-azurerm/pull/151)) ([3310d80](https://github.com/test-kitchen/kitchen-azurerm/commit/3310d80))

## [1.1.0] - 2020-08-19

* Update error messages to mention `kitchen.yml` not `.kitchen.yml` (@tas50)
* Update the default password we generate to be 25 characters to avoid failures on newer Windows releases (@StylusEaterChef)
* Remove `simplecov` development dependency (@tas50)
* Updated Readme to be more explicit about credentials settings (@Vasu1105)
* Remove tags in readme that could possibly confuse users (@jasonwbarnett)
* Fix Azure SP documentation link and give an example on how to setup (@StylusEaterChef)
* Update installation instructions not to mention ChefDK (@tas50)

* To avoid confusion added more detail description ([#138](https://github.com/test-kitchen/kitchen-azurerm/pull/138)) ([a05deb7](https://github.com/test-kitchen/kitchen-azurerm/commit/a05deb7))
* Remove tags that could possibly confuse users ([#141](https://github.com/test-kitchen/kitchen-azurerm/pull/141)) ([0cf15ea](https://github.com/test-kitchen/kitchen-azurerm/commit/0cf15ea))
* Fix Azure SP documentation link and give an example on how to setup. Thanks JM. ([#143](https://github.com/test-kitchen/kitchen-azurerm/pull/143)) ([ede331e](https://github.com/test-kitchen/kitchen-azurerm/commit/ede331e))
* Minor command update for creating the Azure SP. ([#144](https://github.com/test-kitchen/kitchen-azurerm/pull/144)) ([542b088](https://github.com/test-kitchen/kitchen-azurerm/commit/542b088))
* Proposed solution for issue #142. ([#146](https://github.com/test-kitchen/kitchen-azurerm/pull/146)) ([255fe25](https://github.com/test-kitchen/kitchen-azurerm/commit/255fe25))
* Update error message to mention kitchen.yml not .kitchen.yml ([8b78f17](https://github.com/test-kitchen/kitchen-azurerm/commit/8b78f17))
* Remove Simplecov dev dep ([e416832](https://github.com/test-kitchen/kitchen-azurerm/commit/e416832))

## [1.0.0] - 2020-05-06

* Add more specs and refactor Credentials [PR #135](https://github.com/test-kitchen/kitchen-azurerm/pull/135) (@jasonwbarnett)
* Fix using `user_assigned_identities` config [PR #136](https://github.com/test-kitchen/kitchen-azurerm/pull/136) (@zanecodes)

## [0.17.0] - 2020-04-23

* Add MSI Support [PR #134](https://github.com/test-kitchen/kitchen-azurerm/pull/134) (@jasonwbarnett)

* Remove the bundler dev dep ([#133](https://github.com/test-kitchen/kitchen-azurerm/pull/133)) ([e3e4f8d](https://github.com/test-kitchen/kitchen-azurerm/commit/e3e4f8d))
* Update CHANGELOG.md ([9b04c9f](https://github.com/test-kitchen/kitchen-azurerm/commit/9b04c9f))

## [0.16.0] - 2020-04-22

* Add support for marketplace plan information [PR #132](https://github.com/test-kitchen/kitchen-azurerm/pull/132) (@jasonwbarnett)

* Migrate testing to github actions ([#130](https://github.com/test-kitchen/kitchen-azurerm/pull/130)) ([3841f34](https://github.com/test-kitchen/kitchen-azurerm/commit/3841f34))
* Add badge and fix typos in the readme ([860d83b](https://github.com/test-kitchen/kitchen-azurerm/commit/860d83b))
* Add missing items to the changelog ([172ee2d](https://github.com/test-kitchen/kitchen-azurerm/commit/172ee2d))
* More changelog updates ([77b7b4b](https://github.com/test-kitchen/kitchen-azurerm/commit/77b7b4b))
* Updating licensing and authorship info ([7b4106d](https://github.com/test-kitchen/kitchen-azurerm/commit/7b4106d))

## [0.15.2] - 2020-03-23

* Fix require_relative for azure_credentials [PR #129](https://github.com/test-kitchen/kitchen-azurerm/pull/129) (@jasonwbarnett)
* Refactor Kitchen::Driver::Credentials class [PR #128](https://github.com/test-kitchen/kitchen-azurerm/pull/128) (@jasonwbarnett)
* Default password is now generated rather than hard-coded [#124](https://github.com/test-kitchen/kitchen-azurerm/pull/124) (@stuartpreston)
* Add retry logic when checking deployment state [#125](https://github.com/test-kitchen/kitchen-azurerm/pull/125x) (@albertvaka)
* Only add password to deployment template if ssh_key is not set [#126](https://github.com/test-kitchen/kitchen-azurerm/pull/126) (@KSerrania)

## [0.15.1] - 2020-01-14

* Use require_relative instead of require [PR #123](https://github.com/test-kitchen/kitchen-azurerm/pull/123) (@tas50)

* Add rake gemtasks ([8884d2d](https://github.com/test-kitchen/kitchen-azurerm/commit/8884d2d))

## [0.15.0] - 2019-11-29

* Enable WinRM HTTP listener by default [PR #121](https://github.com/test-kitchen/kitchen-azurerm/pull/121) (@sean-nixon)
* Default subscription_id to AZURE_SUBSCRIPTION_ID environment variable if not supplied[df79c787fa299cb6eff4a2fd7807fe28ce2bc725](https://github.com/test-kitchen/kitchen-azurerm/commit/df79c787fa299cb6eff4a2fd7807fe28ce2bc725) (@stuartpreston)
* Allow nic name to be passed in as a parameter [PR #112](https://github.com/test-kitchen/kitchen-azurerm/pull/112) (@libertymutual)
* Support for creating VM with Azure KeyVault certificate [PR #120](https://github.com/test-kitchen/kitchen-azurerm/pull/120) (@javgallegos)

* Updating to latest chefstyle ([f691f10](https://github.com/test-kitchen/kitchen-azurerm/commit/f691f10))
* Update sshkey requirement from &gt;= 1.0.0, ~&gt; 1 to &gt;= 1.0.0, &lt; 3 ([#114](https://github.com/test-kitchen/kitchen-azurerm/pull/114)) ([bd2d731](https://github.com/test-kitchen/kitchen-azurerm/commit/bd2d731))
* Fixing style, adding info about WinRM over HTTP ([ee948de](https://github.com/test-kitchen/kitchen-azurerm/commit/ee948de))
* Fix style issue ([382b8ea](https://github.com/test-kitchen/kitchen-azurerm/commit/382b8ea))
* Make secrets non optional in the template ([12ef60c](https://github.com/test-kitchen/kitchen-azurerm/commit/12ef60c))

## [0.14.9] - 2019-07-30

* Support [Ephemeral OS Disk](https://azure.microsoft.com/en-us/updates/azure-ephemeral-os-disk-now-generally-available/),  (@stuartpreston)

* Unpin the bundler dev dep ([#107](https://github.com/test-kitchen/kitchen-azurerm/pull/107)) ([8c8b60c](https://github.com/test-kitchen/kitchen-azurerm/commit/8c8b60c))
* Add ssh_public_key for separate public key location. ([#108](https://github.com/test-kitchen/kitchen-azurerm/pull/108)) ([9d71096](https://github.com/test-kitchen/kitchen-azurerm/commit/9d71096))
* Adding ephemeral OS disk support ([98956f5](https://github.com/test-kitchen/kitchen-azurerm/commit/98956f5))
* Merge branch 'master' of https://github.com/test-kitchen/kitchen-azurerm ([f810c4f](https://github.com/test-kitchen/kitchen-azurerm/commit/f810c4f))

## [0.14.8] - 2018-12-30

* Support [Azure Managed Identities](https://github.com/test-kitchen/kitchen-azurerm#kitchenyml-example-10---enabling-managed-service-identities), [PR #106](https://github.com/test-kitchen/kitchen-azurerm/pull/105) (@zanecodes)
* Apply vm_tags to all resources in resource group [PR #105](https://github.com/test-kitchen/kitchen-azurerm/pull/105) (@josh-hetland)

## [0.14.7] - 2018-12-18

* Updating Azure SDK dependencies, [PR #104](https://github.com/test-kitchen/kitchen-azurerm/pull/104) (@stuartpreston)

## [0.14.6] - 2018-12-11

* Support tags at Resource Group level, [PR #102](https://github.com/test-kitchen/kitchen-azurerm/pull/102) (@pgryzan-chefio)
* Pin azure_mgmt_resources to 0.18.0 to avoid issue retrieving IP address of node during kitchen create [#99](https://github.com/test-kitchen/kitchen-azurerm/issues/99) (@stuartpreston)

* Switch to Chefstyle and don't ship the changelog ([#100](https://github.com/test-kitchen/kitchen-azurerm/pull/100)) ([ec6397c](https://github.com/test-kitchen/kitchen-azurerm/commit/ec6397c))
* Merge branch 'chef-cft-rg-tagging' ([2819035](https://github.com/test-kitchen/kitchen-azurerm/commit/2819035))
* Revert gemspec ([07684d2](https://github.com/test-kitchen/kitchen-azurerm/commit/07684d2))

## [0.14.5] - 2018-09-30

* Support Shared Image Gallery (preview Azure feature) (@zanecodes)

* Update virtualMachines API version ([#96](https://github.com/test-kitchen/kitchen-azurerm/pull/96)) ([21936d1](https://github.com/test-kitchen/kitchen-azurerm/commit/21936d1))
* Quiet Rubocop until 0.58.1 hits default Travis images ([c1e3607](https://github.com/test-kitchen/kitchen-azurerm/commit/c1e3607))

## [0.14.4] - 2018-08-10

* Adding capability to execute ARM template after VM deployment, ```post_deployment_template``` and ```post_deployment_parameters``` added (@sebastiankasprzak)

* Feature/post deployment template ([#95](https://github.com/test-kitchen/kitchen-azurerm/pull/95)) ([897455b](https://github.com/test-kitchen/kitchen-azurerm/commit/897455b))

## [0.14.3] - 2018-07-16

* Add `destroy_resource_group_contents` (default: false) property to allow contents of Azure Resource Group to be deleted rather than entire Resource Group, fixes [#90](https://github.com/test-kitchen/kitchen-azurerm/issues/85)

* Add destroy_resource_group_contents configuration option ([#92](https://github.com/test-kitchen/kitchen-azurerm/pull/92)) ([528599f](https://github.com/test-kitchen/kitchen-azurerm/commit/528599f))

## [0.14.2] - 2018-07-09

* Add `destroy_explicit_resource_group` (default: false) property to allow reuse of specific Azure RG, fixes [#85](https://github.com/test-kitchen/kitchen-azurerm/issues/85)

* Put the badges in the usual spot ([#86](https://github.com/test-kitchen/kitchen-azurerm/pull/86)) ([f8138c1](https://github.com/test-kitchen/kitchen-azurerm/commit/f8138c1))
* Get the build green again ([#87](https://github.com/test-kitchen/kitchen-azurerm/pull/87)) ([9d7e7cf](https://github.com/test-kitchen/kitchen-azurerm/commit/9d7e7cf))
* Adding destroy_explicit_resource_group option ([#88](https://github.com/test-kitchen/kitchen-azurerm/pull/88)) ([26a440f](https://github.com/test-kitchen/kitchen-azurerm/commit/26a440f))

## [0.14.1] - 2018-05-10

* Support for soverign clouds with latest Azure SDK for Ruby, fixes [#79](https://github.com/test-kitchen/kitchen-azurerm/issues/79)
* Raise error when subscription_id is not available, fixes [#74](https://github.com/test-kitchen/kitchen-azurerm/issues/74)

* Updating Ruby version for Travis ([b573186](https://github.com/test-kitchen/kitchen-azurerm/commit/b573186))
* Modernizing examples in the readme (driver_config -&gt; driver) ([55b768d](https://github.com/test-kitchen/kitchen-azurerm/commit/55b768d))
* Adding addtional options to support sovereign environments ([#82](https://github.com/test-kitchen/kitchen-azurerm/pull/82)) ([eb6e1a5](https://github.com/test-kitchen/kitchen-azurerm/commit/eb6e1a5))
* Raise when subscription_id is not available ([#83](https://github.com/test-kitchen/kitchen-azurerm/pull/83)) ([88dd284](https://github.com/test-kitchen/kitchen-azurerm/commit/88dd284))
* v0.14.1 ([0b2fa2c](https://github.com/test-kitchen/kitchen-azurerm/commit/0b2fa2c))

## [0.14.0] - 2018-04-10

* Update Azure SDK to latest version, upgrade to latest build tools

* Upgrading to Azure SDK 0.15 for compatibility for other tooling ([#78](https://github.com/test-kitchen/kitchen-azurerm/pull/78)) ([8587f25](https://github.com/test-kitchen/kitchen-azurerm/commit/8587f25))

## [0.13.0] - 2017-12-26

* Switch to new Microsoft telemetry system [#73](https://github.com/test-kitchen/kitchen-azurerm/issues/73)

* Updating telemetry aspects of ARM templates ([49cf46a](https://github.com/test-kitchen/kitchen-azurerm/commit/49cf46a))
* Merge branch 'release0.13' ([41c7496](https://github.com/test-kitchen/kitchen-azurerm/commit/41c7496))

## [0.12.4] - 2017-11-17

* Adding `explicit_resource_group_name` property to driver configuration

* Adding explicit_resource_group_name parameter ([4496806](https://github.com/test-kitchen/kitchen-azurerm/commit/4496806))
* Fixing unused variable linting issue ([366b7f4](https://github.com/test-kitchen/kitchen-azurerm/commit/366b7f4))

## [0.12.3] - 2017-10-18

* Pinning to version 0.14.0 of Microsoft Azure SDK for Ruby, avoid namespace changes

## [0.12.2] - 2017-09-20

* Fix issue with location of data_disks in internal.erb [#67](https://github.com/test-kitchen/kitchen-azurerm/pull/67https://github.com/test-kitchen/kitchen-azurerm/pull/67) (@ehanlon)

## [0.12.1] - 2017-09-10

* Fix for undefined local variable when using pre_deployment_template [#65](https://github.com/test-kitchen/kitchen-azurerm/issue/65)

* Removing additional post-deployment template added in error ([e31fa45](https://github.com/test-kitchen/kitchen-azurerm/commit/e31fa45))

## [0.12.0] - 2017-09-01

* Additional managed disks can be specified in configuration and left unformatted or formatted on Windows(@stuartpreston)
* Added `azure_resource_group_prefix` and `azure_resource_group_suffix` parameter (@stuartpreston)

* Adding data_disk functionality ([03a8ecc](https://github.com/test-kitchen/kitchen-azurerm/commit/03a8ecc))
* Updating readme for data_disks ([4f518e1](https://github.com/test-kitchen/kitchen-azurerm/commit/4f518e1))

## [0.11.0] - 2017-07-20

* Pin to latest ARM SDK and constants [#59](https://github.com/test-kitchen/kitchen-azurerm/pull/59) (@smurawski)

## [0.10.0] - 2017-07-03

* Support for custom images (@elconas)
* Support for custom-data (Linux only) (@elconas)
* Support for custom OS sizes (@elconas)

* Custom images, custom-data (Linux) and os size support ([13c57f5](https://github.com/test-kitchen/kitchen-azurerm/commit/13c57f5))
* Fixed issue with empty custom_data ([#57](https://github.com/test-kitchen/kitchen-azurerm/pull/57)) ([d95e52b](https://github.com/test-kitchen/kitchen-azurerm/commit/d95e52b))

## [0.9.1] - 2017-05-25

* Support for Managed Disks enabled by default (@stuartpreston)
* Add ```use_managed_disks``` driver_config parameter (@stuartpreston)

* Adding managed disk support ([99aafab](https://github.com/test-kitchen/kitchen-azurerm/commit/99aafab))
* Adding managed disks documentation ([3d594d9](https://github.com/test-kitchen/kitchen-azurerm/commit/3d594d9))

## [0.9.0] - 2017-04-28

* Support for AzureUSGovernment, AzureChina and AzureGermanCloud environments
* Add ```azure_environment``` driver_config parameter (@stuartpreston)

* Adding support for AzureUSGovernment cloud and sovereign clouds ([c498440](https://github.com/test-kitchen/kitchen-azurerm/commit/c498440))

## [0.8.1] - 2017-02-28

* Adding provider identifier tag to all created resources (@stuartpreston)

* Updating Ruby to later version in Travis ([d91dfaa](https://github.com/test-kitchen/kitchen-azurerm/commit/d91dfaa))
* Resolve Rubocop issues on Windows with latest ChefDK ([25cee68](https://github.com/test-kitchen/kitchen-azurerm/commit/25cee68))
* Changing org from Pendrica to Test-Kitchen ([#46](https://github.com/test-kitchen/kitchen-azurerm/pull/46)) ([1f6465d](https://github.com/test-kitchen/kitchen-azurerm/commit/1f6465d))
* Adding MS-specific tagging to ARM templates. ([d659e43](https://github.com/test-kitchen/kitchen-azurerm/commit/d659e43))

## [0.8.0] - 2017-01-16

* [Unattend.xml used instead of Custom Script Extension to inject WinRM configuration/AKA support proxy server configurations](https://github.com/pendrica/kitchen-azurerm/pull/44) (@hbuckle)
* [Public IP addresses can now be used to connect even if the VM is connected to an existing subnet](https://github.com/pendrica/kitchen-azurerm/pull/42) (@vlesierse)
* [Resource Tags can now be applied to the created VMsPR](https://github.com/pendrica/kitchen-azurerm/pull/38)  (@liamkirwan)

* Fixing rubocop errors ([ba760c8](https://github.com/test-kitchen/kitchen-azurerm/commit/ba760c8))
* Update driver to include tag parameter ([#38](https://github.com/test-kitchen/kitchen-azurerm/pull/38)) ([5e13c71](https://github.com/test-kitchen/kitchen-azurerm/commit/5e13c71))
* Public IP support for existing vnet deployment ([#42](https://github.com/test-kitchen/kitchen-azurerm/pull/42)) ([8c7b400](https://github.com/test-kitchen/kitchen-azurerm/commit/8c7b400))
* Use unattend.xml for winrm setup script ([#44](https://github.com/test-kitchen/kitchen-azurerm/pull/44)) ([3eb2159](https://github.com/test-kitchen/kitchen-azurerm/commit/3eb2159))

## [0.7.2] - 2016-11-03

* Bug: When repeating a completed deployment, deployment would fail with a nil error on resource_name (@stuartpreston)

## [0.7.1] - 2016-09-17

* Bug: WinRM is not enabled where the platform name does not contain 'nano' (@stuartpreston)

* Support Nano server if nano in instance.platform.name ([184d90f](https://github.com/test-kitchen/kitchen-azurerm/commit/184d90f))
* Change nano logic, support other Windows servers ([0bbf02b](https://github.com/test-kitchen/kitchen-azurerm/commit/0bbf02b))

## [0.7.0] - 2016-09-15

* Support creation of Windows Nano Server (ignoring automatic WinRM setting application) (@stuartpreston)

## [0.6.0] - 2016-08-22

* Supports latest autogenerated resources from Azure SDK for Ruby (0.5.0) (@stuartpreston)
* Removes unnecessary direct dependencies on older ms_rest libraries (@stuartpreston)
* ssh_key will be used in preference to password if both are supplied (@stuartpreston)

* Rubocop fixes ([17deec7](https://github.com/test-kitchen/kitchen-azurerm/commit/17deec7))
* Upgrading to version 0.5.0 of Azure SDK for Ruby, fixes to support ChefDK 0.17.17 ([51a26f1](https://github.com/test-kitchen/kitchen-azurerm/commit/51a26f1))

## [0.5.0] - 2016-08-07

* Adding support for internal (e.g. ExpressRoute/VPN) access to created VM (@stuartpreston)

* Adding ExpressRoute and VPN support ([3f5b852](https://github.com/test-kitchen/kitchen-azurerm/commit/3f5b852))

## [0.4.1] - 2016-07-01

* Adding explicit dependency on concurrent-ruby gem (@stuartpreston)

* Version 0.4.1 ([27baf62](https://github.com/test-kitchen/kitchen-azurerm/commit/27baf62))

## [0.4.0] - 2016-06-26

* Adding capability to execute ARM template prior to VM deployment, ```pre_deployment_template``` and ```pre_deployment_parameters``` added (@stuartpreston)

* Pinning inifile to &gt;=3.0.0 ([64fbfa4](https://github.com/test-kitchen/kitchen-azurerm/commit/64fbfa4))
* Updating Rubocop ([81922bc](https://github.com/test-kitchen/kitchen-azurerm/commit/81922bc))

## [0.3.6] - 2016-05-10

* Remove version pin on inifile gem dependency, compatible with newer ChefDK (@stuartpreston)

* Update README.md ([#27](https://github.com/test-kitchen/kitchen-azurerm/pull/27)) ([77dcec4](https://github.com/test-kitchen/kitchen-azurerm/commit/77dcec4))
* loosing version pin on inifile dependency ([7ee4a6d](https://github.com/test-kitchen/kitchen-azurerm/commit/7ee4a6d))

## [0.3.5] - 2016-03-21

* Remove transport name restriction on SSH key upload (allow rsync support) (@stuartpreston)
* Support SSH public keys with newlines as generated by ssh-keygen (@stuartpreston)

* Remove ssh transport name restriction ([33ee825](https://github.com/test-kitchen/kitchen-azurerm/commit/33ee825))

## [0.3.4] - 2016-03-19

* Additional diagnostics when Azure Resource Group fails to create successfully (@stuartpreston)

* Adding diag to Resource Group creation on error ([b66494e](https://github.com/test-kitchen/kitchen-azurerm/commit/b66494e))

## [0.3.3] - 2016-03-07

* Pinning ms_rest_azure dependencies to avoid errors when using latest ms_rest_azure library (@stuartpreston)

* Pinning ms_rest_azure dependencies to avoid breaking changes in 0.2 ([f4b0ac6](https://github.com/test-kitchen/kitchen-azurerm/commit/f4b0ac6))

## [0.3.2] - 2016-03-07

* Breaking: Linux machines are now created using a temporary sshkey (~/.ssh/id_kitchen-azurerm) instead of password (@stuartpreston)
* Real error message shown if credentials are incorrect (@stuartpreston)

* supporting ssh key VM creation for ssh transport ([e200611](https://github.com/test-kitchen/kitchen-azurerm/commit/e200611))
* Resolving rubocop issue fail -&gt; raise ([2c8be43](https://github.com/test-kitchen/kitchen-azurerm/commit/2c8be43))
* Merge branch 'master' of https://github.com/pendrica/kitchen-azurerm into support-sshkey ([68d5542](https://github.com/test-kitchen/kitchen-azurerm/commit/68d5542))
* Display correct error message if invalid credentials ([cddc4eb](https://github.com/test-kitchen/kitchen-azurerm/commit/cddc4eb))
* Use correct variable name to detect ssh mode ([633d9c2](https://github.com/test-kitchen/kitchen-azurerm/commit/633d9c2))

## [0.2.6](https://github.com/test-kitchen/kitchen-azurerm/compare/v0.2.5...v0.2.6) (2016-01-26)

* Fix thrown exception even on successful deployment ([d741451](https://github.com/test-kitchen/kitchen-azurerm/commit/d741451))

## [0.2.5](https://github.com/test-kitchen/kitchen-azurerm/compare/v0.2.3...v0.2.5) (2016-01-26)

* Support Premium Storage, Boot Diagnostics etc. ([#18](https://github.com/test-kitchen/kitchen-azurerm/pull/18)) ([3b747a3](https://github.com/test-kitchen/kitchen-azurerm/commit/3b747a3))
* Fixing issue caused by Rubocop autocorrect ([521e151](https://github.com/test-kitchen/kitchen-azurerm/commit/521e151))

## [0.2.4] - 2016-01-26

* Support Premium Storage and Boot Diagnostics (@stuartpreston)
* If deployment fails, show the message from the failing operation (@stuartpreston)
* Updated Windows 2008 R2 example (@stuartpreston)

## [0.2.3] - 2015-12-17

* ```kitchen create``` can now be executed multiple times, updating an existing deployment if an error occurs (@smurawski)

* be a bit more specific on where we want the sub-id ([#13](https://github.com/test-kitchen/kitchen-azurerm/pull/13)) ([660889c](https://github.com/test-kitchen/kitchen-azurerm/commit/660889c))
* allow multiple creates - validates the current state info ([#12](https://github.com/test-kitchen/kitchen-azurerm/pull/12)) ([d73a22f](https://github.com/test-kitchen/kitchen-azurerm/commit/d73a22f))
* Updating changelog and up version ([59eb702](https://github.com/test-kitchen/kitchen-azurerm/commit/59eb702))

## [0.2.2] - 2015-12-10

* Add an option for users to specify a custom script for WinRM (support Windows 2008 R2) (@andrewelizondo)
* Add azure_management_url parameter for Azure Stack support (@andrewelizondo)

* Update README.md ([b4d9b77](https://github.com/test-kitchen/kitchen-azurerm/commit/b4d9b77))
* Merge branch 'andrewelizondo-customize-vm-name' ([fc74c52](https://github.com/test-kitchen/kitchen-azurerm/commit/fc74c52))
* Initializing Travis ([#8](https://github.com/test-kitchen/kitchen-azurerm/pull/8)) ([084a793](https://github.com/test-kitchen/kitchen-azurerm/commit/084a793))
* add azure_management_url for initial azure stack support ([#9](https://github.com/test-kitchen/kitchen-azurerm/pull/9)) ([b31dc23](https://github.com/test-kitchen/kitchen-azurerm/commit/b31dc23))
* add an option for users to specify their a custom script for winrm ([#11](https://github.com/test-kitchen/kitchen-azurerm/pull/11)) ([1103e12](https://github.com/test-kitchen/kitchen-azurerm/commit/1103e12))

## [0.2.1] - 2015-10-06

* Pointing to updated Azure SDK for Ruby, supports Linux

* Updated refs to Azure SDK for Linux support ([17cc587](https://github.com/test-kitchen/kitchen-azurerm/commit/17cc587))

## [0.2.0] - 2015-09-29

* Logs should be sent to info, not stdout (@stuartpreston)
* Added WinRM support, enables WinRM and WinRM/s and configures server for Basic/Negotiate authentication (@stuartpreston)
* Store server_id earlier so it can be retrieved if resources fail to create in Azure (@stuartpreston)

* Set server_id state as early as possible ([67160c1](https://github.com/test-kitchen/kitchen-azurerm/commit/67160c1))
* Adding WinRM enablement during ARM deployment ([08f3ebb](https://github.com/test-kitchen/kitchen-azurerm/commit/08f3ebb))
* Updating Readme for WinRM support ([6cf252f](https://github.com/test-kitchen/kitchen-azurerm/commit/6cf252f))
* Remove stdout, log to info ([c2368ac](https://github.com/test-kitchen/kitchen-azurerm/commit/c2368ac))

## [0.1.3] - 2015-09-23

* Support *nix by changing the driver name to lowercase 'azurerm', remove Chef references (@gadgetmg)

* Normalize Azurerm class name ([#1](https://github.com/test-kitchen/kitchen-azurerm/pull/1)) ([2ceb03e](https://github.com/test-kitchen/kitchen-azurerm/commit/2ceb03e))

## [0.1.2] - 2015-09-23

* Initial release, supports provision of all public image types in Azure (@stuartpreston)

* Initial commit ([2f68369](https://github.com/test-kitchen/kitchen-azurerm/commit/2f68369))
* Multiple platform support, initial release ([6ca0224](https://github.com/test-kitchen/kitchen-azurerm/commit/6ca0224))
