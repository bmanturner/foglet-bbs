# Feature Research

**Domain:** SSH-first BBS operations surfaces and invite-driven community management
**Researched:** 2026-04-23
**Confidence:** MEDIUM-HIGH

## Feature Landscape

This milestone is not inventing a new kind of admin product. Terminal-native community systems usually expose compact user defaults, role-gated moderation and sysop tools, and lightweight social affordances directly from the main prompt. The common pattern is: short menus, fast actions, explicit access checks, and very little hidden automation.

For Foglet, the strongest fit is to keep each new surface narrow and operator-friendly:

- `Account` is for private identity and presentation defaults, not a sprawling profile hub.
- `Invites` is a reusable issuance/review surface shared across roles, with behavior driven by config.
- `Moderation` is a triage workspace tied to boards/users/actions, not a generic ticket system.
- `Sysop` is the live control room for site config, boards, limits, and user administration.
- `Oneliners` and main-menu polish should make the board feel inhabited without turning the main screen into noisy chat.

### Account & Preferences

#### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Edit private profile basics (`location`, `tagline`, optional real-name/contact fields already modeled) | Terminal communities usually let users tune the small bits of identity shown around the system | LOW | Keep this text-first and private-by-default; no public profile builder |
| Edit presentation defaults (`timezone`, `12h/24h`, theme) | Synchronet-style account defaults and modern BBS themes make per-user display settings standard | LOW | This is core for the main-menu timestamp requirement and future date rendering elsewhere |
| Toggle visibility-style preferences | Terminal boards commonly expose simple caller/chat visibility or paging preferences | LOW | Best milestone fit: last-callers visibility and similar low-risk toggles already reflected in the data model |
| Save changes immediately with clear success/error feedback | Text UIs need deterministic confirmation because users cannot inspect hidden state easily | LOW | Avoid multi-step wizards unless a field is sensitive |

#### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Live preview of timestamp formatting and theme selection | Makes a TUI settings screen feel concrete instead of abstract | LOW | Preview should reuse real main-menu formatting, not a fake sample |
| “Where this preference shows up” hints | Reduces confusion in text UIs where consequences are otherwise invisible | LOW | Example: “Main menu clock, thread timestamps” |
| Preference inheritance fallback | Lets sysops ship site defaults while users override only what they care about | MEDIUM | Good fit because Foglet already has runtime config + user prefs layering |

#### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Full social profile editing surface | Feels like “account management” should include everything | Pushes Foglet toward web-forum profile sprawl and moderation/privacy overhead | Keep account edits focused on identity basics and presentation defaults |
| Too many terminal/client knobs | Classic BBSes often exposed dozens of toggles | Produces confusing menus and permanent support burden | Limit milestone scope to preferences with visible product impact |
| Credential and SSH-key management in the same first pass | Users eventually expect it | Sensitive workflows are harder to get right in a TUI and are not required for this milestone goal | Defer to a later security-focused account phase |

### Invite Workflows

#### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Generate invite codes from a shared `INVITES` tab | Invite-only systems need a single obvious place to mint codes | MEDIUM | Reusable surface is the right milestone call; behavior changes by role/config, not by duplicated UI |
| Redeem invite during registration with real validation | Anything less makes invite-only mode fake | MEDIUM | This directly addresses the current stubbed validation concern in the codebase |
| Show status for each code (`active`, `used`, `revoked`, `expired`) | Operators need to understand whether a code is still usable without leaving the TUI | MEDIUM | One-line status summaries fit terminal workflows well |
| Record issuer, redemption target, timestamps, and remaining uses | Auditability is standard whenever invites gate access | MEDIUM | At minimum: created by, redeemed by, redeemed at, use count/max uses |
| Let authorized users revoke unused invites | Prevents stale or leaked codes from remaining valid forever | LOW | This is more useful than fancy invite discovery or search in v1.1 |

#### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Reusable single-use or multi-use codes | Covers both “invite one friend” and “staff can onboard a cohort” without new UX | MEDIUM | Keep model simple: one code, max uses, optional expiry |
| Optional note/purpose per invite | Helps moderators/sysops remember why a code exists | LOW | Especially useful in text UIs where context is otherwise lost |
| Role-scoped visibility in the same tab | Makes one screen usable in Account, Moderation, and Sysop without forking workflows | MEDIUM | Users see only their invites; sysops can see all; moderators depend on config |

#### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Referral trees / viral invite mechanics | Common in modern social products | Wrong fit for a BBS and adds abuse/analytics complexity | Stick to explicit issuer-created codes |
| Bulk invite campaigns and templated outbound messaging | Feels efficient for onboarding | Depends on mature email/delivery workflows and turns the TUI into a CRM | Defer until outbound messaging is a real product requirement |
| Hidden auto-approval rules on redemption | Seems convenient | Makes access control hard to reason about from the terminal | Show explicit rights, expiry, and redemption outcomes in the tab |

### Moderation Surfaces

#### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| A tabbed moderation workspace (`Queue`, `Log`, `Users`, `Sanctions`, `Boards`) | Terminal-native moderation usually groups actions by operator task, not by CRUD entity | MEDIUM | The milestone scaffold is correct; the tabs should be real destinations, not placeholders only |
| Review reported or moderated content with enough board/thread/user context to act | Mods need to decide without bouncing through multiple screens blindly | MEDIUM | Show target type, author, board, timestamp, and recent related actions |
| Apply a small set of sanctions (`warn`, `mute`, temporary restriction, account suspension path`) | Basic operator action set is expected in community software | MEDIUM | Keep sanctions explicit and logged; do not build a full policy engine yet |
| Inspect user history relevant to moderation | User lookup is standard in telnet/SSH-era systems and modern BBSes alike | MEDIUM | Minimum useful slice: role, status, recent sanctions, recent reports, invite provenance if relevant |
| Record every moderation action in a readable log | Text-first ops lives or dies on audit trails | LOW | Log should be browseable from the moderation surface, not hidden in server logs |

#### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Board-aware moderation boundaries | Matches classic sub-op / room-admin patterns instead of assuming all moderators are global | MEDIUM | This aligns with Foglet’s future board-scoped moderator direction |
| Queue actions with one-key shortcuts after selection | Fast, confident moderation is a core terminal advantage | MEDIUM | Only after the selected item has enough context on screen |
| Embedded invite tab for mods when config allows | Useful for trusted community growth without promoting everyone to sysop | MEDIUM | Good differentiator because it reuses the same invite workflow cleanly |

#### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Full case-management / ticketing system | Seems “professional” for moderation | Heavy workflow overhead and poor fit for a small SSH-first board | Keep queue + log + sanctions; defer appeals/case threads |
| AI-style automatic sanctions | Promises lower operator load | High false-positive risk and opaque behavior in a community product | Surface heuristics or flags later, but keep actions human-confirmed |
| Separate moderation UI for every object type | Feels precise | Creates navigation sprawl in a TUI | Use one workspace with object-type aware detail panels |

### Sysop Surfaces

#### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Site settings tab for runtime behavior (`registration_mode`, invite rights, oneliner policy, time display defaults, etc.) | Sysops expect to operate the BBS from inside the BBS | MEDIUM | Must respect the project’s runtime config philosophy and avoid DB-edit-only settings |
| Boards/categories lifecycle management | Classic BBSes treat board/room structure as a primary sysop responsibility | MEDIUM | Create, edit, archive, reorder, and tune posting/readability rules |
| User administration with role/status changes | Every reference system exposes some text-mode user editor or validation flow | MEDIUM | Minimum useful actions: find user, inspect account, change role/status, view invites/sanctions |
| System limits and operational controls | Terminal communities depend on configurable limits and toggles rather than ad hoc code edits | MEDIUM | Examples: invite generators, registration mode, oneliner length/rate rules, board defaults |
| Read-only system information panel | Sysops need live operational context without dropping to shell | LOW | Keep it observability-lite: counts, config state, maybe SSH/node/session snapshots |

#### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Consistent “change summary” previews before saving config | Prevents accidental destructive edits in a keyboard UI | MEDIUM | Especially important for registration and board permission changes |
| Fast board bootstrap/edit flows | Board creation is a frequent sysop job in community software | MEDIUM | Good future enhancement after the basic tab is stable |
| Unified user detail pane combining account, sanctions, invites, and board access | Reduces operator hopping between screens | MEDIUM | Valuable, but should be incremental rather than a hard dependency for launch |

#### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Full replacement for shell/admin tooling in one phase | Attractive for “all in the TUI” purity | Break-glass and deployment tasks still belong outside the app | Keep day-to-day operations in TUI; leave bootstrap and disaster recovery external |
| Deep nested config trees | Mirrors web admin panels | Terrible fit for terminal navigation and increases misconfiguration risk | Organize by a few high-signal tabs with concise forms |
| Per-setting bespoke screens | Feels safer | Causes menu explosion and slows common tasks | Group related settings with explicit validation and save feedback |

### Oneliners & Main-Menu Polish

#### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Render the main-menu clock using the user’s timezone and 12h/24h preference | Personal time rendering is the stated milestone goal and immediately visible polish | LOW | Refreshing every minute is sufficient; anything faster is noise |
| Show a small recent-oneliner or rotating oneliner area on the main menu | Terminal communities commonly use one-line social/status affordances to make the system feel alive | LOW | Keep it bounded and readable; one latest line or a short recent list is enough |
| Let users post a short oneliner from the main menu or a minimal entry flow | “Read-only shoutbox” feels incomplete in BBS culture | LOW | Fast entry matters more than rich formatting |
| Basic moderation controls for oneliners | Lightweight social spaces need fast cleanup | LOW | At minimum: delete/hide and maybe rate limit or cooldown |

#### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Contextual footer text like “posted by X, Y minutes ago” using user-local time | Makes the surface feel inhabited without adding chat complexity | LOW | Reuse the same timestamp preference formatter |
| Rotate recent oneliners on idle refresh | Adds life to the main menu while staying terminal-native | LOW | Do not animate aggressively; update on minute tick or explicit refresh |
| Presence-adjacent hints (`users online`, recent caller, latest oneliner) | Gives a stronger “arriving somewhere” feeling | MEDIUM | Good future expansion once presence is solid and not noisy |

#### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Full real-time shoutbox with constant push updates | Feels lively | Turns the main menu into chat spam and complicates focus/state in SSH clients | Keep oneliners append-only and refresh on sane intervals |
| Rich formatting, mentions, reactions, threads | Common modern social affordances | Too heavy for a one-line social strip and changes the product shape | Keep oneliners plain text and short |
| Putting too much ops data on the main menu | Feels “informative” | Makes the landing screen cluttered and intimidating | Reserve the main menu for welcome, clock, lightweight social cues, and primary navigation |

## Feature Dependencies

```text
User timezone/theme preferences
    -> main-menu personalized timestamp rendering

Invite code generation
    -> persisted invite model
    -> registration redemption validation
    -> runtime config for who may generate invites

Moderation queue/log/users/sanctions
    -> authorization model
    -> report/sanction persistence
    -> board-aware access boundaries

Sysop site/boards/limits/users
    -> runtime config writes
    -> board/category management flows
    -> shared invite tab permissions

Oneliners main-menu surface
    -> persisted oneliner write path
    -> bounded recent-oneliner read path
    -> moderation cleanup hooks
```

### Dependency Notes

- **Account preferences require immediate persistence:** timestamp and theme changes only feel real if the user sees them on the next render.
- **Invite UX requires real enforcement:** generation without registration redemption and consumption tracking should not ship.
- **Moderation tabs require auth before feature depth:** a shallow but correctly gated moderation surface is better than a deeper unsafe one.
- **Sysop config editing depends on clear validation boundaries:** terminal-native admin tools need explicit save/apply behavior to avoid confusion.
- **Oneliners depend on moderation hooks from day one:** even a lightweight shoutbox becomes operational work immediately.

## MVP Definition

### Launch With (v1.1 milestone)

- [ ] `Account`: edit timezone, 12h/24h, theme, and a small set of private profile fields
- [ ] `Invites`: generate, list, revoke, redeem, and audit invite codes through a shared tab
- [ ] `Moderation`: functional tabs for queue, log, user lookup, sanctions, and board-aware context
- [ ] `Sysop`: site config, board/category management, user role/status management, and limits toggles
- [ ] `Main menu`: user-localized timestamp plus bounded recent oneliners with quick posting

### Add After Validation (v1.x)

- [ ] Theme/timestamp previews and preference inheritance hints
- [ ] Multi-use invites with optional expiry/note fields if not included in first pass
- [ ] Moderator-scoped invite issuance when config enables it
- [ ] Richer user detail panes combining sanctions, invites, and activity
- [ ] Presence-adjacent main-menu signals like online count or recent caller info

### Future Consideration (v2+)

- [ ] Password/email/SSH-key self-service inside Account
- [ ] Invite campaign tooling, referral trees, or outbound onboarding flows
- [ ] Appeals, moderation cases, saved moderator views, or automation-assisted triage
- [ ] Advanced sysop observability and bulk-edit tools
- [ ] Real-time chat-like shoutbox behavior beyond simple oneliners

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Account presentation defaults | HIGH | LOW | P1 |
| Real invite enforcement + shared invite tab | HIGH | MEDIUM | P1 |
| Functional moderation workspace with logging | HIGH | MEDIUM | P1 |
| Sysop runtime config and board/user operations | HIGH | MEDIUM | P1 |
| Main-menu localized clock + basic oneliners | HIGH | LOW | P1 |
| Preview/hint polish in account/settings flows | MEDIUM | LOW | P2 |
| Moderator invite delegation | MEDIUM | MEDIUM | P2 |
| Unified rich operator detail panes | MEDIUM | MEDIUM | P2 |
| Presence-heavy menu embellishments | LOW-MEDIUM | MEDIUM | P3 |
| Campaign/referral/automation systems | LOW | HIGH | P3 |

**Priority key:**
- P1: Must have for this milestone
- P2: Strong follow-on once the core surfaces are stable
- P3: Defer unless the milestone grows substantially

## Terminal-Native Reference Patterns

| Area | Reference Pattern | Our Approach |
|------|-------------------|--------------|
| User defaults | Synchronet exposes a compact defaults screen for terminal behavior and per-user options | Use a compact Account screen with only settings that materially change Foglet’s UI |
| User and moderator ops | Synchronet and Citadel both expose text-mode user editing, validation, and access changes | Keep moderator/sysop actions keyboard-first with clear logs and explicit role checks |
| Board/room permissions | Synchronet sub-boards and Citadel rooms are access-scoped, sometimes invisible to unauthorized users | Preserve board-aware permissions and leave room for board-scoped moderators |
| New-user control | Mystic and Citadel both support tighter new-user gating, validation, or restricted initial access | Build invite-only flows as a first-class operator-controlled mode |
| Main-menu social polish | ENiGMA and classic BBS culture keep oneliners/rumours near the front door | Add a lightweight oneliner strip, not a full chat surface |

## Sources

- Synchronet User Documentation — user defaults, private one-line messaging, user interaction, chat toggles: https://www.synchro.net/docs/user.html (HIGH)
- Synchronet User Editor — text-mode user editing, quick validation, default inspection, restriction flags: https://www.synchro.net/docs/user_editor.html (HIGH)
- Synchronet Message Base docs — per-group/sub-board access, posting requirements, moderated posting, sub-op model: https://www.synchro.net/docs/message_section.html (HIGH)
- Synchronet Sysop docs — confirms the broader user-management and validation toolset: https://www.synchro.net/docs/sysop.html (MEDIUM-HIGH)
- Citadel System Administration Manual — new-user validation, disabling self-service signup, room invitation and kick-out flows, admin editing: https://www.citadel.org/system_administration_manual.html (HIGH)
- Mystic BBS feature list — moderators per message base, security profiles, online security-profile editing, new-user notifications: https://www.mysticbbs.com/features.html (MEDIUM-HIGH)
- Mystic Wiki, New User Settings 1 — password-gated new-user registration and initial security choices: https://wiki.mysticbbs.com/doku.php?id=config_newuser_settings1 (MEDIUM-HIGH)
- ENiGMA½ features and screenshots — customizable themes, new user application, built-in oneliner, rumour/oneliner affordance: https://enigma-bbs.github.io/features/ and https://enigma-bbs.github.io/screenshots/ (MEDIUM)

---
*Feature research for: SSH-first BBS operations surfaces and invites*
*Researched: 2026-04-23*
