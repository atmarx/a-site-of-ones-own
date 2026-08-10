# Azure Virtualmin Research Web Host Specification

Status: Infrastructure baseline implemented; service not production-approved  
Version: 0.2  
Last updated: 2026-08-05  
Owner: Research Web Hosting

## 1. Purpose

This document defines the target architecture and implementation contract for a
single Azure Linux virtual machine running the open-source Virtualmin GPL web
hosting stack. The environment is intended to host individually registered
research websites whose DNS `A` records are manually pointed at one stable Azure
public IPv4 address.

The first release deliberately favors a small, understandable system over a
high-availability platform. It reproduces the important properties of the
working local installation while placing the host in an Azure-only network with
no route to campus private networks.

## 2. Goals

- Provision the Azure infrastructure repeatably with Bicep.
- Install Virtualmin GPL with Nginx, PHP-FPM, and MariaDB.
- Exclude local mail, spam filtering, antivirus, DNS hosting, FTP, and Jailkit.
- Give the host a stable Azure Standard public IPv4 address.
- Publish websites by manually creating an explicit `A` record for each managed
  service hostname, bring-your-own domain, and alias. No wildcard DNS is used.
- Provide central WordPress fleet visibility through a MainWP Dashboard hosted
  separately on a campus RFC1918 subnet.
- Keep website files and MariaDB data on a dedicated, initially 64 GiB Azure
  managed disk that can be expanded without rebuilding the host.
- Prevent private connectivity to campus networks and limit the effect of a compromised
  host on other private resources.
- Make deployment state, verification, backup, recovery, and ownership clear
  enough for another administrator to operate the system.

## 3. Non-goals

- Hosting or relaying email.
- Authoritative DNS service on the VM.
- FTP access.
- Connectivity to campus networks through VPN, ExpressRoute, VNet peering, or private IP
  routing.
- Hosting the MainWP Dashboard on this VM or exposing its administration
  interface to the public Internet.
- Automatic management of each hosted domain's external DNS zone.
- Multi-VM high availability, zero-downtime maintenance, or automatic failover.
- Treating Bicep as the source of truth for Virtualmin domains or website
  content. Virtualmin remains a stateful application.
- Hosting regulated or restricted data without a separate security and
  compliance review.

## 4. Architecture Decisions

| Area | Decision | Reason |
| --- | --- | --- |
| Hosting model | One public Azure VM | Matches Virtualmin's stateful host model and keeps the first release operable. |
| Operating system | Rocky Linux 10, x86_64, Generation 2, from Rocky's official Azure Community Gallery | Matches the proven local host, is a Virtualmin Grade A supported OS, and avoids tenant Private Marketplace restrictions. |
| Virtualmin edition | Virtualmin GPL stable | Open-source edition requested; no license secret is required. |
| Stack | `LEMP` with `--type mini` | Provides Nginx, PHP-FPM, and MariaDB while omitting mail, local DNS, FTP, and related services. A clean LEMP installation follows Virtualmin's supported automated path. |
| Public ingress | Standard SKU static IPv4 directly on the VM NIC | Simple, stable DNS target; Standard public IPs require explicit NSG allows. |
| Hostname | Azure-managed public-IP FQDN | It resolves as soon as the public IP exists and is separate from all customer domains. |
| Customer DNS | One manually managed `A` record per managed service hostname, bring-your-own domain or subdomain, and alias | Makes each published name an explicit approval and inventory event; no wildcard DNS is used in release 1. |
| WordPress fleet management | MainWP Dashboard on a separate campus RFC1918 subnet, connecting outbound through NAT to each public site's MainWP Child plugin over HTTPS | Provides a private single pane of glass without adding a route from the Azure host to campus private networks. |
| Private networking | Dedicated VNet and subnet with no peering, VPN, ExpressRoute, or campus DNS | Removes direct private network paths. |
| Persistent data | Separate 64 GiB managed disk using LVM, with its XFS logical volume mounted directly at `/home` | Starts economically, keeps web data off the OS disk, supports quotas, and can grow online later. |
| MariaDB data | `/home/.virtualmin-data/mysql` bind-mounted at `/var/lib/mysql` | Keeps databases on the expandable data volume without sacrificing a direct `/home` quota mount. |
| Administration | SSH key authentication and Webmin on TCP 10000, both limited to approved public CIDRs | Keeps management interfaces off the unrestricted Internet. |
| Availability | Single instance | Accepted for release 1; recovery is through backups and redeployment. |

## 5. High-level Topology

```text
Individual domain A records
          |
          v
Azure Standard static public IPv4
          |
   Dedicated-subnet NSG
   - 80/443 from Internet
   - 22/10000 from admin CIDRs
   - no mail/DNS/FTP ingress
          |
Rocky Linux VM in isolated Azure VNet
   - Nginx + PHP-FPM
   - Virtualmin GPL / Webmin
   - MariaDB bound locally
          |
64 GiB expandable managed data disk
   - GPT partition -> LVM PV -> vg_webdata/lv_webdata
   - /home (XFS, user/group quotas)
   - /home/.virtualmin-data/mysql -> /var/lib/mysql
          |
Off-host Azure Blob backups
```

For WordPress fleet management, a separate connection originates outside this
Azure deployment:

```text
Private campus MainWP Dashboard
          |
   outbound campus NAT
          |
   public HTTPS/443
          |
          v
Azure public IP -> WordPress MainWP Child plugins
```

The MainWP Dashboard has no private connection to the Azure VNet, and the Azure
host has no route to the Dashboard's RFC1918 address. Core Dashboard-to-Child
traffic is initiated by the Dashboard over the same public TCP 443 endpoint as
normal site traffic, so no additional Azure NSG rule or public port is needed.

The VNet must not be peered to another VNet and must not contain a virtual
network gateway. Its effective routes must show no path to campus RFC1918
address space. An isolated VNet prevents private lateral movement; it does not
prevent a compromised server from attacking public university services over the
Internet. Normal host hardening, monitoring, and patching are still required.

## 6. Azure Resource Model

The initial implementation uses a resource-group-scoped Bicep deployment. One
resource group contains all host resources so ownership and cost are easy to
identify. Production data resources receive deletion locks.

### 6.1 Required resources

| Resource | Baseline configuration |
| --- | --- |
| Virtual network | Dedicated address space, provisionally `10.44.0.0/16`; no peerings or gateway. |
| Subnet | Provisionally `10.44.1.0/24`; optionally enabled for the Microsoft Storage service endpoint. |
| Network security group | Attached to the dedicated subnet; rules are defined in Section 8. |
| Public IP | Standard SKU, static IPv4, Azure DNS label, idle timeout 15 minutes. |
| Network interface | One dynamic private IPv4 configuration and the public IP; accelerated networking when the selected VM size supports it. |
| Managed data disk | Initially 64 GiB, LUN 0, host caching `None`, default `StandardSSD_LRS`, configurable by parameter. |
| Linux VM | Rocky Linux 10.2 Gen2 (`RESF-Rocky-10-x86_64-LVM/10.2.20260525` in the official Rocky Community Gallery), Trusted Launch, NVMe disk controller. |
| Backup storage account | Standard GRS, private containers, TLS 1.2 minimum, shared-key access disabled when the backup implementation supports Entra authentication. |
| Blob container | Dedicated to Virtualmin domain backups; no anonymous access. |
| Managed identity | System-assigned identity on the VM with blob data rights scoped only to the backup container or storage account. |
| Resource locks | `CanNotDelete` on the data disk, public IP, and backup storage account in production. |

### 6.2 Provisional compute defaults

- VM size: `Standard_D2as_v7` (2 vCPU, 8 GiB RAM, AMD Turin, NVMe-only disk controller, Premium storage capable).
- OS disk: 32 GiB `StandardSSD_LRS`, deleted with the VM.
- Data disk: 64 GiB `StandardSSD_LRS`, detached rather than deleted when the VM
  is deleted.
- Architecture: x86_64.
- Security: Trusted Launch with Secure Boot and vTPM, subject to a deployment
  test with the selected Rocky image and Virtualmin kernel packages.
- Boot diagnostics: enabled with Azure-managed storage.

These are capacity starting points, not promises about workload size. The VM and
disk SKUs remain parameters so cost and performance can be adjusted after
measuring CPU, memory pressure, disk latency, IOPS, and database growth.

The official Community Gallery image is pinned to
`RESF-Rocky-10-x86_64-LVM/10.2.20260525` in gallery
`rocky-dc1c6aa6-905b-4d9c-9577-63ccc28c482a`; upgrades are intentional changes
rather than an implicit use of `latest`. Community Gallery use avoids the
tenant Private Marketplace purchase-plan dependency encountered with the
equivalent `resf` Marketplace offer.

### 6.3 Resource lifecycle

- The data disk supports two deployment modes: create a new empty managed disk,
  or attach an existing/restored managed disk by resource ID.
- The data disk attachment uses `deleteOption: Detach`.
- Increasing `dataDiskSizeGB` is supported; decreasing an Azure managed disk is
  not. LVM and XFS expansion inside the guest is a separate, deliberate
  operation described in Section 9.3.
- The public IP is an independent resource and is retained when a VM is rebuilt.
  This matters because every customer domain points to it.
- The deployment is run in incremental mode and preceded by `what-if`.
- A resource group deletion is a disaster operation. Locks must be removed
  explicitly before the protected data disk, public IP, or backup account can be
  deleted.
- Replacing the VM creates a fresh OS disk. Stateful recovery uses either an
  Azure VM restore or Virtualmin backups; the first-boot installer is not an
  in-place upgrade mechanism.

## 7. Bicep Interface

### 7.1 Required parameters

| Parameter | Type | Notes |
| --- | --- | --- |
| `location` | string | Target Azure region; defaults to the resource group's `eastus`. |
| `namePrefix` | string | Short, lowercase workload prefix used in resource names. |
| `environment` | string | For example `dev`, `test`, or `prod`. |
| `adminUsername` | string | Non-root sudo user created by Azure. |
| `sshPublicKey` | secure string | Public key text only; private keys never enter Bicep, cloud-init, or the repository. |
| `adminSourceCidrs` | array | One or more public egress CIDRs allowed to reach SSH and Webmin. `0.0.0.0/0` is rejected. |
| `owner` | string | Operational owner tag. |
| `dataClassification` | string | Explicit classification tag and policy input. |

### 7.2 Optional parameters and defaults

| Parameter | Default |
| --- | --- |
| `vmSize` | `Standard_D2as_v7` |
| `osDiskSizeGB` | `32` |
| `osDiskSku` | `StandardSSD_LRS` |
| `dataDiskSizeGB` | `64` |
| `dataDiskSku` | `StandardSSD_LRS` |
| `vnetAddressPrefix` | `10.44.0.0/16` |
| `subnetAddressPrefix` | `10.44.1.0/24` |
| `enableDeletionLocks` | `true` for production |
| `tags` | empty object merged with required tags |

### 7.3 Outputs

The deployment must return:

- Public IPv4 address.
- Azure-managed host FQDN.
- Virtualmin URL, `https://<host-fqdn>:10000/`.
- SSH command using the configured admin user.
- VM, NIC, public IP, data disk, and backup account resource IDs.
- The expected bootstrap status command and log path.

No password, access token, private key, connection string, or storage account key
may appear in deployment outputs.

## 8. Network and Security Controls

### 8.1 Inbound NSG rules

| Priority | Source | Protocol/port | Purpose |
| --- | --- | --- | --- |
| 100 | `Internet` | TCP 80 | Public HTTP and ACME HTTP challenges. |
| 110 | `Internet` | TCP 443 | Public HTTPS websites. |
| 200 | `adminSourceCidrs` | TCP 22 | Administrative SSH/SFTP. |
| 210 | `adminSourceCidrs` | TCP 10000 | Virtualmin/Webmin administration. |
| 3000 | `VirtualNetwork` | Any | Explicit deny overriding Azure's default VNet-to-VNet allow. |
| 65500 | Any | Any | Azure default deny. |

The admin CIDRs must be public NAT egress addresses, such as approved campus or VPN public egress ranges. A private client address such as `10.0.0.0/8` will not
match traffic arriving through the VM's public IP.

There are no inbound rules for SMTP, submission, IMAP, POP, DNS, FTP, MariaDB,
or the Virtualmin-installed range `10000-10100`. Only TCP 10000 is needed for
the master administration interface in this design.

### 8.2 Outbound NSG rules

- Explicitly deny TCP 25 to `Internet` to reduce spam abuse from a compromised
  site. Azure may also restrict port 25, but the design does not depend on that.
- Explicitly deny traffic whose destination is the `VirtualNetwork` service tag,
  overriding Azure's default VNet outbound allow. This host does not require
  private east-west traffic.
- Permit normal Internet egress for OS and Virtualmin updates, ACME, external
  APIs, and approved authenticated mail submission services if a hosted
  application later needs them.
- Preserve access to Azure platform endpoints required by DHCP, DNS, metadata,
  the VM agent, backup, and monitoring.

The effective NSG rules and routes are deployment acceptance checks. No future
VNet peering or gateway may be added without revisiting this specification.

### 8.3 Guest controls

- Keep SELinux enabled in Virtualmin's supported Permissive baseline, with
  labels and audit logging intact; treat Enforcing as a separate policy project.
- Disable SSH password authentication and direct root login.
- Configure `firewalld` to mirror the NSG: public 80/443 and source-restricted
  22/10000 only.
- Remove installer-added guest firewall openings for DNS, mail, FTP, and broad
  passive-port or Webmin ranges.
- Bind MariaDB to loopback only. Do not publish TCP 3306.
- Use a separate Unix account, home directory, PHP-FPM pool, and database
  credentials for each Virtualmin virtual server.
- Treat Nginx configuration as platform-managed. Nginx does not process
  `.htaccess`; test WordPress permalinks and every approved plugin for rewrite,
  redirect, header, access-control, and caching requirements before launch.
- Install MainWP Child only on approved WordPress sites. Connect each child to
  the approved private Dashboard using HTTPS certificate verification, a
  dedicated MainWP administrator identity, and the MainWP Unique Security ID.
  The Unique Security ID is mandatory during enrollment.
- Enable Webmin multi-factor authentication for administrator accounts during
  production handoff.
- Do not install an Azure extension, package repository, or site-level software
  that is not part of the reviewed baseline.

This remains shared hosting: all sites share one kernel, Nginx instance, and
database server. A sufficiently privileged application exploit can affect other
sites. Workloads requiring strong tenant isolation belong on separate VMs or a
different platform.

## 9. First-boot Provisioning

Bicep supplies a versioned first-boot bootstrap payload through `customData` and
cloud-init. Cloud-init may continue after Azure reports the VM resource ready,
so deployment success is not the same as application readiness. The deployment
wrapper and verification script must wait for the bootstrap service's terminal
status.

### 9.1 Bootstrap properties

- The executable script is stored in the repository and loaded by Bicep; it is
  not downloaded from an unversioned project URL.
- The Virtualmin installer itself is downloaded from the official Virtualmin
  HTTPS endpoint during bootstrap.
- The script logs to `/var/log/research-web-hosting-bootstrap.log` and writes a
  success marker under `/var/lib/research-web-hosting/`.
- Every step is idempotent or guarded. The script must never run the Virtualmin
  installer to upgrade, repair, or reinstall an existing Virtualmin system.
- The script fails closed when it encounters an unexpected disk signature,
  filesystem, mount, hostname, or existing service state.
- The installer checksum or downloaded script is retained with the deployment
  log so the exact installation input can be audited.

### 9.2 Ordered bootstrap sequence

1. Wait for the Azure data disk at stable LUN 0 path
   `/dev/disk/azure/data/by-lun/0` (with the legacy SCSI by-LUN path as a
   compatibility fallback), without depending on an incidental `/dev/nvmeXnY`
   or `/dev/sdX` name.
2. Inspect the disk before any write. If blank, create a GPT partition of type
   Linux LVM, initialize an LVM physical volume, create volume group
   `vg_webdata`, create logical volume `lv_webdata`, and format that LV as XFS
   with label `VM_DATA`. The initial LV may use all available extents because
   the managed disk and PV can be enlarged later. If the disk already contains
   the expected LVM and filesystem markers, preserve it. Otherwise stop without
   formatting.
3. Mount the XFS logical volume temporarily and copy the image-created `/home`
   contents, including the admin user's `authorized_keys`, before replacing the
   `/home` mount.
4. Add an `/etc/fstab` entry using the XFS filesystem UUID for `/home` with
   `defaults,noatime,uquota,gquota,nofail` and mount it directly.
5. Create `/home/.virtualmin-data/mysql`, bind it to `/var/lib/mysql`, and make
   the bind mount persistent in `/etc/fstab` with a dependency on `/home`.
6. Apply SELinux file contexts for home directories and `mysqld_db_t` for the
   relocated MariaDB tree. Virtualmin's EL installer intentionally leaves
   SELinux in Permissive mode; retain policy labels and audit logging, do not
   disable SELinux entirely, and track Enforcing mode as a separately tested
   hardening project and governance exception.
7. Set the system hostname to the Azure-managed public-IP FQDN. It must not be a
   domain that Virtualmin will host.
8. Run the current official GPL installer on the fresh OS:

   ```bash
   sudo sh -c "$(curl -fsSL https://download.virtualmin.com/virtualmin-install)" -- \
     --bundle LEMP \
     --type mini \
     --hostname "$HOST_FQDN" \
     --yes \
     --no-banner
   ```

9. Confirm the GPL installer's `webmin-virtual-server` package is installed and
   the stable Virtualmin repository is configured.
10. Disable unwanted Virtualmin features and verify that Postfix, Dovecot,
    SpamAssassin, ClamAV, BIND, and ProFTPD are absent or disabled. Do not merely
    hide them from the UI.
11. Apply the guest firewall policy after the installer, because the installer
    may add firewall rules.
12. Verify Nginx, PHP-FPM, MariaDB, Webmin, XFS quotas, mounts, listeners, and
    `virtualmin check-config` before writing the success marker.
13. Install and configure backup/monitoring tools only after Virtualmin has
    completed. This preserves Virtualmin's expectation of a fresh supported OS.

For an Azure hostname that already resolves and is reachable on port 80, the
installer is allowed to request its hostname certificate. A certificate failure
does not justify enabling unrestricted access to port 10000; repair the
certificate after SSH access is established.

### 9.3 Expanding the data volume

Capacity expansion is a guarded boot-time operation after the Azure disk size
is changed. After taking and verifying a current backup:

1. Increase `dataDiskSizeGB` in the approved Bicep parameter file and deploy the
   managed disk change. Azure supports online growth for eligible attached data
   disks, though the runbook may choose a maintenance window and reboot for a
   simpler failure model.
2. Reboot the VM or run `grow-research-web-data.service`; it resolves and
   validates LUN 0 before changing storage.
3. The service runs `growpart`, `pvresize`, `lvextend`, and `xfs_growfs` only
   when their expected disk, PV, VG, LV, volume marker, and `/home` mount match.
4. Verify quotas, MariaDB, free space, backups, and a test site.

The runbook must resolve and print every device, partition, PV, VG, LV, and mount
before changing it. It must stop if LUN 0 does not map to the expected
`vg_webdata` identifiers. An alternative future growth path is to attach
another managed disk as a new PV in the same VG, but enlarging the original disk
keeps the first release simpler.

### 9.4 Initial administrator access

Azure creates the sudo administrator with SSH-key authentication and no usable
login password. Virtualmin can authenticate a sudo-capable system user, but the
browser login requires a password. The first-login runbook is therefore:

1. SSH with the deployment key.
2. Set a strong system password for the admin user with `sudo passwd
   <adminUsername>`. SSH password authentication remains disabled, so this
   password is for PAM/Webmin rather than remote shell access.
3. Log in to Virtualmin through the admin-restricted TCP 10000 endpoint.
4. Complete the post-install wizard, run Check Configuration, and enable Webmin
   MFA.

No initial password is embedded in Bicep parameters or cloud-init data.

## 10. DNS and Certificates

- The public IP receives an Azure DNS label such as
  `<unique-label>.<region>.cloudapp.azure.com`; this is the VM hostname and
  administration name.
- Each managed service hostname, bring-your-own domain or subdomain, and alias,
  including an approved institutional subdomain, gets an explicit public `A`
  record pointing to the Bicep output `publicIpAddress`.
- Do not create a wildcard record in release 1.
- Do not create `MX`, SPF, DKIM, or DMARC records for this host.
- Do not publish an `AAAA` record until IPv6 is deliberately designed, filtered,
  and tested.
- Use a low TTL such as 300 seconds during onboarding or migration, then raise it
  to the domain owner's normal value after validation.
- TLS terminates in Nginx on the VM. Azure does not issue or manage customer
  certificates in this direct-to-VM design; Azure only supplies the static IP
  and Azure-managed host FQDN.
- Request a Let's Encrypt certificate in Virtualmin only after every requested
  name resolves publicly to this host. Virtualmin GPL supports Let's Encrypt
  issuance and automatic renewal for its virtual servers.
- Use the ACME HTTP-01 challenge. Let's Encrypt retrieves a token below
  `http://<domain>/.well-known/acme-challenge/` on TCP 80. Port 80 must remain
  publicly reachable; a normal redirect from HTTP to HTTPS is acceptable.
- An institutional certificate service, where one exists, is not the baseline certificate provider for hosted sites. The hosting team is not expected to receive ACME
  authority spanning all institutional and externally managed DNS zones that
  customers may use. An institutional certificate is an exception that must identify
  the owner of issuance and renewal.
- HTTP-01 does not issue wildcard certificates, which is consistent with this
  design because every domain and subdomain is registered individually.
- Before issuance, check for restrictive DNS CAA records and include every
  desired name, such as both the apex and `www`, in DNS and in the certificate
  request.
- If Azure Front Door or Application Gateway is introduced later, certificate
  termination can move to that service. That is a different architecture and
  does not remove the need to secure and usually encrypt traffic to the origin.
- Maintain a versioned, non-secret domain inventory containing domain, owner,
  DNS provider, expected public IP, onboarding date, and retirement state. The
  inventory records intent but does not update external DNS.

## 11. Backup and Recovery

The data disk is not a backup. Deletion locks, disk snapshots, and replication
also do not replace application-level backups.

### 11.1 Required backup layers

1. Virtualmin domain backups run at least nightly and include all virtual server
   features, website files, databases, users, and Virtualmin configuration.
2. Backups leave the VM and are uploaded to a dedicated Azure Blob container.
3. The VM uses its managed identity for Blob access. Long-lived storage keys or
   interactive `az login --use-device-code` sessions are not acceptable for a
   scheduled production job.
4. The storage account uses GRS by default, blob versioning, soft delete, and a
   lifecycle policy matching approved retention.
5. Local staging files are removed only after upload and integrity verification.

Provisional retention is 14 daily, 8 weekly, and 12 monthly recovery points.
Final retention, RPO, and RTO require owner approval before production data is
hosted.

Virtualmin documents Azure Blob as a cloud backup provider, but implementation
must prove that its scheduled path works non-interactively with Azure managed
identity. If the built-in integration cannot do so, a root-owned systemd timer
will call `virtualmin backup-domain`, upload with Azure CLI or AzCopy using the
VM identity, verify the object, and then remove local staging data.

### 11.2 Optional Azure VM Backup

Azure VM Backup can provide whole-machine recovery in addition to portable
Virtualmin backups. It is off by default in the first parameter set pending a
cost and retention review. If enabled, use an Enhanced policy
compatible with Trusted Launch and validate Linux pre/post scripts for MariaDB
application consistency. Snapshot-only disk backup is crash-consistent and is
not the sole database recovery method.

### 11.3 Recovery paths

- **Domain error or deletion:** restore the affected Virtualmin domain backup.
- **OS failure with healthy data disk:** deploy a fresh VM, preserve or attach
  the disk, and follow the reviewed recovery runbook. Do not allow first boot to
  format a disk with existing signatures.
- **Host loss or uncertain compromise:** deploy a clean VM and clean data disk,
  restore Virtualmin backups, validate each site, and then attach the retained
  public IP. Reusing an OS disk from a compromised machine is not acceptable.
- **Azure regional event:** restore from GRS backups into the approved recovery
  region and update each domain using the domain inventory.

A restore test is required before production launch and at least quarterly
afterward. The test must restore one representative PHP site and MariaDB
database to an isolated temporary host and record elapsed time and findings.

## 12. Patching, Monitoring, and Operations

- Apply Rocky Linux and Virtualmin stable updates on a documented maintenance
  cadence. Never use the Virtualmin install script as an updater.
- Manage guest OS assessment and patching through native Azure Update Manager.
  This Azure VM uses the Azure Linux VM Agent and must not be enrolled as an
  Azure Arc-enabled server; Arc is reserved for future non-Azure hosts.
- Keep periodic assessment enabled with `assessmentMode:
  AutomaticByPlatform`. Before production, add a parameterized
  `Microsoft.Maintenance/maintenanceConfigurations` guest-patch schedule and
  assignment after approving its maintenance window, package classifications,
  and reboot policy. Scheduled patching sets the Azure VM to customer-managed
  schedules; routine SSH-driven `dnf update` is then an exception workflow.
- Reboots are planned events for this single-node service and require an outage
  notice appropriate to the hosted sites.
- Enable Azure boot diagnostics and basic platform health monitoring from day 1.
- Boot diagnostics uses Azure-managed storage. The workload storage account is
  dedicated to Virtualmin backups and is not a telemetry or diagnostics sink.
- Before production, alert on VM unavailable, sustained CPU pressure, low OS or
  data disk free space, high disk latency, failed backup timer, failed bootstrap,
  and HTTP/HTTPS unavailability.
- Forward authentication, Webmin, Nginx, MariaDB, and system logs to the
  institution's approved log destination when one is selected. Do not place
  credentials or website secrets in logs.
- Review Virtualmin administrators, Unix users, hosted domains, TLS expiry,
  package updates, NSG rules, effective routes, and backup success monthly.
- Use the private MainWP Dashboard for WordPress inventory and update
  visibility. Keeping the Dashboard private does not remove the public MainWP
  Child plugin from each site's attack surface; keep the Dashboard, Child
  plugin, WordPress core, themes, and plugins patched under the approved change
  policy.
- Record all manually created DNS entries in the domain inventory before a site
  is considered supported.

Defender for Servers and just-in-time management access are recommended options
if the subscription already licenses them. The baseline remains secure without
them by requiring fixed admin source CIDRs.

## 13. Repository Layout to Implement

```text
templates/azure/
  host-specification.md
  main.bicep
  parameters/
    prod.example.bicepparam
  bootstrap/
    virtualmin-bootstrap.sh
    grow-data-disk.sh
    virtualmin-backup.sh
  scripts/
    deploy.ps1
    verify.ps1
playbook/
  service-offering.md
```

Real parameter files may be committed only when they contain no credentials,
private key material, access tokens, or sensitive network details. The existing
private key in the working folder is not an Azure provisioning input and must
never be copied into this structure or committed.

## 14. Deployment Workflow

1. Select the subscription, region, resource group, admin CIDRs, SSH public key,
   and approved parameter set.
2. Confirm Rocky Linux 10 image and VM SKU availability in the target region;
   pin the exact image version.
3. Run Bicep lint/build and shell static analysis.
4. Run `az deployment group what-if` and review replacements, deletions, role
   assignments, and lock changes.
5. Deploy in incremental mode through `scripts/deploy.ps1`.
6. Wait for the bootstrap service, rather than only the ARM deployment, to
   report success.
7. Run `scripts/verify.ps1` from an approved admin source network.
8. Set the admin's Webmin password over SSH, enable MFA, complete the Virtualmin
   wizard, and rerun Check Configuration.
9. Configure and test off-host backup before adding a customer domain.
10. Add one test domain `A` record, create its Virtualmin virtual server, issue
    TLS, and run functional and restore tests.
11. For a test WordPress site, install MainWP Child, require a Unique Security
    ID, and verify that the private MainWP Dashboard can connect through campus NAT using public HTTPS without an additional Azure ingress rule.
12. Record the deployment outputs, owner, recovery point, DNS entry, and
    operational handoff.

## 15. Acceptance Criteria

### 15.1 Infrastructure

- A second identical Bicep deployment reports no unintended changes.
- The public IPv4 address is Standard SKU, static, and protected from accidental
  deletion in production.
- Effective routes show no peering, VPN, ExpressRoute, or private path to campus networks.
- Effective NSG rules expose only 80/443 publicly and 22/10000 from approved
  public CIDRs.
- TCP 21, 25, 53, 110, 143, 465, 587, 993, 995, 3306, and 10001-10100 are not
  publicly reachable.
- The VM identity has no Azure role broader than its documented backup and
  monitoring needs.
- The MainWP Dashboard has no public inbound listener or NAT rule and no private
  network connection to the Azure VNet. Its only required path to hosted sites
  is outbound through campus NAT to public TCP 443.

### 15.2 Guest and storage

- The OS disk is 32 GiB and contains no website document roots or MariaDB data.
- `/home` is a direct XFS mount from `/dev/vg_webdata/lv_webdata` on the 64 GiB
  data disk and is mounted by filesystem UUID.
- `pvs`, `vgs`, and `lvs` show the expected LUN 0 partition, `vg_webdata`, and
  `lv_webdata` with no unexpected PVs.
- XFS user and group quota accounting and enforcement are enabled on `/home`.
- `/var/lib/mysql` resolves to the data disk through the documented bind mount.
- The admin user's SSH key remains available after `/home` is mounted.
- SELinux is Permissive rather than disabled, labels remain applied, and
  MariaDB starts without context errors.
- Nginx, PHP-FPM, MariaDB, and Webmin are enabled and healthy after reboot;
  Apache is inactive.
- Postfix, Dovecot, BIND, ProFTPD, SpamAssassin, and ClamAV are absent or
  disabled, and their ports are closed.
- `virtualmin check-config` succeeds for the enabled web and database features.
- Virtualmin reports the public IPv4 address as the default address for new
  virtual servers.

### 15.3 User-facing service

- SSH succeeds with the configured key and fails with password authentication.
- The Azure host FQDN resolves to the deployed public IP.
- The Virtualmin URL presents a valid hostname certificate or has a documented
  certificate remediation completed before production.
- A test domain resolves to the public IP, serves HTTP and HTTPS, receives a
  valid certificate, executes PHP, and reaches only its own test database.
- A test WordPress site serves post-name permalinks, the REST API, media
  uploads, and approved plugin routes without relying on `.htaccess`.
- The private MainWP Dashboard can synchronize a test WordPress site through
  campus NAT and the site's public HTTPS endpoint with certificate verification
  enabled and no additional Azure ingress port.
- MainWP enrollment fails with a missing or mismatched Unique Security ID and
  succeeds only when the Child plugin and approved Dashboard use the same ID.
- A nightly domain backup is visible off-host and a representative restore has
  succeeded.

## 16. Known Risks and Tradeoffs

| Risk | Treatment |
| --- | --- |
| Single VM or zone failure causes an outage | Accept for release 1; monitor, back up, document recovery, and measure RTO. |
| Shared-host compromise crosses site boundaries | Use per-domain users and PHP-FPM pools, patch promptly, restrict administrators, and move higher-risk workloads to separate hosts. |
| MainWP compromise gives an attacker privileged reach across WordPress sites | Keep the Dashboard on a private RFC1918 subnet, require MFA and least administrative membership, patch and back it up, protect and rotate connection keys, log actions, and require the Unique Security ID for every Child enrollment. |
| Direct public origin has no WAF | Keep software current and logs monitored; evaluate Azure Front Door or Application Gateway WAF when risk or traffic justifies it. |
| Manual DNS can drift or slow recovery | Keep a versioned domain inventory and use a low migration TTL. Protect the public IP from deletion. |
| A 64 GiB Standard SSD may run out of capacity or IOPS | Alert early, measure I/O and utilization, and expand the disk/LV or change SKU through the reviewed runbook. |
| Managed disks and XFS cannot be shrunk in place | Treat capacity changes as increases; migrate to a new smaller disk if reduction is ever required. |
| Bootstrap changes do not update an existing VM | Treat bootstrap as first-boot configuration; use reviewed operations procedures or rebuild/restore for major baseline changes. |
| Isolation can be weakened later by Azure networking changes | Explicitly deny VNet traffic, monitor effective routes, and require review before adding peering or gateways. |
| Virtualmin leaves SELinux Permissive on Enterprise Linux | Retain SELinux labels and audit events, document the exception, use per-site users/PHP-FPM and layered network controls, and test Enforcing mode policies separately before changing production. |

## 17. Decisions Required Before Implementation

The following values do not block writing the template, but production defaults
cannot be finalized without them:

- Azure subscription, resource group naming convention, and deployment region.
- Approved managed service parent domain and ownership of its per-site DNS
  request process.
- MainWP Dashboard owner, private hosting location, administrator and MFA
  policy, stable NAT egress identity, backup/recovery procedure, and authority
  for centralized WordPress changes.
- Approved public CIDRs for SSH and Virtualmin administration.
- Administrator username and SSH public key source.
- Confirmation of production quota for `Standard_D2as_v7`; availability and
  image compatibility have been verified in `eastus`.
- Backup retention, required RPO/RTO, and whether Azure VM Backup is funded.
- Log Analytics/Defender licensing and the approved alert destination.
- Azure Update Manager maintenance window, update classifications, and reboot
  policy. Azure Arc onboarding is required only for future non-Azure servers.
- Data classification and whether any hosted research application has additional
  compliance requirements.
- Ownership of the manually maintained domain inventory and DNS change process.

## 18. Implementation Phases

1. **Infrastructure skeleton:** Bicep resources, parameters, outputs, locks, and
   `what-if` deployment wrapper.
2. **Host bootstrap:** safe LVM initialization, direct XFS `/home` mount,
   MariaDB bind mount, Virtualmin GPL mini install, and firewall hardening.
3. **Verification:** automated Azure, network, mount, quota, service, package,
   listener, and Virtualmin configuration checks.
4. **Data protection:** managed-identity Blob backups, retention, alerts, and a
   successful isolated restore test.
5. **Pilot domain:** manual DNS, TLS, PHP/database test, monitoring, and owner
   handoff.
6. **WordPress fleet management:** connect a pilot WordPress site to the private
   MainWP Dashboard using outbound NAT, HTTPS verification, and the mandatory
   Unique Security ID.
7. **Production readiness:** resolve every decision in Section 17 and capture
   the approved parameter set and runbooks.

## 19. References

- [Virtualmin GPL download and installation](https://www.virtualmin.com/download/)
- [Virtualmin automated installation and mini mode](https://www.virtualmin.com/docs/installation/automated/)
- [Virtualmin operating system support](https://www.virtualmin.com/docs/os-support/)
- [Virtualmin backup and restore](https://www.virtualmin.com/docs/backup-and-migration/how-to-backup-virtual-servers/)
- [Virtualmin cloud storage providers](https://www.virtualmin.com/docs/backup-and-migration/cloud-storage-providers/)
- [Azure Linux VM Bicep quickstart](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/quick-create-bicep)
- [Azure VM custom data and cloud-init behavior](https://learn.microsoft.com/en-us/azure/virtual-machines/custom-data)
- [Azure public IP addresses](https://learn.microsoft.com/en-us/azure/virtual-network/ip-services/public-ip-addresses)
- [Azure network security groups](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview)
- [Expand Azure virtual disks on Linux](https://learn.microsoft.com/en-us/azure/virtual-machines/linux/expand-disks)
- [Azure Trusted Launch](https://learn.microsoft.com/en-us/azure/virtual-machines/trusted-launch)
- [Rocky Linux on Azure Community Gallery](https://rockylinux.org/news/rocky-on-azure-community-gallery)
- [Azure Community Gallery VM images](https://learn.microsoft.com/en-us/azure/virtual-machines/vm-generalized-image-version#community-gallery)
- [Azure Update Manager overview](https://learn.microsoft.com/en-us/azure/update-manager/overview)
- [Azure Update Manager scheduled patching](https://learn.microsoft.com/en-us/azure/update-manager/scheduled-patching)
- [Azure Arc-enabled servers prerequisites](https://learn.microsoft.com/en-us/azure/azure-arc/servers/prerequisites)
- [Azure VM Backup](https://learn.microsoft.com/en-us/azure/backup/backup-azure-vms-introduction)
- [Azure Disk Backup](https://learn.microsoft.com/en-us/azure/backup/disk-backup-overview)
- [Let's Encrypt HTTP-01 challenge](https://letsencrypt.org/docs/challenge-types/)
- [Let's Encrypt guidance for port 80](https://letsencrypt.org/docs/allow-port-80/)
- [MainWP introduction](https://docs.mainwp.com/getting-started/mainwp-introduction)
- [MainWP connection security](https://docs.mainwp.com/advanced/miscellaneous/mainwp-connection-security)
- [MainWP ports and user agent](https://mainwp.com/kb/what-port-and-user-agent-does-mainwp-use/)
