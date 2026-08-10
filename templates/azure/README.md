# Azure Reference Implementation

This is a complete, deployable Azure implementation of the hosting platform described in the [playbook](../../playbook/index.md): a direct-to-VM Virtualmin GPL host for research group websites.  The authoritative architecture, acceptance criteria, and operational contract live in the [host specification](host-specification.md) — read it before deploying.

The deployment deliberately has no Front Door, Application Gateway, reverse proxy, load balancer, private campus route, mail stack, DNS server, or FTP server.

Virtualmin is installed as a minimal LEMP stack: Nginx, PHP-FPM, and MariaDB.  Apache is not an active service.  Nginx has no per-directory `.htaccess` facility, so redirects, rewrites, access controls, and plugin-specific web server directives must be reviewed and managed in the Nginx virtual-server configuration.

## Resources

- One isolated VNet/subnet and one NSG.
- One static Standard public IPv4 address and accelerated NIC.
- One `Standard_D2as_v7` Rocky Linux 10 VM with a 32 GiB OS managed disk.
- One detachable 64 GiB data managed disk at LUN 0.
- One GRS storage account and private Blob container for off-host backups.
- A system-assigned VM identity, container-scoped Blob role, and deletion locks.

The data disk is GPT + LVM + XFS.  It mounts at `/home`; MariaDB uses a bind mount from that volume.  The boot-time growth service extends the partition, PV, LV, and XFS filesystem after `dataDiskSizeGB` is increased in Azure.

Boot diagnostics uses Azure-managed storage.  The deployment's GRS storage account is only for private Virtualmin backups; centralized logs are not enabled by this template.  Guest update assessment uses native Azure Update Manager through the Azure Linux VM Agent.  Do not install the Azure Arc Connected Machine agent on this Azure VM; Arc is the onboarding path for non-Azure hosts.

Virtualmin's Enterprise Linux installer leaves SELinux in Permissive mode.  The bootstrap retains SELinux labels (including the relocated MariaDB context) and audit visibility.  Enforcing mode requires a separately tested policy baseline and is not silently enabled by this deployment.

## Prerequisites

1. Install Azure CLI and sign in to your Azure tenant.
2. Create (or choose) a resource group, and use an identity that can deploy resources, role assignments, and locks in it.
3. Supply an OpenSSH public key such as `$HOME\.ssh\id_ed25519.pub`.
4. Determine the public NAT egress CIDR(s) from which SSH and Virtualmin will be administered.  Private, reserved, documentation-only, and `0.0.0.0/0` CIDRs are rejected by the deployment wrapper.

The Rocky image is pinned to the official Community Gallery image `RESF-Rocky-10-x86_64-LVM/10.2.20260525` in public gallery `rocky-dc1c6aa6-905b-4d9c-9577-63ccc28c482a`.  This avoids a commercial Marketplace plan and any tenant Private Marketplace approval path.

## Validate

From this directory, run:

```powershell
.\scripts\deploy.ps1 `
  -SubscriptionId 'REPLACE_WITH_SUBSCRIPTION_ID' `
  -ResourceGroupName 'REPLACE_WITH_RESOURCE_GROUP' `
  -SshPublicKeyPath "$HOME\.ssh\id_ed25519.pub" `
  -AdminSourceCidrs @('REPLACE_WITH_PUBLIC_NAT_IP/32')
```

This builds Bicep, validates it against Azure Resource Manager, and prints a `what-if`.  It changes no resources.

## Deploy

After reviewing the `what-if`, repeat the command with `-Deploy`:

```powershell
.\scripts\deploy.ps1 `
  -SubscriptionId 'REPLACE_WITH_SUBSCRIPTION_ID' `
  -ResourceGroupName 'REPLACE_WITH_RESOURCE_GROUP' `
  -SshPublicKeyPath "$HOME\.ssh\id_ed25519.pub" `
  -AdminSourceCidrs @('REPLACE_WITH_PUBLIC_NAT_IP/32') `
  -Deploy
```

The wrapper waits up to 90 minutes for Virtualmin bootstrap, runs guest and network verification, and prints the SSH command and Virtualmin URL.  A failed bootstrap retains its log at `/var/log/research-web-hosting-bootstrap.log` and does not write the completion marker.

## First Handoff

1. Set the admin user's Webmin password over SSH and enable Webmin MFA.
2. Complete the Virtualmin post-install wizard and run Check Configuration.
3. Create one explicit domain `A` record pointing to the deployment's public IP.
4. Add the domain in Virtualmin, request its Let's Encrypt certificate using HTTP-01, and test a backup and restore before onboarding customer sites.

Port 80 must remain publicly reachable for HTTP-01 and redirect traffic.  SSH and TCP 10000 remain restricted to the supplied administrator CIDRs.

After deployment, record the outcome using the [acceptance record template](acceptance-record-template.md).
