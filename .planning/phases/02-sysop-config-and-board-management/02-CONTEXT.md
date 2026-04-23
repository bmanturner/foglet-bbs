# Phase 2: Sysop Config and Board Management - Context

**Gathered:** 2026-04-23 (assumptions mode — all 13 areas locked in `02-ASSUMPTIONS-REVIEW.md`)
**Status:** Ready for planning (Phase 1.1 `Modal.Form` has landed; see `lib/foglet_bbs/tui/widgets/modal/form.ex`)

<domain>
## Phase Boundary

Sysops can manage typed site policy, invite-generation policy, board/category lifecycle,
and system details from the TUI on top of the Phase 1 authorization backbone. The phase
delivers real behavior behind the Phase 0 sysop shell tabs (`SITE | BOARDS | LIMITS |
SYSTEM | USERS`), writing through `Foglet.Config.put/3` and `Foglet.Boards.*` with
actor-aware `Bodyguard.permit/4` guards. Category CRUD is born guarded in this phase.

Covers requirements INVT-06, INVT-07, SYSO-02, SYSO-03, SYSO-04. Out of scope: site
identity (name/MOTD/banner), USERS tab behavior (Phase 8), invite generation/redemption
UI (Phases 3/4), and any unschematized config keys.
</domain>

<decisions>
## Implementation Decisions

### Config surface (§1, §2, §13)
- **D-01:** The SITE and LIMITS tabs render by iterating `Foglet.Config.Schema.entries/0`
  and `Schema.fetch_spec/1` — never by reading rows from the `configuration` table. This
  is the hard guardrail that keeps unschematized / aspirational keys out of the UI
  (success criterion 1; `REQUIREMENTS.md:81`).
- **D-02:** Tab partition is encoded as two module attributes on the Sysop screen,
  `@site_keys` and `@limits_keys` (Alternative (a)). A new schematized key must be added
  to one of the two lists explicitly; a test enforces that every `Schema.entries/0` key
  appears in exactly one list.
- **D-03:** Partition is split by TYPE (Alternative (a) of §2):
  - **SITE:** `registration_mode`, `invite_code_generators`, `require_email_verification`,
    plus the new `invite_generation_per_user_limit` (see D-04).
  - **LIMITS:** `max_post_length`, `max_thread_title_length`,
    `email_verify_resend_cooldown_seconds`.
- **D-04:** INVT-07 adds ONE new schematized integer key
  `invite_generation_per_user_limit` (type `:integer`, `min: 0`, default `0`, where
  `0` means "unlimited"; Alternative (a) of §3). No new `:union`/`:nullable` plumbing.
  The SITE row is rendered conditionally: visible only when
  `invite_code_generators == "any_user"`, hidden otherwise. Phase 3 (generation
  enforcement) and Phase 4 (INVITES tab visibility) consume both keys.
- **D-05:** SITE tab does NOT expose site identity (name/MOTD/banner) or any
  unschematized key. USERS tab remains the Phase 0 scaffold. Invite generation and
  redemption UI stay out of scope (Phase 3 / Phase 4).

### Config write path (§4, §5)
- **D-06:** The Sysop form calls `Foglet.Config.put/3` (the actor-aware tagged-tuple
  variant at `config.ex:138-168`), NEVER `put!/3`. `put!/3` raises and is reserved for
  seeds / trusted internal callers.
- **D-07:** Validation errors (`:unknown_key`, `:invalid_value`) surface INLINE under
  the offending field using `theme.error.fg`, mirroring
  `Foglet.TUI.Screens.NewThread` (`new_thread.ex:117-122, 314-319`). In the Phase 1.1
  `Modal.Form` primitive this is the `set_errors/2` path (D-18 of Phase 01.1).
- **D-08:** Non-recoverable errors (`:forbidden`, `:db_error`) route to the shared
  `%Foglet.TUI.Modal{type: :error}` flow and return the user to `:main_menu`.
  `:forbidden` is treated as "actor was demoted mid-session".
- **D-09:** No PubSub broadcasts on config writes. The ETS invalidation already
  performed by `Foglet.Config.put/3` → `do_put!/3` → `invalidate/1`
  (`config.ex:232`) is the sole propagation mechanism — every reader picks up the new
  value on its next `get!/1`. Cross-node/real-time reactivity is deferred to the phase
  that first needs it (Phase 4 INVITES visibility is the likely trigger).

### Boards & Categories domain (§6, §7)
- **D-10:** Category CRUD is additive to `Foglet.Boards` — NO `Foglet.Categories`
  module (Alternative (a) of §6). New functions:
  - `create_category/2` (actor-first; wraps the current `create_category/1` for
    actor-first parity with `create_board/3`)
  - `update_category/3`
  - `archive_category/2`
  Each follows the `Bodyguard.permit(Foglet.Authorization, action, actor, :site)` +
  `with :ok <-` pattern from `boards.ex:71-102`.
- **D-11:** `Foglet.Boards.Category` gains an `archive_changeset/1` mirroring
  `Foglet.Boards.Board.archive_changeset/1` (`board.ex:55-59`).
- **D-12:** `archive_board/2` keeps its current flag-flip behavior — it does NOT stop
  the running `Foglet.Boards.Server` GenServer. The supervisor's
  `Foglet.Boards.boot_board_servers/0` `where: b.archived == false` predicate makes
  application restart the re-decision point. No `DynamicSupervisor.terminate_child/2`
  plumbing is added in this phase. Posting is already blocked at the write layer by
  `Board.postable_by`.

### Screen architecture (§8, §10)
- **D-13:** `Foglet.TUI.Screens.Sysop.State` grows per-tab fields:
  `site_form`, `limits_form`, `boards_view`, `system_snapshot`. Draft state is retained
  across tab switches (no blur-save).
- **D-14:** Each tab owns a submodule under `lib/foglet_bbs/tui/screens/sysop/` exposing
  `init/1 + handle_key/2 + render/2`:
  - `sysop/site_form.ex`
  - `sysop/limits_form.ex`
  - `sysop/boards_view.ex`
  - `sysop/system_snapshot.ex`
  The parent `Sysop` screen handles tab-bar keys and delegates non-tab-bar keys to the
  active tab's submodule. Matches the `sysop/state.ex`, `new_thread/state.ex`, and
  `post_reader/state.ex` precedents (`CONVENTIONS.md:47-49`).
- **D-15:** SITE and LIMITS render as full-tab inline forms (not in a modal). They
  show an explicit `[Ctrl+S] Save` key hint in the style of `new_thread.ex:139`.
  Explicit save only — no dirty-on-blur auto-save.
- **D-16:** BOARDS tab renders a vertically-stacked list grouped by category
  (category heading rows with indented board rows) using
  `Foglet.TUI.Widgets.List.SelectionList` + `ListRow` (the same primitives
  `new_thread.ex:77-80` uses). `boards_view` owns the list AND whichever modal is
  currently open (or `nil`).
- **D-17:** BOARDS create/edit uses the **Phase 1.1 `Foglet.TUI.Widgets.Modal.Form`**
  primitive (`lib/foglet_bbs/tui/widgets/modal/form.ex`). Field types exercised:
  `:text` (slug, title), `:textarea` (description), `:enum` (category selection),
  `:boolean` (sysop-only flag where applicable). The form is rendered inside
  `Foglet.TUI.App.render_modal_overlay/2` — `Modal.Form.render/2` must not be wrapped
  in its own border (per Phase 01.1 RESEARCH Pitfall 4).
- **D-18:** BOARDS archive uses the existing read-only `%Foglet.TUI.Modal{type:
  :confirm}` `Y/N` prompt — NOT `Modal.Form`. Archival is a single-action
  confirmation, not a form.
- **D-19:** SITE and LIMITS field types map to `Modal.Form` field types even though
  they render inline on the tab: `:boolean` / `:enum` → same widgets; `:integer` with
  `:min`/`:max` → `:integer` field with caller-side range validation on submit. If
  rendering inline (not-in-a-modal) costs too much adapter work, the planner MAY
  instead render SITE/LIMITS directly with `TextInput` / `Checkbox` / `RadioGroup`
  primitives; `Modal.Form` is required only for BOARDS per D-17.

### SYSTEM tab (§9)
- **D-20:** SYSTEM is read-only (per SYSO-04) and snapshot-based (Alternative (a) of §9).
  Snapshot on tab enter; `r` keypress re-samples. NO auto-refresh ticker.
- **D-21:** Snapshot fields:
  - BBS version — `:application.get_key(:foglet_bbs, :vsn)`
  - Uptime — `:erlang.statistics(:wall_clock)`
  - Active session count — `Registry.count(Foglet.Sessions.Registry)`
  - Active board server count —
    `DynamicSupervisor.count_children(Foglet.Boards.Supervisor)`
  - OTP process count — `:erlang.system_info(:process_count)`
  - DB pool size — `FogletBbs.Repo.config/0` (`:pool_size` key)
  No new telemetry module. `FogletBbsWeb.Telemetry` is for Phoenix/LiveDashboard, not
  the TUI.

### Authorization wiring (§11)
- **D-22:** Every domain call (`Foglet.Config.put/3`,
  `Foglet.Boards.{create,update,archive}_board/_`,
  `Foglet.Boards.{create,update,archive}_category/_`) passes `state.current_user` as
  actor and `:site` as scope (Phase 1 D-04 / D-06 / D-08).
- **D-23:** The Sysop screen does NOT call `Bodyguard.permit?/4` for advisory
  rendering. Screen-level `ShellVisibility.sysop_visible?/1`
  (`shell_visibility.ex:51-53`) is the only UI-level gate. The domain is the trust
  boundary (Phase 1 D-17 / D-18).
- **D-24:** `{:error, :forbidden}` from any domain call is interpreted as
  "actor was demoted mid-session" and routed to the `:error` modal + return to
  `:main_menu` (consistent with D-08). This covers Phase 1 D-25's stale-snapshot case
  at the UI layer.

### Testing (§12)
- **D-25:** New assertions live in EXISTING test files where possible:
  - `test/foglet_bbs/config_test.exs` — extend for
    `invite_generation_per_user_limit` (happy / `:forbidden` / `:unknown_key` /
    `:invalid_value`).
  - `test/foglet_bbs/boards/boards_test.exs` — extend for `update_category/3`,
    `archive_category/2`, and actor-first `create_category/2`.
  - `test/foglet_bbs/tui/screens/sysop_test.exs` — extend for render-output
    assertions and key-handling smoke tests on each tab.
- **D-26:** Per-tab submodule tests MAY live under
  `test/foglet_bbs/tui/screens/sysop/` (mirroring the `new_thread_test.exs` split)
  if `sysop_test.exs` grows unwieldy. Planner's discretion.
- **D-27:** TUI tests use `Foglet.TUI.RenderHelpers.collect_text_values/1` and build
  `%Foglet.TUI.App{}` structs directly (`sysop_test.exs:9-17` pattern). All
  persistence tests use `FogletBbs.DataCase, async: false` because the
  `:foglet_config` ETS table is process-global (`config_test.exs:3`).

### Acceptance / quality gate
- **D-28:** `mix precommit` must pass (compile --warnings-as-errors, format, credo
  --strict, sobelow, dialyzer) before the phase is considered done. Per project
  CLAUDE.md.

### Claude's Discretion
- Exact field ordering within SITE / LIMITS / BOARDS forms. Recommend order-of-declaration
  from `Schema.entries/0` so adding a new schematized key inserts predictably.
- Whether the conditional `invite_generation_per_user_limit` row (D-04) hides or greys
  out when `invite_code_generators != "any_user"`. Recommend HIDE — matches the
  ShellVisibility pattern (reactivity via next render).
- Whether to surface `:db_error` as a distinct error-modal message vs a generic
  "couldn't save". Recommend a distinct message including the reason, since sysops are
  the audience and opacity helps no-one here.
- Whether inline SITE/LIMITS submit is keyed on `Ctrl+S` only or also `Enter` when the
  last field is focused. Recommend `Ctrl+S` ONLY — avoids accidental saves while
  typing in an integer/text field; mirrors `new_thread.ex:139`.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `.planning/phases/02-sysop-config-and-board-management/02-ASSUMPTIONS-REVIEW.md` —
  the 13-area assumption log this CONTEXT.md codifies
- `.planning/REQUIREMENTS.md` — INVT-06, INVT-07, SYSO-02, SYSO-03, SYSO-04
- `.planning/ROADMAP.md` — Phase 2 success criteria (lines 63-67)
- `.planning/phases/01-authorization-and-scope-backbone/01-CONTEXT.md` — authz seam
  decisions carried forward (D-02 call shape, D-04/06/08 actor+scope,
  D-12 action-atom allowlist, D-17/18 domain-as-trust-boundary, D-19 actor-first CRUD
  signature, D-25 demoted-mid-session semantics)
- `.planning/phases/01.1-shared-modal-form-primitive/01.1-CONTEXT.md` — `Modal.Form`
  primitive contract (init/handle_event/render triplet, field types, set_errors,
  render-in-overlay-slot constraint)
- `docs/DATA_MODEL.md` §11 — authoritative list of seeded vs aspirational config keys
- `docs/ARCHITECTURE.md` — module boundaries
- `.planning/codebase/CONVENTIONS.md` §§42-49 — per-screen submodule layout convention

**Code references (verified 2026-04-23):**
- `lib/foglet_bbs/config.ex:138-168` — `put/3` tagged-tuple variant (call this, not `put!/3`)
- `lib/foglet_bbs/config.ex:232` — `invalidate/1` ETS cache propagation
- `lib/foglet_bbs/config/schema.ex:39-106, 118-126, 159` — `entries/0`, `fetch_spec/1`,
  `@allowed_types`
- `lib/foglet_bbs/boards.ex:35-39, 45-59, 71-102, 125-131` — `boot_board_servers/0`,
  existing category CRUD, `create_board/3` Bodyguard pattern, `archive_board/2`
- `lib/foglet_bbs/boards/board.ex:55-59` — `archive_changeset/1` reference pattern
- `lib/foglet_bbs/tui/widgets/modal/form.ex` — Phase 1.1 `Modal.Form` primitive
- `lib/foglet_bbs/tui/app.ex` — `render_modal_overlay/2` chrome slot
- `lib/foglet_bbs/tui/screens/sysop.ex:41`, `lib/foglet_bbs/tui/shell_visibility.ex:51-53, 69-72` —
  sysop-screen visibility gate + invites-visible reactivity precedent
- `lib/foglet_bbs/tui/screens/new_thread.ex:77-80, 101-103, 117-122, 139, 237, 314-319` —
  list + label + inline-error + `Ctrl+S` + modifier-key precedents
- `test/foglet_bbs/tui/screens/sysop_test.exs:9-17, 96, 147` — render/key-test fixtures
- `test/foglet_bbs/config_test.exs:3` — `DataCase, async: false` precedent
- `test/support/foglet/tui/render_helpers.ex` — `collect_text_values/1`
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.Config` — `get!/1`, `put/3` (actor-aware), `put!/3` (unsafe), `invalidate/1`
- `Foglet.Config.Schema` — `entries/0`, `fetch_spec/1`, `check/2`; types
  `:string | :integer | :boolean` with `:enum`, `:min`, `:max`, `:description`
- `Foglet.Authorization` (Phase 1) — `Bodyguard.permit/4`, `permit?/4`, `scopes_for/2`
- `Foglet.Boards` — existing board CRUD with Bodyguard, `create_category/1` (to be
  widened), `get_category!/1`, `list_categories/0`, `boot_board_servers/0`
- `Foglet.TUI.Widgets.Modal.Form` (Phase 1.1) — `init/1`, `handle_event/2`, `render/2`,
  `set_errors/2`; supports `:text`, `:integer`, `:boolean`, `:enum`, `:textarea`
- `Foglet.TUI.Widgets.Input.{TextInput, Checkbox, RadioGroup}` — primitives for inline
  SITE/LIMITS forms
- `Foglet.TUI.Widgets.List.SelectionList` + `ListRow` — BOARDS tab list
- `Foglet.TUI.Modal` — existing `:error` and `:confirm` variants
- `Foglet.TUI.App.render_modal_overlay/2` — modal chrome
- `Foglet.TUI.ShellVisibility.sysop_visible?/1` — screen-level authz gate
- `Foglet.TUI.Theme` — `primary`, `accent`, `error`, `dim`, `title` slots
- `Foglet.TUI.RenderHelpers` (test/support) — `collect_text_values/1`

### Established Patterns
- D-14 stateful widget triplet (`init/1 + handle_event/2 + render/2`)
- Actor-first domain CRUD: `fun(actor, attrs_or_id[, attrs])` with
  `Bodyguard.permit/4` as the first `with` clause
- Inline field error (`theme.error.fg`) + modal for non-recoverable errors —
  mirrors `NewThread`
- Per-tab/submodule split under `screens/<screen>/` (established by
  `screens/sysop/state.ex`, `screens/new_thread/state.ex`,
  `screens/post_reader/state.ex`)
- ETS-only cache propagation with process-global `:foglet_config` table
- `async: false` on any test touching `Foglet.Config`

### Integration Points
- The Sysop screen (`Foglet.TUI.Screens.Sysop`) is the sole caller. It is already
  wired into the tab bar and the app shell (Phase 0 D-03, D-05, D-11, D-12).
- `Foglet.Config.put/3` and `Foglet.Boards.*` are the only domain entry points used.
- `Modal.Form` state lives inside `boards_view`, which lives inside `Sysop.State`.
- No edits to `Foglet.TUI.App` are required; the overlay slot already routes events
  to the active modal first (per Phase 01.1 integration note).
</code_context>

<specifics>
## Specific Ideas

- §3 (INVT-07) sentinel encoding: `0 = unlimited` chosen over the two-key
  mode+value alternative specifically because `Foglet.Config.Schema`'s
  `@allowed_types` is `[:string, :integer, :boolean]` today — introducing
  `:union`/`:nullable` just for this row would drag a schema-layer change into a
  phase that shouldn't need one. Phase 3 (generation) and Phase 4 (INVITES
  visibility) both read through the sentinel.
- Conditional row visibility for `invite_generation_per_user_limit` (D-04) is
  re-evaluated on every `render/1`, matching `ShellVisibility.invites_visible?/2`'s
  re-read-on-render pattern (`shell_visibility.ex:69-72`). No listener is needed.
- Archive of a live board (D-12) is advisory: the hidden board stays in-memory on
  its server but is invisible via `list_boards/0` and unwritable via
  `Board.postable_by`. Cheap to upgrade to immediate server termination later by
  adding `BoardSupervisor.stop_board/1`; not required in v1.1.
- §8's corrected approach (use Phase 1.1 `Modal.Form`) intentionally avoids baking
  form-step state machinery into `Sysop` itself. Every future CRUD-on-list workflow
  (moderation bans, account edits, invite-generation config) will reuse
  `Modal.Form`; this phase is the first consumer and should treat its usage as the
  worked example for those future flows.
</specifics>

<deferred>
## Deferred Ideas

- Site identity fields (site name, MOTD, login banner) — require new unschematized
  keys; explicitly out of scope per `REQUIREMENTS.md:81`.
- USERS tab content — Phase 8 (moderation / user admin).
- Invite generation/redemption UI — Phase 3 persistence, Phase 4 tab visibility.
- Aspirational operational limits listed in `docs/DATA_MODEL.md:699-709` (rate
  limits, retention days, oneliner caps) — deferred to v2 per `SYSO-06`
  (`REQUIREMENTS.md:67`) until typed runtime consumers exist.
- Real-time cross-session config reactivity (PubSub broadcasts on config writes) —
  Phase 4 will revisit when INVITES tab visibility needs it.
- `BoardSupervisor.stop_board/1` for immediate-offline board archival.
- Auto-refreshing SYSTEM tab (ticker-driven live metrics).
- Advisory `permit?/4` checks on row-level disable states.
- Per-tab submodule test split under `test/foglet_bbs/tui/screens/sysop/` — adopt
  only if `sysop_test.exs` becomes unwieldy.

### Reviewed Todos (not folded)
None — no open todos matched phase 2 at time of discuss.
</deferred>
