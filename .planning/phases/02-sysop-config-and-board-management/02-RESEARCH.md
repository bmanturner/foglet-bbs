# Phase 2: Sysop Config and Board Management — Research

**Researched:** 2026-04-23
**Domain:** Elixir/Phoenix TUI — sysop admin flows, typed runtime config, Ecto category/board CRUD, Raxol Modal.Form
**Confidence:** HIGH — all findings are VERIFIED against live codebase artifacts

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Config surface (D-01 – D-05)**
- SITE and LIMITS tabs render by iterating `Foglet.Config.Schema.entries/0` and `Schema.fetch_spec/1` — never by reading rows directly from the `configuration` table.
- Tab partition is encoded as two module attributes `@site_keys` and `@limits_keys` on the Sysop screen. A test enforces every `Schema.entries/0` key appears in exactly one list.
- SITE keys: `registration_mode`, `invite_code_generators`, `require_email_verification`, plus new `invite_generation_per_user_limit`.
- LIMITS keys: `max_post_length`, `max_thread_title_length`, `email_verify_resend_cooldown_seconds`.
- INVT-07 adds ONE new schematized integer key `invite_generation_per_user_limit` (type `:integer`, `min: 0`, default `0`, where `0` = unlimited). No new `:union`/`:nullable` plumbing.
- `invite_generation_per_user_limit` row is conditionally visible only when `invite_code_generators == "any_user"`, hidden otherwise.
- SITE tab does NOT expose site identity or unschematized keys. USERS tab remains Phase 0 scaffold.

**Config write path (D-06 – D-09)**
- TUI calls `Foglet.Config.put/3` (actor-aware tagged-tuple), NEVER `put!/3`.
- Validation errors surface INLINE under the offending field using `theme.error.fg` via `Modal.Form.set_errors/2`.
- Non-recoverable errors (`:forbidden`, `:db_error`) route to `%Foglet.TUI.Modal{type: :error}` + return to `:main_menu`.
- No PubSub broadcasts on config writes; ETS invalidation in `do_put!/3` is the sole propagation mechanism.

**Boards & Categories domain (D-10 – D-12)**
- Category CRUD is additive to `Foglet.Boards` — NO separate `Foglet.Categories` module.
- New functions: `create_category/2` (actor-first), `update_category/3`, `archive_category/2`.
- `Foglet.Boards.Category` gains `archive_changeset/1` mirroring `Board.archive_changeset/1`.
- `archive_board/2` keeps flag-flip behavior — no `DynamicSupervisor.terminate_child/2` in this phase.

**Screen architecture (D-13 – D-19)**
- `Sysop.State` grows per-tab fields: `site_form`, `limits_form`, `boards_view`, `system_snapshot`.
- Each tab owns a submodule under `lib/foglet_bbs/tui/screens/sysop/`: `site_form.ex`, `limits_form.ex`, `boards_view.ex`, `system_snapshot.ex`, each exposing `init/1 + handle_key/2 + render/2`.
- SITE and LIMITS render as full-tab inline forms (NOT in a modal), with explicit `[Ctrl+S] Save`.
- BOARDS tab renders a vertically-stacked list grouped by category using `SelectionList` + `ListRow`. Create/edit uses `Modal.Form` inside `render_modal_overlay/2`. `Modal.Form.render/2` must not be wrapped in its own border.
- BOARDS archive uses existing `%Foglet.TUI.Modal{type: :confirm}` Y/N prompt — NOT `Modal.Form`.
- SITE and LIMITS field types mirror `Modal.Form` types; fallback to `TextInput`/`Checkbox`/`RadioGroup` if inline adapter cost is prohibitive.

**SYSTEM tab (D-20 – D-21)**
- Read-only snapshot. Snapshot on tab enter; `r` keypress re-samples. No auto-refresh.
- Snapshot fields: BBS version, uptime, active session count, active board server count, OTP process count, DB pool size.

**Authorization wiring (D-22 – D-24)**
- Every domain call passes `state.current_user` as actor and `:site` as scope.
- No advisory `permit?/4` in the screen render path. `ShellVisibility.sysop_visible?/1` is the only UI-level gate.
- `{:error, :forbidden}` = "actor was demoted mid-session" — route to error modal + `:main_menu`.

**Testing (D-25 – D-27)**
- Extend existing `config_test.exs`, `boards_test.exs`, `sysop_test.exs`.
- TUI tests use `collect_text_values/1` and `%Foglet.TUI.App{}` struct directly.
- All persistence tests use `FogletBbs.DataCase, async: false` (ETS table is process-global).

**Quality gate (D-28)**
- `mix precommit` must pass before phase is done.

### Claude's Discretion
- Exact field ordering within SITE / LIMITS / BOARDS forms (recommend declaration order from `Schema.entries/0`).
- Whether `invite_generation_per_user_limit` row hides or greys out when not applicable (recommend HIDE).
- Whether `:db_error` surfaces as distinct message vs generic (recommend distinct with reason, sysop audience).
- Whether inline SITE/LIMITS submit triggers on `Ctrl+S` only or also `Enter` on last field (recommend `Ctrl+S` ONLY).

### Deferred Ideas (OUT OF SCOPE)
- Site identity fields (name, MOTD, login banner).
- USERS tab content (Phase 8).
- Invite generation/redemption UI (Phase 3/4).
- Aspirational operational limits (rate limits, retention days, oneliner caps).
- Real-time cross-session config reactivity via PubSub.
- `BoardSupervisor.stop_board/1` for immediate-offline board archival.
- Auto-refreshing SYSTEM tab.
- Advisory `permit?/4` checks on row-level disable states.
- Per-tab submodule test split (planner's discretion).
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| INVT-06 | Sysop can set invite generation policy to `sysop_only`, `mods`, or `any_user` | SITE tab inline form writing `invite_code_generators` via `Config.put/3`; schema entry and enum already defined |
| INVT-07 | Sysop can set per-user invite generation limit (unlimited or numeric cap) when `any_user` is enabled | New schematized key `invite_generation_per_user_limit` added to `Config.Schema`; conditional row visibility |
| SYSO-02 | Sysop can edit seeded runtime config values for registration, invite policy, and limits | SITE and LIMITS tabs iterate schema entries; validated through `Config.put/3` |
| SYSO-03 | Sysop can create, update, list, and archive categories and boards from the `BOARDS` tab | Actor-aware `create_category/2`, `update_category/3`, `archive_category/2` added to `Foglet.Boards`; BOARDS tab with `Modal.Form` |
| SYSO-04 | Sysop can inspect system details from the `SYSTEM` tab | Read-only snapshot submodule using BEAM/OTP introspection APIs |
</phase_requirements>

---

## Summary

Phase 2 delivers real behavior behind the Phase 0 Sysop workspace scaffold. It touches three distinct concerns: (1) typed runtime config editing across SITE and LIMITS tabs, (2) board/category CRUD via the BOARDS tab, and (3) a read-only SYSTEM tab snapshot. All three sit on top of the authorization backbone from Phase 1 and the `Modal.Form` primitive from Phase 1.1.

The codebase is highly prepared for this work. `Foglet.Config`, `Foglet.Config.Schema`, and `Foglet.Boards` already exist with the right write paths; the Phase 1 Bodyguard pattern is established throughout; and `Modal.Form` is ready to consume. The primary additive work is: (a) one new schematized config key, (b) three actor-first category domain functions with `archive_changeset/1`, (c) four per-tab submodules for the Sysop screen, and (d) extending the `Sysop.State` struct to hold per-tab form/view state.

The most consequential design constraint is that the SITE and LIMITS tabs render inline (not in a modal) by iterating `Schema.entries/0` — unschematized keys are structurally excluded because no schema entry exists for them. This is the guardrail for SYSO-02 success criterion 1. The BOARDS tab is the only tab that uses `Modal.Form` inside `render_modal_overlay/2`.

**Primary recommendation:** Follow the CONTEXT.md decisions exactly. The scaffold, write paths, widget primitives, and test infrastructure are all present; the phase is additive and well-bounded.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Config schema validation | Domain (`Foglet.Config.Schema`) | — | Pure-data module, no DB dependency; validates before any write |
| Config read/write | Domain (`Foglet.Config`) | ETS cache | Actor-aware `put/3`; ETS invalidation on write |
| Board/Category CRUD | Domain (`Foglet.Boards`) | DB (`Foglet.Boards.Board/Category`) | Actor-first functions with Bodyguard guards |
| SITE / LIMITS tab rendering | TUI Screen submodule (`sysop/site_form.ex`, `sysop/limits_form.ex`) | `Foglet.TUI.Widgets.Input.*` | Inline form; delegates field widgets to Input primitives |
| BOARDS tab list + modals | TUI Screen submodule (`sysop/boards_view.ex`) | `Modal.Form`, `SelectionList` | Owns list state AND active modal state |
| SYSTEM tab snapshot | TUI Screen submodule (`sysop/system_snapshot.ex`) | BEAM/OTP APIs | Pure read from `:erlang.*`, `Registry`, `DynamicSupervisor` |
| Authorization gate (screen level) | `Foglet.TUI.ShellVisibility` | — | `sysop_visible?/1` only; no advisory per-row checks |
| Authorization enforcement | Domain (`Foglet.Authorization` via Bodyguard) | — | Trust boundary is the domain, not the TUI |

---

## Standard Stack

### Core (all already in mix.deps)
| Library | Purpose | Verified Location |
|---------|---------|-------------------|
| `Foglet.Config` / `Foglet.Config.Schema` | Runtime config read/write/validate | `lib/foglet_bbs/config.ex`, `lib/foglet_bbs/config/schema.ex` |
| `Foglet.Boards` | Category and board CRUD | `lib/foglet_bbs/boards.ex` |
| `Foglet.TUI.Widgets.Modal.Form` | BOARDS create/edit modal form | `lib/foglet_bbs/tui/widgets/modal/form.ex` |
| `Foglet.TUI.Widgets.Input.{TextInput, Checkbox, RadioGroup}` | SITE/LIMITS inline field widgets | `lib/foglet_bbs/tui/widgets/input/` |
| `Foglet.TUI.Widgets.List.{SelectionList, ListRow}` | BOARDS tab grouped list | used in `new_thread.ex:77-80` |
| `Foglet.TUI.Modal` (`:confirm` / `:error` variants) | Archive confirmation + error routing | `lib/foglet_bbs/tui/modal.ex` |
| `Foglet.TUI.App.render_modal_overlay/2` | Modal chrome slot | `lib/foglet_bbs/tui/app.ex` |
| `Bodyguard` | Actor-aware authorization | `lib/foglet_bbs/authorization.ex` |
| `Ecto` / `FogletBbs.Repo` | Persistence for board/category CRUD | throughout `lib/foglet_bbs/` |

**No new dependencies required for this phase.**

---

## Architecture Patterns

### System Architecture Diagram

```
Keyboard input
      │
      ▼
Foglet.TUI.App (conductor)
      │ routes to active screen
      ▼
Foglet.TUI.Screens.Sysop (tab-bar + delegation)
      │ delegates non-tab-bar keys to active tab submodule
      ├──► sysop/site_form.ex ──► Config.put/3 ──► Config.Schema.validate ──► DB + ETS invalidate
      ├──► sysop/limits_form.ex ──► Config.put/3 ──► (same path)
      ├──► sysop/boards_view.ex
      │         │
      │         ├── list path ──► Boards.list_categories/Boards.list_boards ──► DB
      │         └── modal path ──► Modal.Form ──► Boards.{create,update,archive}_category/board ──► DB
      ├──► sysop/system_snapshot.ex ──► :erlang.* / Registry / DynamicSupervisor (read-only)
      └──► [USERS: Phase 0 placeholder — no change]

Error paths:
  {:error, :forbidden}  ──► Foglet.TUI.Modal{type: :error} ──► :main_menu
  {:error, :db_error}   ──► Foglet.TUI.Modal{type: :error} ──► :main_menu
  {:error, :invalid_value} | {:error, :unknown_key} ──► Modal.Form.set_errors/2 (inline under field)
```

### Recommended Project Structure (additive changes only)

```
lib/foglet_bbs/
├── config/
│   └── schema.ex            # ADD: invite_generation_per_user_limit entry
├── boards/
│   └── category.ex          # ADD: archive_changeset/1
├── boards.ex                # ADD: create_category/2, update_category/3, archive_category/2
└── tui/
    └── screens/
        └── sysop/
            ├── state.ex     # MODIFY: add site_form, limits_form, boards_view, system_snapshot fields
            ├── site_form.ex     # NEW
            ├── limits_form.ex   # NEW
            ├── boards_view.ex   # NEW
            └── system_snapshot.ex # NEW

test/foglet_bbs/
├── config_test.exs          # EXTEND: invite_generation_per_user_limit cases
├── boards/
│   └── boards_test.exs      # EXTEND: update_category/3, archive_category/2, create_category/2 (actor-first)
└── tui/screens/
    └── sysop_test.exs       # EXTEND: per-tab render + key smoke tests
```

### Pattern 1: New Schematized Config Key (INVT-07)

**What:** Add `invite_generation_per_user_limit` to `@entries` in `Foglet.Config.Schema`.
**When to use:** Any time a new runtime-editable key is needed. Schema entry is prerequisite to TUI exposure.

```elixir
# Source: lib/foglet_bbs/config/schema.ex — append to @entries
%{
  key: "invite_generation_per_user_limit",
  type: :integer,
  default: 0,
  description: "Per-user invite generation cap when any_user mode is active. 0 = unlimited (INVT-07 D-04).",
  enum: nil,
  min: 0,
  max: nil
}
```

Also add a typed accessor to `Foglet.Config`:
```elixir
# Source: lib/foglet_bbs/config.ex (typed accessors section)
@spec invite_generation_per_user_limit() :: non_neg_integer()
def invite_generation_per_user_limit, do: get!("invite_generation_per_user_limit")
```

And seed it in `priv/repo/seeds.exs` following the existing `[seed]` log pattern.

### Pattern 2: Actor-First Category Domain Function (D-10)

**What:** Widen `Foglet.Boards` to include actor-aware category mutations mirroring the board CRUD pattern.
**When to use:** Any time category state is changed from the TUI — must go through an actor-first function.

```elixir
# Source: lib/foglet_bbs/boards.ex — modelled on create_board/3 (lines 71-102) and archive_board/2 (lines 125-131)

@spec create_category(Foglet.Accounts.User.t() | nil, map()) ::
        {:ok, Category.t()} | {:error, Ecto.Changeset.t()} | {:error, :forbidden}
def create_category(actor, attrs) do
  with :ok <- Bodyguard.permit(Foglet.Authorization, :create_category, actor, :site) do
    %Category{}
    |> Category.changeset(attrs)
    |> Repo.insert()
  end
end

@spec update_category(Foglet.Accounts.User.t() | nil, Category.t(), map()) ::
        {:ok, Category.t()} | {:error, Ecto.Changeset.t()} | {:error, :forbidden}
def update_category(actor, %Category{} = category, attrs) do
  with :ok <- Bodyguard.permit(Foglet.Authorization, :update_category, actor, :site) do
    category
    |> Category.changeset(attrs)
    |> Repo.update()
  end
end

@spec archive_category(Foglet.Accounts.User.t() | nil, Category.t()) ::
        {:ok, Category.t()} | {:error, Ecto.Changeset.t()} | {:error, :forbidden}
def archive_category(actor, %Category{} = category) do
  with :ok <- Bodyguard.permit(Foglet.Authorization, :archive_category, actor, :site) do
    category
    |> Category.archive_changeset()
    |> Repo.update()
  end
end
```

`Category.archive_changeset/1` mirrors `Board.archive_changeset/1` [VERIFIED: `lib/foglet_bbs/boards/board.ex:55-59`]:
```elixir
def archive_changeset(category) do
  category
  |> cast(%{archived: true}, [:archived])
  |> validate_required([:archived])
end
```

**Authorization action atoms** (`:create_category`, `:update_category`, `:archive_category`) must be added to the `Foglet.Authorization` action allowlist [VERIFIED: Phase 1 D-12 pattern].

### Pattern 3: Sysop State Expansion (D-13)

**What:** Extend `Sysop.State` with per-tab submodule state. Draft is retained across tab switches.

```elixir
# Source: lib/foglet_bbs/tui/screens/sysop/state.ex — extend existing struct

@type t :: %__MODULE__{
        tabs: Tabs.t(),
        active_tab: non_neg_integer(),
        site_form: Foglet.TUI.Screens.Sysop.SiteForm.t() | nil,
        limits_form: Foglet.TUI.Screens.Sysop.LimitsForm.t() | nil,
        boards_view: Foglet.TUI.Screens.Sysop.BoardsView.t() | nil,
        system_snapshot: Foglet.TUI.Screens.Sysop.SystemSnapshot.t() | nil
      }

defstruct [:tabs, active_tab: 0, site_form: nil, limits_form: nil, boards_view: nil, system_snapshot: nil]
```

Each submodule field is `nil` until the tab is first entered; `init/1` is called lazily on first tab activation.

### Pattern 4: Per-Tab Submodule Shape (D-14)

**What:** Each of the four new submodules exposes the standard triplet.

```elixir
# Example shape — all four submodules follow this contract
defmodule Foglet.TUI.Screens.Sysop.SiteForm do
  @moduledoc "..."

  @type t :: %__MODULE__{...}
  defstruct [...]

  @spec init(keyword()) :: t()
  def init(opts \\ []), do: ...

  @spec handle_key(map(), t()) :: {t(), [{atom(), any()}]}
  def handle_key(event, state), do: ...

  @spec render(t(), map()) :: any()
  def render(state, theme), do: ...
end
```

The parent `Sysop` screen delegates non-tab-bar events to the active tab's submodule via the submodule's `handle_key/2`.

### Pattern 5: Inline Config Form (SITE / LIMITS, D-15 / D-19)

**What:** Render config fields inline on the tab surface (no modal), with explicit `[Ctrl+S] Save`.

Key implementation notes:
- Iterate `@site_keys` / `@limits_keys` and call `Schema.fetch_spec/1` for each to get type, enum, min/max, description.
- For `:string` with `enum:` list → `RadioGroup` or `Checkbox` (single-selection).
- For `:integer` → `TextInput` (integer mode, min-validated on submit).
- For `:boolean` → `Checkbox`.
- On `Ctrl+S`: collect field values, call `Config.put/3` for each dirty field, surface inline errors or error modal.
- `Ctrl+S` detection: `%{key: :ctrl_s}` — verify against `new_thread.ex:139` for exact event shape [VERIFIED: `new_thread.ex:237`].

### Pattern 6: BOARDS Tab with Modal.Form (D-16 / D-17)

**What:** Vertically-stacked category+board list; create/edit opens `Modal.Form` in the overlay slot.

```elixir
# BoardsView state holds: list data, selected index, active modal (nil | Modal.Form.t())
# On 'n' (new board): Modal.Form.init(fields: [...board fields...], on_submit: ..., on_cancel: ...)
# On 'e' (edit): Modal.Form.init with pre-populated field values
# On 'D' (archive): %Foglet.TUI.Modal{type: :confirm, ...}
# render/2: if boards_view.modal, render list + overlay; else render list only
```

`Modal.Form` field spec for a board:
```elixir
[
  %{name: :slug,        type: :text,     label: "Slug",        max_length: 50},
  %{name: :name,        type: :text,     label: "Name",        max_length: 100},
  %{name: :description, type: :textarea, label: "Description"},
  %{name: :category_id, type: :enum,     label: "Category",    options: category_options},
  %{name: :postable_by, type: :enum,     label: "Postable by", options: ["members", "mods_only", "sysop_only"]}
]
```

### Pattern 7: SYSTEM Snapshot (D-20 / D-21)

**What:** One-shot introspection on tab enter and on `r` keypress.

```elixir
defp take_snapshot do
  {:ok, vsn} = :application.get_key(:foglet_bbs, :vsn)
  {wall_ms, _} = :erlang.statistics(:wall_clock)
  session_count = Registry.count(Foglet.Sessions.Registry)
  board_count = DynamicSupervisor.count_children(Foglet.Boards.Supervisor).active
  process_count = :erlang.system_info(:process_count)
  pool_size = FogletBbs.Repo.config()[:pool_size]

  %{
    version: to_string(vsn),
    uptime_ms: wall_ms,
    session_count: session_count,
    board_count: board_count,
    process_count: process_count,
    db_pool_size: pool_size
  }
end
```

`r` keypress in SystemSnapshot calls `take_snapshot/0` and replaces `system_snapshot` in `Sysop.State`.

### Anti-Patterns to Avoid

- **Reading config rows for UI rendering:** Never query the `configuration` table to build the SITE or LIMITS form. Always drive from `Schema.entries/0`. This is the schema-gated key guardrail.
- **Calling `Config.put!/3` from the TUI:** `put!/3` raises on failure. The TUI must use `put/3` (tagged-tuple variant) for recoverable error handling.
- **Wrapping `Modal.Form.render/2` in a border:** `render_modal_overlay/2` already provides the chrome. A second border causes double-border rendering (RESEARCH Pitfall 4 from Phase 01.1).
- **Separate `Foglet.Categories` module:** All category functions go in `Foglet.Boards` (D-10). The existing module boundary is the right home.
- **Lazy-loading categories inside `Modal.Form.on_submit`:** Load category list for the BOARDS tab in `BoardsView.init/1` and refresh on create/archive, not inside the closure.
- **Using `async: true` in config tests:** `:foglet_config` ETS table is process-global; `async: false` is mandatory [VERIFIED: `config_test.exs:3`].

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Schema-gated key exposure | Custom allowlist in the TUI | `Schema.entries/0` iteration + `@site_keys`/`@limits_keys` module attributes | Schema is already the authoritative list; divergence causes silent exposure of new keys |
| Per-field type coercion (integer text input → integer) | Custom string parsing | `Modal.Form` coerces `:integer` fields on submit [VERIFIED: `form.ex:177`] | Edge cases: empty string, negative, non-numeric |
| Modal form focus/navigation | Custom Tab cycling | `Modal.Form.handle_event/2` [VERIFIED: `form.ex:86-129`] | Focus index, wrap, Shift-Tab, Esc all handled |
| Archive confirmation prompt | Custom Y/N implementation | `%Foglet.TUI.Modal{type: :confirm}` (already used in the codebase) | Existing pattern for single-action confirmations |
| Authorization checks at screen render | Custom role comparisons | `ShellVisibility.sysop_visible?/1` (screen level) + Bodyguard (domain level) | Two-tier established pattern; screen is advisory, domain is trust boundary |
| SYSTEM tab BEAM introspection | Custom telemetry wiring | `:erlang.statistics/1`, `:erlang.system_info/1`, `Registry.count/1`, `DynamicSupervisor.count_children/1` | These are plain function calls; no process or subscription needed |

---

## Common Pitfalls

### Pitfall 1: Missing action atoms in `Foglet.Authorization`
**What goes wrong:** `Bodyguard.permit(Foglet.Authorization, :create_category, ...)` returns `{:error, :forbidden}` even for a sysop actor, because the action atom is not in the allowlist.
**Why it happens:** Phase 1 D-12 established an explicit action-atom allowlist. New verbs (`:create_category`, `:update_category`, `:archive_category`) must be added to the policy module.
**How to avoid:** Check `lib/foglet_bbs/authorization.ex` for the `can?/4` or `permit?/4` action pattern before implementing any new domain call. Add the three category action atoms in the same task as the domain functions.
**Warning signs:** `create_category/2` returns `{:error, :forbidden}` for a sysop struct in tests.

### Pitfall 2: ETS stale cache after config write in tests
**What goes wrong:** A test that writes config then reads it back gets the old value from the ETS cache.
**Why it happens:** `Config.get!/1` caches in `:foglet_config` ETS. The Ecto sandbox rolls back the DB, but ETS is process-global and not rolled back.
**How to avoid:** Follow the existing `config_test.exs` setup that calls `Config.invalidate(key)` for every schematized key before and after each test [VERIFIED: `config_test.exs:17-23`]. New test cases for `invite_generation_per_user_limit` must add the key to `@test_keys` (it derives from `Schema.defaults()`, so adding the schema entry is sufficient).
**Warning signs:** Tests pass in isolation but fail when the full suite is run.

### Pitfall 3: `Sysop.State` field nil guard on first tab enter
**What goes wrong:** `handle_key` is called on a tab whose submodule state field is still `nil` (not yet initialized).
**Why it happens:** Submodule state is initialized lazily on first activation. The parent screen must guard and call `SubModule.init/1` before delegating events.
**How to avoid:** In `Sysop.handle_key`, when delegating to a submodule: `sub_state = ss.boards_view || BoardsView.init(current_user: state.current_user, ...)`.
**Warning signs:** `FunctionClauseError` or `MatchError` when navigating to a tab for the first time.

### Pitfall 4: `invite_generation_per_user_limit` seed missing
**What goes wrong:** `Config.get!("invite_generation_per_user_limit")` raises `Ecto.NoResultsError` in dev/prod after the schema entry is added but before the seed is run.
**Why it happens:** Schema.ex declares the key; `priv/repo/seeds.exs` must explicitly seed it. Adding the entry to `@entries` does not auto-seed.
**How to avoid:** Add the new key to `priv/repo/seeds.exs` in the same task as the schema change. Re-run `mix run priv/repo/seeds.exs` on existing DBs.
**Warning signs:** Works in test (DataCase seeds may differ) but crashes in dev when opening the SITE tab.

### Pitfall 5: `Modal.Form` event routing when overlay is active
**What goes wrong:** Keyboard events meant for `Modal.Form` are also handled by the parent boards list (e.g., `j`/`k` navigation runs while the create-board form is open).
**Why it happens:** The parent `Sysop.handle_key` must check whether a modal is active before delegating to the boards submodule's list-navigation logic.
**How to avoid:** In `BoardsView.handle_key/2`, dispatch events to `Modal.Form.handle_event/2` first when `boards_view.modal != nil`. Return `{:no_match, state}` from list navigation path when modal is open. [VERIFIED: Phase 01.1 CONTEXT integration note confirms overlay slot routes events to active modal first at the app level, but submodule must also gate internally.]
**Warning signs:** `SelectionList` index changes while a modal form is visible.

### Pitfall 6: Conditional `invite_generation_per_user_limit` row and field state desync
**What goes wrong:** The limit row is hidden (correct) but its draft value in the inline form state is not reset when `invite_code_generators` is changed away from `"any_user"`.
**Why it happens:** Draft state is retained across tab switches (D-13). If the sysop sets `invite_code_generators` to `"sysop_only"` and saves, but the limit field still has an old draft, the next save could submit a stale value.
**How to avoid:** On submit, only submit fields that are visible. If `invite_code_generators != "any_user"`, do not call `Config.put/3` for `invite_generation_per_user_limit` in the same save operation. Alternatively, submit them independently (each field saves on `Ctrl+S` independently).
**Warning signs:** Unexpected `invite_generation_per_user_limit` writes in the DB when the per-user limit row is hidden.

---

## Code Examples

### Config.put/3 call shape from TUI
```elixir
# Source: lib/foglet_bbs/config.ex:144-168
case Foglet.Config.put(state.current_user, "invite_code_generators", value) do
  {:ok, _entry} ->
    # success — form is clean; show no error
    new_ss = %{ss | site_form: SiteForm.clear_error(ss.site_form, :invite_code_generators)}
    {:update, put_ss(state, new_ss), []}

  {:error, :forbidden} ->
    # actor demoted mid-session
    {:update, %{state | modal: error_modal("Permission denied. You may have been demoted.")}, []}

  {:error, :invalid_value} ->
    new_form = SiteForm.set_error(ss.site_form, :invite_code_generators, "Invalid value")
    {:update, put_ss(state, %{ss | site_form: new_form}), []}

  {:error, :db_error} ->
    {:update, %{state | modal: error_modal("Database error saving configuration.")}, []}
end
```

### Boards.list for BOARDS tab rendering
```elixir
# Source: lib/foglet_bbs/boards.ex — list_categories already returns non-archived in display_order
# Extend to preload boards for grouped rendering:
categories = Foglet.Boards.list_categories()
# Then per-category: Foglet.Boards.list_boards(category.id) or preload :boards in query
```

### SYSTEM snapshot fields
```elixir
# Source: CONTEXT.md D-21 / BEAM stdlib
{:ok, vsn} = :application.get_key(:foglet_bbs, :vsn)
{wall_ms, _} = :erlang.statistics(:wall_clock)
session_count = Registry.count(Foglet.Sessions.Registry)
%{active: board_count} = DynamicSupervisor.count_children(Foglet.Boards.Supervisor)
process_count = :erlang.system_info(:process_count)
pool_size = FogletBbs.Repo.config()[:pool_size]
```

### Extending `config_test.exs` for the new key
```elixir
# Source: pattern from test/foglet_bbs/config_test.exs
# NOTE: @test_keys auto-includes the new key once schema.ex is updated
# because @test_keys = Map.keys(Schema.defaults())

describe "invite_generation_per_user_limit (INVT-07)" do
  test "accepts 0 (unlimited)" do
    assert {:ok, _} = Config.put(sysop_actor(), "invite_generation_per_user_limit", 0)
    assert Config.get!("invite_generation_per_user_limit") == 0
  end

  test "accepts positive integer" do
    assert {:ok, _} = Config.put(sysop_actor(), "invite_generation_per_user_limit", 5)
    assert Config.get!("invite_generation_per_user_limit") == 5
  end

  test "rejects negative integer (below_min: 0)" do
    assert {:error, :invalid_value} = Config.put(sysop_actor(), "invite_generation_per_user_limit", -1)
  end

  test "rejects non-sysop actor" do
    assert {:error, :forbidden} = Config.put(mod_actor(), "invite_generation_per_user_limit", 1)
  end
end
```

---

## State of the Art

| Old Approach | Current Approach | Impact on Phase 2 |
|--------------|------------------|--------------------|
| Reading `configuration` rows directly in TUI | Iterate `Schema.entries/0`; schema is the UI source of truth | SITE/LIMITS tabs are structurally incapable of exposing aspirational keys |
| Single-module `create_category/1` (no actor) | Actor-first `create_category/2` with Bodyguard (Phase 1 pattern) | Three new functions follow established pattern; no new auth plumbing |
| Phase 0 Sysop: placeholder render only | Phase 2: real form state via per-tab submodules | `Sysop.State` grows four new fields; delegation pattern replaces placeholder branches |

**Nothing deprecated in this phase.** Existing `create_category/1` (no actor) should be kept for seeds / `put!/3`-style trusted callers; the new `create_category/2` is additive, not a replacement.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `:create_category`, `:update_category`, `:archive_category` action atoms are not yet in `Foglet.Authorization`'s allowlist | Architecture Patterns / Pattern 2 | If they ARE already there, the task to add them is a no-op — low risk |
| A2 | `Foglet.Boards.list_boards/1` (by category_id) exists or a preload path is available for grouped BOARDS rendering | Pattern 6 | If not present, a `list_boards_for_category/1` function or a preload must be added — small additive task |

---

## Open Questions

1. **Does `list_boards` accept a `category_id` filter, or must the BOARDS tab load all boards and group in-memory?**
   - What we know: `list_boards/0` exists (boots board servers); grouping by category is needed for the BOARDS tab.
   - What's unclear: Whether a `list_boards_for_category/1` function exists or must be added.
   - Recommendation: Add `list_boards_by_category/0` returning `[{Category.t(), [Board.t()]}]` in the same task as the BOARDS tab submodule; simpler than two separate list calls per render.

2. **Does `Foglet.Authorization` already have the three new category action atoms?**
   - What we know: Phase 1 established an explicit allowlist via Bodyguard (D-12).
   - What's unclear: Whether anyone pre-populated `:create_category` etc. as part of Phase 1.
   - Recommendation: Check `lib/foglet_bbs/authorization.ex` at plan time; add them if absent, treat as no-op if present.

---

## Environment Availability

Step 2.6: SKIPPED — phase is purely additive Elixir/Ecto/TUI code. No external tools, services, CLIs, or runtimes beyond the existing project stack are required.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | ExUnit (built-in Elixir) |
| Config file | `test/test_helper.exs` |
| Quick run command | `mix test test/foglet_bbs/config_test.exs test/foglet_bbs/boards/boards_test.exs test/foglet_bbs/tui/screens/sysop_test.exs` |
| Full suite command | `mix test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INVT-06 | `Config.put/3` writes `invite_code_generators` enum values | unit | `mix test test/foglet_bbs/config_test.exs` | ✅ (extend) |
| INVT-07 | `invite_generation_per_user_limit` accepts 0 and positive int, rejects negative, rejects non-sysop | unit | `mix test test/foglet_bbs/config_test.exs` | ✅ (extend) |
| INVT-07 | SITE tab hides limit row when `invite_code_generators != "any_user"` | unit render | `mix test test/foglet_bbs/tui/screens/sysop_test.exs` | ✅ (extend) |
| SYSO-02 | SITE / LIMITS tabs render schematized key fields | unit render | `mix test test/foglet_bbs/tui/screens/sysop_test.exs` | ✅ (extend) |
| SYSO-02 | `Config.put/3` `:forbidden` routes to error modal | unit | `mix test test/foglet_bbs/tui/screens/sysop_test.exs` | ✅ (extend) |
| SYSO-03 | `create_category/2` (actor-first) happy + forbidden paths | unit | `mix test test/foglet_bbs/boards/boards_test.exs` | ✅ (extend) |
| SYSO-03 | `update_category/3` happy + forbidden paths | unit | `mix test test/foglet_bbs/boards/boards_test.exs` | ✅ (extend) |
| SYSO-03 | `archive_category/2` sets `archived: true`, forbidden for non-sysop | unit | `mix test test/foglet_bbs/boards/boards_test.exs` | ✅ (extend) |
| SYSO-03 | BOARDS tab renders list; create/edit modal opens and submits | unit render + key smoke | `mix test test/foglet_bbs/tui/screens/sysop_test.exs` | ✅ (extend) |
| SYSO-04 | SYSTEM tab renders without crash; `r` key refreshes snapshot | unit render + key smoke | `mix test test/foglet_bbs/tui/screens/sysop_test.exs` | ✅ (extend) |

### Sampling Rate
- **Per task commit:** `mix test test/foglet_bbs/config_test.exs test/foglet_bbs/boards/boards_test.exs test/foglet_bbs/tui/screens/sysop_test.exs`
- **Per wave merge:** `mix test`
- **Phase gate:** `mix precommit` (compile --warnings-as-errors, format, credo --strict, sobelow, dialyzer) green before `/gsd-verify-work`

### Wave 0 Gaps
None — existing test infrastructure covers all phase requirements. All three target test files already exist and follow established patterns. Phase 2 only extends them.

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Not touched in this phase |
| V3 Session Management | no | Not touched |
| V4 Access Control | yes | Bodyguard + `Foglet.Authorization` — domain is trust boundary (D-22/D-23) |
| V5 Input Validation | yes | `Foglet.Config.Schema.validate/2` for config; `Ecto.Changeset` validations for board/category fields |
| V6 Cryptography | no | No secret handling |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Sysop-screen bypass (navigate directly without going through main menu gate) | Elevation of privilege | `ShellVisibility.sysop_visible?/1` in `render/1` as defensive check; domain functions enforce Bodyguard regardless |
| Writing arbitrary config keys not in schema | Tampering | `Schema.validate/2` called by `Config.put/3` before any DB write; `{:error, :unknown_key}` returned |
| Stale sysop session (actor demoted mid-session) | Elevation of privilege | `{:error, :forbidden}` from any domain call triggers error modal + `:main_menu` return (D-24) |
| Integer overflow / negative values for config limits | Tampering | `min: 0` constraint on `invite_generation_per_user_limit`; `min: 1` on `max_post_length` etc.; enforced in `Schema.check_range/2` |

---

## Sources

### Primary (HIGH confidence — VERIFIED against live codebase)
- `lib/foglet_bbs/config.ex` — `put/3` tagged-tuple API, `put!/3`, `invalidate/1`
- `lib/foglet_bbs/config/schema.ex` — `entries/0`, `fetch_spec/1`, `validate/2`, `@allowed_types`, full entry list
- `lib/foglet_bbs/boards.ex` — existing board CRUD, `create_category/1`, Bodyguard pattern
- `lib/foglet_bbs/boards/board.ex` — `archive_changeset/1` reference implementation
- `lib/foglet_bbs/boards/category.ex` — Category schema and changeset
- `lib/foglet_bbs/tui/widgets/modal/form.ex` — `init/1`, `handle_event/2`, `render/2`, `set_errors/2`
- `lib/foglet_bbs/tui/screens/sysop.ex` — Phase 0 scaffold being replaced
- `lib/foglet_bbs/tui/screens/sysop/state.ex` — struct being extended
- `lib/foglet_bbs/tui/screens/new_thread.ex` — inline error, `Ctrl+S`, `SelectionList`/`ListRow` patterns
- `lib/foglet_bbs/tui/screens/new_thread/state.ex` — per-screen state struct pattern
- `test/foglet_bbs/tui/screens/sysop_test.exs` — `build_state/1`, `collect_text_values/1` usage
- `test/foglet_bbs/config_test.exs` — `async: false`, ETS invalidation setup pattern
- `test/foglet_bbs/boards/boards_test.exs` — `allow_board_server!/1`, actor fixtures
- `.planning/phases/02-sysop-config-and-board-management/02-CONTEXT.md` — all 28 implementation decisions
- `docs/DATA_MODEL.md §11` — canonical config key list, seeded vs aspirational
- `docs/ARCHITECTURE.md §8` — configuration layering philosophy
- `.planning/codebase/CONVENTIONS.md` — module naming, file structure, test patterns, error handling

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries are in-repo with verified call shapes
- Architecture: HIGH — all decisions locked in CONTEXT.md; patterns verified against live code
- Pitfalls: HIGH — derived from codebase inspection and locked decisions
- Open questions: LOW confidence on exact `list_boards` signature — requires a single file read at plan time

**Research date:** 2026-04-23
**Valid until:** Stable until any of `config.ex`, `config/schema.ex`, `boards.ex`, or `widgets/modal/form.ex` are modified.
