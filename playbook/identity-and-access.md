# Identity and Access

This page is optional.  The platform works without it: Virtualmin installs WordPress with ordinary local accounts — a username and password per person, per site — and for a small fleet with attentive owners that is genuinely fine.  Everything else in this playbook assumes nothing more.

But local accounts accumulate three quiet problems as a fleet grows, and this page documents one integration that solves all three at once.  Read it as a pattern with a worked example, not a requirement.

## The three problems

**The leaving problem.**  A student graduates, or a staff member moves on.  Their campus account is disabled the way campus accounts are — centrally, promptly, automatically.  Their WordPress password on the lab site keeps working, because nobody remembers to remove it, because removal requires someone to remember it across every site they ever touched.  Ask any web team how many active accounts belong to people who left years ago.  Then don't ask them to check, because checking is the work nobody has time for.

**The delegation problem.**  A faculty member wants their new student to edit the site.  With local accounts that means creating a user, inventing a password, choosing a role, and emailing credentials — a small task that somehow still generates a support ticket.

**The which-site problem.**  A perfectly capable editor simply does not remember their site's address, or that the login page is at `/wp-admin`.  They should not have to.

## The shape of the solution

Single sign-on (SSO) against the campus identity provider (IdP — the service that answers "who is this person?" for your institution) solves the leaving problem: when the campus account dies, the site login dies with it.  Group-based authorization solves the delegation problem: adding an editor becomes adding a person to a group, no passwords involved.  And once a central service knows who someone is and which groups they belong to, a login portal that lists their sites solves the which-site problem for free.

The worked example below uses [Globus](https://www.globus.org/) — specifically Globus Auth (an OpenID Connect provider) and Globus Groups — for reasons that will resonate at research institutions:

- Many research universities already run Globus for data transfer, so the accounts, the campus IdP federation (via InCommon/CILogon), and the operational familiarity already exist.
- Registering OAuth clients at [developers.globus.org](https://developers.globus.org/) requires no ticket to your central identity team.  If your institution's app-registration process involves a committee, this matters more than any technical property.
- Group membership can be managed by the faculty themselves in the Globus web app, including inviting people by email.
- The recipe is portable: any campus in the InCommon federation gets the same integration, which is why it can live in a public playbook at all.

If you don't have Globus, the pattern ports to any OpenID Connect provider — see [the alternatives](#if-you-dont-have-globus) below.

## What faculty experience

The pitch to your service owner is three sentences, each answering a question you will otherwise answer forever:

- *Someone left the group — can they still edit the site?*  No.  Their campus account was disabled, so their site login stopped working, automatically, within hours.
- *How do I add my new student as an editor?*  Add them to your group.  That's the whole procedure — they log in with their campus account and the site already knows their role.
- *I don't remember our site's address.*  Go to the one login page, sign in, and every site you can edit is a button.  Click it and you land in the right dashboard.

## The pieces

### One stock plugin, one small layer of your own

Each WordPress site runs the [OpenID Connect Generic Client](https://wordpress.org/plugins/daggerhart-openid-connect-generic/) plugin — stock, from the WordPress.org directory, auto-updated by its maintainers — pointed at Globus Auth's endpoints.

Resist the temptation to fork the plugin to add your provider-specific logic.  An OpenID Connect client is security-critical code (state validation, nonce checks, token verification), and a fork means merging every upstream security release into your diverged copy, forever, across a fleet — the same bus-factor trap this project's own guide warns faculty about with boutique themes.  The plugin publishes an extensive filter API precisely so you don't have to.

Your provider-specific logic lives in a **must-use plugin** (mu-plugin): a single PHP file in `wp-content/mu-plugins/`, shipped by the platform template.  Must-use plugins load always, appear in no dashboard, and cannot be deactivated by a site administrator — which is exactly the property you want for an enforcement layer.  The people a control governs should not hold its off switch.

The mu-plugin does two jobs through the stock plugin's filters:

- **Pin authentication to the campus identity** — via the `openid-connect-generic-auth-url` filter, append Globus Auth's `session_required_single_domain=<your campus domain>` parameter to the authorization request.  Globus accounts can have multiple linked identities (a personal Google account, an ORCID); this parameter forces authentication through the campus IdP specifically, so the login that succeeds is always the one the campus can revoke.  Add `session_required_mfa=true` if you want multi-factor authentication enforced at the identity layer without touching WordPress.
- **Map groups to roles** — Globus Auth's OpenID Connect claims include a stable identity UUID (`sub`), username, and email, but *not* group memberships; those live behind the separate Globus Groups API.  So on each login, the mu-plugin takes the `sub` from the claim and asks the Groups API whether that identity is an active member of this site's admins or editors group, using a platform service credential that sits as a manager on every site group.  Member of the admins group: WordPress Administrator.  Editors group: Editor.  Neither: login denied — which is also how someone removed from a group loses access at their next session, not at someone's eventual remembering.

Keep the plugin's session length short — hours, not the WordPress default of days — so the lockout window after an offboarding or a group removal is tight.

### Two groups per site, faculty as managers

Each site gets two Globus Groups: `<site>-admins` and `<site>-editors`.  Record their UUIDs in your site inventory (see [governance](governance-and-launch-gates.md)) — the inventory is already your source of truth for what exists; these are two more columns.

Make the principal investigator (PI) a *manager* of both groups.  Managers can add and remove members and send email invitations from the Globus web app — which means the delegation problem is now solved by the faculty member, self-service, without a ticket.  Your platform service credential is an administrator on every group so the mu-plugin can check memberships and your provisioning can create them.

### Per-site OAuth clients

Register one confidential OpenID Connect client per site rather than one shared client with many redirect addresses.  A compromised site then leaks only its own client secret, not the fleet's — the same blast-radius reasoning behind the platform's per-site Unix accounts and databases.

### Break-glass accounts

Keep one local WordPress administrator account per site, outside the SSO path, so an identity-provider outage cannot lock the operator out.  Generate the password at site creation and escrow it — and the client secret — in a shared password-manager vault the platform team controls.  That vault is now fleet crown jewels *and* the first page of your recovery runbook; give it a line in the decision register (who holds access, how it's reviewed).

The management plane is unaffected either way: MainWP children connect on their own keys, and `wp` command-line administration runs as the site's Unix user on the host, below WordPress authentication entirely.

### Provisioning at site creation

Every piece above is scriptable, which means the whole identity story can be provisioned by the same automation that creates the site.  Virtualmin's post-creation hook (the same mechanism that installs WordPress from your server template) runs one script that:

1. Registers the site's OAuth client via the Globus Auth API and captures the secret.
2. Creates the two groups via the Groups API, adds the PI as manager, adds the platform credential as administrator.
3. Configures the stock plugin via the WordPress command-line tool, run as the site's own user: `su <siteuser> -c 'wp --path=/home/<siteuser>/public_html option update ...'`.
4. Drops the mu-plugin into `wp-content/mu-plugins/`.
5. Creates the break-glass administrator and escrows its password and the client secret in the vault.
6. Appends the group UUIDs to the site inventory.

A site is born with its identity wiring complete, and "manually setting up each site" collapses into one step of the site-creation runbook.

### The launcher

The icing: a small portal at one memorable address, so nobody needs to know their site's URL.

It's a confidential OAuth client of its own — a couple hundred lines of Flask or similar, hostable as one more virtual server on the same VM.  A user signs in with Globus (which means their campus IdP), the portal requests the Groups API's `view_my_groups_and_memberships` scope, intersects the user's groups with the site inventory's group-UUID columns, and renders a button per site.  Exactly one match — the common case — can redirect straight through.  Clicking a button lands on that site's `/wp-admin`; the site's own OpenID Connect flow completes silently because the Globus session is already warm.  The portal never mints WordPress sessions itself — it just makes the per-site handshake invisible and answers the which-site problem with a page.

There's a quiet governance benefit hiding here: the portal only works if the site inventory is accurate, which turns the inventory from a compliance artifact into a load-bearing one.  Systems that break visibly when neglected get maintained.

## If you don't have Globus

The pattern — stock OpenID Connect plugin, a non-deactivatable mapping layer you own, groups per site, escrowed break-glass accounts, provisioning at creation — ports to any provider:

- **Microsoft Entra ID** (or any campus IdP with OpenID Connect): works with the same stock plugin, and Entra can include group claims directly in the token, which removes the need for a separate groups-API call.  The trade: app registrations and group management typically run through your central identity team, per site, at their pace.
- **[CILogon](https://www.cilogon.org/)** directly, if your institution subscribes: campus federation without the Globus layer.
- **Nothing at all**: local WordPress accounts, an offboarding step in your site-review checklist, and honesty in the decision register that the leaving problem is handled by process rather than by architecture.  For a five-site fleet, that can be the right answer.

## If you adopt this, touch the guide

Two faculty-guide pages assume the default local-account world and should be revised in your localized copy: `guide/how-it-works/users-and-roles.md` (adding an editor becomes "add them to your group") and `guide/how-it-works/getting-started.md` (logging in becomes "use the portal, or your campus credentials at the site").  The guide's underlying principle survives untouched: roster members are content, not accounts, and sites must outlive every graduation — this integration just makes the second half automatic.

## Decisions this adds to the register

- Identity provider and the pinned campus domain; whether multi-factor authentication is required, and for whom.
- Session length and re-authentication cadence.
- Group naming convention and who may manage memberships.
- Vault location, access roster, and review cadence for break-glass credentials and client secrets.
- Portal hostname, its owner, and its place in the site inventory.
- The fallback path when the identity provider is unavailable.
