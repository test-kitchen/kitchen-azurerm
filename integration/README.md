# Integration suites

The unit suite stubs HTTP at the wire, so it can prove the driver *sends* the
right request but never that Azure accepts it. These suites close that gap: each
one deploys a real virtual machine and asserts, on the instance, that the driver
configured it the way the suite asked for.

They are not part of `rake default`. They deploy real resources and cost real
money.

## What each suite covers

| Suite | What it proves |
| --- | --- |
| `default` | Create, converge and destroy with an SSH key, a public IP and a generated security group. |
| `password` | With no `ssh_key`, the driver generates a password and stores it in state. |
| `tags` | `vm_tags` reach the virtual machine, read back from instance metadata. |
| `data-disks` | Both configured data disks are attached at the requested sizes. |
| `custom-data` | `custom_data` reaches cloud-init and runs. |
| `identity` | A system-assigned identity is attached and can mint ARM tokens. |
| `os-disk` | `os_disk_size_gb`, `storage_account_type` and `open_ports`. |
| `fqdn` | `use_fqdn_hostname` connects over the DNS name rather than the address. |
| `long-prefix` | A `vm_prefix` longer than three characters still yields names Azure accepts. |
| `pre-post-deploy` | `pre_deployment_template` and `post_deployment_template`. |
| `winrm` | The Windows path: custom-data bootstrap, unattend content, WinRM listeners. |
| `format-data-disks` | `format_data_disks` initialises and NTFS-formats a raw disk. |

## Running them

You need a subscription, credentials with rights to create resources (see
[Authentication](../README.md#authentication)), and enough vCPU quota in the
target region for four `Standard_B1s` instances at once.

```sh
bundle install
export AZURE_SUBSCRIPTION_ID=...
cd integration
bundle exec kitchen list
bundle exec kitchen test default-ubuntu-2204
```

Or from the repository root:

```sh
bundle exec rake integration:test      # everything
bundle exec rake integration:destroy   # clean up after a failed run
```

`kitchen test` destroys on success. It leaves the instance up on failure so you
can log in and look, so **run `kitchen destroy` when you are done** — or
`rake integration:destroy`, which does it for every suite.

### Settings

| Variable | Default | Purpose |
| --- | --- | --- |
| `AZURE_SUBSCRIPTION_ID` | *none* | Required. |
| `KITCHEN_AZURE_LOCATION` | `eastus` | Region to deploy into. |
| `KITCHEN_SSH_KEY` | `~/.ssh/id_kitchen_azurerm` | Private key to use. The driver generates one if the file does not exist. |
| `KITCHEN_RUN_ID` | `local` | Tagged onto every resource group, so a leaked one can be traced back to the run that made it. |

## Concurrency and quota

The suites run four at a time by default. A fresh subscription is often capped
at 10 vCPU in a region, and the two Windows suites use `Standard_B2s` (2 vCPU
each), so raising `--concurrency` much past four tends to fail with
`OperationNotAllowed` rather than run faster.

## In CI

`.github/workflows/integration.yml` runs these weekly against `main`, and on
demand through **Actions → Integration Tests → Run workflow**. It is never
triggered by a pull request: secrets are not available to forks, and every run
costs money.

CI authenticates with workload identity federation, exchanging GitHub's OIDC
token for an Entra ID one, so no client secret is stored. That also makes CI the
only place `Azure::WorkloadIdentityToken` is exercised — it cannot run on a
developer's machine.

It needs three repository secrets, and a federated credential on the app
registration scoped to this repository:

| Secret | Value |
| --- | --- |
| `AZURE_SUBSCRIPTION_ID` | Subscription to deploy into. |
| `AZURE_TENANT_ID` | Directory the app registration lives in. |
| `AZURE_CLIENT_ID` | Application (client) ID. No secret is needed. |

## Adding a suite

Add it to `kitchen.yml` with a script in `scripts/`. Assertions live in the
**provisioner**, not a verifier: the script is transferred over the driver's own
transport and executed on the instance, so reaching the machine at all is part
of every assertion, and a non-zero exit fails the suite. Keep each suite pointed
at one behaviour — when it fails, its name should say what broke.
