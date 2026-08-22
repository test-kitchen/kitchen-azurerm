# Contributing to kitchen-azurerm

Contributions to the project are welcome via pull requests. Bug reports and feature requests are welcome too.

## Reporting issues

Report bugs and request features on the [issue tracker](https://github.com/test-kitchen/kitchen-azurerm/issues). For bugs, please include:

- the version of kitchen-azurerm and Test Kitchen you are using
- your host platform — the driver is tested on Windows, macOS, and Ubuntu
- your `kitchen.yml` with subscription IDs, tenant IDs, and secrets removed
- the output of the failing command, ideally with `-l debug`

Deployment failures usually surface as an Azure deployment error. The deployment
name and correlation ID from the debug output make those far easier to trace in
the Azure portal.

## Development setup

```sh
git clone https://github.com/test-kitchen/kitchen-azurerm.git
cd kitchen-azurerm
bundle install
```

## Running the tests

```sh
bundle exec rake          # unit tests and linting
bundle exec rake spec     # unit tests only
bundle exec rake style    # Cookstyle / RuboCop only
```

To run a single spec file:

```sh
bundle exec rspec spec/kitchen/driver/azurerm_spec.rb
```

Many style offenses can be corrected automatically:

```sh
bundle exec cookstyle -a
```

The unit tests stub the Azure SDK, so they neither deploy resources nor require
a subscription or a service principal.

## Manual testing

Changes that touch deployment, networking, or identity should also be exercised
against a real subscription, since the stubbed tests cannot catch API-level
regressions.

**This creates billable resources.** Worth exercising separately, since they take
different paths through the driver:

- **Linux and Windows**, which differ in WinRM configuration and data disk
  formatting
- **a created resource group** versus `explicit_resource_group_name`, including
  the `destroy_explicit_resource_group` behaviour
- **pre- and post-deployment ARM templates**
- **managed identities**, both system- and user-assigned

Afterwards, confirm in the portal that the resource group was actually removed —
a run that fails partway through can leave a VM, disks, and a public IP behind.

## Submitting changes

1. Fork the repository.
2. Create a feature branch off `main`.
3. Make your change, adding or updating tests to cover it.
4. Make sure `bundle exec rake` passes.
5. Push the branch to your fork and open a pull request.

Please keep pull requests focused on a single change — it makes review much
faster. Update the driver properties tables in `README.md` when you add or
change a configuration option.

## Release process

Releases are handled by the maintainers.

1. Update `lib/kitchen/driver/azurerm_version.rb` with the new version.
2. Update `CHANGELOG.md`.
3. Merge to `main`; the publish workflow builds the gem and pushes it to
   RubyGems.
