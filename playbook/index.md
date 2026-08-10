# The Operator's Playbook

The [faculty guide](../guide/index.md) is one half of A Site of One's Own — the half your researchers read.  This playbook is the other half: what the campus team decides, deploys, and promises so those faculty sites have somewhere solid to live.

It descends from a real deployment at a US university, de-identified for publication.  The technical details are kept intact; the institutional specifics are yours to fill in.  Treat it as a working starting point from people who have run this, not as compliance advice.

One honest note before you build: you can also buy this.  [Reclaim Hosting](https://www.reclaimhosting.com/domain-of-ones-own/) — the people who grew Domain of One's Own from a campus experiment into a movement — will run an institutional version of essentially this model: an annual fee, your own virtual machine, their management layer, and years of experience behind it.  If you can get that budget approved, they are the proven path, and this playbook will still help you understand exactly what you're buying.  This project exists for the other outcome: the year the line item didn't survive, and your team decided to take the onus on itself.

## The case for a central service

The budget math here is strange, and worth naming before you make the pitch you will inevitably have to make.  Nobody blinks when a research group spends a few hundred dollars a year on hosting; forty groups doing it separately is invisible.  A single central line item for the same capability gets scrutinized — even at an entirely reasonable price.  And the corollary, familiar to anyone who has run this gauntlet: the same service built from an existing cloud subscription and staff time requires no purchase order at all.  Spend shaped like consumption and salary is invisible; spend shaped like a signature is not.  If you argue this service on hosting cost alone, you will lose to the invisible status quo every time.

Because the savings were never in the hosting.  They are in everything each group no longer has to do alone: choosing a platform, learning it, securing it, backing it up, and remembering it exists after the one student who ran it graduates.  Done well centrally, dozens of small, badly-maintained wheels become one well-maintained one — and even the wheel is not the point.  The value shows up as a consistent institutional presence instead of a patchwork of expired certificates and abandoned themes; as researchers who feel supported instead of left to fend for themselves; and as lab websites that help principal investigators recruit graduate students competitively in their fields — because a prospective student comparing labs sees the website before the science.

The cost of the platform is real and visible.  The value is larger, but only if the service is delivered well — which is precisely what the launch gates below are for.

## The pieces

- **[Service offering](service-offering.md)** — the service design: who can request a site, what the service includes and pointedly does not, hostname and DNS policy, certificates, responsibilities, lifecycle, and the decisions a service owner must approve before launch.  This is the document you adapt into your institution's own service description.
- **[Governance and launch gates](governance-and-launch-gates.md)** — the gap between "deployed" and "open for business": the decision register, the site inventory, backup proof, monitoring, runbooks, and the evidence your governance process will want back.
- **[Identity and access](identity-and-access.md)** — an optional single sign-on integration (worked example: Globus Auth and Globus Groups) that answers three questions forever: departed members can't log in, faculty add editors by adding people to a group, and a central login portal teleports users to the right dashboard without knowing their site's address.  Local WordPress accounts remain the default; this is the upgrade path.
- **[Azure reference implementation](../templates/azure/README.md)** — a complete deployable template: Bicep, guarded first-boot bootstrap, backup and disk-growth tooling, deployment and verification scripts, and the [host specification](../templates/azure/host-specification.md) that serves as its architecture document and acceptance contract.

## The shape of the platform

One cloud VM running Virtualmin GPL (the open-source web hosting control panel) with Nginx, PHP-FPM, and MariaDB.  Each research site is a Virtualmin virtual server: its own Unix account, home directory, PHP-FPM pool, and database.  Sites get explicit DNS records (no wildcards), Let's Encrypt certificates, nightly off-host backups, and platform patching.  WordPress sites are enrolled in a MainWP dashboard hosted privately on campus, reaching the public sites outbound over HTTPS — a single pane of glass with no private route between campus and the host.

The design deliberately favors a small, understandable system over a high-availability platform: one VM, explicit names, boring components, guarded automation, and recovery through backups rather than redundancy.  For a fleet of research group brochure sites, that trade is the right one — and it is a trade, stated honestly in the documents rather than discovered during an outage.

Azure is the first reference implementation because that is where this was first built.  The service design is provider-agnostic; a Proxmox, OpenStack, or bare-metal implementation of the same contract would slot in beside it under `templates/`.  Contributions welcome.

## Where to start

Read the service offering to decide if this is the service you want to run.  Read the host specification to see exactly what you would be operating.  Then work the launch gates — they are the difference between hosting websites and running a service.
