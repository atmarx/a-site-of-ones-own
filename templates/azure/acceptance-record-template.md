# Deployment Acceptance Record — Template

Copy this file for each environment, fill in the values after deployment, and keep the completed copy in your institution's operational records — not in a public repository.  A completed record contains real subscription IDs, addresses, and hostnames; sanitize before sharing anything beyond your operations team.

Status: <infrastructure accepted / launch gates open>
Recorded: <date>
Environment: <dev / test / prod>

## Deployment

- Subscription: `<subscription-id>`
- Resource group: `<resource-group>`
- Region: `<region>`
- Successful deployment: `<deployment-name>`
- VM: `<vm-name>`, `<vm-size>`, Rocky Linux <version>
- Public IPv4: `<public-ip>`
- Bootstrap host: `<azure-managed-fqdn>`
- Approved management source: `<admin-cidrs>`

Record any deployment attempts that failed and why — future operators inherit the lesson.  Two field notes from the deployment this template descends from, kept because they will save you an afternoon:

- Referencing the Rocky Community Gallery image through the generic image ID field fails ARM validation; the deployment must use `communityGalleryImageId` (as this template's Bicep now does).
- An unnecessary Agentless-scanning preview property on the VM resource failed the deployment; keep preview properties out of the baseline.

## Verified Baseline

Check each item against the acceptance criteria in the [host specification](host-specification.md), and record the evidence:

- [ ] ARM deployment completed and the VM is running.
- [ ] Trusted Launch, Secure Boot, vTPM, NVMe controller, accelerated networking, and the expected OS/data disks are present.
- [ ] LUN 0 is GPT -> LVM PV -> `vg_webdata/lv_webdata` -> XFS mounted at `/home` with enforced user and group quotas.
- [ ] `/home/.virtualmin-data/mysql` is bind-mounted at `/var/lib/mysql`.
- [ ] Virtualmin GPL installed with Nginx, PHP-FPM, and MariaDB; Apache inactive.
- [ ] Mail, local DNS, FTP, Cockpit, and their public listeners are disabled.
- [ ] MariaDB listens only on loopback.
- [ ] Public TCP 22, 80, 443, and 10000 are reachable from the approved source only; 25, 53, 3306, and 9090 are blocked.
- [ ] A real admin SSH key login and passwordless sudo check succeeded; password authentication fails.
- [ ] AzCopy installed from its pinned official archive after checksum verification.
- [ ] The VM managed identity uploaded, listed, and deleted a test Blob in the private backup container without a key or SAS.
- [ ] The disk-growth oneshot and the backup path completed; the nightly backup timer is enabled.
- [ ] Azure Update Manager assessment completed; update and reboot state recorded.

## Supported Exceptions

Record deviations the deployment accepts deliberately, for example:

- Virtualmin's Enterprise Linux installer leaves SELinux in Permissive mode; labels and audit visibility remain enabled.
- No public IPv6 address is assigned.
- Central log ingestion and platform alerting not yet implemented.

## Pending DNS

| Name | Target | Intended use |
| --- | --- | --- |
| `<management-fqdn>` | `<public-ip>` | Virtualmin/Webmin host identity; not a customer virtual server |
| `<first-site-fqdn>` | `<public-ip>` | First test/pilot virtual server |

After the records resolve, change the Virtualmin host identity through its supported hostname workflow and issue the management certificate before using the first name.  Use the second name for HTTP-01, WordPress, isolation, backup, and restore acceptance tests.

## Open Launch Gates

Carry the unresolved items from the [governance and launch gates](../../playbook/governance-and-launch-gates.md) checklist here, with owners and dates, for example:

- [ ] Source control and key custody confirmed safe.
- [ ] Update Manager maintenance window, classifications, and reboot policy approved and deployed.
- [ ] Authoritative site/domain inventory established; unknown hostnames rejected.
- [ ] Webmin administrator password set, MFA enabled, administrator roster recorded.
- [ ] Central monitoring, log forwarding, alert routing, and an incident-isolation exercise completed.
- [ ] Approved backup retention tiers reconciled with Blob lifecycle automation.
- [ ] Representative backup and isolated restore completed with recorded RPO/RTO evidence.
- [ ] Operating runbooks complete; MainWP approved or explicitly deferred.
