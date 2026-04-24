# Phase 05: Account Preferences and Live Session Refresh - Research

**Researched:** 2026-04-24  
**Domain:** Phoenix/Ecto account preferences, SSH TUI state, session GenServer refresh  
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Extend the existing `users` row for Account preferences: add dedicated `users.timezone`, continue storing `preferences["time_format"]`, and continue storing the saved theme in `users.theme`.
- **D-02:** Keep `Foglet.Accounts.update_profile/2` as the Account profile/preference mutation boundary rather than creating a separate preferences table or Account-only persistence API.
- **D-03:** New user defaulting belongs in the Accounts/User registration path so all registration modes persist timezone, default `"12h"` time format, and the default registered Foglet theme consistently.
- **D-04:** Put timezone, time format, theme, and bounded private-profile validation in `Foglet.Accounts.User.profile_changeset/2` so invalid values are rejected for every caller of `Accounts.update_profile/2`, not only the TUI.
- **D-05:** Validate `timezone` as an IANA timezone with Timex; use `Timex.Timezone.exists?/1` for save validation.
- **D-06:** Derive the default timezone from `Timex.Timezone.local/0` plus `Timex.Timezone.name_of/1` when possible, and fall back to `"Etc/UTC"` when local timezone resolution is unavailable or invalid.
- **D-07:** Validate `preferences["time_format"]` as exactly `"12h"` or `"24h"`.
- **D-08:** Validate `theme` against registered Foglet theme ids from `Foglet.TUI.Theme.ids/0`, preserving string storage and atom/string round-trip behavior.
- **D-09:** Normalize blank `location`, `tagline`, and `real_name` values to `nil`; enforce the SPEC maximums of 80, 120, and 120 characters respectively.
- **D-10:** Prefer exploring inline editable forms directly inside the Account `PROFILE` and `PREFS` tabs instead of locking `Foglet.TUI.Widgets.Modal.Form` as the default UX.
- **D-11:** Treat Phase 5 as the reference opportunity for a good inline page form pattern in Foglet's TUI, especially because inline theme selection may make unsaved theme preview more natural than a modal flow.
- **D-12:** Researcher and planner may still choose `Modal.Form` if codebase evidence shows it is clearly better, but the default planning bias should be inline Account forms with explicit focus, save, cancel/revert, and field-error behavior.
- **D-13:** Preserve the existing Account screen/tab model: `PROFILE`, `PREFS`, and conditional `INVITES` stay in `Foglet.TUI.Screens.Account.State`; Account continues to own local UI state under `state.screen_state[:account]`.
- **D-14:** Do not change shared `INVITES` behavior in Phase 5. Account profile/preference input must coexist with, not replace or fork, the Phase 4 shared invite delegation.
- **D-15:** Theme preview should be modeled as an unsaved candidate theme in Account state. Rendering may temporarily resolve that candidate for the Account screen, but persisted `users.theme`, durable session theme, and session process state must remain unchanged until save.
- **D-16:** Canceling, leaving Account, or otherwise discarding unsaved changes must revert rendering to the saved session/user theme and leave the database unchanged.
- **D-17:** Theme preview is scoped to theme only; timezone and time-format preview remain out of scope.
- **D-18:** A successful Account save updates all three active snapshots together: `state.current_user`, `state.session_context` preference fields including `theme`, and the backing `Foglet.Sessions.Session` state.
- **D-19:** Add a first-class session update API for preference snapshots rather than reaching into the Session GenServer state from Account code.
- **D-20:** `Foglet.SSH.CLIHandler` should seed `session_context` from the saved user preference snapshot when an authenticated session starts instead of always using `Foglet.TUI.Theme.default()`.
- **D-21:** The session preference snapshot should include at least saved timezone, saved time format, and resolved theme so Phase 6 can render user-facing time without reconnecting.
- **D-22:** Cover persistence and validation in Accounts/User tests, including invalid timezone, invalid time format, invalid theme, blank profile normalization, and max-length rejection.
- **D-23:** Cover Account TUI inline editing behavior with focused tests for field navigation, save, cancel/revert, field-level errors, and unsaved theme preview.
- **D-24:** Cover live refresh through TUI/session tests proving a successful save updates `state.current_user`, `state.session_context`, and `Foglet.Sessions.Session.get_state/1`.
- **D-25:** `mix precommit` must pass before Phase 5 is considered complete.

### Claude's Discretion

- Exact inline form layout, key bindings, and field ordering, as long as terminal-native focus, save, cancel/revert, and visible error feedback are clear.
- Whether Profile and Prefs use one shared inline-form helper module or separate small tab modules.
- Exact wording of validation and success messages.
- Whether Timex default-timezone derivation is wrapped in `User`, `Accounts`, or a small helper module, as long as the validation/defaulting contract is tested.

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ACCT-02 | User can edit private profile details from Account, including `location`, `tagline`, and `real_name`. | Existing `User.profile_changeset/2` and `Accounts.update_profile/2` are the correct mutation boundary; add normalization and max-length checks there. [VERIFIED: lib/foglet_bbs/accounts/user.ex; lib/foglet_bbs/accounts.ex] |
| ACCT-03 | User can choose a valid IANA timezone and new accounts default to system timezone until changed. | Add `users.timezone`, default via Timex local lookup/name resolution with `"Etc/UTC"` fallback, validate with `Timex.Timezone.exists?/1`. [VERIFIED: 05-CONTEXT.md] [CITED: https://hexdocs.pm/timex/Timex.Timezone.html] |
| ACCT-04 | User can choose 12-hour or 24-hour time display and new accounts default to 12-hour time. | Store `"12h"`/`"24h"` under `preferences["time_format"]`; default registration attrs/changeset must ensure `"12h"`. [VERIFIED: 05-CONTEXT.md; lib/foglet_bbs/accounts/user.ex] |
| ACCT-05 | User can choose a registered Foglet TUI theme from Account. | Validate string theme ids against `Foglet.TUI.Theme.ids/0` converted to strings; resolve saved id to `%Foglet.TUI.Theme{}` for session context. [VERIFIED: lib/foglet_bbs/tui/theme.ex] |
| ACCT-06 | User sees saved Account preference changes reflected in the active session without reconnecting. | Add a public Session update API and have Account save update `current_user`, `session_context`, and Session GenServer state together. [VERIFIED: lib/foglet_bbs/sessions/session.ex; lib/foglet_bbs/tui/screens/account.ex] |
</phase_requirements>

## Summary

Phase 5 should be planned as a narrow vertical slice through the existing `users` schema, `Foglet.Accounts.update_profile/2`, `Foglet.TUI.Screens.Account`, `Foglet.Sessions.Session`, and `Foglet.SSH.CLIHandler.build_context/3`. The codebase already has the profile fields, theme field, JSON `preferences`, Account tabs, registered theme ids, and Session state; the missing pieces are the `timezone` column, explicit validation/defaulting contracts, inline Account edit state, and a first-class Session preference snapshot update API. [VERIFIED: lib/foglet_bbs/accounts/user.ex; lib/foglet_bbs/tui/screens/account.ex; lib/foglet_bbs/sessions/session.ex; lib/foglet_bbs/ssh/cli_handler.ex]

Use Timex as locked by context, not Elixir stdlib alone, because this phase requires IANA timezone validation and best-effort local timezone resolution. `Timex.Timezone.exists?/1`, `local/0`, and `name_of/1` are present in Timex 3.7.13 docs, and `mix hex.info timex` reports `{:timex, "~> 3.7"}` with latest release `3.7.13`. [VERIFIED: mix hex.info timex] [CITED: https://hexdocs.pm/timex/Timex.Timezone.html]

**Primary recommendation:** Implement one shared Account preference snapshot helper plus inline Account tab submodules, while keeping persistence validation in `User.profile_changeset/2` and live refresh in a new `Sessions.Session.update_preferences/2` API. [VERIFIED: 05-CONTEXT.md; lib/foglet_bbs/tui/widgets/README.md]

## Project Constraints (from AGENTS.md / CLAUDE.md)

- Run `mix precommit` when implementation is complete; it runs compile, format, credo, sobelow, and dialyzer. [VERIFIED: AGENTS.md; CLAUDE.md]
- Use `Req` for HTTP requests and avoid `httpoison`, `tesla`, and `httpc`; this phase should need no HTTP client. [VERIFIED: AGENTS.md; CLAUDE.md]
- Prefer stdlib date/time unless asked, with `date_time_parser` as the only sanctioned parsing exception; Phase 5 is explicitly asked to add/use Timex for timezone behavior. [VERIFIED: AGENTS.md; 05-CONTEXT.md]
- Generate migrations with `mix ecto.gen.migration migration_name_using_underscores`; `mix help ecto.gen.migration` confirms timestamped migration generation under `priv/repo/migrations`. [VERIFIED: AGENTS.md; mix help ecto.gen.migration]
- Tests should use `start_supervised!/1`/`start_supervised/1`, avoid `Process.sleep/1`, and synchronize GenServers with `:sys.get_state/1` or monitored `:DOWN`. [VERIFIED: AGENTS.md; test/foglet_bbs/sessions/session_test.exs]
- Do not nest multiple modules in one file, do not use struct Access syntax, and remember Elixir block expressions rebind rather than mutate. [VERIFIED: AGENTS.md]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| Persist private profile fields | API / Backend | Database / Storage | `Accounts.update_profile/2` owns writes and Ecto stores fields on `users`. [VERIFIED: lib/foglet_bbs/accounts.ex] |
| Validate timezone/time format/theme | API / Backend | TUI | `User.profile_changeset/2` must reject invalid values for every caller; TUI only surfaces errors. [VERIFIED: 05-CONTEXT.md] |
| Inline Account editing UX | Browser / Client equivalent: SSH TUI | API / Backend | Account screen owns focus/draft/error state under `screen_state[:account]`; saves call Accounts. [VERIFIED: lib/foglet_bbs/tui/screens/account.ex] |
| Unsaved theme preview | SSH TUI | API / Backend | Candidate theme is render-only until save; database/session state stay unchanged until persistence succeeds. [VERIFIED: 05-CONTEXT.md] |
| Live session preference refresh | Session Layer | SSH TUI | Session GenServer holds active preference snapshot; TUI state mirrors it after save. [VERIFIED: docs/ARCHITECTURE.md; lib/foglet_bbs/sessions/session.ex] |
| Session startup preference seeding | SSH Layer | API / Backend | `CLIHandler.build_context/3` fetches the user and builds `session_context` before `App.init/1`. [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex] |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Elixir / OTP | Elixir 1.19.5 / OTP 28 | Application/runtime language | Installed toolchain for this project. [VERIFIED: elixir --version] |
| Phoenix | 1.8.5 | Web endpoint and app framework | Existing project dependency. [VERIFIED: mix.lock] |
| Ecto SQL | 3.13.5 | Schema, changeset, migration, Repo updates | Existing persistence layer for `users`. [VERIFIED: mix.lock; lib/foglet_bbs/accounts/user.ex] |
| PostgreSQL | psql 14.20 client available | Backing database for `users` | Existing migrations target Postgres/citext/jsonb style. [VERIFIED: psql --version; priv/repo/migrations/20260418000002_create_users.exs] |
| Timex | 3.7.13 latest, add `{:timex, "~> 3.7"}` | IANA timezone validation and local timezone lookup | Locked by Phase 5 context; docs expose `exists?/1`, `local/0`, `name_of/1`. [VERIFIED: mix hex.info timex] [CITED: https://hexdocs.pm/timex/Timex.Timezone.html] |
| Raxol / local TUI widgets | raxol_liveview 2.4.0 in lock | Terminal UI primitives and themed widgets | Existing Account screen and widgets use Raxol DSL and local theme contract. [VERIFIED: mix.lock; docs/raxol/getting-started/WIDGET_GALLERY.md; lib/foglet_bbs/tui/widgets/README.md] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Bodyguard | 2.4.3 | Authorization backbone | Not central for self-profile writes, but preserve actor-aware patterns if adding any privileged path. [VERIFIED: mix.lock] |
| Sobelow | 0.14.1 | Security static analysis | Runs in `mix precommit`; account input handling should pass it. [VERIFIED: mix.lock; mix.exs] |
| Credo | 1.7.18 | Static analysis/style | Runs in `mix precommit`; keep helpers small and typed. [VERIFIED: mix.lock; mix.exs] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Timex timezone validation | Elixir `Calendar`/`DateTime` only | Rejected by locked decision; stdlib can convert known zones but Phase 5 explicitly chose Timex validation/defaulting. [VERIFIED: 05-CONTEXT.md] |
| Inline Account forms | `Foglet.TUI.Widgets.Modal.Form` | Modal.Form exists and works, but locked planning bias is inline because theme preview and tab-local editing fit better. [VERIFIED: 05-CONTEXT.md; lib/foglet_bbs/tui/widgets/modal/form.ex] |
| Separate preferences table | New `user_preferences` schema | Rejected by locked decision; use existing `users` row. [VERIFIED: 05-CONTEXT.md] |

**Installation:**

```elixir
# mix.exs
{:timex, "~> 3.7"}
```

**Version verification:** `mix hex.info timex` succeeded with escalated network access and reported `Config: {:timex, "~> 3.7"}` and release `3.7.13`. [VERIFIED: mix hex.info timex]

## Architecture Patterns

### System Architecture Diagram

```text
SSH authenticated user
  -> Foglet.SSH.CLIHandler.build_context/3
  -> Accounts.get_user/1
  -> preference snapshot builder
       timezone: user.timezone
       time_format: user.preferences["time_format"]
       theme: Theme.resolve(saved_theme_id)
  -> Foglet.TUI.App.init/1
  -> Account screen drafts/edit state under state.screen_state[:account]
       save
       -> Accounts.update_profile/2
       -> User.profile_changeset/2 validation
       -> Repo.update(users)
       -> reload/update current_user
       -> Sessions.Session.update_preferences/2
       -> state.session_context refreshed
       -> render with saved/preview theme
```

### Recommended Project Structure

```text
lib/foglet_bbs/
├── accounts/user.ex                         # schema, defaults, profile validation
├── accounts.ex                              # update_profile/2 boundary unchanged
├── sessions/session.ex                      # preference snapshot fields + update API
├── ssh/cli_handler.ex                       # session_context startup snapshot
└── tui/screens/account/
    ├── state.ex                             # tab state plus drafts/errors/candidate theme
    ├── profile_form.ex                      # inline PROFILE tab behavior
    └── prefs_form.ex                        # inline PREFS tab behavior
```

### Pattern 1: Normalize and Validate at the Changeset Boundary

**What:** Extend `User.profile_changeset/2` to cast `:timezone`, normalize blank private fields to `nil`, validate field lengths, validate theme id strings, and validate `preferences["time_format"]`. [VERIFIED: lib/foglet_bbs/accounts/user.ex]

**When to use:** Every Account profile/preference save through `Accounts.update_profile/2`. [VERIFIED: lib/foglet_bbs/accounts.ex]

**Example:**

```elixir
user
|> cast(attrs, [:location, :tagline, :real_name, :timezone, :theme, :preferences])
|> normalize_blank_profile_fields()
|> validate_length(:location, max: 80)
|> validate_length(:tagline, max: 120)
|> validate_length(:real_name, max: 120)
|> validate_timezone()
|> validate_theme()
|> validate_time_format()
```

### Pattern 2: Build a Session Preference Snapshot Once

**What:** Use a helper that turns `%User{}` into a stable map: `%{timezone: ..., time_format: ..., theme_id: ..., theme: Theme.resolve(...)}`. [VERIFIED: 05-CONTEXT.md; lib/foglet_bbs/tui/theme.ex]

**When to use:** Use the same helper in `CLIHandler.build_context/3`, `Session.init/1`/promotion if needed, and Account save refresh so startup and live refresh cannot drift. [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex; lib/foglet_bbs/sessions/session.ex]

### Pattern 3: Inline TUI Forms Own Draft State, Domain Owns Truth

**What:** Account screen state stores drafts, focus index, field errors, dirty status, and `candidate_theme_id`; persistence remains in Accounts. [VERIFIED: lib/foglet_bbs/tui/screens/account/state.ex; 05-CONTEXT.md]

**When to use:** Use for PROFILE and PREFS tabs; preserve `INVITES` delegation to `InvitesSurface.render/2`. [VERIFIED: lib/foglet_bbs/tui/screens/account.ex]

### Anti-Patterns to Avoid

- **Mutating only TUI state after save:** This would satisfy the current frame but leave `Foglet.Sessions.Session.get_state/1` stale and fail ACCT-06. [VERIFIED: 05-CONTEXT.md]
- **Reaching into GenServer state from Account code:** Add a public Session API instead of `:sys.get_state`/manual state mutation. [VERIFIED: 05-CONTEXT.md]
- **Validating only in Account UI:** Other callers of `Accounts.update_profile/2` would bypass timezone/theme/time-format checks. [VERIFIED: 05-CONTEXT.md]
- **Using `String.to_atom/1` on user theme input:** Theme input is user-controlled; convert registered atom ids to strings for comparison and use `String.to_existing_atom/1` only after validation or resolve through a safe mapping. [ASSUMED]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| IANA timezone validation | Custom timezone list or regex | `Timex.Timezone.exists?/1` | Timex already uses timezone data and exposes existence validation. [CITED: https://hexdocs.pm/timex/Timex.Timezone.html] |
| Local timezone lookup | OS-specific shell parsing | `Timex.Timezone.local/0` + `name_of/1` with fallback | Timex Local docs describe OS-specific lookup sources. [CITED: https://hexdocs.pm/timex/Timex.Timezone.Local.html] |
| Theme registry | Duplicate allowed theme ids | `Foglet.TUI.Theme.ids/0` / `resolve/1` | Existing module is the single source of truth for registered themes. [VERIFIED: lib/foglet_bbs/tui/theme.ex] |
| Account persistence API | New preferences context/table | `Foglet.Accounts.update_profile/2` | Locked phase boundary and existing context function. [VERIFIED: 05-CONTEXT.md; lib/foglet_bbs/accounts.ex] |
| GenServer state mutation | Direct state access from TUI | `Sessions.Session.update_preferences/2` | Public API keeps Session ownership intact. [VERIFIED: 05-CONTEXT.md] |

**Key insight:** This phase is not about inventing preferences infrastructure; it is about making the existing `users` row and Session/TUI snapshots agree in all code paths. [VERIFIED: 05-CONTEXT.md; docs/ARCHITECTURE.md]

## Common Pitfalls

### Pitfall 1: Preferences Map Replaces Existing Keys

**What goes wrong:** Saving `preferences: %{"time_format" => "24h"}` can wipe unrelated future preferences if the implementation replaces the whole map blindly. [ASSUMED]  
**Why it happens:** Ecto `:map` fields are whole-field values unless code merges explicitly. [ASSUMED]  
**How to avoid:** Merge incoming `time_format` into existing `user.preferences || %{}` in a changeset helper or Account attrs normalizer. [ASSUMED]  
**Warning signs:** Tests only assert `time_format` and never seed an unrelated preference key. [ASSUMED]

### Pitfall 2: Theme String/Atom Drift

**What goes wrong:** `users.theme` stores strings while `Theme.ids/0` returns atoms, so direct inclusion checks can reject valid values or accept unsafe conversions. [VERIFIED: lib/foglet_bbs/accounts/user.ex; lib/foglet_bbs/tui/theme.ex]  
**Why it happens:** Current schema stores `theme` as `:string`; theme registry ids are atoms. [VERIFIED: lib/foglet_bbs/accounts/user.ex; lib/foglet_bbs/tui/theme.ex]  
**How to avoid:** Build `valid_theme_ids = Theme.ids() |> Enum.map(&Atom.to_string/1)` and resolve through a safe atom lookup after validation. [ASSUMED]  
**Warning signs:** New code calls `String.to_atom(theme)` on raw input. [ASSUMED]

### Pitfall 3: Unsaved Theme Preview Leaks Into Session

**What goes wrong:** Moving through the theme selector updates `state.session_context.theme` or Session GenServer before save, making cancel unable to revert. [VERIFIED: 05-CONTEXT.md]  
**Why it happens:** Existing render reads `Theme.from_state(state)` from `session_context.theme`. [VERIFIED: lib/foglet_bbs/tui/theme.ex]  
**How to avoid:** Account render should use a local render theme override for its body/frame when `candidate_theme_id` exists, while leaving `session_context` unchanged until save. [ASSUMED]  
**Warning signs:** Tests see `Session.get_state(pid)` change before Account save. [VERIFIED: 05-CONTEXT.md]

### Pitfall 4: Registration Modes Default Differently

**What goes wrong:** Open registration gets defaults but invite-only or sysop-approved users do not. [VERIFIED: lib/foglet_bbs/accounts.ex]  
**Why it happens:** `register_user/1` dispatches to separate open, invite-only, and pending paths. [VERIFIED: lib/foglet_bbs/accounts.ex]  
**How to avoid:** Put defaults in `User.registration_changeset/2` or a common helper used before all inserts, not just one branch. [VERIFIED: 05-CONTEXT.md]

### Pitfall 5: Session Startup and Live Refresh Use Different Shapes

**What goes wrong:** `CLIHandler.build_context/3` and Account save construct different `session_context` keys. [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex; 05-CONTEXT.md]  
**Why it happens:** Current startup hardcodes `theme: Theme.default()` and has no timezone/time_format keys. [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex]  
**How to avoid:** Use a shared snapshot helper for startup and save. [ASSUMED]

## Code Examples

### Timex Validation and Defaulting

```elixir
# Source: https://hexdocs.pm/timex/Timex.Timezone.html
Timex.Timezone.exists?("America/Chicago")
Timex.Timezone.local() |> Timex.Timezone.name_of()
```

`exists?/1` returns boolean; `local/0` may return timezone info or `{:error, term()}`; `name_of/1` may return a string or error tuple, so defaulting must pattern match and fall back to `"Etc/UTC"`. [CITED: https://hexdocs.pm/timex/Timex.Timezone.html]

### Existing Account Mutation Boundary

```elixir
# Source: lib/foglet_bbs/accounts.ex
def update_profile(%User{} = user, attrs) do
  user
  |> User.profile_changeset(attrs)
  |> Repo.update()
end
```

This should remain the public save boundary. [VERIFIED: lib/foglet_bbs/accounts.ex]

### Existing Theme Resolution

```elixir
# Source: lib/foglet_bbs/tui/theme.ex
def ids, do: Map.keys(@themes)
def default, do: resolve(:gray)
```

The saved database string should validate against these ids and resolve to a `%Foglet.TUI.Theme{}` snapshot for `session_context.theme`. [VERIFIED: lib/foglet_bbs/tui/theme.ex]

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Account PROFILE/PREFS placeholders | Inline Account forms with real domain save | Phase 5 | Plan should replace placeholder bodies without changing tab model. [VERIFIED: lib/foglet_bbs/tui/screens/account.ex; 05-CONTEXT.md] |
| Session startup uses `Theme.default()` | Startup derives saved user preference snapshot | Phase 5 | `CLIHandler.build_context/3` must read saved theme/timezone/time_format. [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex; 05-CONTEXT.md] |
| Session state stores identity/terminal only | Session state stores preference snapshot too | Phase 5 | Add fields and update API; tests should inspect `Session.get_state/1`. [VERIFIED: lib/foglet_bbs/sessions/session.ex; 05-CONTEXT.md] |

**Deprecated/outdated:**
- Account placeholder copy: should be replaced for PROFILE/PREFS in Phase 5. [VERIFIED: lib/foglet_bbs/tui/screens/account.ex]
- Hardcoded default theme in SSH context for authenticated users: should be replaced with saved preference snapshot. [VERIFIED: lib/foglet_bbs/ssh/cli_handler.ex]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Avoid `String.to_atom/1` on user theme input; use safe string validation/mapping. | Anti-Patterns, Pitfalls | Security/static-analysis risk and atom table growth risk if raw user strings become atoms. |
| A2 | Ecto map preference updates should merge to avoid dropping unrelated keys. | Common Pitfalls | Future preference keys could be lost on Account save. |
| A3 | Account render may need a local theme override for preview rather than mutating `session_context`. | Common Pitfalls | Preview implementation could be awkward if ScreenFrame only reads from state. |
| A4 | A shared snapshot helper should be introduced to prevent startup/live refresh drift. | Architecture Patterns, Pitfalls | Duplicate code could drift and break Phase 6 clock behavior. |

## Open Questions

1. **Where should the shared preference snapshot helper live?**
   - What we know: It must be available to Accounts/TUI/SSH/Session code. [VERIFIED: 05-CONTEXT.md]
   - What's unclear: Whether the best local boundary is `Foglet.Accounts.User`, `Foglet.Accounts`, `Foglet.Sessions.Preferences`, or `Foglet.TUI.PreferenceSnapshot`. [ASSUMED]
   - Recommendation: Put pure user-to-snapshot/default helpers near Accounts or Sessions, not inside Account screen modules, so SSH startup and TUI save share it. [ASSUMED]

2. **Should existing users be backfilled in SQL or on read?**
   - What we know: Add `users.timezone`; new accounts need persisted defaults. [VERIFIED: 05-CONTEXT.md]
   - What's unclear: Existing local data volume and whether all existing rows can safely receive the same default at migration time. [ASSUMED]
   - Recommendation: Migration should add nullable/defaulted column and update existing nulls to resolved/fallback timezone in application migration or use `"Etc/UTC"` DB default; planner should choose a deterministic migration-safe path. [ASSUMED]

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Elixir | Compile/tests | yes | 1.19.5 | none |
| Mix | Deps/migrations/tests | yes | 1.19.5 | none |
| PostgreSQL client | Ecto DB work | yes | psql 14.20 | project test DB config |
| Hex network | Verify/add Timex | yes with escalation | Timex 3.7.13 latest | HexDocs/web for API docs |
| Timex dependency | Phase implementation | not installed yet | 3.7.13 latest available | none; locked decision requires Timex |

**Missing dependencies with no fallback:**
- `:timex` is not currently in `mix.exs`/`mix.lock`; Phase 5 must add it. [VERIFIED: mix.exs; mix.lock]

**Missing dependencies with fallback:**
- None. [VERIFIED: local environment audit]

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit with Phoenix/Ecto sandbox conventions. [VERIFIED: test directory] |
| Config file | `test/test_helper.exs`; project also uses `mix precommit`. [VERIFIED: test/test_helper.exs; mix.exs] |
| Quick run command | `mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/sessions/session_test.exs test/foglet_bbs/ssh/cli_handler_test.exs` |
| Full suite command | `mix precommit` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| ACCT-02 | Profile fields save, blank normalization, max lengths | unit/integration | `mix test test/foglet_bbs/accounts/accounts_test.exs` | yes, extend |
| ACCT-03 | Timezone column default and invalid timezone rejection | unit/integration | `mix test test/foglet_bbs/accounts/accounts_test.exs` | yes, extend |
| ACCT-04 | `"12h"`/`"24h"` persistence and default | unit/integration | `mix test test/foglet_bbs/accounts/accounts_test.exs` | yes, extend |
| ACCT-05 | Registered theme validation and Account selector save | unit/TUI | `mix test test/foglet_bbs/tui/screens/account_test.exs` | yes, extend |
| ACCT-06 | Save refreshes current_user, session_context, Session state | integration | `mix test test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/sessions/session_test.exs` | yes, extend |

### Sampling Rate

- **Per task commit:** focused test command for touched layer. [VERIFIED: project test layout]
- **Per wave merge:** all Phase 5 touched tests. [ASSUMED]
- **Phase gate:** `mix precommit` green before `/gsd-verify-work`. [VERIFIED: AGENTS.md; 05-CONTEXT.md]

### Wave 0 Gaps

- [ ] Extend `test/foglet_bbs/accounts/accounts_test.exs` for timezone/time_format/theme/private-profile validation. [VERIFIED: current file exists]
- [ ] Extend `test/foglet_bbs/tui/screens/account_test.exs` for inline field navigation/save/cancel/errors/preview. [VERIFIED: current file exists]
- [ ] Extend `test/foglet_bbs/sessions/session_test.exs` for preference snapshot update API. [VERIFIED: current file exists]
- [ ] Extend `test/foglet_bbs/ssh/cli_handler_test.exs` or App init context tests for saved preference seeding. [VERIFIED: current file exists]

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | no | No credential changes in scope; do not touch password/email/SSH keys. [VERIFIED: 05-SPEC.md] |
| V3 Session Management | yes | Session GenServer update API should update only authenticated user's active session preference snapshot. [VERIFIED: lib/foglet_bbs/sessions/session.ex; 05-CONTEXT.md] |
| V4 Access Control | yes | Account save must operate on `state.current_user`; do not allow arbitrary user id attrs. [ASSUMED] |
| V5 Input Validation | yes | Ecto changeset validation for timezone, time_format, theme, and bounded strings. [VERIFIED: 05-CONTEXT.md] |
| V6 Cryptography | no | No cryptographic material in scope. [VERIFIED: 05-SPEC.md] |

### Known Threat Patterns for Phoenix/Ecto Account Preferences

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Mass assignment of account/security fields | Elevation of privilege | `profile_changeset/2` must cast only profile/preference fields, not role/status/email/password. [VERIFIED: lib/foglet_bbs/accounts/user.ex] |
| Stored terminal control sequences in profile fields | Tampering | Consider stripping or escaping control characters before rendering profile strings in TUI. [ASSUMED] |
| Atom exhaustion through theme conversion | Denial of service | Validate against registered strings before any atom conversion; avoid `String.to_atom/1`. [ASSUMED] |
| Preference spoofing via client/session_context attrs | Tampering | Persist through `Accounts.update_profile/2`; derive live snapshot from saved user, not raw TUI context. [VERIFIED: 05-CONTEXT.md] |

## Sources

### Primary (HIGH confidence)

- `.planning/phases/05-account-preferences-and-live-session-refresh/05-CONTEXT.md` - locked implementation decisions and testing requirements.
- `.planning/phases/05-account-preferences-and-live-session-refresh/05-SPEC.md` - phase scope, acceptance criteria, out-of-scope boundaries.
- `.planning/REQUIREMENTS.md` - ACCT-02 through ACCT-06 requirement text.
- `docs/ARCHITECTURE.md` - Session layer and SSH lifecycle boundaries.
- `docs/DATA_MODEL.md` - user schema/persistence conventions.
- `AGENTS.md` / `CLAUDE.md` - project-specific Phoenix/Elixir/testing constraints.
- `lib/foglet_bbs/accounts/user.ex` - current User schema and changesets.
- `lib/foglet_bbs/accounts.ex` - `update_profile/2` boundary and registration paths.
- `lib/foglet_bbs/tui/screens/account.ex` / `state.ex` - Account tab model and screen state.
- `lib/foglet_bbs/sessions/session.ex` - current Session GenServer state/API.
- `lib/foglet_bbs/ssh/cli_handler.ex` - startup `session_context` construction.
- `lib/foglet_bbs/tui/theme.ex` - registered theme ids and theme resolution.
- `mix hex.info timex` - Timex package version availability.

### Secondary (MEDIUM confidence)

- `https://hexdocs.pm/timex/Timex.Timezone.html` - Timex timezone functions.
- `https://hexdocs.pm/timex/Timex.Timezone.Local.html` - Timex local timezone lookup behavior.
- `docs/raxol/getting-started/WIDGET_GALLERY.md` - Raxol DSL widget usage.
- `lib/foglet_bbs/tui/widgets/README.md` - local widget conventions.

### Tertiary (LOW confidence)

- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - current dependencies verified from `mix.lock`, local versions, and Hex package lookup.
- Architecture: HIGH - relevant project modules and phase decisions are explicit.
- Pitfalls: MEDIUM - several risks are inferred from standard Ecto/TUI/GenServer behavior and marked `[ASSUMED]`.

**Research date:** 2026-04-24  
**Valid until:** 2026-05-24 for local architecture; 2026-05-01 for Timex/package currency.
