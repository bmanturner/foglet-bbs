# Phase 7: Oneliners and Main Menu Social Strip - Research

**Researched:** 2026-04-24
**Domain:** Phoenix/Ecto domain context plus Raxol terminal UI integration
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Add `Foglet.Oneliners` and `Foglet.Oneliners.Entry` as a normal Ecto context/schema backed directly by Postgres.
- **D-02:** Do not require a GenServer ring buffer in Phase 7. Persistence and recent-list queries from the database are sufficient for this phase; any future cache must remain secondary to Postgres.
- **D-03:** The public domain API should include a create path for authenticated users and a bounded recent-visible listing path for main-menu rendering.
- **D-04:** The oneliner schema uses the locked/documented shape: `body`, `hidden`, `hidden_reason`, `user_id`, `hidden_by_id`, and `timestamps(updated_at: false)`.
- **D-05:** Set `user_id` from the authenticated actor in the context/API path, not through `cast/3` caller attrs.
- **D-06:** Enforce the Phase 7 hard body limit of 120 characters and reject blank bodies without inserting a row.
- **D-07:** Accepted entries default to `hidden: false`.
- **D-08:** Prevent the same user from posting two visible oneliners in a row. If the latest visible oneliner belongs to the current actor, creation returns a clear validation/domain error without inserting a row.
- **D-09:** Recent listing returns visible entries only, newest first, capped to the requested limit.
- **D-10:** The listing API preloads author data needed by the TUI so rendering can show handles without relying on nonexistent lazy loading.
- **D-11:** Hidden-entry support may exist in the schema for Phase 8, but Phase 7 UI must not expose hide behavior.
- **D-12:** `Foglet.TUI.Screens.MainMenu` remains a pure/stateless renderer with no public `init_screen_state/1`.
- **D-13:** `MainMenu.render/1` reads recent oneliners already loaded into app state and renders them in the locked horizontal `split_pane` layout: navigation on the left, `Oneliners` panel on the right.
- **D-14:** Oneliner rows render as `@handle  body`, keep each entry to one visual row, cap/clip long handles around the locked 12-character presentation target, truncate or clip body text to the pane width, and omit timestamps.
- **D-15:** Existing navigation text, role-gated Account/Moderation/Sysop entries, key bindings, key-bar affordances, and 80x24 layout smoke expectations must remain intact.
- **D-16:** `Foglet.TUI.App` owns oneliner loading and refresh command tasks rather than running database reads inside `MainMenu.render/1`.
- **D-17:** Opening or returning to the main menu should trigger a bounded recent-oneliner load so the strip can render current persisted data.
- **D-18:** After a successful oneliner post, refresh the loaded recent-oneliner list and return to `:main_menu`.
- **D-19:** Do not add chat-like live typing, replies, reactions, or broad real-time conversation behavior in Phase 7.
- **D-20:** The `[O]` main-menu key opens a focused oneliner composer/modal using existing modal/form/input infrastructure, not a separate full-screen composer and not inline text-entry state inside `MainMenu`.
- **D-21:** Valid submit persists one oneliner, closes the focused composer/modal, refreshes recent oneliners, and returns to the main menu.
- **D-22:** Invalid submit, including blank, over-length, or back-to-back same-user posting, keeps the composer/modal focused and surfaces a visible validation/domain error without inserting a row.
- **D-23:** Cancel returns to the main menu without creating an oneliner.
- **D-24:** Add database-backed tests for persistence, schema shape, hidden default, 120-character acceptance, 121-character rejection, blank rejection, visible-only newest-first listing, author preload, and back-to-back same-user rejection.
- **D-25:** Add TUI tests for zero, one, and many oneliners in the split-pane main-menu layout, including long handle/body row clipping and no timestamp rendering.
- **D-26:** Add TUI/app tests proving `[O]` opens the focused composer/modal, valid submit persists and refreshes, invalid submit stays focused with error, cancel creates no row, and no Phase 7 UI exposes moderation hide behavior.
- **D-27:** `mix precommit` must pass before the phase is considered complete.

### Claude's Discretion
- Exact module/function names inside `Foglet.Oneliners`, as long as the public API is clear and tested.
- Exact recent-oneliner display limit, as long as it is bounded and the TUI tests cover overflow.
- Exact copy for empty state, validation errors, and success feedback.
- Whether the focused composer uses `Foglet.TUI.Widgets.Modal.Form` directly or a small dedicated wrapper around the same modal/input primitives, as long as it stays focused and does not make `MainMenu` stateful.
- Exact command/message names for load, submit, and refresh paths in `Foglet.TUI.App`.

### Deferred Ideas (OUT OF SCOPE)
- A 24-hour per-user oneliner cooldown configurable by sysops - defer to a future policy/config phase because Phase 7 explicitly excludes sysop-editable oneliner policy, configurable max length, and richer controls.
- Oneliner moderation hide UI - Phase 8 owns `MODR-05`.
- Oneliner retention windows, richer browsing, and broader oneliner controls - v2 scope under `SYSO-06` and `ONEL-04`.
</user_constraints>

## Project Constraints (from CLAUDE.md)

- Run `mix precommit` after changes and fix failures; it runs compile warnings-as-errors, format, Credo strict, Sobelow, and Dialyzer. [VERIFIED: CLAUDE.md]
- Use `Req` for HTTP if needed, and do not add `:httpoison`, `:tesla`, or `:httpc`; Phase 7 does not need HTTP. [VERIFIED: CLAUDE.md]
- Use Elixir stdlib date/time modules; Phase 7 should not add date/time dependencies. [VERIFIED: CLAUDE.md]
- Read architecture, data model, Raxol, and widget docs before non-trivial TUI/data changes. [VERIFIED: CLAUDE.md]
- Do not place multiple modules in one file; structs do not implement `Access`; programmatically set `user_id` outside `cast/3`; generate migrations with `mix ecto.gen.migration`. [VERIFIED: CLAUDE.md]
- In tests, use `start_supervised!/1` for processes and avoid `Process.sleep/1` / `Process.alive?/1`. [VERIFIED: CLAUDE.md]

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ONEL-01 | User can view recent oneliners on the main menu. [VERIFIED: .planning/REQUIREMENTS.md] | Use app-owned recent-oneliner state, domain listing preload, and Raxol `split_pane`. [VERIFIED: 07-CONTEXT.md; docs/raxol/getting-started/WIDGET_GALLERY.md] |
| ONEL-02 | User can post a short oneliner from the main menu. [VERIFIED: .planning/REQUIREMENTS.md] | Use `[O]` dispatch to focused `Modal.Form`, then `Foglet.TUI.App` submit task. [VERIFIED: 07-CONTEXT.md; lib/foglet_bbs/tui/widgets/README.md] |
| ONEL-03 | Oneliner posts persist across restart and respect a bounded maximum length. [VERIFIED: .planning/REQUIREMENTS.md] | Use Postgres-backed Ecto schema/context with 120-character validation and persistence tests. [VERIFIED: 07-SPEC.md; docs/DATA_MODEL.md] |
</phase_requirements>

## Summary

Phase 7 should be implemented as a conventional Phoenix/Ecto domain context plus a thin Raxol UI integration. The authoritative state belongs in Postgres through `Foglet.Oneliners.Entry`; `Foglet.TUI.App` should load a bounded recent-visible list into app state and `MainMenu.render/1` should only render that state. [VERIFIED: 07-CONTEXT.md; docs/DATA_MODEL.md; lib/foglet_bbs/tui/app.ex]

Do not build a Phase 7 GenServer cache, chat-like PubSub loop, moderation workflow, or inline main-menu editor. The established local TUI pattern is pure screens plus app-owned command tasks and modal routing, and the available widgets already include `Modal.Form` and `TextInput` with max-length support. [VERIFIED: 07-CONTEXT.md; lib/foglet_bbs/tui/app.ex; lib/foglet_bbs/tui/widgets/modal/form.ex; lib/foglet_bbs/tui/widgets/input/text_input.ex]

**Primary recommendation:** Use `Foglet.Oneliners.create_entry(user, attrs)` and `Foglet.Oneliners.list_recent_visible(limit)` style APIs, backed by Ecto changesets/queries, then wire `Foglet.TUI.App` commands `:load_oneliners` and `:submit_oneliner` into a stateless split-pane `MainMenu`. [VERIFIED: local context/code scan]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Persist oneliner records | Database / Storage | API / Backend | Postgres is the source of truth for domain state, and Data Model defines `oneliners`. [VERIFIED: docs/ARCHITECTURE.md; docs/DATA_MODEL.md] |
| Validate/create oneliner | API / Backend | Database / Storage | Context functions own persistence, validations, ownership assignment, and tagged results. [VERIFIED: .planning/codebase/CONVENTIONS.md; CLAUDE.md] |
| Recent visible list | API / Backend | Database / Storage | Context query filters hidden rows, orders newest first, caps limit, and preloads author. [VERIFIED: 07-CONTEXT.md] |
| Main-menu strip rendering | Browser / Client equivalent: SSH TUI | API / Backend | Raxol screen renders loaded app state; it must not call the database. [VERIFIED: 07-CONTEXT.md; lib/foglet_bbs/tui/screens/main_menu.ex] |
| Composer flow | SSH TUI app layer | API / Backend | `Foglet.TUI.App` owns modal state and async command tasks; domain context performs submit. [VERIFIED: lib/foglet_bbs/tui/app.ex; lib/foglet_bbs/tui/widgets/modal/form.ex] |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Phoenix | 1.8.5 | Application shell and endpoint infrastructure | Already pinned; project is a Phoenix application. [VERIFIED: mix.exs; mix.lock] |
| Ecto SQL | 3.13.5 | Migrations, schemas, queries, Repo persistence | Project's documented data model and contexts use Ecto/Postgres. [VERIFIED: mix.exs; mix.lock; docs/DATA_MODEL.md] |
| Postgrex | 0.22.0 | PostgreSQL adapter | Existing DB adapter in lockfile. [VERIFIED: mix.lock] |
| Raxol | path dependency `vendor/raxol`; related packages 2.4.0 in lock | Terminal UI runtime and View DSL | Existing TUI app uses `Raxol.Core.Runtime.Application` and View DSL. [VERIFIED: mix.exs; mix.lock; lib/foglet_bbs/tui/app.ex] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| ExUnit | Elixir 1.19.5 built-in | Unit/integration tests | Use for domain and TUI tests. [VERIFIED: elixir --version; .planning/codebase/TESTING.md] |
| Ecto SQL Sandbox | via Ecto SQL 3.13.5 | Isolated DB tests | Use `FogletBbs.DataCase` for oneliner context/schema tests. [VERIFIED: .planning/codebase/TESTING.md] |
| Sobelow / Credo / Dialyxir | Sobelow 0.14.1, Credo 1.7.18, Dialyxir 1.4.7 | Quality/security/type gates | Covered by `mix precommit`. [VERIFIED: mix.lock; CLAUDE.md] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Ecto context/query | GenServer ring buffer | Deferred by locked D-02; cache is future optimization and Postgres remains authoritative. [VERIFIED: 07-CONTEXT.md; docs/ARCHITECTURE.md] |
| `Modal.Form` | Full-screen composer | Rejected by D-20; full-screen flow would make posting feel heavier and add unnecessary screen state. [VERIFIED: 07-CONTEXT.md] |
| `TextInput` max length | Custom input parser | Existing widget supports `max_length`; hand-rolled editing risks cursor/key regressions. [VERIFIED: lib/foglet_bbs/tui/widgets/input/text_input.ex] |

**Installation:** No new dependencies. [VERIFIED: mix.exs; 07-CONTEXT.md]

**Version verification:** Versions were read from `mix.lock` and local commands, not training data. [VERIFIED: mix.lock; elixir --version; mix --version]

## Architecture Patterns

### System Architecture Diagram

```text
[MainMenu key O]
      |
      v
[Foglet.TUI.App opens focused Modal.Form]
      |
      v
[Submit payload body]
      |
      v
[Foglet.TUI.App Command.task]
      |
      v
[Foglet.Oneliners.create_entry(user, %{body: body})]
      |
      +--> blank/too long/latest same user? --> changeset/domain error --> keep modal focused with errors
      |
      v
[Repo insert oneliners row: hidden=false, user_id actor-owned]
      |
      v
[Foglet.Oneliners.list_recent_visible(limit) preloads :user]
      |
      v
[App state recent_oneliners]
      |
      v
[MainMenu.render/1 split_pane: navigation left, Oneliners right]
```

### Recommended Project Structure

```text
lib/foglet_bbs/
├── oneliners.ex                    # Ecto context: create/list APIs
├── oneliners/
│   └── entry.ex                    # schema + changeset
└── tui/
    ├── app.ex                      # app state, command tasks, modal submit routing
    └── screens/main_menu.ex        # stateless split-pane render and O key dispatch

priv/repo/migrations/
└── *_create_oneliners.exs          # table, FKs, hidden default, partial index

test/foglet_bbs/
├── oneliners/oneliners_test.exs    # DataCase domain tests
├── tui/screens/main_menu_test.exs  # split-pane/row/key render tests
├── tui/app_test.exs                # modal submit/cancel/refresh tests
└── tui/layout_smoke_test.exs       # 80x24 smoke coverage
```

### Pattern 1: Context-Owned Actor Assignment

**What:** Build the changeset from `%Entry{user_id: user.id}` and cast only caller-owned content such as `:body`; do not cast `user_id`. [VERIFIED: CLAUDE.md; .planning/codebase/CONVENTIONS.md]

**When to use:** Every public create path for oneliners. [VERIFIED: 07-CONTEXT.md]

**Example:**

```elixir
# Source: CLAUDE.md + .planning/codebase/CONVENTIONS.md
def create_entry(%User{} = user, attrs) do
  %Entry{user_id: user.id}
  |> Entry.create_changeset(attrs)
  |> Repo.insert()
end
```

### Pattern 2: Query Preload Before Rendering

**What:** Recent listing query filters hidden rows, orders descending by `inserted_at`, limits, and preloads `:user`. [VERIFIED: 07-CONTEXT.md; docs/DATA_MODEL.md]

**When to use:** Any TUI path that needs `entry.user.handle`. [VERIFIED: 07-CONTEXT.md]

**Example:**

```elixir
# Source: docs/DATA_MODEL.md + 07-CONTEXT.md
from(e in Entry,
  where: e.hidden == false,
  order_by: [desc: e.inserted_at],
  limit: ^limit,
  preload: [:user]
)
```

### Pattern 3: App-Owned I/O, Stateless Screen Render

**What:** `MainMenu.handle_key/2` emits command tuples; `Foglet.TUI.App` converts them into `Foglet.TUI.Command.task/2` work and updates state on result. [VERIFIED: lib/foglet_bbs/tui/screens/main_menu.ex; lib/foglet_bbs/tui/app.ex]

**When to use:** Loading recent oneliners and submitting the composer. [VERIFIED: 07-CONTEXT.md]

**Example:**

```elixir
# Source: lib/foglet_bbs/tui/app.ex command-task pattern
defp do_update({:load_oneliners}, state) do
  oneliners_mod = domain_module(state, :oneliners)

  task =
    Foglet.TUI.Command.task(:load_oneliners, fn ->
      {:oneliners_loaded, oneliners_mod.list_recent_visible(@oneliner_limit)}
    end)

  {state, [task]}
end
```

### Anti-Patterns to Avoid

- **Database calls from `MainMenu.render/1`:** Render must be pure and use app state. [VERIFIED: 07-CONTEXT.md]
- **Inline editor state inside MainMenu:** D-12/D-20 require a stateless menu and focused modal. [VERIFIED: 07-CONTEXT.md]
- **Ring buffer as first implementation:** D-02 explicitly excludes it for Phase 7. [VERIFIED: 07-CONTEXT.md]
- **Casting `user_id`:** Ownership must be assigned by context code. [VERIFIED: CLAUDE.md]
- **Lazy author access:** Ecto has no lazy preload; the query must preload author data before rendering. [VERIFIED: CLAUDE.md; 07-CONTEXT.md]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Persistence and validation | Custom storage or ETS-only cache | Ecto schema/context + Postgres | Data model says Postgres is authoritative; restart persistence is required. [VERIFIED: docs/ARCHITECTURE.md; 07-SPEC.md] |
| Recent list caching | GenServer ring buffer | Direct bounded Ecto query | D-02 excludes Phase 7 cache requirement. [VERIFIED: 07-CONTEXT.md] |
| Text input editing | Custom key buffer | `Foglet.TUI.Widgets.Input.TextInput` via `Modal.Form` | Existing widget handles key translation and `max_length`. [VERIFIED: lib/foglet_bbs/tui/widgets/input/text_input.ex] |
| Modal focus/routing | Screen-local modal state | `Foglet.TUI.App.modal` and `Modal.Form` | App already prevents underlying screens from consuming keys while modal is open. [VERIFIED: lib/foglet_bbs/tui/app.ex] |
| Authorization/moderation UI | Hide controls in Phase 7 | No UI for hide behavior | Phase 8 owns `MODR-05`; Phase 7 may only include schema fields. [VERIFIED: 07-CONTEXT.md; .planning/REQUIREMENTS.md] |

**Key insight:** The hard part is respecting ownership boundaries, not inventing infrastructure: persistence belongs to Ecto/Postgres, transient TUI state belongs to `Foglet.TUI.App`, and `MainMenu` remains a renderer. [VERIFIED: docs/ARCHITECTURE.md; 07-CONTEXT.md; lib/foglet_bbs/tui/app.ex]

## Common Pitfalls

### Pitfall 1: Back-to-Back Guard Race
**What goes wrong:** Two quick submissions can both see the same latest row and insert two visible entries for the same user. [ASSUMED]
**Why it happens:** The same-user guard is naturally a read-then-write operation. [ASSUMED]
**How to avoid:** Use an `Ecto.Multi` or `Repo.transact/1` path that checks latest visible entry immediately before insert; document residual concurrency risk if not locking. [VERIFIED: .planning/codebase/CONVENTIONS.md]
**Warning signs:** Tests only cover sequential calls and no transaction boundary is visible. [ASSUMED]

### Pitfall 2: Form Max Length Is Not Domain Validation
**What goes wrong:** UI prevents typing more than 120 chars but tests or alternate callers can still insert over-length bodies. [VERIFIED: lib/foglet_bbs/tui/widgets/input/text_input.ex; 07-SPEC.md]
**Why it happens:** `TextInput` is a UI control, not the authoritative domain boundary. [VERIFIED: .planning/codebase/CONVENTIONS.md]
**How to avoid:** Enforce length and blank checks in `Entry.create_changeset/2`; use TextInput `max_length: 120` only as UX. [VERIFIED: CLAUDE.md; 07-CONTEXT.md]
**Warning signs:** Only TUI tests cover 121-character rejection. [VERIFIED: 07-CONTEXT.md]

### Pitfall 3: Preload Omitted Until Render Test Fails
**What goes wrong:** `entry.user.handle` is unavailable or rendered as missing because the listing query returns bare entries. [VERIFIED: 07-CONTEXT.md; CLAUDE.md]
**Why it happens:** Ecto associations are not lazy loaded. [VERIFIED: CLAUDE.md]
**How to avoid:** Make `list_recent_visible/1` preload `:user` and assert `Ecto.assoc_loaded?(entry.user)`. [VERIFIED: 07-CONTEXT.md]
**Warning signs:** MainMenu tests create maps manually but domain tests do not assert author preload. [ASSUMED]

### Pitfall 4: Split Pane Crowds Existing Main Menu
**What goes wrong:** The right panel hides Account/Moderation/Sysop entries or keybar affordances at 80x24. [VERIFIED: 07-SPEC.md]
**Why it happens:** `split_pane` consumes horizontal width and existing smoke tests expect navigation to remain visible. [VERIFIED: docs/raxol/getting-started/WIDGET_GALLERY.md; 07-CONTEXT.md]
**How to avoid:** Keep navigation left, oneliners right, use the locked ratio/min size, and extend layout smoke tests. [VERIFIED: 07-SPEC.md]
**Warning signs:** Tests assert only text presence, not 80x24 render stability. [VERIFIED: test/foglet_bbs/tui/screens/main_menu_test.exs]

### Pitfall 5: Modal.Form Callback Semantics
**What goes wrong:** `Modal.Form.handle_event/2` calls `on_submit` and returns `:submitted`, but the caller still needs to update app state/errors afterward. [VERIFIED: lib/foglet_bbs/tui/widgets/modal/form.ex]
**Why it happens:** `Modal.Form` is stateful data, not a process; app code owns routing and modal replacement. [VERIFIED: lib/foglet_bbs/tui/widgets/README.md; lib/foglet_bbs/tui/app.ex]
**How to avoid:** Follow existing Sysop modal adaptation pattern: callback emits a submit message/command, and App updates modal errors or closes modal. [VERIFIED: lib/foglet_bbs/tui/screens/sysop/boards_view.ex; lib/foglet_bbs/tui/app.ex]
**Warning signs:** Invalid submit dismisses the modal or stores errors somewhere outside the form state. [VERIFIED: 07-CONTEXT.md]

## Code Examples

### Migration Shape

```elixir
# Source: docs/DATA_MODEL.md + mix help ecto.gen.migration
create table(:oneliners, primary_key: false) do
  add :id, :uuid, primary_key: true
  add :body, :string, null: false
  add :hidden, :boolean, null: false, default: false
  add :hidden_reason, :string
  add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
  add :hidden_by_id, references(:users, type: :uuid, on_delete: :nilify_all)

  timestamps(type: :utc_datetime_usec, updated_at: false)
end

create index(:oneliners, [:inserted_at], where: "hidden = false")
```

### Schema Changeset

```elixir
# Source: docs/DATA_MODEL.md + CLAUDE.md
schema "oneliners" do
  field :body, :string
  field :hidden, :boolean, default: false
  field :hidden_reason, :string

  belongs_to :user, Foglet.Accounts.User
  belongs_to :hidden_by, Foglet.Accounts.User

  timestamps(updated_at: false)
end

def create_changeset(entry, attrs) do
  entry
  |> cast(attrs, [:body])
  |> update_change(:body, &String.trim/1)
  |> validate_required([:body, :user_id])
  |> validate_length(:body, min: 1, max: 120)
end
```

### Main Menu Split Pane

```elixir
# Source: docs/raxol/getting-started/WIDGET_GALLERY.md + 07-SPEC.md
split_pane(
  direction: :horizontal,
  ratio: {2, 3},
  min_size: 24,
  children: [menu_panel, oneliners_panel]
)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Architecture doc's future `Foglet.Oneliners` GenServer ring buffer | Phase 7 direct Ecto context/query, no required cache | Locked in Phase 7 context on 2026-04-24 | Planner must not introduce cache work in this phase. [VERIFIED: docs/ARCHITECTURE.md; 07-CONTEXT.md] |
| Full-screen or inline composer | Focused modal/form launched by `[O]` | Locked in Phase 7 spec/context on 2026-04-24 | MainMenu remains stateless. [VERIFIED: 07-SPEC.md; 07-CONTEXT.md] |
| Timestamped feed/chat presentation | Compact `@handle  body`, no timestamps | Locked in Phase 7 spec/context on 2026-04-24 | Strip stays atmospheric, not chat-like. [VERIFIED: 07-SPEC.md] |

**Deprecated/outdated:**
- Treating the data-model ring buffer note as Phase 7 scope is outdated for this phase; D-02 supersedes it. [VERIFIED: 07-CONTEXT.md]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Concurrent double-submit can bypass a naive read-then-write same-user guard. | Common Pitfalls | May need stronger transaction/locking plan if concurrent TUI submits are possible. |
| A2 | Sequential tests may miss preload or race issues if they only use manually shaped maps. | Common Pitfalls | Planner should include explicit domain assertions. |

## Open Questions

1. **Should the same-user guard be transactionally locked?**
   - What we know: The behavior is locked; latest visible same-user insert must fail. [VERIFIED: 07-CONTEXT.md]
   - What's unclear: The project has no existing oneliner table, so there is no established local lock pattern for this exact invariant. [VERIFIED: codebase scan]
   - Recommendation: Implement the guard in the context immediately before insert, preferably inside `Repo.transact/1`; add sequential tests now and leave any stronger DB lock decision to implementation if a clean local pattern emerges. [VERIFIED: .planning/codebase/CONVENTIONS.md]

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Elixir | Mix tasks/tests | yes | 1.19.5 / OTP 28 | none |
| Mix | migration/test/precommit | yes | 1.19.5 | none |
| PostgreSQL client | DB development visibility | yes | psql 14.20 | `mix test` aliases create/migrate test DB |
| Raxol docs/vendor dep | TUI rendering | yes | path dep + 2.4.0 packages in lock | none |

**Missing dependencies with no fallback:** None found. [VERIFIED: elixir --version; mix --version; psql --version; mix.lock]

**Missing dependencies with fallback:** None found. [VERIFIED: local commands]

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit built into Elixir 1.19.5 [VERIFIED: elixir --version; .planning/codebase/TESTING.md] |
| Config file | `test/test_helper.exs`; DataCase at `test/support/data_case.ex` [VERIFIED: .planning/codebase/TESTING.md] |
| Quick run command | `mix test test/foglet_bbs/oneliners/oneliners_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/app_test.exs` |
| Full suite command | `mix precommit` |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| ONEL-01 | Recent visible strip renders in main menu split pane | TUI unit/smoke | `mix test test/foglet_bbs/tui/screens/main_menu_test.exs` | yes, extend |
| ONEL-01 | 80x24 layout keeps nav/keybar visible | TUI smoke | `mix test test/foglet_bbs/tui/layout_smoke_test.exs` | yes, extend |
| ONEL-02 | `[O]` opens modal; valid/invalid/cancel flow | TUI app integration | `mix test test/foglet_bbs/tui/app_test.exs` | yes, extend |
| ONEL-03 | Persist, validate, list recent visible, preload author | DB integration | `mix test test/foglet_bbs/oneliners/oneliners_test.exs` | no, Wave 0 |

### Sampling Rate

- **Per task commit:** `mix test` for the touched test file(s). [VERIFIED: mix help test]
- **Per wave merge:** `mix test test/foglet_bbs/oneliners/oneliners_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`. [VERIFIED: local test structure]
- **Phase gate:** `mix precommit` green before `/gsd-verify-work`. [VERIFIED: CLAUDE.md]

### Wave 0 Gaps

- [ ] `test/foglet_bbs/oneliners/oneliners_test.exs` - covers ONEL-03 persistence/listing/validation. [VERIFIED: file absent from code scan]
- [ ] Migration file under `priv/repo/migrations/` - required before DataCase tests can pass. [VERIFIED: docs/DATA_MODEL.md]
- [ ] MainMenu/App tests need extension for ONEL-01/ONEL-02. [VERIFIED: test/foglet_bbs/tui/screens/main_menu_test.exs; test/foglet_bbs/tui/app_test.exs]

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | yes | Require `current_user` actor for create path; no anonymous posts. [VERIFIED: 07-SPEC.md] |
| V3 Session Management | yes | Use existing session/TUI app state; do not create new session behavior. [VERIFIED: docs/ARCHITECTURE.md; lib/foglet_bbs/tui/app.ex] |
| V4 Access Control | yes | Domain API sets `user_id` from authenticated actor; Phase 7 exposes no hide UI. [VERIFIED: 07-CONTEXT.md; CLAUDE.md] |
| V5 Input Validation | yes | Ecto changeset trims/rejects blank and validates max length 120. [VERIFIED: 07-CONTEXT.md] |
| V6 Cryptography | no | Phase 7 does not introduce cryptographic operations. [VERIFIED: 07-SPEC.md] |

### Known Threat Patterns for Phoenix/Ecto TUI

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Actor spoofing via caller-supplied `user_id` | Spoofing/Elevation of Privilege | Never cast `user_id`; assign from authenticated user in context. [VERIFIED: CLAUDE.md; 07-CONTEXT.md] |
| Abuse/noise from repeated same-user posts | Denial of Service | Reject latest-visible same-user posting. [VERIFIED: 07-CONTEXT.md] |
| Hidden/moderated content leaking into main menu | Information Disclosure | Listing query filters `hidden == false`; Phase 7 UI exposes no hide controls. [VERIFIED: 07-CONTEXT.md] |
| Terminal layout corruption from long text | Denial of Service | Hard body cap plus one-row clipping/truncation in render tests. [VERIFIED: 07-SPEC.md] |

## Sources

### Primary (HIGH confidence)
- `CLAUDE.md` - project directives, Ecto/test gotchas, precommit requirement.
- `.planning/phases/07-oneliners-and-main-menu-social-strip/07-CONTEXT.md` - locked decisions and implementation boundaries.
- `.planning/phases/07-oneliners-and-main-menu-social-strip/07-SPEC.md` - requirements, acceptance criteria, UI constraints.
- `.planning/REQUIREMENTS.md` - ONEL-01, ONEL-02, ONEL-03.
- `docs/ARCHITECTURE.md` - domain/Postgres source-of-truth and future ring-buffer context.
- `docs/DATA_MODEL.md` - oneliners schema, indexes, relationships.
- `docs/raxol/getting-started/WIDGET_GALLERY.md` - `split_pane` and View DSL primitives.
- `lib/foglet_bbs/tui/app.ex` - app-owned state, command tasks, modal routing.
- `lib/foglet_bbs/tui/screens/main_menu.ex` - current stateless menu implementation.
- `lib/foglet_bbs/tui/widgets/modal/form.ex` and `lib/foglet_bbs/tui/widgets/input/text_input.ex` - composer primitives.
- `mix.exs` and `mix.lock` - dependency stack and versions.

### Secondary (MEDIUM confidence)
- `.planning/codebase/CONVENTIONS.md` and `.planning/codebase/TESTING.md` - generated codebase conventions and test patterns verified against local files.
- `mix help ecto.gen.migration` and `mix help test` - task behavior verified locally.

### Tertiary (LOW confidence)
- Assumptions about concurrent same-user posting race risk; not proven by current code because oneliner implementation does not yet exist.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - verified from `mix.exs`, `mix.lock`, and local docs.
- Architecture: HIGH - phase decisions, app/screen code, and data-model docs agree.
- Pitfalls: MEDIUM - most are verified local constraints; concurrency race concern is a design-risk assumption.

**Research date:** 2026-04-24
**Valid until:** 2026-05-24 for local architecture; re-check dependency versions before adding/upgrading packages.
