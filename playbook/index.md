# The Operator's Playbook

The [faculty guide](../guide/index.md) is one half of A Site of One's Own — the half your researchers read.  This playbook is the other half: what the campus team decides, deploys, and promises so those faculty sites have somewhere solid to live.

It descends from a real deployment at a US university, de-identified for publication.  The technical details are kept intact; the institutional specifics are yours to fill in.  Treat it as a working starting point from people who have run this, not as compliance advice.

## The pieces

- **[Service offering](service-offering.md)** — the service design: who can request a site, what the service includes and pointedly does not, hostname and DNS policy, certificates, responsibilities, lifecycle, and the decisions a service owner must approve before launch.  This is the document you adapt into your institution's own service description.
- **[Governance and launch gates](governance-and-launch-gates.md)** — the gap between "deployed" and "open for business": the decision register, the site inventory, backup proof, monitoring, runbooks, and the evidence your governance process will want back.
- **[Azure reference implementation](../templates/azure/README.md)** — a complete deployable template: Bicep, guarded first-boot bootstrap, backup and disk-growth tooling, deployment and verification scripts, and the [host specification](../templates/azure/host-specification.md) that serves as its architecture document and acceptance contract.

## The shape of the platform

One cloud VM running Virtualmin GPL (the open-source web hosting control panel) with Nginx, PHP-FPM, and MariaDB.  Each research site is a Virtualmin virtual server: its own Unix account, home directory, PHP-FPM pool, and database.  Sites get explicit DNS records (no wildcards), Let's Encrypt certificates, nightly off-host backups, and platform patching.  WordPress sites are enrolled in a MainWP dashboard hosted privately on campus, reaching the public sites outbound over HTTPS — a single pane of glass with no private route between campus and the host.

The design deliberately favors a small, understandable system over a high-availability platform: one VM, explicit names, boring components, guarded automation, and recovery through backups rather than redundancy.  For a fleet of research group brochure sites, that trade is the right one — and it is a trade, stated honestly in the documents rather than discovered during an outage.

Azure is the first reference implementation because that is where this was first built.  The service design is provider-agnostic; a Proxmox, OpenStack, or bare-metal implementation of the same contract would slot in beside it under `templates/`.  Contributions welcome.

## Where to start

Read the service offering to decide if this is the service you want to run.  Read the host specification to see exactly what you would be operating.  Then work the launch gates — they are the difference between hosting websites and running a service.
