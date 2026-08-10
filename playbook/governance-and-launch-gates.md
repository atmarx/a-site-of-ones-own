# Governance and Launch Gates

A deployed host is not a service.  Between "the Bicep ran" and "faculty can request sites" sits a set of institutional decisions, records, and proofs — and skipping them is how a hosting platform becomes orphaned operational debt three years later.  This page is the checklist for that gap, adapted from a real governance review of this platform.

Static validation — the Bicep builds, the scripts parse — establishes static validity only.  It does not establish production readiness or successful service operation.  Everything below is about closing that distance.

## The Authority Boundary

Your institution's IT-governance documentation owns durable service scope, eligibility, ownership, review triggers, lifecycle, and required control outcomes.  The implementation (this repository's templates, plus your operational records) owns exact topology, resource names, deployment parameters, verification, runbooks, and evidence.

Keep the boundary clean in both directions.  Do not copy secrets, private keys, private network ranges, detailed host inventory, administrative endpoints, or raw recovery topology into governance documents.  Return stable evidence references and sanitized outcome summaries instead.

A typical governance artifact set for a service like this:

- A platform profile (what the service is and its control posture).
- A service-use guideline (who may use it, for what).
- A stewardship model (roles and responsibilities).
- Request, onboarding, and migration procedures.
- Review, suspension, and retirement procedures.
- A backup, restore, and recovery-validation procedure.
- A controls mapping and an intake template.

The [service offering](service-offering.md) in this playbook is the seed for several of these.

## Priority 0: Resolve Before Customer Onboarding

### Repository and key hygiene

Keep the implementation under version control from day one, and treat key custody as a control, not a convention.  Ignore rules are not custody controls: confirm no private key has ever entered history, store keys in approved credential storage, rotate any key whose exposure is uncertain, and never ingest private key material into Bicep, parameters, cloud-init, deployment output, documentation, or test fixtures.

### Honest status language

Keep infrastructure status and service status separate, and say which one you mean.  "Infrastructure baseline implemented; service not production-approved" is the honest phrasing until every launch gate below is closed.  A template that deployed cleanly is not a service anyone should be onboarded to.

### A service decision register

Create a versioned, non-secret record of approved production values and who approved them:

- Accountable service owner, technical owner, budget owner, support channel, and escalation route.
- Cloud subscription, region, resource group and naming rules, and cost-allocation tags.
- Managed parent domain, DNS request authority, and domain-inventory owner.
- Supported PHP and application versions, default site storage and database quotas, administrator limits, and traffic expectations.
- Administrator identity, MFA, approved access sources, access review, emergency access, and offboarding.
- Maintenance cadence, notice period, support hours, availability language, RPO, RTO, and backup retention.
- Update-management maintenance window, update classifications, reboot policy, and exception path.
- Central logging destination, log retention, monitoring alerts, vulnerability scanning, and response targets.
- MainWP owner, private hosting location, administrators, MFA, stable outbound identity, backup, recovery, audit logging, connection-key rotation, and update authority.
- Annual review, non-emergency remediation, suspension, archival, redirect, final-backup, and deletion timelines.

No secrets and no raw privileged review material belong in the register.

### An authoritative site and domain inventory

Create a versioned schema or operational integration covering, at minimum:

- Stable site ID, title, purpose, state, site owner, technical contact, and review date.
- Canonical hostname, aliases, DNS owner/provider, expected target, certificate state, and redirect state.
- Data classification, authentication, user-submitted-data flag, approved application type, runtime, quota, and exception references.
- Site administrators, MainWP enrollment and authority, backup state, last successful backup, and restore-test reference.
- Onboarding, launch, renewal, suspension, owner-transfer, retirement, archive, redirect-expiration, and deletion dates.

The inventory is the source of truth for names.  Provisioning and verification should reject or flag a Virtualmin domain or served hostname that is absent from it, and unknown hostnames must never fall through to another tenant's site.

### Reconcile backup retention, then prove recovery

The [host specification](../templates/azure/host-specification.md) proposes 14 daily, 8 weekly, and 12 monthly recovery points.  The template's Blob lifecycle policy, as shipped, deletes base blobs after 400 days and versions after 30 days — it does not implement those tiers.  Parameterize or otherwise implement the retention schedule your service owner approves, and document how pruning preserves the intended daily, weekly, and monthly points.

Then prove recovery, before the first customer:

1. Run a real site-and-database backup using managed identity.
2. Verify the uploaded objects and the backup-failure signal.
3. Restore a representative PHP site and database to an isolated target.
4. Record elapsed time, achieved recovery point, application validation, defects, and remediation.
5. Test the clean-host recovery path without inadvertently formatting or overwriting retained data.

An enabled backup timer is useful evidence.  It is not proof that a usable backup exists.

### Monitoring, logging, and incident routing

The specification names the desired monitoring; the template does not implement the complete operational path.  Add or integrate:

- Alerts for host unavailability, resource exhaustion, storage pressure and latency, public HTTP/HTTPS failure, certificate expiry, bootstrap failure, backup failure or staleness, and unexpected infrastructure or network drift.
- Approved forwarding and retention for authentication, administrative, web, database, backup, and security-relevant logs.
- Vulnerability scanning and severity-based remediation targets for the host, Virtualmin, WordPress, plugins, themes, and the MainWP management plane.
- A site-isolation and incident-escalation runbook that preserves evidence and invokes the institutional security-incident process.

Exercise at least one alert and the isolation handoff before launch.

## Priority 1: Complete the Operable Service

### Build the MainWP management plane, or defer it explicitly

MainWP is part of the proposed service but is not implemented by the Azure template.  Either create a separately governed implementation and runbook, or record a launch decision to defer it.  Before enablement, verify private administration, MFA, least privilege, audit logs, backup and recovery, patching, connection-key rotation, dedicated child-site identities, required Unique Security IDs, certificate verification, and explicit fleet-update authority.

### Operational runbooks

Create implementation-local runbooks for:

- Site creation and acceptance testing.
- Explicit DNS and certificate activation, and certificate renewal failure.
- Legacy path-to-hostname migration and redirect validation.
- Runtime and storage quota changes.
- Site-level backup and restore.
- Operating-system failure with retained data.
- Clean rebuild after host loss or compromise.
- Regional recovery and coordinated DNS changes.
- Administrator onboarding, review, emergency access, and offboarding.
- Vulnerable or compromised site isolation.
- Renewal, owner transfer, suspension, retirement, redirect expiration, and deletion.

Exact commands, identifiers, and topology belong in these runbooks — not in governance documents, and not in a public repository.

### Extended verification

Preserve the template's infrastructure checks and add evidence for: unknown-hostname isolation; cross-site filesystem, runtime, database, and credential separation; enforced default quotas; HTTPS issuance and renewal monitoring; Webmin MFA and the current administrator roster; backup execution, freshness, object integrity, and failure alerting; representative restoration; inventory-to-Virtualmin and inventory-to-DNS reconciliation; MainWP connection rejection when required controls are missing; and drift checks for routes, ingress, unnecessary listeners, role assignments, resource locks, and retention policies.

## Evidence to Return to Governance

| Evidence | Governance consumer |
|---|---|
| Approved decision register and role assignments | Platform profile and stewardship model |
| Sanitized infrastructure acceptance summary | Control profile |
| Inventory schema and reconciliation result | Platform profile, onboarding, and lifecycle procedures |
| Administrator MFA, review, and offboarding evidence | Control profile |
| Monitoring/logging source inventory and a tested alert | Control profile |
| Backup success, retention configuration, and isolated restore record | Backup/restore procedure and control profile |
| MainWP operating decision and acceptance evidence | Platform profile and stewardship model |
| Incident-isolation exercise result | Control profile |
| First site onboarding record, secrets removed | Onboarding procedure |
| First annual review or retirement record | Lifecycle procedure |

Return stable references and sanitized outcomes.  Do not return raw logs, secrets, addresses, credentials, private routes, or detailed host inventory.

## Production Readiness Exit Criteria

The service is ready for customer onboarding when:

- The service owner approves every launch gate and residual-risk decision.
- Source control and key custody are safe.
- The domain and site inventory is authoritative and reconciled.
- Administrator identity, MFA, access review, and offboarding are operational.
- Monitoring, logging, vulnerability response, and incident routing are tested.
- Approved retention is implemented and a representative isolated restore has succeeded.
- MainWP is either production-ready under an approved operating model or explicitly deferred.
- Site intake, onboarding, migration, renewal, suspension, retirement, and recovery runbooks are usable by another operator.
- Governance receives the sanitized evidence references needed to move the service documents through review.

That last clause is the quiet test of the whole list: could another operator, holding only these documents, run the service you built?  When the answer is yes, open the doors.
