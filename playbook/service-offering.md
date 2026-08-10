# Research Web Hosting Service Offering

Status: Draft for discussion  
Version: 0.1  
Last updated: 2026-07-28  
Service owner: Research Web Hosting

## 1. Service Summary

Research Web Hosting provides a managed home for public websites that support university research. The service is intended for project, lab, center, instrument,
conference, and research-outreach sites that need conventional Linux web
hosting but do not justify a separately operated server.

Each site is created as a Virtualmin virtual server on a shared Azure Linux
host. The baseline platform provides Nginx, PHP-FPM, and, when requested,
MariaDB. Sites receive HTTPS, site-scoped filesystem and database credentials,
platform patching, monitoring, and off-host backups.

This is shared hosting on a single virtual machine. It is not a high-availability
application platform, a managed application-development service, or an
appropriate default for regulated or restricted research data.

## 2. Who Can Request a Site

Any current university faculty or staff member may request a site on behalf of an active research activity. A research computing or IT staff member may
also submit a request for the responsible research group.

Students, external collaborators, and affiliates may administer or contribute
to a site, but their request must be sponsored by a current university faculty or staff member.

Every site must have:

- An accountable service owner who is a current university faculty or staff member.
- A technical or content contact who can respond to security, maintenance, and
  renewal notices.
- A stated research purpose and an appropriate data classification.
- An agreed hostname and a plan for maintaining the site's application and
  content.

Requests are subject to a lightweight suitability, security, naming, and
capacity review. A request is not automatically approved merely because the
requester is eligible.

The following are not the intended use of this service:

- Personal home pages, course assignments, or general departmental websites
  without a research purpose.
- Commercial hosting or sites primarily operated for an outside organization.
- Applications containing regulated, restricted, export-controlled, or
  otherwise sensitive data unless separately reviewed and approved.
- High-availability, high-traffic, compute-intensive, or strong-isolation
  workloads.
- Applications requiring root access, arbitrary containers, a custom network
  perimeter, or a software stack incompatible with the shared host.

## 3. What the Service Includes

The baseline offering includes:

- One Virtualmin virtual server per independently managed site.
- A separate Unix account, home directory, PHP-FPM pool, logs, and quotas.
- Nginx hosting for static content and supported PHP applications.
- One or more MariaDB databases when requested.
- A managed service hostname, a bring-your-own domain, or both.
- A Let's Encrypt certificate, issued using ACME HTTP-01, for every approved
  public hostname.
- Site-scoped SFTP/SSH access from approved networks; no root access.
- Operating-system, Virtualmin, Nginx, PHP, and MariaDB maintenance by the
  hosting team.
- Nightly off-host backups and documented restoration procedures. Retention,
  recovery-point, and recovery-time commitments remain to be approved before
  production launch.
- Platform health and backup monitoring.

The baseline does not include:

- Website design, content creation, application development, or routine CMS
  content administration.
- A guarantee that the hosting team will maintain third-party themes, plugins,
  or custom application code.
- Domain registration fees or ownership of a requester's external domain.
- Authoritative DNS service on the Virtualmin host.
- Email boxes, email relaying, mailing lists, or DNS mail records.
- FTP, shell root access, dedicated IP addresses, or dedicated virtual
  machines.
- A web application firewall, automatic failover, or zero-downtime
  maintenance.

### 3.1 WordPress fleet visibility

Every service-managed WordPress site should be enrolled in a MainWP Dashboard
to provide the hosting team with a single pane of glass for inventory, health,
version, and update visibility. MainWP may also perform approved maintenance
actions, but enrollment does not by itself transfer responsibility for
application code, plugins, themes, or content from the site owner.

The MainWP Dashboard is a separate management-plane system and will not run on
the public Azure web-hosting VM. It will run on a campus RFC1918 subnet and will
be reachable only through approved private administrative access. The Dashboard
initiates outbound HTTPS connections through campus NAT to the MainWP Child
plugin on each public WordPress site:

```text
Campus private administrator
          |
          v
MainWP Dashboard on RFC1918 subnet
          |
   outbound NAT and HTTPS/443
          |
          v
Public WordPress site with MainWP Child
```

This design does not add VNet peering, VPN, private routing, or an inbound path
from the Azure host to campus networks. The Azure sites remain reachable through their
normal public HTTPS endpoints; MainWP needs no additional public port.

The Dashboard is a high-value administrative system because its connection
keys can authorize actions across many sites. It must be patched and backed up,
use MFA for administrators, restrict administrative membership, retain audit
logs, and have a documented recovery and key-rotation procedure.

During enrollment, the MainWP Child plugin's Unique Security ID (the security
code) is mandatory and must match the value entered in the approved Dashboard.
Each child site should use a dedicated MainWP administrator identity, verify its
HTTPS certificate, and be connected only to that Dashboard.

Keeping the Dashboard private protects its login and administration interface,
but it does not remove the MainWP Child plugin from each public WordPress site's
attack surface. The Child plugin and WordPress must remain patched and
monitored. MainWP extensions that require an unsolicited Internet callback to
the private Dashboard are outside the baseline unless separately reviewed.

## 4. Hostnames and Domains

### 4.1 Managed service hostname

Yes, the service should offer a hostname by default. The final parent domain
requires institutional DNS approval; an illustrative format is:

```text
<short-name>.sites.research.example.edu
```

The hosting team assigns the short name, avoids reserved or confusing names,
and records it in the service inventory. A managed hostname gives every site a
usable institutional address even when the research group does not own a
domain.

### 4.2 Bring-your-own domain

A requester may instead, or additionally, use a domain or subdomain controlled
by the research group or its DNS provider. Examples include:

```text
example.org
www.example.org
project.department.example.edu
```

The domain owner remains responsible for registration and for authorizing DNS
changes. Each approved name must resolve publicly to the service's static IPv4
address before HTTPS is issued and the site goes live. The hosting team will
provide the required record value and verify DNS, HTTP, and HTTPS.

One name is designated as the canonical hostname. Additional approved names are
normally configured as aliases that redirect to the canonical hostname instead
of serving duplicate URLs.

### 4.3 Explicit DNS for each site

Release 1 will not request or depend on wildcard DNS. Every managed service
hostname, bring-your-own hostname, and site alias requires an explicit public
DNS record as part of onboarding or migration. The normal record is:

```text
<approved-fqdn>.  A  <service-static-ipv4>
```

The DNS record is requested only after the name and site have been approved.
This makes the DNS change an intentional control point, provides a record of
each active name, and avoids sending arbitrary names in a service namespace to
the shared host. DNS records must be removed or redirected through the approved
retirement process when a site is decommissioned.

- Only inventoried and approved names are configured in Virtualmin.
- Requests with an unknown `Host` header are rejected or sent to a neutral
  service page; they must never fall through to another research site.
- The service inventory is the source of truth for assigned, reserved, and
  retired names.

### 4.4 Certificates

Let's Encrypt using ACME HTTP-01 is the standard certificate mechanism. The
hosting team requests a certificate through Virtualmin only after every
approved hostname resolves to the service and TCP 80 is publicly reachable.
Virtualmin then manages renewal for the configured site.

An institutional certificate service may exist at your university, but it is not the baseline for this shared service because the hosting team will not have ACME credentials with
certificate authority across the many institutional and externally managed DNS
names that sites may bring. HTTP-01 validates control through the individual
public website instead and therefore works consistently across those DNS
boundaries. An institutional certificate would require a documented exception,
including who owns issuance and renewal.

HTTP-01 cannot issue wildcard certificates, which is consistent with the
explicit per-site DNS and certificate model.

## 5. Why Sites Use Hostnames, Not URL Directories

The supported unit of hosting is a hostname, for example:

```text
lab-a.sites.research.example.edu
```

The service will not provision independent sites as URL paths such as:

```text
sites.research.example.edu/lab-a
```

Virtualmin does use a directory structure on disk. A top-level virtual server
normally stores content in `/home/<owner>/public_html`, and its sub-servers can
be stored below `/home/<owner>/domains/<hostname>/public_html`. That filesystem
layout does not make the sites URL-path based; Nginx still selects them by
hostname.

It is technically possible to put multiple applications in subdirectories of
one site's `public_html` directory or to configure a per-directory reverse
proxy. Those applications share the parent site's identity, configuration,
certificate, quota, access controls, and failure boundary. Many applications
also require special configuration to work correctly below a URL prefix.
Consequently, a path may be used by one site owner to organize components of
the same site, but it is not offered as an independently owned or supported
site.

### 5.1 Migrating legacy path-based sites

A common legacy pattern -- one IIS server publishing many group sites as URL paths -- is a migration case rather
than a reason to reproduce path-based tenancy in Virtualmin:

```text
https://research.eng.example.edu/<department-slug>/<group-slug>/
```

Each independently managed group site should receive a new canonical FQDN, for
example:

```text
https://<group-slug>.sites.research.example.edu/
```

The legacy path should then issue an HTTP `301 Moved Permanently` redirect to
the new hostname. Redirect rules should preserve the remainder of a deep link
and its query string where practical, so that, for example:

```text
https://research.eng.example.edu/dept-a/group-b/publications/item.html
```

redirects to:

```text
https://group-b.sites.research.example.edu/publications/item.html
```

The transition should work as follows:

1. Inventory every legacy path, owner, canonical target, and content status.
2. Create and validate the new hostname-based Virtualmin site.
3. Test the old-to-new mapping with a temporary redirect before making it
   permanent.
4. Enable the `301` redirect only after content, deep links, HTTPS, and
   application behavior have been verified.
5. Retain DNS and a valid certificate for `research.eng.example.edu` for as long
   as the compatibility redirects are promised.

During an incremental migration, `research.eng.example.edu` can continue to
point to IIS and IIS can redirect each completed path. DNS cannot send different
URL paths on the same hostname to different servers. When IIS is retired, the
whole legacy hostname can move to a service-owned, redirect-only Nginx virtual
server on this host (or to another lightweight redirect service) containing the
complete path-to-hostname map.

Virtualmin can technically serve directories or configure per-path reverse
proxies within one parent website. That would leave the migrated sites sharing
the parent website's ownership and operational boundary, and many applications
need special handling for URL prefixes, redirects, cookies, and absolute asset
paths. It is therefore not the supported migration target. The redirect-only
legacy virtual server is a compatibility layer, not a collection of independent
path-based tenants.

## 6. Request and Onboarding Process

A request should capture:

- Site title, purpose, sponsoring research activity, and expected lifetime.
- Accountable service owner and technical/content contacts.
- Requested managed short name and any bring-your-own names.
- Data classification and whether users submit or store data.
- Static/PHP requirements, database requirements, expected storage and traffic,
  and any scheduled jobs or external integrations.
- Requested site administrators and their university identities.
- Desired launch date and any migration source.

The hosting team will:

1. Review suitability, data classification, capacity, and naming.
2. Confirm the canonical hostname, aliases, DNS owner, and certificate names.
3. Create the Virtualmin virtual server with the approved feature set and
   quota.
4. Coordinate the explicit DNS record and verify public resolution.
5. Issue HTTPS, provide site-scoped access, and complete a functional check.
6. Add the owner, hostnames, DNS details, backup state, and lifecycle dates to
   the service inventory.

## 7. Responsibilities

| Area | Research Web Hosting | Site owner |
| --- | --- | --- |
| Infrastructure | Operate Azure VM, storage, network controls, and backups. | Provide funding or approval if a request needs exceptional capacity. |
| Platform | Patch and maintain the OS and baseline hosting stack. | Use only approved site-level software and report compatibility needs. |
| Application | Provide site-scoped runtime and access; operate the private MainWP Dashboard for WordPress fleet visibility. | Maintain application code, CMS core, plugins, themes, dependencies, and content unless another support agreement says otherwise. |
| Security | Harden and monitor the host; respond to platform incidents. | Protect credentials, remove stale administrators, remediate vulnerable site code, and report incidents promptly. |
| DNS and TLS | Provide DNS targets, coordinate the managed namespace, and automate certificate renewal. | Maintain domain registration and authorize records for bring-your-own domains. |
| Data | Back up supported site files, databases, and Virtualmin configuration. | Classify data, avoid unapproved sensitive data, and validate restored application behavior. |
| Lifecycle | Send review and retirement notices and preserve approved recovery points. | Keep contacts current, participate in periodic review, and approve renewal or retirement. |

## 8. Availability, Maintenance, and Recovery

The first release runs on one Azure VM and has no automatic failover. Planned
maintenance and an unexpected VM, disk, region, or application failure can make
sites unavailable. The pilot should therefore be described as best effort
until an uptime target, support hours, escalation path, recovery point objective
(RPO), and recovery time objective (RTO) are approved.

The hosting team will announce planned disruptive maintenance when practical,
monitor platform and backup health, and restore supported files and databases
from the available recovery points. Application-level repair after restoration
remains a shared effort with the site owner.

## 9. Security and Acceptable Use

- Sites are public by default. Authentication requirements must be reviewed
  before onboarding.
- The host must not store regulated or restricted research data without a
  separate review and written approval.
- Site owners must apply supported application updates promptly and remove
  abandoned code, accounts, plugins, and credentials.
- A compromised, abusive, materially vulnerable, or ownerless site may be
  isolated or suspended to protect the shared service.
- Sites must not send bulk mail, operate network services, mine cryptocurrency,
  or perform unrelated long-running computation.
- Shared hosting provides process and account separation, not the isolation of
  a dedicated VM. Higher-risk workloads will be directed to another platform.

## 10. Lifecycle and Retirement

Site ownership and need should be reviewed at least annually. A site must be
transferred to a new eligible service owner when the current owner leaves the university. If no owner accepts responsibility, the site will be retired after
notice.

The final policy must define notice periods, archival duration, domain and
redirect handling, and when backups are permanently deleted. Emergency
suspension for an active security or abuse incident does not require the normal
retirement notice period.

## 11. Current Decisions and Remaining Approvals

| Question | Current proposal |
| --- | --- |
| Who can request? | University faculty or staff for a sponsored research activity; students and external collaborators require a faculty/staff sponsor. |
| Will the service offer hostnames? | Yes. Every site can receive a name below a dedicated institutional service namespace. |
| Are bring-your-own domains supported? | Yes, with explicit owner-authorized DNS pointing each approved name to the service. |
| Wildcard or explicit DNS? | Explicit public DNS record for every managed hostname, bring-your-own hostname, and alias. No wildcard DNS is planned for release 1. |
| How are certificates issued? | Let's Encrypt through Virtualmin using ACME HTTP-01 after explicit DNS resolves to the service. An institutional certificate service is not the baseline because service-wide ACME authority is not available across all possible DNS zones. |
| Does every site still need an FQDN? | Yes. Every site is hostname-based, and every approved hostname or alias must have its own DNS record before activation. |
| Are independently managed path-based sites offered? | No. URL paths may be components of one site, not separate service tenants. Legacy path trees may be retained as redirect-only compatibility endpoints. |
| How are WordPress sites viewed centrally? | Enroll them in a MainWP Dashboard hosted on a campus RFC1918 subnet. The Dashboard reaches public child sites through outbound NAT and HTTPS; it is not hosted on or privately connected to the Azure VM. A MainWP Unique Security ID is required for every enrollment. |

Before production launch, the service owner must still approve:

- The exact managed parent domain.
- The request form, review authority, support channel, and escalation path.
- Default storage, database, administrator, and bandwidth limits.
- Supported PHP versions and the policy for CMS/application maintenance.
- MainWP Dashboard ownership, private hosting location, administrator policy,
  NAT egress identity, backup and recovery procedure, and authority to apply
  centralized updates.
- Site-administrator network access and authentication requirements.
- Backup retention, RPO, RTO, uptime language, and maintenance notice periods.
- Annual review, suspension, archival, and final-deletion timelines.

## 12. Technical References

- [Virtualmin: How to Create Virtual Servers](https://www.virtualmin.com/docs/getting-started/how-to-create-virtual-servers/)
- [Virtualmin: `create-domain`](https://www.virtualmin.com/docs/development/api-programs/create-domain/)
- [Virtualmin: Uploading and Editing Website Data](https://www.virtualmin.com/docs/server-components/uploading-and-editing-website-data/)
- [Virtualmin: `create-proxy`](https://www.virtualmin.com/docs/development/api-programs/create-proxy/)
- [MainWP: Introduction](https://docs.mainwp.com/getting-started/mainwp-introduction)
- [MainWP: Connection Security](https://docs.mainwp.com/advanced/miscellaneous/mainwp-connection-security)
- [MainWP: Ports and User Agent](https://mainwp.com/kb/what-port-and-user-agent-does-mainwp-use/)
- [Azure Virtualmin Research Web Host Specification](../templates/azure/host-specification.md)
