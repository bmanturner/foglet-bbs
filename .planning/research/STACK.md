# Stack Research

**Domain:** Operations surfaces, invites, preference-driven time rendering, and oneliners for an SSH-first Phoenix BBS
**Researched:** 2026-04-23
**Confidence:** HIGH

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| `Timex` | `~> 3.7` | Approved milestone dependency for timezone-aware rendering and formatting | This is the required dependency addition for v1.1. It gives Foglet an explicit, project-level path for validating IANA zones and rendering user-local time without adding a larger i18n stack. |
| Elixir stdlib (`DateTime`, `Calendar.strftime/3`, `Base`, `:crypto`) | Elixir 1.19.5 | UTC storage, supporting time/date operations, and secure invite-code generation | Stdlib should still own UTC persistence, general date handling, and secure random bytes even with Timex added for user-local rendering. |
| Ecto + PostgreSQL | existing (`ecto_sql ~> 3.13`, Postgres) | Persist invite codes, oneliners, and user display preferences | Invite workflows and shoutbox state are authoritative domain data, not cache data. Postgres already matches the project rule that durable truth lives in the DB. |
| Phoenix PubSub + OTP timers | existing | Push oneliner updates and drive the main-menu minute refresh | `Foglet.TUI.App` already uses interval subscriptions and PubSub forwarding. Reuse that instead of adding a scheduler, polling loop library, or separate event bus. |
| Raxol + existing Foglet TUI widgets | existing vendored runtime | Account, moderation, sysop, and reusable invite-tab surfaces | These new screens are stack consumers, not a reason to introduce LiveView, web forms, or another terminal framework. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `Hammer` | existing `~> 7.3.0` | Rate-limit invite generation/redemption attempts and oneliner posting | Use if these new actions need per-user or per-IP throttling. Do not add a second rate-limiter. |
| `Oban` | existing `~> 2.18` | Optional cleanup of expired invites or retention pruning | Only use if this milestone adds background cleanup. It is not required for invite redemption or oneliner display; synchronous expiry checks are enough. |
| `Req` | existing project standard | Future external HTTP only if an explicit operational sync task is added later | Not needed for this milestone itself. Keep using `Req` if a later admin tool needs HTTP; do not add `Tesla` or `HTTPoison`. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `mix precommit` | Quality gate for compile, format, credo, sobelow, and dialyzer | Required by project guidelines after implementation work lands. |
| Targeted `mix test` runs | Verify invite workflows, config accessors, timezone formatting, and oneliner buffering | Prefer focused test runs while building, then `mix precommit` at the end. |

## Required Stack Changes

### 1. Add real timezone support

Required:

- Add `{:timex, "~> 3.7"}` to `deps/0`.

- Keep timestamps stored in UTC.
- Store the user's preferred IANA timezone name in `users.preferences`, for example `%{"time_zone" => "America/Chicago"}`.
- Store the display preference as a simple presentation value, preferably `%{"time_format" => "12h" | "24h"}` or a boolean like `%{"time_24h" => true}`.
- Render the main-menu clock through one shared formatter that uses Timex for user-local timezone handling and formatting.

Concrete formatting choice:

- 24h: Timex-backed formatter renders an equivalent of `%Y-%m-%d %H:%M`
- 12h: Timex-backed formatter renders an equivalent of `%Y-%m-%d %I:%M %p`

Recommendation:

- Keep timezone and 12h/24h settings inside `users.preferences` for this milestone.
- Validate them through Ecto changesets or an `embedded_schema`, not a new preferences table.

### 2. Add invite persistence, not invite libraries

Required:

- Add an `invite_codes` table and schema in the existing Accounts/domain layer.
- Use stdlib crypto for code generation: `:crypto.strong_rand_bytes/1` plus `Base.encode32/2` or `Base.url_encode64/2`.
- Persist a digest of the code, not the raw bearer secret, so leaked DB rows do not become usable invites.
- Model invite lifecycle in Ecto/Postgres: creator, optional redeemer, max uses, use count, expires_at, revoked_at, and optional note/context.
- Keep authorization driven by existing `Foglet.Config.registration_mode/0` and `invite_code_generators/0`.

Integration points:

- `Foglet.Config.Schema` / `Foglet.Config` remain the runtime-policy source.
- Account, moderation, and sysop invite tabs should call shared context functions; no per-surface stack split.
- Invite redemption should happen synchronously in the registration flow; no queue is required.

### 3. Add oneliners as a domain module plus in-memory buffer

Required:

- Implement the documented `oneliners` schema/table in Ecto/Postgres.
- Add a supervised `Foglet.Oneliners` GenServer that owns the recent-visible ring buffer.
- Write DB-first, then update/broadcast to the in-memory buffer through existing PubSub patterns.
- Use the existing TUI subscription/timer infrastructure for screen refreshes.

Integration points:

- Add `Foglet.Oneliners` to `FogletBbs.Application` children.
- Reuse Phoenix PubSub and `Foglet.TUI.PubSubForwarder`; do not add a second cache or message bus.
- Reuse `Hammer` if shoutbox posting needs throttling.

### 4. Extend typed runtime config only where operators need it

Required:

- Keep using `Foglet.Config.Schema` and typed accessors for operator policy.
- Existing invite config keys are already correctly placed there.

Optional but likely worthwhile:

- Promote `oneliners_max_length` from aspirational docs into `Foglet.Config.Schema` if sysops must tune shoutbox policy from the TUI in this milestone.

Not required for this milestone:

- A broad config-system rewrite
- A separate settings service
- Feature-flag libraries

## Installation

```bash
# Required addition
mix deps.get timex
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| `Timex` | Elixir stdlib-only timezone handling | Use the stdlib-only route only if the project deliberately backs away from the approved milestone dependency decision. |
| `users.preferences` JSONB + Ecto validation | Separate `user_preferences` table | Only if preferences become query-heavy, reportable, or independently versioned. Current needs are small and presentation-only. |
| Existing PubSub + OTP intervals + optional existing Oban | New cron/scheduler/job dependency | Do not use an alternative here. If cleanup becomes necessary, use existing Oban rather than adding another job system. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `ex_cldr_dates_times` or a broader i18n stack for this milestone | Too much surface area for the current needs; the project only needs timezone-aware rendering and 12h/24h presentation | `Timex ~> 3.7` plus stdlib date/time handling |
| Invite-code helper libs (`nanoid`, `hashids`, short-ID packages) | Unnecessary dependency for a small, security-sensitive code path | `:crypto.strong_rand_bytes/1` + `Base.encode32/2` or `Base.url_encode64/2` |
| New scheduler/cron/job deps | Minute clock refresh and synchronous redemption do not need background infrastructure | Existing Raxol interval subscriptions; existing Oban only if later cleanup is actually required |
| New cache/event-bus deps (`Cachex`, custom message broker, etc.) | Oneliners only need a small in-memory ring buffer and PubSub fanout | Existing OTP GenServer + Phoenix PubSub |
| New date/time parsing deps | The milestone renders time; it does not require free-form date parsing | Stdlib only; if parsing ever appears, follow project guidance and evaluate `date_time_parser` then |

## Stack Patterns by Variant

**If timezone choice is user-editable now:**

- Validate against real IANA names, not ad hoc abbreviations like `CST`.
- Validate against Timex-supported canonical IANA names before saving.
- Keep the persisted value as the canonical IANA name.

**If invite codes are single-use only:**

- Keep the schema simple: digest, created_by_id, redeemed_by_id, redeemed_at, expires_at, revoked_at.
- Do not add background cleanup; reject expired or already-used codes at redemption time.

**If invites later need reusable multi-use batches:**

- Add `max_uses` and `use_count` columns and keep redemption transactional in Postgres.
- Still do not add a separate invite service or queue.

**If the product later needs locale-aware month/day names:**

- Re-evaluate CLDR at that point.
- Do not bring CLDR in just to switch between `02:15 PM` and `14:15`.

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| `elixir 1.19.5` | `Timex ~> 3.7` | Timex is widely used in Elixir applications for timezone-aware date rendering and fits the approved milestone dependency choice. |
| `phoenix 1.8.5` / `ecto_sql 3.13` | `Timex ~> 3.7` | No framework-level coupling; Timex sits at the application layer for parsing, shifting, and formatting user-local time. |
| Existing Raxol runtime | Existing PubSub + interval subscriptions | Main-menu time refresh and oneliner updates fit the current TUI event model. |

## Sources

- Local project context: `.planning/PROJECT.md`, `docs/ARCHITECTURE.md`, `docs/DATA_MODEL.md`, `.planning/codebase/CONCERNS.md`, `lib/foglet_bbs/config/schema.ex`, `lib/foglet_bbs/accounts/user.ex`
- Elixir `Calendar` docs — https://hexdocs.pm/elixir/Calendar.html
- Elixir `DateTime` docs — https://hexdocs.pm/elixir/DateTime.html
- Timex docs — https://hexdocs.pm/timex/Timex.html
- Timex getting started / formatting docs — https://hexdocs.pm/timex/getting-started.html
- Hex package metadata for current `timex` release — https://hex.pm/packages/timex

---
*Stack research for: operations surfaces, invites, preference-driven time rendering, and oneliners*
*Researched: 2026-04-23*
