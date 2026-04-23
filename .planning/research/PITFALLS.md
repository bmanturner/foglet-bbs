# Pitfalls Research

**Domain:** Operations surfaces, invites, moderation, preferences, and oneliners in an SSH-first Phoenix/OTP/Raxol BBS
**Researched:** 2026-04-23
**Confidence:** HIGH

## Critical Pitfalls

### Pitfall 1: Consuming invites outside the user-creation transaction

**What goes wrong:**
`invite_only` looks wired in the TUI, but invite enforcement is fake or lossy. Codes get accepted before a user exists, codes get burned on a failed registration, or the same code can be reused because user creation never records the consumption.

**Why it happens:**
The current seam is already dangerous: [`lib/foglet_bbs/tui/screens/register.ex`](../../lib/foglet_bbs/tui/screens/register.ex) validates invites in the wizard step, and [`lib/foglet_bbs/accounts.ex`](../../lib/foglet_bbs/accounts.ex) `register_user/1` ignores `invite_code` entirely. The existing fallback in `valid_invite_code?/1` accepts any non-empty alphanumeric code when invite persistence is absent.

**How to avoid:**
- Add a real invite persistence layer before enabling `registration_mode = "invite_only"`.
- Make invite redemption happen in the same `Repo.transact/1` that inserts the user.
- Lock the invite row while redeeming so two concurrent registrations cannot consume the same code.
- Record `generated_by_id`, `consumed_by_id`, `consumed_at`, `revoked_at`, and any scope/usage limits on the invite record.
- Keep the invite-step UI as syntax/lookup only; do not mutate state there.
- Reject registration if the transaction cannot both create the user and mark the invite consumed.

**Warning signs:**
- `invite_only` is enabled and arbitrary strings still pass registration.
- Invite counts in the UI do not match DB state.
- Consumed invites have no linked user.
- Failed registrations reduce available invites.

**Phase to address:**
Phase 2: Invite persistence and registration enforcement.

---

### Pitfall 2: Treating authorization as a screen concern

**What goes wrong:**
Moderator/sysop actions look hidden from regular users, but any future caller that reaches the domain function can still lock threads, move threads, delete content, or edit operational state without a policy check.

**Why it happens:**
The current domain APIs are not actor-aware. [`lib/foglet_bbs/threads.ex`](../../lib/foglet_bbs/threads.ex) exposes `lock_thread/1`, `sticky_thread/1`, `move_thread/2`, and `delete_thread/1` without an acting user or scope check. `.planning/codebase/CONCERNS.md` already flags that TUI authz is missing.

**How to avoid:**
- Add a single authorization layer before adding mod/sysop controls.
- Require actor-aware APIs such as `lock_thread(actor, thread)` and `update_config(actor, key, value)`.
- Centralize policy in one module so SSH TUI, Mix tasks, and future channels use the same rules.
- Return explicit `{:error, :forbidden}` results and test them.
- Log successful moderation actions in an append-only mod-action trail.

**Warning signs:**
- Role checks only appear in `render/1` or tab visibility code.
- `current_user.role` is read directly in screen modules to decide whether an action is allowed.
- Domain functions can be called without an actor.

**Phase to address:**
Phase 1: Authorization and policy foundation.

---

### Pitfall 3: Hard-coding global moderator semantics into v1.1 surfaces

**What goes wrong:**
The first moderation screen works only for global mods, then becomes expensive to unwind when board-scoped moderators arrive. Tabs, queries, and sanctions all assume `role == :mod` means global reach.

**Why it happens:**
The current user model has `:role`, but the data model already points toward scoped moderation through `board_moderators`. [`docs/DATA_MODEL.md`](../../docs/DATA_MODEL.md) explicitly models board-level moderator assignments, while `.planning/PROJECT.md` says v1.1 must leave room for future board-scoped moderation.

**How to avoid:**
- Model permissions as capability plus scope, not just role.
- Make moderation queries board-aware from day one, even if sysops currently see everything.
- Keep global sysop powers separate from board-scoped moderator powers.
- Design tab data providers so a moderator can be shown only the boards, reports, and users they are allowed to act on.
- Include scope in mod-action metadata.

**Warning signs:**
- Moderation screens query all reports or all boards for every `:mod`.
- A moderator can issue sanctions unrelated to any moderated board.
- Board assignment tables exist in docs/migrations, but no policy code reads them.

**Phase to address:**
Phase 1: Authorization and policy foundation, then carried into Phase 4 moderation surface work.

---

### Pitfall 4: Session-context drift after account or sysop changes

**What goes wrong:**
The user changes theme or time display preferences, or the sysop changes invite/config rules, but the current SSH session keeps using stale values. The UI and the action path disagree about what is actually enabled.

**Why it happens:**
This repo snapshots operational context at connection time. [`lib/foglet_bbs/ssh/cli_handler.ex`](../../lib/foglet_bbs/ssh/cli_handler.ex) builds `session_context` once with `registration_mode`, `max_post_length`, and `theme: Foglet.TUI.Theme.default()`. [`lib/foglet_bbs/tui/app.ex`](../../lib/foglet_bbs/tui/app.ex) `{:promote_session, user}` does not refresh `session_context`. The account profile path updates the user row, not the in-memory TUI snapshot.

**How to avoid:**
- Decide which values are session snapshots and which must be read live on every action.
- After saving account preferences, refresh `current_user` and the derived `session_context` fields in the active session.
- After sysop config writes, invalidate config cache and refresh any connected operational screens that depend on it.
- Do not rely on login-time defaults for theme or registration-mode-sensitive visibility.
- Add tests for “save preference without reconnect” and “sysop flips config while surface is open.”

**Warning signs:**
- Theme changes do not apply until reconnect.
- INVITES tab visibility is wrong after config edits.
- Main menu clock keeps the old format after a preference save.
- Screen render logic and submit logic read different sources of truth.

**Phase to address:**
Phase 3: Account preferences and session refresh.

---

### Pitfall 5: Adding timezone and 12h/24h preferences without a real time contract

**What goes wrong:**
Main-menu timestamps render incorrectly, fall back silently to UTC, or crash for users with invalid timezones. DST boundaries behave inconsistently, and later timestamp surfaces format time differently than the main menu.

**Why it happens:**
The project stores UTC timestamps correctly, but there is no current timezone contract in the user schema beyond a generic `preferences` map, and I could not find a configured timezone database in `mix.exs`, `config/`, or `lib/`. Without that, “timezone preference” is easy to fake in one screen and impossible to trust everywhere else.

**How to avoid:**
- Define the preference schema up front: an IANA timezone name plus a `12h`/`24h` enum.
- Validate preference values before saving; never trust raw map writes into `preferences`.
- Add a single formatter module for all user-facing timestamps.
- Decide explicitly whether this milestone supports full timezone conversion or only UTC plus formatting preference.
- If full timezone conversion is required, wire and test the timezone database as a deliberate stack decision instead of hiding it inside a screen.

**Warning signs:**
- Free-form timezone strings are stored in `preferences`.
- Tests use the machine local timezone.
- Main menu renders user-local time but post metadata still shows raw UTC or relative time from another codepath.

**Phase to address:**
Phase 3: Account preferences and session refresh.

---

### Pitfall 6: Letting TUI surface sprawl outrun the current screen architecture

**What goes wrong:**
Account, moderation, and sysop screens ship as large one-off modules with duplicated tabs, duplicated state plumbing, and more `do_update/2` branches. Small fixes then require editing multiple surfaces, and navigation bugs multiply.

**Why it happens:**
The current TUI has only a handful of screens and a large central dispatcher in [`lib/foglet_bbs/tui/app.ex`](../../lib/foglet_bbs/tui/app.ex). [`lib/foglet_bbs/tui/screens/main_menu.ex`](../../lib/foglet_bbs/tui/screens/main_menu.ex) is intentionally stateless today, and `.planning/PROJECT.md` explicitly calls for shared invite-tab primitives rather than forks.

**How to avoid:**
- Build reusable tab, table, and form widgets first, then compose surfaces from them.
- Keep one invite state machine that can be embedded into Account, Moderation, and Sysop.
- Create explicit screen-state structs for complex new surfaces instead of ad hoc maps.
- Keep command names domain-shaped rather than screen-shaped where the behavior is shared.
- Add tests for tab navigation and state retention before adding per-tab business logic.

**Warning signs:**
- Three separate invite forms appear in the diff.
- `App.do_update/2` gains near-identical clauses for account invites, mod invites, and sysop invites.
- Main menu starts accumulating unrelated modal and form state.

**Phase to address:**
Phase 4: Moderation/sysop/account surface scaffolding.

---

### Pitfall 7: Exposing sysop config controls for keys the runtime cannot actually honor

**What goes wrong:**
The sysop screen presents toggles for themes, oneliner limits, retention days, or other settings that are only aspirational in docs. The UI either crashes on save, writes unschematized rows, or implies the setting is active when no runtime code reads it.

**Why it happens:**
[`lib/foglet_bbs/config/schema.ex`](../../lib/foglet_bbs/config/schema.ex) intentionally schematizes only six keys. [`docs/DATA_MODEL.md`](../../docs/DATA_MODEL.md) lists additional aspirational keys like `themes_available`, `oneliners_max_length`, and `last_callers_retention_days`, but those are not live config today.

**How to avoid:**
- Only expose keys that already have schema entries, typed accessors, and runtime consumers.
- Add config support in this order: schema entry, accessor, seed, runtime consumer, then UI.
- Render future settings as read-only placeholders if the navigation scaffold needs them.
- Keep operational labels tied to canonical config keys to avoid rename drift.

**Warning signs:**
- Screen modules contain raw string keys instead of typed accessors.
- `Config.put!` is being bypassed for convenience.
- Sysop UI claims a limit changed, but runtime behavior is unchanged until code deploy.

**Phase to address:**
Phase 4: Sysop configuration surface.

---

### Pitfall 8: Building oneliners as UI garnish instead of moderated domain data

**What goes wrong:**
The shoutbox feels live in a demo but loses data on restart, cannot be moderated properly, leaks hidden entries from cache, or becomes a spam funnel on the main menu.

**Why it happens:**
The architecture and data-model docs expect DB-first writes, a ring buffer cache, PubSub fanout, and moderation hooks, but the current application supervision tree does not yet start any oneliners process and no implementation exists in `lib/`. This makes “quick UI-first” scaffolding especially risky.

**How to avoid:**
- Implement `oneliners` as a proper context with DB persistence first.
- Treat the ring buffer as a cache only; rebuild it from DB on boot.
- Include `hidden`, `hidden_by`, and mod-action logging from the first moderation pass.
- Add rate limits and a max-length policy before exposing write controls from the main menu.
- Ensure hide/unhide invalidates the cache and refreshes connected viewers.

**Warning signs:**
- Main-menu oneliners disappear after restart.
- Hidden entries remain visible until reconnect.
- There is no mod action when a sysop hides an oneliner.
- The oneliner path bypasses any rate-limiting or cooldown checks.

**Phase to address:**
Phase 5: Main-menu and oneliners integration.

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Keep `invite_only` as a UI-only regex check | Lets screens ship before the invite table exists | Security theater; impossible to reason about invite inventory or reuse | Never |
| Gate mod/sysop actions by hidden tabs only | Faster scaffolding in the TUI | Every new caller reopens the authorization hole | Never |
| Use raw `preferences` map writes for timezone and clock format | No schema work up front | Drift, invalid values, migration pain, inconsistent formatting | Only for throwaway prototypes, not milestone code |
| Copy the INVITES tab into Account, Moderation, and Sysop | Fastest way to show progress | Divergent fixes, duplicated tests, conflicting state models | Never |
| Expose aspirational config keys before runtime consumers exist | Makes the sysop menu look complete | Misleading controls and save-path failures | Only as read-only placeholders |

## Integration Gotchas

Common mistakes when connecting subsystems inside this codebase.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Register screen ↔ Accounts context | Validate or consume the invite in `register.ex` before user insert | Move invite consumption into an actor-aware Accounts transaction |
| Sysop config UI ↔ `Foglet.Config` | Save free-form keys that are not in `Config.Schema` | Expose only schematized keys with typed accessors and runtime consumers |
| Account preferences ↔ active TUI session | Persist the user row but leave `session_context` untouched | Refresh the active session and any derived theme/time formatting immediately after save |
| Oneliners context ↔ main menu | Treat the ring buffer as truth | Make Postgres authoritative and rebuild/cache from there |
| Moderation tabs ↔ Threads/Posts contexts | Call ungated context functions directly from screen handlers | Route through policy-checked moderation APIs that require actor and scope |

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Per-screen minute timers implemented ad hoc | Duplicate refresh events, extra `do_update/2` churn, hard-to-reason screen transitions | Keep one app-level ticker for the main-menu clock and unsubscribe when off-screen | Breaks once users switch screens often or multiple timers accumulate in one session |
| Oneliners rendered from the DB on every main-menu paint | Slow menu renders and noisy DB traffic | Maintain a bounded cache and explicit refresh path | Breaks once the shoutbox becomes a hot path rather than occasional garnish |
| Moderation tabs loading all users/reports/boards eagerly | Large tab switches, sluggish SSH interaction | Page and scope queries by active tab and actor permissions | Breaks as soon as the user table and report queue stop being toy-sized |

## Security Mistakes

Domain-specific security issues beyond generic web security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Storing or logging redeemable invite codes carelessly | Invite leakage and unauthorized registration | Treat invite codes as secrets, show once on generation, avoid debug logs in production, and consider storing only a digest |
| Allowing unlimited invite-code guesses on the registration flow | Brute-force invite discovery | Apply per-connection and per-IP throttles to invite submission, not just full registration |
| Letting moderators act without board scope checks | Unauthorized sanctions or content actions | Enforce capability-plus-scope policy in the domain layer |
| Hiding oneliners without audit logging | Silent abuse or unreviewable moderation | Record hide actions in the mod-action log with actor, reason, and target |

## UX Pitfalls

Common user experience mistakes in this domain.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Preferences save successfully but nothing changes until reconnect | Users do not trust the Account screen | Apply preference changes live or state clearly that reconnect is required |
| Visible but unimplemented moderation/sysop tabs | Operators assume features exist and hit dead ends | Mark scaffold-only tabs clearly and keep actions disabled until wired |
| Main-menu shoutbox dominates the sparse menu layout | The BBS feels noisy instead of alive | Keep oneliners bounded and visually subordinate to navigation |
| Clock formatting differs between main menu and post metadata | The interface feels inconsistent and buggy | Use one timestamp formatter for every user-facing surface |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Invite-only registration:** Often missing transactional invite consumption and replay protection — verify two concurrent redeems cannot both succeed.
- [ ] **INVITES tab reuse:** Often missing shared state/actions — verify Account, Moderation, and Sysop all call the same invite-domain API.
- [ ] **Moderator surface:** Often missing actor-aware policy checks — verify every mutation path rejects unauthorized actors even if a screen leaks it.
- [ ] **Timezone preferences:** Often missing validation and live refresh — verify invalid zone names are rejected and saved preferences affect the current session.
- [ ] **Oneliners:** Often missing moderation and persistence — verify restart recovery, hide/unhide cache invalidation, and rate limiting.
- [ ] **Sysop config editor:** Often missing runtime consumers — verify every exposed control has a typed accessor and an effect in running code.

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Invite codes accepted without real enforcement | HIGH | Disable `invite_only`, audit registrations created during the bad window, backfill invite linkage if possible, rotate all outstanding invites |
| Unauthorized moderator action path ships | HIGH | Disable the affected action in the TUI, add actor-aware policy checks, audit recent mod-action candidates and content mutations |
| Preference/session drift ships | MEDIUM | Add session refresh hooks, force-refresh active sessions on next interaction, and re-test theme/time preference flows |
| Unschematized sysop config is exposed | MEDIUM | Hide the control, remove bad rows from `configuration`, then add schema/accessor/runtime support before re-enabling |
| Oneliners ship as cache-only | MEDIUM | Freeze posting, persist the missing authoritative store, rebuild cache from DB, then re-enable with moderation and limits |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Consuming invites outside the user-creation transaction | Phase 2: Invite persistence and registration enforcement | Two simultaneous redeems of one code result in exactly one user and one consumed invite row |
| Treating authorization as a screen concern | Phase 1: Authorization and policy foundation | Domain tests prove regular users and wrong-scope moderators receive `{:error, :forbidden}` |
| Hard-coding global moderator semantics | Phase 1 then Phase 4 | Board-scoped test fixtures can see only their assigned reports/actions |
| Session-context drift after account or sysop changes | Phase 3: Account preferences and session refresh | Save theme/time preference in-session and assert main-menu rendering updates without reconnect |
| Adding timezone and 12h/24h preferences without a time contract | Phase 3: Account preferences and session refresh | Invalid zones are rejected, valid zones format deterministically in tests, UTC fallback is explicit |
| Letting TUI surface sprawl outrun the current screen architecture | Phase 4: Moderation/sysop/account surface scaffolding | Shared invite/tab widgets back all three surfaces and `App.do_update/2` avoids copy-paste command clauses |
| Exposing sysop config controls the runtime cannot honor | Phase 4: Sysop configuration surface | Every editable control maps to `Config.Schema`, a typed accessor, and a live runtime consumer |
| Building oneliners as UI garnish instead of moderated domain data | Phase 5: Main-menu and oneliners integration | Restart recovery, hide/unhide, and rate-limit tests all pass against the real context |

## Sources

- [`.planning/PROJECT.md`](../../.planning/PROJECT.md)
- [`docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md)
- [`docs/DATA_MODEL.md`](../../docs/DATA_MODEL.md)
- [`.planning/codebase/CONCERNS.md`](../../.planning/codebase/CONCERNS.md)
- [`lib/foglet_bbs/tui/screens/register.ex`](../../lib/foglet_bbs/tui/screens/register.ex)
- [`lib/foglet_bbs/accounts.ex`](../../lib/foglet_bbs/accounts.ex)
- [`lib/foglet_bbs/threads.ex`](../../lib/foglet_bbs/threads.ex)
- [`lib/foglet_bbs/tui/app.ex`](../../lib/foglet_bbs/tui/app.ex)
- [`lib/foglet_bbs/tui/screens/main_menu.ex`](../../lib/foglet_bbs/tui/screens/main_menu.ex)
- [`lib/foglet_bbs/ssh/cli_handler.ex`](../../lib/foglet_bbs/ssh/cli_handler.ex)
- [`lib/foglet_bbs/config/schema.ex`](../../lib/foglet_bbs/config/schema.ex)
- [`lib/foglet_bbs/accounts/user.ex`](../../lib/foglet_bbs/accounts/user.ex)

---
*Pitfalls research for: operations surfaces and invites in Foglet BBS*
*Researched: 2026-04-23*
