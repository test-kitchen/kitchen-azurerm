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
bundle exec rake          # unit tests and linting, the same as CI
bundle exec rake test     # unit tests only
bundle exec rake style    # Cookstyle / Chefstyle only
```

To run a single spec file:

```sh
bundle exec rspec spec/unit/kitchen/driver/azurerm_spec.rb
```

Many style offenses can be corrected automatically:

```sh
bundle exec rake style:autocorrect
```

**Do not run `cookstyle` on its own here.** This project is linted with the
Chefstyle rule set, which Cookstyle only applies when it is asked for — either
by the `--chefstyle` flag, or by requiring `cookstyle/chefstyle` before
Cookstyle loads, which is what the Rakefile does. A bare `bundle exec cookstyle`
instead lints against the cookbook rule set and reports thousands of offenses
that are not real, every one of them marked autocorrectable:

```text
35 files inspected, 2480 offenses detected, 2480 offenses autocorrectable
```

so `cookstyle -a` will happily rewrite the whole repository against rules it is
not held to. Use the Rake tasks above, or `bundle exec cookstyle --chefstyle`,
which is exactly what CI runs. The `require: - cookstyle/chefstyle` line in
`.rubocop.yml` cannot help: RuboCop reads it only after Cookstyle has already
decided which rule set it is using.

The unit tests stub HTTP at the wire with WebMock, so they neither deploy
resources nor require a subscription or a service principal. WebMock also blocks
real network access outright, so an accidentally unstubbed request fails loudly
rather than reaching Azure.

### Talking to Azure

The driver calls the Azure Resource Manager REST API directly, using only the
Ruby standard library. The pieces live under `lib/kitchen/driver/azure/`:

| File | Responsibility |
| --- | --- |
| `environments.rb` | Endpoints for each Azure cloud (public, US Government, China, Germany). |
| `token_provider.rb` | Acquires and caches access tokens: workload identity federation, service principal, managed identity, or `az login`. |
| `arm_client.rb` | The ten ARM requests the driver makes. |
| `http.rb` | A small `Net::HTTP` wrapper that separates transient network failures from real API errors. |

One trap worth knowing about: Test Kitchen defines `Kitchen::StandardError`, and
this code lives inside `module Kitchen`. A bare `StandardError` in that namespace
resolves to Test Kitchen's class, not `::StandardError`, so `rescue StandardError`
silently stops catching ordinary errors. Always write `::StandardError`
explicitly here.

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
5. Write the commit subject as a [Conventional Commit](https://www.conventionalcommits.org/).
6. Push the branch to your fork and open a pull request.

Please keep pull requests focused on a single change — it makes review much
faster. Update the driver properties tables in `README.md` when you add or
change a configuration option.

### Commit messages

Commit subjects are not just for readers here: releases are automated, and the
subject line is what decides whether a release happens at all and what version
it gets. Use one of these types:

| Type | Effect on the next release |
| --- | --- |
| `fix:` | Patch version bump, listed under Bug Fixes. |
| `feat:` | Minor version bump, listed under Features. |
| `docs:`, `test:`, `refactor:`, `chore:`, `ci:` | No version bump, and not listed in the changelog. |

Append `!` (`feat!:`) or add a `BREAKING CHANGE:` footer for a major bump.

Because a squashed pull request lands as a single commit, the **pull request
title** is what ends up in the changelog. A `fix:` PR that quietly adds a
feature, or a `chore:` PR that fixes a bug, produces a release with the wrong
version and a changelog that does not mention the change at all — which is
also why pull requests here are kept to a single concern.

## Release process

Releases are automated with
[release-please](https://github.com/googleapis/release-please); there is nothing
to do by hand, and `lib/kitchen/driver/azurerm_version.rb` and `CHANGELOG.md`
should not be edited in a pull request.

1. A merge to `main` runs release-please, which reads the Conventional Commit
   subjects since the last release.
2. If any of them warrant one, it opens or updates a release pull request that
   bumps the version file and writes the changelog entries.
3. Merging that release pull request tags the release and publishes the gem to
   RubyGems and GitHub Packages.

The release pull request belongs to the bot and does not resolve conflicts on
its own. If it picks one up, rebase it by hand, keeping `main`'s content and the
bot's version — never force the branch back to an older version.
