# A Site of One's Own

*A research-group website guide for universities — and the faculty they host.*

Every research group deserves a public front door it actually owns.  **A Site of One's Own** (SoOO, in the lineage of [Domain of One's Own](https://indieweb.org/Indieweb_for_Education)) is a complete, institution-agnostic package for running WordPress sites for university research groups — both halves of the service:

- **[The faculty guide](guide/index.md)** — what your researchers read: plain-language pages on how their site works and what to put on it.
- **[The operator's playbook](playbook/index.md)** — what your campus team runs: the service design, the governance launch gates, and a deployable Azure reference implementation (Virtualmin on a single hardened VM, with Bicep, bootstrap, backup, and verification tooling).

An institution can clone this repository and stand up the whole service: provision from the template, work the launch gates, localize the guide, open office hours.

The promise, and the closing line of the guide itself: launch is a morning; the habit is fifteen minutes a semester.

The audience is faculty and their delegates: plain language, every acronym explained on first use, no assumed WordPress knowledge.  Marketing for University Faculty 101.

## Structure

```
playbook/
  index.md                     Operator orientation — the platform's shape and where to start
  service-offering.md          Service design: eligibility, inclusions, DNS/TLS policy, lifecycle
  governance-and-launch-gates.md  From "deployed" to "open for business": decisions, inventory, proofs
templates/
  azure/
    README.md                  Validate / deploy / verify walkthrough
    host-specification.md      Authoritative architecture and acceptance contract
    acceptance-record-template.md  Fill-in record for each deployment
    main.bicep                 Full infrastructure template (VM, network, disk, backup storage)
    parameters/                Example parameter file
    bootstrap/                 Guarded first-boot Virtualmin install, disk growth, blob backup
    scripts/                   deploy.ps1 (what-if + deploy + bootstrap wait), verify.ps1
guide/
  index.md                     Start here — what the service is/isn't, how the guide is organized
  launch-checklist.md          Pre-launch walkthrough + the semester-review habit
  how-it-works/
    getting-started.md         Logging in, dashboard tour, first edit, revisions safety net
    pages-and-posts.md         The two content types and when to use each
    themes.md                  The four offered themes; why no "lab" themes
    plugins.md                 The catalog; why no self-install; backups/security already handled
    users-and-roles.md         Editor vs Administrator; roster members are not accounts
    images-and-media.md        Photo guidance, formats, copyright, consent, alt text
    accessibility.md           The built-in checker and the four habits
    writing-for-the-web.md     Front-loading, the smart outsider, the neighbor test
  site-pages/
    homepage.md                The ten-second test and the one-sentence formula
    research.md                3–6 projects, plain language, funding acknowledgments
    people.md                  Team Members plugin, role groupings, the alumni section
    publications.md            teachPress + BibTeX workflow; why no live feeds
    equipment.md               Facilities showcase; doubles as grant facilities-section draft
    principal-investigator.md  Third-person bio + CV as PDF
    join-us.md                 Recruiting page; the "mention which paper" email filter
    contact.md                 Form over posted email; mailing vs shipping address
    news.md                    Posts, cadence honesty, permission to skip the page
```

## Deliberately generic — localize at deployment

The pages carry no university names, no specific web addresses, no branding.  To make them yours:

- `[support email]` — appears in `guide/index.md`; add your help address (and office-hours details to match your support model).
- Login instructions in `getting-started.md` assume university single sign-on at `/wp-admin`; adjust if your setup differs.
- Search for `[` to find every bracketed placeholder.

## The service design behind the guide

The full operator documentation lives in [the playbook](playbook/index.md); the guide pages encode its faculty-visible consequences, decided during service planning:

- **One blessed path per need.**  Team Members for people pages, teachPress for publications — named in the guide because faculty see those names in their dashboard.  Fleet heterogeneity is the enemy; escape hatches exist but go undocumented.
- **A small set of generalist themes** (the WordPress default, Astra, Kadence, GeneratePress), all maintained by large teams, all updated centrally.  No premium "lab" themes: page-builder lock-in, per-site licensing, and single-developer bus factor make them wrong for a fleet — and the guide explains that case in faculty-friendly terms.
- **Security and backups live at the platform layer**, not in per-site plugins.  The guide says so out loud (`how-it-works/plugins.md`) so the Wordfence question gets answered before it is asked.  A security scanner remains an on-demand incident-response tool, not a resident.
- **Content outlives members.**  Publications import into the site rather than feeding live from personal accounts; rosters are content entries, not user accounts.  Sites must survive every graduation.
- **Sites start from templates.**  The guide assumes new sites arrive with draft versions of the core pages, so faculty fill in blanks rather than face an empty screen.
- Written generically where a service still has choices to make: the contact form plugin and the accessibility checker are described by role, not by name, so either decision slots in without guide edits.

## Conventions

- Cross-links between pages are relative `.md` links; re-point them to page addresses when the content moves into WordPress.
- One paragraph per line (no hard wraps), so pages paste cleanly into the block editor.
- Double spaces after periods, as is right and proper.

## Provenance

Drafted by Claude (Anthropic's Fable 5) in extended collaboration with [Andrew Marx](https://github.com/atmarx), who supplied the service design, the taste, and the cutting-room floor.  Shared in the spirit of the guide itself: own your stuff, and show your seams.
