# Phase 25: Operator Console Conversion - Research

**Researched:** 2026-04-25
**Domain:** Elixir / Raxol TUI presentation-layer conversion onto in-repo primitives
**Confidence:** HIGH (all primitives, precedents, and conventions are in-repo and verified)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Modal.Form Reuse Strategy For Tab Bodies**
- **D-01:** Use `Foglet.TUI.Widgets.Modal.Form` directly inline as a tab body for Account profile, Account preferences, Sysop site, and Sysop limits forms. The screen owns the `%Modal.Form{}` struct in its sibling `state.ex`, calls `Modal.Form.handle_event/2`, and renders with `Modal.Form.render(form, theme: theme)` — exactly matching the established `lib/foglet_bbs/tui/screens/sysop/boards_view.ex` precedent.
- **D-02:** Do **not** introduce a parallel "tab-body adapter" module. SPEC R1's "or a tab-body adapter" wording is a fallback only; the existing body-only rendering contract on `Modal.Form` is sufficient.
- **D-03:** For Account preferences, extend `Modal.Form` with a RadioGroup-style enum field that supports arrow-key cycling for the theme swatch and other enumerated preferences. This keeps prefs uniform with the other four forms and preserves the user's existing arrow-cycle interaction without forcing a Tab/Enter-only path. Existing prefs save/dirty/error behavior tests must continue to pass.

**ConsoleTable Adoption And Selection Ownership**
- **D-04:** Listings convert to `Foglet.TUI.Widgets.Display.ConsoleTable` for Account SSH keys; Moderation log, users, boards, invites; and Sysop boards, users, categories.
- **D-05:** Selection state moves out of bespoke screen-local `selected_index` fields into the `ConsoleTable` (and its wrapped `Display.Table`) cursor. Screens hold the `%ConsoleTable{}` in sibling `state.ex`, route key events through `ConsoleTable.handle_event/2`, and dispatch domain side effects on the returned `Table.action()` (`{state, action}` tuple). This matches `screens/sysop/boards_view.ex:443-485`.
- **D-06:** No domain mutations move into `ConsoleTable` or any other widget. Authorization, context calls, and PubSub remain in screens.

**Destructive-Action Styling**
- **D-07:** Reuse the existing `Foglet.TUI.Presentation.theme_mappings().commands.destructive => :error` mapping for destructive actions. Tab-body destructive command-bar entries set `destructive?: true`; inline emphasis routes through the same mapping helper used by `Chrome.CommandBar` and `Workspace.Inspector`.
- **D-08:** Do **not** add a new `:destructive` slot to the `Foglet.TUI.Theme` struct. Theme-palette changes are explicitly out of scope (UI-03).

**Layout Smoke Harness Shape**
- **D-09:** Extend `test/foglet_bbs/tui/layout_smoke_test.exs` with **per-tab** size-contract blocks for each of the 12 converted tabs (Account: profile, prefs, ssh_keys; Moderation: log, users, boards, invites; Sysop: site, limits, boards, users, system). Activate the tab via the screen's `active_tab` (or equivalent) state key and iterate `[{64, 22}, {80, 24}]`.
- **D-10:** Each per-tab block asserts (a) rendered output stays within bounds, (b) at least one Phase 24 primitive sentinel is present, and (c) primitives do not overlap. Wide-terminal `132x50` is not required this phase.
- **D-11:** Pattern after the existing Phase 22/20 size-contract loops at `layout_smoke_test.exs:273-353` — not the shell-only operator tests at lines 1735-1824.

**Theme-Hygiene Test Style**
- **D-12:** Use the existing `Foglet.TUI.WidgetHelpers.color_atom_leaked?/2` and `color_names/0` helpers for the "no hardcoded color atoms" assertion (R8).
- **D-13:** Do not substitute a static source grep — false-positives on docstrings and misses macro-expanded atoms.

**Ordering And Parallelism**
- **D-14:** Wave 0 establishes shared scaffolding before screen conversion: shared empty-state copy strings (or a small helper), the per-tab smoke-test fixture pattern, and any RadioGroup/enum field extension on `Modal.Form` required by D-03.
- **D-15:** After wave 0, Account, Moderation, and Sysop convert in parallel.
- **D-16:** Sysop is the highest-surface conversion (5 tabs). Moderation is read-only-honest and lowest-risk. Account carries the prefs RadioGroup work from D-03.
- **D-17:** Each screen wave finishes with its own per-tab render tests and per-tab layout smoke tests before being merged.

**Behavior Preservation Guardrails**
- **D-18:** No domain logic, authorization, or PubSub wiring moves into widgets or into Phase 25 code.
- **D-19:** All pre-existing Account, Moderation, Sysop, `Display.Table`, and `Modal.Form` test suites must pass unmodified. No assertion weakening.
- **D-20:** `Workspace.Inspector` is not referenced from `lib/foglet_bbs/tui/screens/` in this phase; grep check enforces this.

### Claude's Discretion
- Exact column definitions and dense-default presets per `ConsoleTable` instance, provided columns are stable, headers labeled, empty-state copy honest, and selection preserved.
- Exact wording of empty-state copy strings.
- Whether the Wave 0 RadioGroup field becomes a public `Modal.Form` field type or a private internal addition.
- Exact split of waves into PRs (one per screen vs combined).

### Deferred Ideas (OUT OF SCOPE)
- Live wiring of `Workspace.Inspector` (UI-02, v1.4).
- Wide-terminal layouts beyond 80x24 (UI-05).
- New theme palette slots / color tuning (UI-03).
- New moderation case-management workflows (UI-04).
- Ultra-compact chrome variants (UI-01).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ACCOUNT-01 | Account profile/prefs/ssh_keys tabs render through Phase 24 primitives. | Modal.Form, ConsoleTable, KvGrid (see Standard Stack). Modal.Form already supports `:enum` fields with `:up`/`:down` cycling — D-03 may be satisfied without new field type (see Pitfall 5). |
| MOD-01 | Moderation tabs use KvGrid summaries + Badge status + ConsoleTable listings. | KvGrid supports `:badge`/`:state` metadata per row (kv_grid.ex:76-104). |
| SYSOP-01 | Sysop tabs (site/limits/boards/users/system) use refreshed Modal.Form + ConsoleTable + KvGrid with metric badges. | BoardsView.ex is canonical Modal.Form-as-tab-body precedent. SystemSnapshot currently uses bespoke `pad_trailing` rows — direct KvGrid swap. |
</phase_requirements>

## Summary

Phase 25 is a **pure presentation conversion** layered onto already-shipped, already-verified Phase 24 primitives. Every primitive (`Display.Badge`, `Display.KvGrid`, `Display.ConsoleTable`, refreshed `Modal.Form`) lives at known paths under `lib/foglet_bbs/tui/widgets/` with stable `init/handle_event/render` triplet contracts. There is one fully-worked precedent — `lib/foglet_bbs/tui/screens/sysop/boards_view.ex` — that demonstrates the exact pattern this phase generalizes: sibling `state.ex` holds the widget struct, screen routes events through `Widget.handle_event/2`, screen interprets the returned `action` tuple and performs domain side effects via context modules.

The risks are not "which library" risks; they are **conversion-discipline** risks: dropping or weakening existing screen tests, leaking color atoms past the theme layer, breaking established key-event shapes (notably `:shift_tab` vs `%{key: :tab, shift: true}`), and introducing hand-rolled selection state alongside the new ConsoleTable cursor. These are catalogued under Common Pitfalls.

**Primary recommendation:** Mirror `sysop/boards_view.ex` precisely. For each converted tab: store widget structs in `state.ex`, dispatch events via `Widget.handle_event/2`, capture submit payloads via the established Process-dictionary stash pattern (Modal.Form discards `on_submit` returns), and let `ConsoleTable` own selection. Resist building bespoke wrappers, adapters, or selection mirrors.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Tab-body rendering (forms) | `Modal.Form` widget | Screen `state.ex` (struct ownership) | Body-only render contract is the established primitive for any inline form. |
| Tab-body rendering (listings) | `Display.ConsoleTable` widget | Screen `state.ex` | ConsoleTable wraps `Display.Table`, owns dense defaults, empty-state copy, selection guard. |
| Tab-body rendering (summaries) | `Display.KvGrid` widget | `Display.Badge` for value-cell state | KvGrid is the only width-safe label/value primitive; supports per-row badge metadata. |
| Status indicators | `Display.Badge` widget | `Presentation.theme_mappings().badges` | Badge is the only primitive that emits `[label]` and routes role -> theme slot. |
| Selection cursor | `Display.ConsoleTable` (delegates to `Display.Table`) | Screen `handle_key` reads `last_action` | Single source of truth — D-05 forbids parallel `selected_index` in screens. |
| Domain mutations | Context modules (`Foglet.Accounts`, `Foglet.Boards`, `Foglet.Config`) | Screen `handle_key` dispatches | D-06/D-18 explicitly forbid domain logic in widgets. |
| Authorization | `Foglet.Authorization` (Bodyguard) | Context modules | Project convention; unchanged by this phase. |
| Color/style routing | `Foglet.TUI.Theme` slots via `Foglet.TUI.Presentation.theme_mappings()` | — | Hardcoded color atoms forbidden (R8, D-12). |
| Layout smoke verification | `test/foglet_bbs/tui/layout_smoke_test.exs` | Per-tab size-contract `for {w, h} <- [{64,22},{80,24}]` loops | D-09/D-11 — pattern after lines 273-353. |

## Standard Stack

> Phase 25 is a conversion onto **in-repo primitives** shipped in Phase 24. There is no external library decision space. The "stack" below is the locked set of modules to consume; alternatives are explicitly forbidden.

### Core (in-repo, MUST use)

| Module | Path | Purpose | Why Standard |
|--------|------|---------|--------------|
| `Foglet.TUI.Widgets.Modal.Form` | `lib/foglet_bbs/tui/widgets/modal/form.ex` | Body-only stateful form; `init/1` + `handle_event/2` + `render/2`; supports `:text`, `:integer`, `:boolean`, `:enum`, `:textarea`. | D-01; only refreshed-treatment form primitive. Verified shipped in Phase 24-VERIFICATION (truth #6). |
| `Foglet.TUI.Widgets.Display.ConsoleTable` | `lib/foglet_bbs/tui/widgets/display/console_table.ex` | Dense operator-table facade over `Display.Table`; honors `selectable: false` on Enter; renders `empty_state` copy with `theme.dim.fg`. | D-04; only operator-table primitive. Verified Phase 24 truth #3/#4. |
| `Foglet.TUI.Widgets.Display.KvGrid` | `lib/foglet_bbs/tui/widgets/display/kv_grid.ex` | Width-safe label/value rows; per-row `badge:` or `state:` metadata renders inline `Display.Badge`. | Only width-safe label/value primitive. Verified Phase 24 truth #2. |
| `Foglet.TUI.Widgets.Display.Badge` | `lib/foglet_bbs/tui/widgets/display/badge.ex` | Compact `[label]` state badge; states `:required`, `:subscribed`, `:locked`, `:sticky`, `:pending`, `:healthy`, `:error`, `:neutral`, `:info`. Routes role -> theme via `Presentation.theme_mappings().badges`. | Only theme-routed badge primitive. Verified Phase 24 truth #1. |

### Supporting (in-repo)

| Module | Path | Purpose | When to Use |
|--------|------|---------|-------------|
| `Foglet.TUI.Presentation` | `lib/foglet_bbs/tui/presentation.ex` | `theme_mappings()` exposes `badges`, `commands.destructive => :error`, `rows`, `tabs`. | Routing destructive emphasis (D-07) and any indirect role -> slot lookup. |
| `Foglet.TUI.Theme` | `lib/foglet_bbs/tui/theme.ex` | Semantic slots (`primary`, `dim`, `accent`, `error`, `warning`, `selected`, `border`, `title`, `info`, `success`). | All `fg:`/`bg:`/`style:` consumption — never hardcoded color atoms. |
| `Foglet.TUI.Widgets.Chrome.ScreenFrame` | `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` | Renders chrome around tab body. | Already wired in Account/Moderation/Sysop shells — do not re-wire. |
| `Foglet.TUI.Widgets.Input.Tabs` | `lib/foglet_bbs/tui/widgets/input/tabs.ex` | Tab bar with `handle_event/2` returning `{:tab_changed, idx}`. | Already wired in shells — unchanged. |
| `Foglet.TUI.WidgetHelpers` | `test/support/foglet/tui/widget_helpers.ex` | `color_atom_leaked?/2`, `color_names/0`, `flatten_text/1`, `text_runs/1`. | Theme-hygiene assertions (D-12) and render-output substring checks. |
| `Foglet.TUI.Modal` | `lib/foglet_bbs/tui/modal.ex` | `%Modal{type: :confirm}` for destructive Y/N flows. | Already used in `boards_view.ex`; pattern carries forward to ban/delete confirms. |

### Alternatives Considered

| Instead of | Could Use | Tradeoff / Why Not |
|------------|-----------|---------------------|
| `Modal.Form` inline | A new `TabBodyForm` adapter | **Explicitly forbidden by D-02.** Body-only contract is sufficient; an adapter adds API surface without earning its keep. |
| `Display.ConsoleTable` | `Display.Table` directly | Loses dense defaults, empty-state copy, and `selectable: false` Enter guard. Use only where the screen has a strong reason; default to ConsoleTable. |
| `Display.ConsoleTable` | `Widgets.List.SelectionList` (current SSH-keys impl) | SelectionList is the legacy hand-rolled row primitive; D-04 directs migration off of it for operator surfaces. |
| Adding `:destructive` theme slot | Reuse `commands.destructive => :error` mapping | **Explicitly forbidden by D-08.** UI-03 deferred. |
| Wide-terminal `Workspace.Inspector` | Inline detail panes | **Explicitly forbidden by D-20.** Inspector deferred to v1.4. |

**Installation:** N/A — all modules are already in the codebase as of Phase 24 ship.

**Version verification:** N/A — in-repo modules, version pinned by current `main` (commit `5b98ab1` and downstream).

## Architecture Patterns

### System Architecture Diagram

```
                         ┌──────────────────────────────────┐
                         │  Foglet.TUI.App (global state)   │
                         │  - current_screen                │
                         │  - screen_state[:account/:mod/:sysop]
                         └──────────────┬───────────────────┘
                                        │ event
                                        ▼
                  ┌──────────────────────────────────────────┐
                  │  Screen module (e.g. Screens.Sysop)      │
                  │  - render/1: build_content(ss, theme)    │
                  │  - handle_key: route to active tab       │
                  └─────────┬──────────────────────────┬─────┘
                            │ active tab               │ tab change
                            ▼                          ▼
        ┌───────────────────────────────┐    ┌─────────────────────┐
        │  Sibling state.ex             │    │  Widgets.Input.Tabs │
        │  (Sysop.State, Account.State, │    │  handle_event/2     │
        │   Moderation.State)           │    └─────────────────────┘
        │  - holds widget structs:      │
        │     %Modal.Form{}             │
        │     %ConsoleTable{}           │
        │  - delegates to widget        │
        │    handle_event/2             │
        │  - captures action tuple      │
        └─────────┬─────────────────────┘
                  │ action: {:row_selected, _} | :submitted | :cancelled | nil
                  ▼
        ┌───────────────────────────────┐
        │  Screen domain dispatch       │
        │  - Bodyguard.permit/4         │
        │  - Foglet.Accounts.* /        │
        │    Foglet.Boards.* /          │
        │    Foglet.Config.put/3        │
        │  - returns {:ok, _} or        │
        │    {:error, %Changeset{}}     │
        └─────────┬─────────────────────┘
                  │ on error
                  ▼
            Modal.Form.set_errors/2 → re-render with inline errors
                  │ on success
                  ▼
            refresh_lists/1 → ConsoleTable re-init with new rows
                  │
                  ▼
            ScreenFrame.render(state, chrome, content, key_hints)
```

### Recommended Project Structure (no new top-level folders)

```
lib/foglet_bbs/tui/screens/
├── account/
│   ├── state.ex              # ADD: %Modal.Form{} for profile/prefs; %ConsoleTable{} for ssh_keys
│   ├── profile_form.ex       # CONVERT: drop bespoke render → Modal.Form.render(form, theme: theme)
│   ├── prefs_form.ex         # CONVERT: same; verify :enum field handles theme/time_format cycling (Pitfall 5)
│   └── ssh_keys_surface.ex   # CONVERT: drop SelectionList → ConsoleTable.render(table, theme: theme)
├── moderation/
│   └── state.ex              # ADD: per-tab %ConsoleTable{} for log/users/boards/invites; %KvGrid entries scope/status block
├── moderation.ex             # CONVERT: render_tab_body/3 emits KvGrid + ConsoleTable
└── sysop/
    ├── state.ex              # ADD: %Modal.Form{} site/limits; %ConsoleTable{} users; KvGrid entries system
    ├── site_form.ex          # CONVERT: drop D-19 fallback → Modal.Form (matches D-01 boards_view pattern)
    ├── limits_form.ex        # CONVERT: same
    ├── users_view.ex         # CONVERT: SelectionList → ConsoleTable; transitions still call Foglet.Accounts
    ├── system_snapshot.ex    # CONVERT: snapshot_row/3 → KvGrid entries with badge: %{state: :healthy/:error/:pending}
    └── boards_view.ex        # ALREADY CONVERTED (precedent — minimal/no changes; verify destructive styling per D-07)
```

### Pattern 1: Inline Modal.Form as Tab Body (D-01, canonical precedent)

**What:** Screen owns the `%Modal.Form{}` struct in sibling `state.ex`; screen renders it as the tab body via `Modal.Form.render(form, theme: theme)`; screen routes key events through `Modal.Form.handle_event/2` and stashes submit payloads through the process dictionary because `Modal.Form` discards the `on_submit` return value (form.ex:114).

**When to use:** Every converted form — Account profile, Account prefs, Sysop site, Sysop limits.

**Example** (paraphrased from `screens/sysop/boards_view.ex:235-294, 436-494`):

```elixir
# state.ex — open the form
form =
  ModalForm.init(
    title: "Edit profile",
    fields: profile_fields(state),     # [%{name: :location, type: :text, label: "Location", value: ...}, ...]
    on_submit: &stash_submit/1,        # discards return; stashes payload
    on_cancel: &noop/0
  )

%{state | profile_form: form}

# Stash adapter
defp stash_submit(payload) do
  Process.put({__MODULE__, :pending_submit}, payload)
  :ok
end

# screen handle_key
defp handle_form_event(event, %State{profile_form: form} = state) do
  Process.delete({__MODULE__, :pending_submit})
  {new_form, action} = ModalForm.handle_event(event, form)

  case action do
    :submitted ->
      payload = Process.get({__MODULE__, :pending_submit})
      Process.delete({__MODULE__, :pending_submit})
      handle_submit_payload(payload, %{state | profile_form: new_form})

    :cancelled ->
      {%{state | profile_form: nil}, []}

    _ ->
      {%{state | profile_form: new_form}, []}
  end
end

# Domain dispatch with changeset error fan-back
defp handle_submit_payload(payload, %State{} = state) do
  case Foglet.Accounts.update_profile(state.current_user, payload) do
    {:ok, _user} ->
      {%{state | profile_form: nil, status_message: "Saved."}, []}

    {:error, %Ecto.Changeset{} = cs} ->
      form = ModalForm.set_errors(state.profile_form, changeset_errors(cs))
      {%{state | profile_form: form}, []}
  end
end
```

### Pattern 2: ConsoleTable-Owned Selection (D-05)

**What:** Drop `selection_index` from screen state. Hold `%ConsoleTable{}` in `state.ex`. Read `last_action` after every event.

**When to use:** SSH keys, Moderation log/users/boards/invites, Sysop boards/users/categories.

**Example** (synthesized from `console_table.ex:64-72` + `boards_view.ex` action-tuple precedent):

```elixir
# state.ex
table =
  ConsoleTable.init(
    columns: [
      %{key: :handle, label: "Handle", width: 20},
      %{key: :role, label: "Role", width: 8},
      %{key: :status, label: "Status", width: 10}
    ],
    rows: load_users(),
    selectable: true,
    empty_state: "No active users in scope."
  )

# screen handle_key
{new_table, action} = ConsoleTable.handle_event(event, state.users_table)

state = %{state | users_table: new_table}

case action do
  {:row_selected, %{id: user_id}} ->
    # dispatch domain side effect
    Foglet.Accounts.transition_status(state.current_user, user_id, :suspended)

  _ ->
    state
end
```

### Pattern 3: KvGrid + Badge Summary Block (Moderation, Sysop System)

**What:** A single `KvGrid.render(entries, theme: theme, width: 78)` call with per-row `state:` or `badge:` keys decorates value cells with `Display.Badge` automatically (kv_grid.ex:76-104).

**Example** (synthesized from `kv_grid.ex` shape):

```elixir
KvGrid.render(
  [
    %{label: "Sessions", value: Integer.to_string(s.session_count), state: :healthy},
    %{label: "Active boards", value: Integer.to_string(s.board_count), state: :healthy},
    %{label: "DB pool", value: Integer.to_string(s.db_pool_size),
      badge: %{state: :pending, label: "tuning", role: :warning}}
  ],
  theme: theme,
  width: 78,
  label_width: 16,
  gap: 2
)
```

For Moderation status block: scope label + status value with `state: :info` for read-only, `state: :error` when `error != nil`, `state: :pending` when `loading? == true`.

### Pattern 4: Destructive Action Routing (D-07)

**What:** Reuse `Presentation.theme_mappings().commands.destructive` (already maps to `:error` slot). Command-bar entries set `destructive?: true`; inline emphasis looks up the slot via `theme_mappings().commands.destructive` -> `Map.fetch!(theme, slot)`.

**When to use:** "Archive board", "Archive category", "Suspend user", "Reject user", "Revoke SSH key" footers and confirm-prompt accents.

**Example:**

```elixir
defp destructive_style(theme) do
  slot = Foglet.TUI.Presentation.theme_mappings().commands.destructive  # :error
  Map.fetch!(theme, slot)  # %{fg: theme.error.fg, ...}
end
```

### Anti-Patterns to Avoid

- **Parallel `selected_index` alongside `%ConsoleTable{}`** — violates D-05; use `last_action` from `ConsoleTable.handle_event/2` only.
- **Wrapping `Modal.Form.render/2` in `box`/`border:`/centering** — double-borders (Pitfall 4 from earlier RESEARCH; called out in `form.ex:18`). Body-only contract is mandatory.
- **Hardcoded color atoms in screens** (`fg: :cyan`, `style: [color: :red]`) — fails `color_atom_leaked?/2` hygiene tests (R8, D-12).
- **Adding domain logic to widgets** — D-06/D-18; widgets stay render+event-routing only.
- **Building a "TabBodyForm" adapter module** — D-02; explicitly forbidden.
- **Referencing `Workspace.Inspector` from screens** — D-20; grep check enforces.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Aligned label/value rendering | Custom `String.pad_trailing/2` rows (current `system_snapshot.ex:55-57`) | `Display.KvGrid.render/2` | KvGrid uses `TextWidth` for unicode-width-safe truncation/padding; bespoke `String.pad_trailing` breaks on multi-byte glyphs (Phase 16 foundation). |
| Selection cursor over rows | `selected_index` integer + manual j/k handlers + custom `SelectionList` | `Display.ConsoleTable` (delegates to `Display.Table` -> Raxol's table) | Raxol's table handles paging, empty-state guard (`selected_row: nil` for `[]`), and arrow-key arithmetic safely (`table.ex:88-92, 105-110`). Hand-rolled selection has known crash modes on empty lists. |
| `[required]` / `[healthy]` / `[error]` text labels | Inline `text("[error]", fg: theme.error.fg)` | `Display.Badge.render(:error, theme: theme)` | Badge routes role -> `Presentation.theme_mappings().badges.error` -> `theme.error` slot. Hardcoding bypasses the mapping contract (R8). |
| Form heading + divider + required marker + footer | Custom title rows + `String.duplicate("─", 40)` + ad-hoc `*` markers + bespoke `[Enter] Submit [Esc] Cancel` lines | `Modal.Form.render/2` (`form.ex:144-169`) | Already does all five visual elements consistently; replicating means visual drift across the four converted forms. |
| Capturing typed payload from `Modal.Form.on_submit` | A wrapping module that mutates state from inside the closure | `Process.put({__MODULE__, :pending_submit}, payload)` stash adapter (`boards_view.ex:436-439`) | Modal.Form deliberately discards the closure return (form.ex:114). Single-process render context makes Process dict safe; this is the documented pattern. |
| Empty-state "No X." copy | Inline `text("No SSH keys.", fg: theme.dim.fg)` | `ConsoleTable.init(empty_state: "No SSH keys registered.")` — primitive renders it via `theme.dim.fg` automatically | Centralizes copy; lets layout smoke tests assert primitive sentinels (D-10 (b)). |

**Key insight:** The temptation in a conversion phase is to build a "small helper" because the primitive feels too generic. Don't. Each helper that wraps a primitive becomes a second source of truth for layout/theme/empty-state copy. The Phase 24 primitives are intentionally caller-driven; "configure them harder" instead of "wrap them."

## Common Pitfalls

### Pitfall 1: `:shift_tab` event-shape mismatch

**What goes wrong:** Existing prefs/profile forms match `%{key: :shift_tab}` (see `account/profile_form.ex:137`, `account/prefs_form.ex:215`). `Modal.Form` matches `%{key: :tab, shift: true}` (form.ex:95).

**Why it happens:** Two different historical event-shape conventions in the codebase — the inline forms were written against Foglet's translated key shape; `Modal.Form` was written against the Raxol vendor shape (`vendor/raxol/lib/raxol/ui/components/modal/events.ex:94`, cited in form.ex:93).

**How to avoid:** Verify in Wave 0 which shape `Foglet.TUI.SSH.CLIHandler` actually delivers to the screen. If both shapes appear in the wild (likely, since both code paths exist), `Modal.Form` MUST handle both — or screen-level event normalization MUST translate before dispatch. Add a unit test for both shapes against `Modal.Form.handle_event/2` in Wave 0.

**Warning signs:** Shift+Tab "does nothing" in a converted form during manual SSH testing; existing prefs back-focus tests pass but new converted-prefs tests fail at the same step.

### Pitfall 2: `Modal.Form.on_submit` return value is discarded

**What goes wrong:** Returning `{:ok, _}` or a state struct from the `on_submit` closure has no effect. The screen receives only `:submitted | :cancelled | nil` from `handle_event/2`.

**Why it happens:** `form.ex:114` reads `_ = state.on_submit.(payload)` — return value bound to underscore.

**How to avoid:** Use the `Process.put({__MODULE__, :pending_submit}, payload)` stash adapter from `boards_view.ex:436-439`. Read it back immediately after `handle_event/2` returns `:submitted`; delete before and after to bound lifetime to the single dispatch.

**Warning signs:** Form submits but no domain mutation fires; or mutation fires with stale data from a previous submit.

### Pitfall 3: Empty-table arithmetic crash on j/k

**What goes wrong:** Forwarding a `%{key: :down}` event into `Display.Table` with zero rows would crash on `nil + 1` arithmetic (`table.ex:104-110` documents this as WR-05).

**Why it happens:** Raxol's table sets `selected_row: 0` only when rows present; otherwise `nil`. Foglet's `Display.Table.handle_event/2` short-circuits empty data to `{state, nil}` — but only if the event reaches `Display.Table`. A bespoke "wrap ConsoleTable" layer that intercepts empty cases incorrectly can re-introduce the crash.

**How to avoid:** Always route through `ConsoleTable.handle_event/2` (which delegates to `Display.Table`). Do not branch on `state.rows == []` in the screen and bypass the widget.

**Warning signs:** Crash on first arrow-key press in an empty SSH-keys/Moderation listing.

### Pitfall 4: Modal-overlay double-border

**What goes wrong:** Wrapping `Modal.Form.render/2` output in `box do … end` or adding `border:` produces a doubled border because `Foglet.TUI.App.render_modal_overlay/2` already provides chrome.

**Why it happens:** The body-only contract is enforced by convention, not by the type system (`form.ex:18-19` calls this out explicitly).

**How to avoid:** When using `Modal.Form` as an inline tab body (D-01 use case — NOT as a true modal overlay), still do not wrap. The Modal.Form output is already a `column` with title/divider/fields/footer — just emit it directly into the tab body.

**Warning signs:** Layout smoke test reports primitives overlap, or visual review shows doubled `─` lines.

### Pitfall 5: D-03 RadioGroup field may already exist

**What goes wrong:** Wave 0 plans to "add" a RadioGroup-style enum field to `Modal.Form`, but `Modal.Form` already supports `:type => :enum` with `:up`/`:down` arrow cycling (`form.ex:236-249`) and renders via `RadioGroup.render/3` (`form.ex:332-335`).

**Why it happens:** The CONTEXT decision was made under the assumption that prefs needed a "RadioGroup-style" addition; the `:enum` type that already exists IS the RadioGroup-rendered field.

**How to avoid:** In Wave 0, **first** verify whether the existing `:enum` field meets prefs UX requirements:
- Theme/time-format choices set via `choices: [...]` and `value: <current>`.
- Cycling on `:up`/`:down` matches existing prefs interaction.
- The "instant theme preview" behavior (`prefs_form.ex:163-169` — sets `:candidate_theme_id` on cycle) is **not** in `Modal.Form` — that's a real gap that may justify either a screen-level interception of the focused-field state or a small extension to expose `field_state_changed` callback. Plan accordingly.

**Warning signs:** Wave 0 starts patching `form.ex` before reading lines 236-249; or the live preview side effect on theme cycle silently disappears in converted prefs.

### Pitfall 6: Hidden Sysop site keys (D-04)

**What goes wrong:** `Sysop.SiteForm.visible_keys/1` (`site_form.ex:69-77`) hides `invite_generation_per_user_limit` unless `invite_code_generators == "any_user"`. Naively passing `@site_keys` into `Modal.Form.init(fields: ...)` re-introduces the hidden field.

**Why it happens:** `Modal.Form` has no concept of conditionally-visible fields; it renders all fields in `:fields`. Visibility logic lives in the screen.

**How to avoid:** Build the `fields:` list from `visible_keys/1` at form-init time. Re-init the `%Modal.Form{}` struct (cheap) when the value of `invite_code_generators` changes — not as a field-list mutation on the live struct.

**Warning signs:** Hidden field reappears in the converted SITE tab; tests that assert key visibility regress.

### Pitfall 7: Read-only honesty regression in Moderation

**What goes wrong:** `Display.ConsoleTable.init(selectable: true)` plus a screen handler that calls a domain mutation on `{:row_selected, _}` accidentally introduces a "fake action" on a read-only Moderation tab (e.g., LOG audit rows are read-only).

**Why it happens:** ConsoleTable's `selectable` defaults are caller-driven; it is easy to flip the wrong tab.

**How to avoid:** Default Moderation log/users/boards listings to `selectable: false` (ConsoleTable returns `{state, nil}` on Enter — `console_table.ex:65`). Only flip `selectable: true` for tabs that actually have a selection-driven side effect. Add a per-tab assertion in render tests.

**Warning signs:** Moderation USERS tab dispatches `Foglet.Accounts.transition_status/3` on Enter; or pre-existing "no fake actions" tests regress.

### Pitfall 8: Layout-smoke shell-only false positive

**What goes wrong:** Tests at `layout_smoke_test.exs:1735-1824` only render the screen shell with no active tab body content. Patterning per-tab tests after these will not exercise the converted primitives.

**Why it happens:** Those tests pre-date Phase 25 and were sufficient for shell-only verification.

**How to avoid:** D-11 explicitly directs patterning after the Phase 22/20 size-contract loops at lines 273-353 (which build a real screen state with an active tab and assert against rendered primitives). Activate the tab via `screen_state[:account/:moderation/:sysop].active_tab`; supply representative fixture rows to the screen state's widget structs before render.

**Warning signs:** Per-tab smoke test passes but the actual tab body is empty in the rendered output (assert primitive sentinel presence to catch this — D-10 (b)).

### Pitfall 9: ConsoleTable column normalization quirk

**What goes wrong:** ConsoleTable normalizes columns with `Map.put_new(:width, 12)` (`console_table.ex:88`), but `Display.Table.normalize_column/1` defaults to `width: 20` (`table.ex:194`). Passing a column without `:width` to ConsoleTable yields a 12-wide column in the display, which may be too tight.

**Why it happens:** Two different default widths between the wrapping primitive and the underlying primitive.

**How to avoid:** Always specify `:width` explicitly on ConsoleTable column specs. Treat the 12-default as "dense default for narrow operator tables, override per-column."

**Warning signs:** Handle/slug/board-name columns truncated to 12 chars in 80x24 layout.

## Code Examples

### Convert a bespoke padded-string row block to KvGrid

```elixir
# Source: synthesized from sysop/system_snapshot.ex (current) + display/kv_grid.ex (target)

# BEFORE (system_snapshot.ex:36-53)
def render(%__MODULE__{snapshot: s}, theme) do
  rows = [
    snapshot_row("Version:", s.version, theme),
    snapshot_row("Uptime:", format_uptime(s.uptime_ms), theme),
    snapshot_row("Sessions:", Integer.to_string(s.session_count), theme),
    # ...
  ]
  column style: %{gap: 0} do
    [text("System snapshot", fg: theme.title.fg, style: [:bold]), text("")] ++ rows
  end
end

defp snapshot_row(label, value, theme) do
  text("  #{String.pad_trailing(label, 16)}#{value}", fg: theme.primary.fg)
end

# AFTER
alias Foglet.TUI.Widgets.Display.KvGrid

def render(%__MODULE__{snapshot: s}, theme) do
  entries = [
    %{label: "Version", value: s.version},
    %{label: "Uptime", value: format_uptime(s.uptime_ms)},
    %{label: "Sessions", value: Integer.to_string(s.session_count), state: :healthy},
    %{label: "Active boards", value: Integer.to_string(s.board_count), state: :healthy},
    %{label: "OTP processes", value: Integer.to_string(s.process_count)},
    %{label: "DB pool size", value: Integer.to_string(s.db_pool_size), state: :info}
  ]

  footer = text("[r] Refresh", fg: theme.dim.fg)

  column style: %{gap: 0} do
    [text("System snapshot", fg: theme.title.fg, style: [:bold]),
     text(""),
     KvGrid.render(entries, theme: theme, width: 60, label_width: 16, gap: 2),
     text(""),
     footer]
  end
end
```

### Convert SelectionList to ConsoleTable for SSH keys

```elixir
# Source: synthesized from account/ssh_keys_surface.ex (current) + display/console_table.ex (target)

# state.ex (Account.SSHKeysState additions)
defstruct [..., :table]

def init(opts) do
  table =
    ConsoleTable.init(
      columns: [
        %{key: :label,        label: "Label",       width: 20},
        %{key: :fingerprint,  label: "Fingerprint", width: 24},
        %{key: :created,      label: "Created",     width: 11},
        %{key: :last_used,    label: "Last used",   width: 18}
      ],
      rows: [],   # repopulated on load
      selectable: true,
      empty_state: "No SSH keys registered yet."
    )

  %__MODULE__{table: table, ...}
end

# After load:
defp set_items(state, items) do
  rows = Enum.map(items, &row_for/1)
  table = ConsoleTable.init(
    columns: state.table.columns,
    rows: rows,
    selectable: true,
    empty_state: state.table.empty_state
  )
  %{state | items: items, table: table}
end

# handle_key — selection now lives in ConsoleTable
def handle_key(event, state) do
  {new_table, action} = ConsoleTable.handle_event(event, state.table)
  state = %{state | table: new_table}

  case action do
    {:row_selected, row} -> {state, [{:account_revoke_key_confirm, row.id}]}
    _ -> {state, []}
  end
end

# render
def render(%__MODULE__{table: table} = state, theme) do
  column style: %{gap: 1} do
    [..., ConsoleTable.render(table, theme: theme), text(@key_hints, fg: theme.dim.fg)]
  end
end
```

### Per-tab layout smoke test (extend layout_smoke_test.exs after line 1735)

```elixir
# Source: pattern after layout_smoke_test.exs:273-353 (Phase 22/20 size-contract)

describe "account profile tab — size contract" do
  setup do
    user = %{id: "u1", handle: "alice", role: :user, status: :active}
    {:ok, user: user}
  end

  for {width, height} <- [{64, 22}, {80, 24}] do
    @width width
    @height height
    @tag :"account profile — size contract"
    test "at #{width}x#{height} primitive renders within bounds", %{user: user} do
      width = @width
      height = @height

      ss = Account.init_screen_state() |> set_active_tab("PROFILE")

      state = %App{
        current_screen: :account,
        current_user: user,
        screen_state: %{account: ss},
        terminal_size: {width, height}
      } |> Map.from_struct()

      tree = Account.render(state)
      positioned = apply_at_size(tree, {width, height})

      texts = Enum.map(text_elements(positioned), & &1.text)

      # (a) bounds
      for el <- text_elements(positioned) do
        assert el.x + TextWidth.display_width(el.text) <= width,
               "element #{inspect(el.text)} overflows width #{width}"
      end

      # (b) Phase 24 primitive sentinel — Modal.Form footer
      assert Enum.any?(texts, &String.contains?(&1, "[Enter] Submit")),
             "expected Modal.Form footer sentinel; got: #{inspect(texts)}"

      # height
      max_y =
        text_elements(positioned)
        |> Enum.map(fn el -> Map.get(el, :y, 0) + Map.get(el, :height, 1) end)
        |> Enum.max(fn -> 0 end)

      assert max_y <= height
    end
  end
end
```

### Theme-hygiene assertion (D-12)

```elixir
# Source: pattern from test/foglet_bbs/tui/widgets/display/badge_test.exs (Phase 24)
import Foglet.TUI.WidgetHelpers

test "converted Sysop SITE tab leaks no color atoms" do
  theme = Foglet.TUI.Theme.default()
  ss = Sysop.init_screen_state() |> set_active_tab("SITE")
  state = build_state(ss)

  serialized = state |> Sysop.render() |> inspect(limit: :infinity)

  for color <- color_names() do
    refute color_atom_leaked?(serialized, color),
           "leaked :#{color} in converted SITE tab"
  end
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Bespoke `String.pad_trailing/2` rows for label/value (e.g. `system_snapshot.ex:55-57`) | `Display.KvGrid.render/2` with `TextWidth`-aware truncation/padding | Phase 24 ship | Multi-byte glyph safety; consistent label-column width across all operator surfaces. |
| `Widgets.List.SelectionList` + `ListRow` + `selected_index` (e.g. `ssh_keys_surface.ex:77-83`) | `Display.ConsoleTable` (delegates to Raxol's `Table` via `Display.Table`) | Phase 24 ship | Empty-state guard, dense defaults, `selectable: false` Enter contract; no more hand-rolled `j/k` arithmetic. |
| Inline form rendering with custom title row + bespoke field labels + ad-hoc `[Enter] Submit` footer (e.g. `prefs_form.ex:18-39`, `profile_form.ex:18-28`, `site_form.ex` D-19 fallback) | `Modal.Form.render(form, theme: theme)` body-only with title + divider + required markers + inline errors + footer | Phase 24 refresh of Modal.Form | Consistent visual hierarchy across all five operator forms; one source of truth for required-marker placement and footer copy. |
| `text("[required]", fg: theme.warning.fg)` ad-hoc badges | `Display.Badge.render(:required, theme: theme)` | Phase 24 ship | Role -> theme slot routing through `Presentation.theme_mappings().badges`; survives theme palette changes without screen edits. |

**Deprecated/outdated for Phase 25:**
- `Widgets.List.SelectionList` for operator screens — kept for non-operator screens for now, but D-04 directs operator-surface migration off of it.
- The "D-19 fallback render path" in `site_form.ex:8-13` (plain text rows + focus marker `▸`) — was an explicit deferral; this phase removes the deferral.

## Runtime State Inventory

> Phase 25 is a presentation-layer conversion. No persistent data, OS state, or service config is renamed or migrated.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — no schemas, migrations, or stored field renames. | None. |
| Live service config | None — `Foglet.Config` keys consumed by SiteForm/LimitsForm are unchanged in name and shape. | None. |
| OS-registered state | None — no SSH/systemd/launchd/Task Scheduler items affected. | None. |
| Secrets/env vars | None — no SOPS/.env keys referenced. | None. |
| Build artifacts | None — pure Elixir source edits within `lib/foglet_bbs/tui/screens/` and corresponding tests; standard `mix compile` rebuild only. | None — `mix precommit` covers it. |

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Erlang/OTP + Elixir | All TUI compilation/testing | Assumed (project precondition) | per `mix.exs` | — |
| `mix precommit` task chain (compile-warnings-as-errors, formatter, Credo, Sobelow, Dialyzer) | R8 / acceptance gate | Assumed (AGENTS.md finish-line rule) | — | — |
| `rtk` shell wrapper | Project convention for command invocation | Assumed (AGENTS.md "Use `rtk` as the shell command prefix") | — | Plain `mix` if rtk unavailable. |
| Vendored `raxol` | `Raxol.Core.Renderer.View`, `Raxol.UI.Components.Table`, `Raxol.UI.Components.Input.MultiLineInput` | Assumed (vendored under `vendor/raxol`) | per vendor pin | — |

**Missing dependencies with no fallback:** None.
**Missing dependencies with fallback:** None.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | ExUnit (Elixir built-in) |
| Config file | `test/test_helper.exs` (assumed standard layout) |
| Quick run command | `rtk mix test test/foglet_bbs/tui/screens/<screen>_test.exs --max-failures 1` |
| Full suite command | `rtk mix test` |
| Layout smoke target | `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` |
| Finish-line gate | `rtk mix precommit` |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| R1 (Account profile/prefs forms) | Modal.Form heading/required markers/inline errors/action footer present; existing dirty/save/error tests pass | unit + render | `rtk mix test test/foglet_bbs/tui/screens/account_test.exs` | Existing test file — extend with primitive-presence asserts. |
| R2 (SSH keys ConsoleTable) | Header + rows render; empty fixture renders empty-state copy; selection preserved | unit + render | `rtk mix test test/foglet_bbs/tui/screens/account/ssh_keys_*_test.exs` | Existing — extend. |
| R3 (Moderation KvGrid + Badge + ConsoleTable) | Per-tab kv-grid summary + at least one badge cell + console-table listing + empty-state copy | unit + render | `rtk mix test test/foglet_bbs/tui/screens/moderation_test.exs` | Existing — extend. |
| R4 (Sysop site/limits forms) | Same Modal.Form acceptance as R1 | unit + render | `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs` (and submodule tests) | Existing — extend. |
| R5 (Sysop boards/users/system) | ConsoleTable for boards/users with selection; KvGrid system snapshot with metric badges | unit + render | `rtk mix test test/foglet_bbs/tui/screens/sysop/*_test.exs` | Existing — extend. |
| R6 (Destructive styling) | Source/render check confirms `commands.destructive` mapping use; no hardcoded color atoms | unit | `rtk mix test test/foglet_bbs/tui/screens/<screen>_test.exs` (theme-hygiene assertions) | New per-tab assertions. |
| R7 (64x22 / 80x24 size contract) | Per-tab size loop asserts bounds + primitive sentinel | unit (layout smoke) | `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` | Existing file — extend with 12 per-tab blocks. |
| R8 (Behavior preservation + theme hygiene + inspector deferral) | Existing suites pass unmodified; `color_atom_leaked?/2` returns false; grep finds zero `Workspace.Inspector` refs in `lib/foglet_bbs/tui/screens/` | unit + grep + finish-line | `rtk mix precommit && rtk grep -r 'Workspace.Inspector' lib/foglet_bbs/tui/screens/` | Existing tests; new grep step. |

### Sampling Rate
- **Per task commit:** focused screen test (e.g. `rtk mix test test/foglet_bbs/tui/screens/account_test.exs --max-failures 1`)
- **Per wave merge:** `rtk mix test test/foglet_bbs/tui/screens/ test/foglet_bbs/tui/layout_smoke_test.exs test/foglet_bbs/tui/widgets/display/ test/foglet_bbs/tui/widgets/modal/`
- **Phase gate:** `rtk mix precommit` green before `/gsd-verify-work`.

### Wave 0 Gaps
- [ ] `test/foglet_bbs/tui/widgets/modal/form_test.exs` — extend with Shift+Tab event-shape coverage for both `%{key: :shift_tab}` AND `%{key: :tab, shift: true}` (Pitfall 1).
- [ ] `test/foglet_bbs/tui/screens/account/prefs_form_test.exs` — verify whether existing `:enum` field meets prefs UX (instant theme preview side effect, Pitfall 5) before deciding D-03 extension scope.
- [ ] Per-tab layout smoke fixture helper: `set_active_tab/2` test helper (or equivalent) that activates a tab in a `screen_state` map for the size-contract loop.
- [ ] No new framework install needed; ExUnit + Raxol already wired.

## Project Constraints (from CLAUDE.md / AGENTS.md)

- **Use `rtk` as the shell command prefix** in this repo (`rtk mix test`, `rtk git status`).
- **Read first:** `docs/raxol/getting-started/WIDGET_GALLERY.md` and `lib/foglet_bbs/tui/widgets/README.md` before TUI/Raxol work.
- **TUI namespace boundaries:** `Foglet.TUI.App` owns global state and screen routing; screens own screen-local rendering and key handling; widgets are reusable primitives. Domain logic lives in contexts, NOT in screens, SSH callbacks, or TUI render functions.
- **Stateful widget contract:** `init/1` + `handle_event/2` + `render/2`.
- **Theme routing:** colors route through `Foglet.TUI.Theme`; pass theme explicitly; render functions stay pure over already-loaded state.
- **Authorization:** use `Bodyguard.permit/4` before domain side effects; advisory UI may use `Bodyguard.permit?/4`. Hidden/disabled UI is never authorization.
- **Read-pointer / persistence invariants:** unchanged by this phase but reaffirmed — context modules own transactions and PubSub.
- **Testing:** `start_supervised!/1`, no `Process.sleep/1`, no `Process.alive?/1`. Synchronize with monitors, explicit messages, `:sys.get_state/1`.
- **Finish line:** `mix precommit` (compile warnings as errors, formatter, Credo, Sobelow, Dialyzer).
- **Memory directives applied:**
  - Verify negative findings (e.g. "no Workspace.Inspector reference") with a real `grep` before claiming.
  - Long review content -> separate file (not relevant for this phase unless Wave 0 turns up surprises).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Existing prefs `:candidate_theme_id` live-preview behavior (`prefs_form.ex:163-169`) is in-scope to preserve. | Pitfall 5 / D-03 | If preview is descoped, no Modal.Form extension is needed and D-03 scope shrinks. Confirm with user before Wave 0 commits to extending `Modal.Form`. |
| A2 | Both `%{key: :shift_tab}` and `%{key: :tab, shift: true}` event shapes can occur in the live SSH event stream. | Pitfall 1 | If only one shape ever reaches screens, only one branch is needed in `Modal.Form.handle_event/2` (reduces D-03/Wave 0 work). Verify with a quick `rtk mix test test/foglet_bbs/tui/ssh_*` probe and an `IO.inspect` instrumentation pass. |
| A3 | Sysop `boards_view.ex` is already correctly using `Modal.Form` per D-01 and needs no rework beyond destructive-styling verification. | "Recommended Project Structure" notes | If `boards_view.ex` deviates from the precedent in subtle ways (e.g. styling), Sysop wave estimate increases. Re-verify in Wave 0. |
| A4 | `Foglet.Theme.default/0` (or equivalent) is the right test harness for theme-hygiene assertions. | "Theme-hygiene assertion" code example | If themes load via `Theme.from_state/1` only, the test helper needs to wrap with a fake state. Verify against existing badge/kv_grid tests in Wave 0. |

## Open Questions

1. **Exact RadioGroup-style addition scope for D-03**
   - What we know: `Modal.Form` already supports `:enum` fields with `:up/:down` arrow cycling and `RadioGroup.render/3` (form.ex:236-249, 332-335).
   - What's unclear: Whether the prefs "live theme preview" side effect (mutates `:candidate_theme_id` mid-cycle without submit) requires a new field-state-changed callback or can be satisfied by a screen-level interception.
   - Recommendation: Wave 0 task — read prefs_form.ex side-effect contract, then decide between (a) screen reads `form.field_states` after each `handle_event/2` and detects enum cursor changes, or (b) extend `Modal.Form` with an `on_field_change` callback. (a) avoids changes to the public Modal.Form API.

2. **Whether to migrate `screens/shared/invites_surface.ex` simultaneously**
   - What we know: Invites surface is shared between Account/Moderation; spec mentions invite tabs in both R2 and R3.
   - What's unclear: Single conversion vs per-screen call sites.
   - Recommendation: Convert `InvitesSurface.render/2` once to `ConsoleTable`; both screens automatically benefit. Sequence in Wave 0 since it's a shared dependency.

3. **Exact column widths at 64x22 for moderation/sysop listings**
   - What we know: ConsoleTable defaults to width 12 per column (Pitfall 9); 64-col viewport leaves ~62 usable after frame chrome.
   - What's unclear: Which columns drop or truncate at 64x22.
   - Recommendation: Discretion (CONTEXT). Default to dense priority columns visible at 64; secondary columns visible at 80. Validate via per-tab smoke test.

## Sources

### Primary (HIGH confidence — in-repo, verified)
- `lib/foglet_bbs/tui/widgets/display/console_table.ex` — full source read.
- `lib/foglet_bbs/tui/widgets/display/badge.ex` — full source read.
- `lib/foglet_bbs/tui/widgets/display/kv_grid.ex` — full source read.
- `lib/foglet_bbs/tui/widgets/display/table.ex` — full source read.
- `lib/foglet_bbs/tui/widgets/modal/form.ex` — full source read.
- `lib/foglet_bbs/tui/screens/sysop/boards_view.ex` — canonical precedent, lines 1-120, 230-300, 435-494 read.
- `lib/foglet_bbs/tui/screens/account/{profile_form,prefs_form,ssh_keys_surface}.ex` — full source read.
- `lib/foglet_bbs/tui/screens/sysop/{site_form,limits_form,users_view,system_snapshot}.ex` — full or partial source read.
- `lib/foglet_bbs/tui/screens/moderation.ex` — lines 1-280 read.
- `lib/foglet_bbs/tui/presentation.ex` — `theme_mappings()` lines 30-110 read.
- `test/support/foglet/tui/widget_helpers.ex` — full source read.
- `test/foglet_bbs/tui/layout_smoke_test.exs` — lines 270-353 (precedent loop), 1735-1830 (shell-only baseline) read.
- `.planning/phases/24-operator-console-primitives/24-VERIFICATION.md` — verification report read; confirms all primitives shipped.
- `.planning/phases/25-operator-console-conversion/25-CONTEXT.md` — locked decisions.
- `.planning/phases/25-operator-console-conversion/25-SPEC.md` — locked requirements.
- `AGENTS.md` / `CLAUDE.md` — project conventions.

### Secondary (MEDIUM confidence)
- None — all claims grounded in in-repo source.

### Tertiary (LOW confidence)
- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every primitive read directly from source; Phase 24 verification report confirms shipped.
- Architecture patterns: HIGH — `boards_view.ex` is a fully-worked precedent for the dominant pattern.
- Pitfalls: HIGH for 1, 2, 3, 4, 6, 7, 8, 9 (all grounded in source); MEDIUM for 5 (depends on whether existing `:enum` field meets prefs UX — flagged as A1).
- Validation architecture: HIGH — ExUnit + existing `layout_smoke_test.exs` pattern.

**Research date:** 2026-04-25
**Valid until:** 2026-05-25 (in-repo modules; only invalidates on Phase 24 primitive churn or `Foglet.TUI.Theme` slot changes — both out-of-scope this phase).
