# Phase 2: Sysop Config and Board Management — Assumptions Review

> **Purpose:** Review these assumptions, mark any you want to correct, then let me know.
> I'll turn the confirmed set into `02-CONTEXT.md` (locked decisions for the planner).
>
> **How to use:** For each area below, either accept the assumption or write a correction
> inline under **My correction:**. When you're done, say "looks good" or send the file back.
>
> **Status (2026-04-23):** All recommended options approved. One correction taken: §8's
> BOARDS create/edit workflow switches from "inline sub-step on the screen" to the new
> `Modal.Form` primitive shipped in **Phase 1.1**. Research + planning for Phase 2 is
> parked until Phase 1.1 merges. This file stays as-is for the audit trail; `02-CONTEXT.md`
> will be written after Phase 1.1 lands so the form-modal plumbing is referenceable.

**Phase goal (ROADMAP.md):** Sysops can manage typed site policy, invite controls,
board/category lifecycle, and system details from the TUI on top of the new authz
backbone (Phase 1).

**Requirements:** INVT-06, INVT-07, SYSO-02, SYSO-03, SYSO-04
**Success Criteria:**
1. Sysop can change seeded runtime config values for registration, invite policy, and
   operational limits from the TUI, and **unschematized config keys are NOT exposed there**.
2. Invite generation policy can be set to `sysop_only`, `mods`, or `any_user`, and
   `any_user` mode can use either unlimited or numeric per-user invite caps.
3. Sysop can create, update, list, and archive categories and boards from the `BOARDS`
   tab **without direct database edits**.
4. Sysop can inspect current system details from the `SYSTEM` tab.

**UI hint:** yes — this phase ships real sysop behavior on top of the Phase 0 sysop
shell and the Phase 1 authz seam.

**Carrying forward (locked in prior phases, not re-decided here):**
- Sysop shell + tab order `SITE | BOARDS | LIMITS | SYSTEM | USERS` (Phase 0 D-11).
- `Foglet.TUI.Widgets.Input.Tabs`, rendered through `Chrome.ScreenFrame` (Phase 0 D-03, D-05).
- `nil = loading`, `[] = empty placeholder`, errors via shared modal (Phase 0 D-12).
- `Bodyguard.permit(Foglet.Authorization, action, actor, scope)` is the call shape (Phase 1 D-02).
- `:edit_config`, `:create_board`, `:update_board`, `:archive_board`,
  `:create_category`, `:update_category`, `:archive_category` atoms already in the
  allowlist (Phase 1 D-12). Config / board CRUD already take `actor` as first arg
  (Phase 1 D-19). Category CRUD is born guarded in this phase.
- Actor is `User.t() | nil` carried as `state.current_user`; sysop ops use `:site` scope
  (Phase 1 D-04, D-06, D-08).

**Hard dependency — Phase 1.1 lands first:**
A new widget `Foglet.TUI.Widgets.Modal.Form` (or equivalent) is delivered in Phase 1.1
before this phase is researched or planned. §8 and §10 below assume it exists.

---

## 1. Typed config surface and the "unschematized keys" guardrail

**Confidence:** Likely

**Assumption:** The SITE and LIMITS tabs introspect `Foglet.Config.Schema.entries/0`
and render one editor row per schematized key, grouping keys into tabs by a small
hard-coded partition. Unschematized / "aspirational" keys listed in
`docs/DATA_MODEL.md` §11 are **never** shown because the UI never reads from the DB row
list — it only iterates `Schema.entries/0`.

**Why this way:**
- `lib/foglet_bbs/config/schema.ex:39-106` is already declarative
  (`:type :string | :integer | :boolean`, `:enum`, `:min`, `:max`, `:description`), and
  `Schema.entries/0` / `fetch_spec/1` are public (lines 118-126).
- `docs/DATA_MODEL.md:697` — "Foglet.Config.Schema declares the seeded keys". The schema
  is the canonical source of truth.
- `REQUIREMENTS.md:81` — "Out of Scope: Broad sysop controls for unschematized config
  keys" makes introspect-the-schema the only design consistent with the scope guardrail.

**If wrong:** If the UI instead queried the `configuration` table directly, historical
rows that pre-date the schema (mentioned in `config.ex:16-18`) could leak into the form
without typed validators — a sysop could save garbage values that break the read path.

**Alternatives:**
- **(a) Recommended — hard-coded partition.** Two module attributes on the Sysop screen
  (`@site_keys`, `@limits_keys`) enumerate which schematized keys land on which tab.
  Simple, explicit. A new schematized key silently drops to whichever tab you add it to
  (or neither — catch with a test).
- **(b) Data-driven — add `:tab` field to schema entries.** Each `Schema.entries/0` entry
  grows a `:tab` field (`:site | :limits`). More self-describing; adds a new concern to
  a schema module that is otherwise pure type/value shape.

**My choice:** _( a / b )_

**My correction:**

---

## 2. SITE vs LIMITS tab partition

**Confidence:** Likely

**Assumption:** SITE holds behavioral/policy toggles. LIMITS holds numeric operational
caps. In concrete terms today:

- **SITE:** `registration_mode`, `invite_code_generators`, `require_email_verification`,
  plus the new `invite_generation_per_user_limit` from §3.
- **LIMITS:** `max_post_length`, `max_thread_title_length`,
  `email_verify_resend_cooldown_seconds`.

The 15+ "aspirational" operational limits in `docs/DATA_MODEL.md:699-709` (rate limits,
retention days, oneliner caps) stay unschematized in v1.1 — LIMITS ships sparse and
grows when later phases land typed runtime consumers (`SYSO-06` v2 deferral,
`REQUIREMENTS.md:67`).

**Why this way:**
- The ROADMAP success criterion enumerates exactly three policy areas: "registration,
  invite policy, and operational limits". That maps cleanly onto the existing six
  schema keys.
- `invite_code_generators` is framed as "invite generation POLICY" in INVT-06 — lives
  more naturally under SITE than LIMITS.

**If wrong:** If the user actually wants `email_verify_resend_cooldown_seconds` grouped
with `require_email_verification` (affinity over numeric-type), LIMITS becomes only the
two content caps. Cosmetic partition difference only.

**Alternatives:**
- **(a) Recommended — split by type.** Booleans + enums on SITE, integers on LIMITS.
  `email_verify_resend_cooldown_seconds` goes to LIMITS.
- **(b) Split by affinity.** Keep `email_verify_resend_cooldown_seconds` with its sibling
  email toggle on SITE; LIMITS holds only `max_post_length` + `max_thread_title_length`.

**My choice:** _( a / b )_

**My correction:**

---

## 3. INVT-07 encoding: one config key or two? ⚠️ WORTH CONFIRMING

**Confidence:** Likely

**Assumption:** Add ONE new schematized integer key
`invite_generation_per_user_limit` (integer, `min: 0`; `0` means unlimited). Keep
`invite_code_generators` unchanged. The SITE tab's INVT-07 row is rendered
conditionally — visible only when `invite_code_generators == "any_user"`, greyed/hidden
otherwise. Phase 3 (generation enforcement) and Phase 4 (INVITES tab visibility) both
read these two keys.

**Why this way:**
- The schema supports `:integer` with `:min` (`schema.ex:74`, `max_post_length` uses
  `min: 1`); a sentinel of `0 = unlimited` matches the existing "integer with range"
  idiom without inventing a new union type.
- `Schema.check/2`'s `@allowed_types` is currently `[:string, :integer, :boolean]`
  (`schema.ex:159`). There is no plumbing for `:union` or `:nullable` today.
- INVT-07 explicitly says "unlimited or a numeric cap" — two states that fit a single
  integer with a sentinel.

**If wrong:** `0 = unlimited` makes "0 invites per user in `any_user` mode"
unrepresentable, which is fine — that's equivalent to turning `any_user` off.

**Alternatives:**
- **(a) Recommended — sentinel.** One key:
  `invite_generation_per_user_limit :: integer, min 0, default 0` where `0 = unlimited`.
- **(b) Two keys + cross-key validation.**
  `invite_generation_per_user_limit_mode :: "unlimited" | "numeric"` +
  `invite_generation_per_user_limit :: integer, min 1`. More explicit; doubles the write
  surface and introduces cross-key validation the schema layer doesn't support today.

**My choice:** _( a / b )_

**My correction:**

---

## 4. Config write path and validation surface in the TUI

**Confidence:** Confident

**Assumption:** The sysop form calls `Foglet.Config.put/3` (the actor-aware
tagged-tuple variant, `config.ex:138-168`), NOT `put!/3`. Validation errors
(`:unknown_key`, `:invalid_value`) surface inline under the offending field using the
same `ss.error` + `theme.error.fg` pattern as `Foglet.TUI.Screens.NewThread`
(`new_thread.ex:117-122, 314-319`). Non-recoverable errors (`:forbidden`, `:db_error`)
route to the shared `%Foglet.TUI.Modal{type: :error}` path.

**Why this way:**
- `put/3` was built in Phase 1 Plan 03 specifically "for interactive callers (TUI sysop
  screen in Phase 2, future API clients)" (`config.ex:126`); `put!/3` raises and is for
  seeds/trusted internal paths.
- `NewThread` already models the inline-validation-error + modal-on-error split — the
  shapes differ but the UX pattern is the same.

**If wrong:** `put!/3` in the form would crash the Raxol `update/2` process and tear
down the session on any validation failure. Putting `:forbidden` inline instead of the
modal would silently reject a demoted-mid-session sysop without them understanding why.

**My correction:** _(leave blank to accept)_

---

## 5. Config change propagation — no PubSub yet, ETS invalidation is enough

**Confidence:** Confident

**Assumption:** Phase 2 does NOT add PubSub broadcasts on config writes.
`Foglet.Config.put/3` → `do_put!/3` → `invalidate/1` (`config.ex:232`) is the sole
propagation mechanism; every other session reads through ETS on next `get!/1` and picks
up the change. Cross-node invalidation is deferred because the app is single-node per
`PROJECT.md` Constraints.

**Why this way:**
- No callers of `Phoenix.PubSub.broadcast/3` exist in `Foglet.Config`.
- The cache is process-global named ETS with `read_concurrency: true` (`config.ex:40`),
  so ETS invalidation from the writer is visible to every reader in the same BEAM
  instance.
- `ShellVisibility.invites_visible?/2` re-reads config on every `render/1`
  (`shell_visibility.ex:69-72`), so a next-keypress tab-set refresh already works for
  the v1.1 reactivity need.

**If wrong:** Phase 4 (INVITES tab visibility) is where real-time reactivity would first
matter. Adding PubSub is additive — reversible.

**My correction:** _(leave blank to accept)_

---

## 6. Boards/Categories CRUD is additive to `Foglet.Boards`, no new context module

**Confidence:** Likely

**Assumption:** Phase 2 extends `Foglet.Boards` with four new functions —
`update_category/3`, `archive_category/2`, plus re-wrapping `create_category/1` as
`create_category/2` with actor-first signature — all following the same
`Bodyguard.permit/4` + `with :ok <-` pattern as `create_board/3`
(`boards.ex:71-102`). No `Foglet.Categories` module is introduced.

The Category schema gains an `archive_changeset/1` mirroring `Board.archive_changeset/1`
(`board.ex:55-59`).

**Why this way:**
- `Foglet.Boards` already owns categories — `create_category/1`, `get_category!/1`,
  `list_categories/0` are co-located (`boards.ex:45-59`).
- Phase 1 CONTEXT D-19's provisional "Foglet.Categories.*" naming was descriptive, not
  prescriptive. The codebase convention is "one context per aggregate root", and
  categories-without-boards are not a meaningful aggregate.
- Tests in `boards_test.exs:24-36` already drive categories through `Foglet.Boards`.

**If wrong:** Splitting into `Foglet.Categories` is a mechanical but unnecessary diff —
module churn without boundary benefit.

**Alternatives:**
- **(a) Recommended — extend `Foglet.Boards`.** Add `update_category/3` and
  `archive_category/2` alongside `create_board/3`. Change `create_category/1` →
  `create_category/2` for actor-first parity.
- **(b) `Foglet.Boards.Categories` submodule.** Namespace-only split; zero API benefit.

**My choice:** _( a / b )_

**My correction:**

---

## 7. Board archival does NOT stop the Board Server

**Confidence:** Confident

**Assumption:** `archive_board/2` flips the `archived` flag only (`boards.ex:125-131`,
`board.ex:55-59`); the running `Foglet.Boards.Server` GenServer for that board keeps
running until the next application restart, at which point
`Foglet.Boards.boot_board_servers/0` (lines 35-39) skips archived boards via the
`where: b.archived == false` predicate. Phase 2 does NOT add runtime
`DynamicSupervisor.terminate_child/2` plumbing.

**Why this way:**
- The current `Foglet.Boards.archive_board/2` already has zero server-termination code
  (lines 123-131). The supervisor's "all non-archived boards start at boot" model
  (`supervisor.ex:9`) makes restart the re-decision point.
- Archived boards still need to be queryable by existing threads/posts. The Server's
  only live purpose is message-number allocation for NEW posts; posting on an archived
  board is blocked at a higher level (UI hides navigation; `Board.postable_by` enforces
  at write time).

**If wrong:** If sysops expect "archive = immediately offline", active sessions could
still hit the Server via a stale thread view. Given archival is rare and advisory, and
the board is already hidden from `list_boards/0`, the UX impact is near-zero. Adding
`BoardSupervisor.stop_board/1` is cheap if needed later.

**My correction:** _(leave blank to accept)_

---

## 8. BOARDS tab layout — categorized list, `Modal.Form` for create/edit, confirm modal for archive

**Confidence:** Confirmed (correction applied)

**Assumption (corrected):** The BOARDS tab renders a vertically-stacked list grouped
by category (category heading rows, indented board rows), using
`Foglet.TUI.Widgets.List.SelectionList` + `ListRow` (already used by
`new_thread.ex:77-80`). Create/edit opens the **new `Foglet.TUI.Widgets.Modal.Form`
primitive delivered in Phase 1.1** — a modal overlay that hosts typed input fields
(text / integer / boolean / enum), handles field focus and Tab/Shift-Tab navigation,
exposes submit and cancel callbacks, and surfaces inline validation errors per field.
Archival stays on the existing read-only `%Foglet.TUI.Modal{type: :confirm}` `Y/N`
prompt.

**Why this way:**
- The original inline-sub-step approach (borrowed from `NewThread`) would have baked
  form-navigation logic into the Sysop screen module. Building `Modal.Form` as a shared
  primitive instead means every future CRUD workflow (moderation bans, account edits,
  invite-generation config) reuses one container rather than re-inventing per-screen
  step machines.
- `NewThread`'s `state.step` pattern stays valid as a precedent for single-flow
  sequences (compose → post), but create-edit-archive workflows on a list are a
  different shape: a modal that opens over the list and returns control to it.
- The read-only `:confirm` modal type is already the right primitive for archive
  confirmation and stays as-is.

**If wrong (minor):** If `Modal.Form`'s field set doesn't cover what categories/boards
need (e.g., no select/enum field yet), Phase 2 either waits on Phase 1.1 to add the
field, or falls back to text-input-only and parses. Phase 1.1's scope should enumerate
field types required by Phase 2 up front — see the Phase 1.1 proposal below.

**Depends on:** Phase 1.1 merging `Modal.Form` with (at minimum) text-input, integer,
boolean, and enum/select field types plus Tab/Shift-Tab focus navigation and per-field
inline error rendering.

**My correction:** Applied — use `Modal.Form` (Phase 1.1), not the inline sub-step.

---

## 9. SYSTEM tab is read-only introspection, manual refresh

**Confidence:** Likely

**Assumption:** The SYSTEM tab renders a static snapshot:
- BBS version (`:application.get_key(:foglet_bbs, :vsn)`)
- Uptime (`:erlang.statistics(:wall_clock)`)
- Active session count (`Registry.count(Foglet.Sessions.Registry)`)
- Active board server count (`DynamicSupervisor.count_children(Foglet.Boards.Supervisor)`)
- OTP process count (`:erlang.system_info(:process_count)`)
- DB pool size (`FogletBbs.Repo.config/0`)

No automatic refresh; `r` keypress re-samples. No actions (read-only per SYSO-04).

**Why this way:**
- The existing registries (`Foglet.Sessions.Registry`, `Foglet.BoardRegistry`) and the
  `Foglet.Boards.Supervisor` are all introspectable via stdlib — no new telemetry
  needed.
- `FogletBbsWeb.Telemetry` is for Phoenix metrics/LiveDashboard, not TUI display.
- `:erlang.statistics/1` and `:erlang.system_info/1` are zero-dep, race-safe snapshots.
- Phase 0 shell tests (`sysop_test.exs:147`) already forbid spurious save-ish commands —
  a read-only SYSTEM tab with explicit refresh fits the "non-chatty" design intent.

**If wrong:** A live-updating metrics dashboard is nicer UX but adds an always-on ticker
per sysop session. Deferring is safe; adding a `Subscription.custom` ticker later mirrors
the heartbeat pattern in `app.ex:185`.

**Alternatives:**
- **(a) Recommended — snapshot-on-enter + `r` to re-sample.** Zero new tickers.
- **(b) Auto-refresh every 10s via a `Subscription.custom`.** More modern UX; one extra
  process per sysop session + added test surface.

**My choice:** _( a / b )_

**My correction:**

---

## 10. Screen state architecture — extend `Sysop.State` with per-tab sub-modules

**Confidence:** Likely

**Assumption:** `Foglet.TUI.Screens.Sysop.State` (`sysop/state.ex`) gains fields for
each tab's working state:

```
site_form: %SiteForm{}
limits_form: %LimitsForm{}
boards_view: %BoardsView{}
system_snapshot: %SystemSnapshot{}
```

Each tab owns a submodule under `lib/foglet_bbs/tui/screens/sysop/`
(e.g. `sysop/site_form.ex`, `sysop/boards_view.ex`), each exposing `init/1`,
`handle_key/2`, `render/2`. The parent `Sysop` screen dispatches `handle_key/2` to the
active tab's module once the tab bar has consumed arrow keys.

SITE and LIMITS tabs render forms **inline on the tab** (full-tab editors) with an
explicit `[Ctrl+S] Save` key hint mirroring `new_thread.ex:139`. BOARDS uses the list +
`Modal.Form` pattern from §8 — `boards_view` owns the list and whichever modal is
currently open (or `nil`). No auto-save anywhere. Draft state is retained across tab
switches inside `Sysop.State`.

**Why this way:**
- `sysop/state.ex` already lives under `lib/foglet_bbs/tui/screens/sysop/`, establishing
  the submodule convention (`CONVENTIONS.md:47-49`).
- `new_thread/state.ex` + `post_reader/state.ex` are the existing precedents.
- Raxol's `update/2` dispatch is key-event-based, so per-tab submodules stay as pure
  `handle_key/2` + `render/2` callables — scales cleanly.
- Explicit save (no dirty-on-blur auto-save) matches `Config.put/3`'s one-call-per-
  (key, value) write semantics and avoids "user typed a partial integer and we saved 0"
  bugs.

**If wrong:** Flat state in `Sysop.State` with no per-tab submodules grows the parent
screen to ~500+ LOC (same trajectory as `post_reader.ex` at 20KB). Per-tab submodules
keep each file under ~250 LOC.

**Alternatives:**
- **(a) Recommended — per-tab submodule** under `sysop/`, one
  `handle_key/2` + `render/2` + `init/1` each; parent `Sysop` delegates on
  non-tab-bar keys.
- **(b) Flat — all tab logic inline in `sysop.ex`.** Faster to write; harder to test;
  parent file balloons.

**My choice:** _( a / b )_

**My correction:**

---

## 11. Authorization wiring — actor is `state.current_user`, no mid-session re-auth check

**Confidence:** Confident

**Assumption:** Every call into `Foglet.Config.put/3`,
`Foglet.Boards.{create,update,archive}_board/_`, and
`Foglet.Boards.{create,update,archive}_category/_` passes `state.current_user` as the
actor. The Sysop screen does NOT call `Bodyguard.permit?/4` for advisory rendering on
its tabs — only sysops can reach the screen per `ShellVisibility.sysop_visible?/1`
(`sysop.ex:41`; `shell_visibility.ex:51-53`). `{:error, :forbidden}` from a domain call
is treated as "actor was demoted mid-session" and routes to the `:error` modal +
returns to `:main_menu`.

**Why this way:**
- Phase 1 D-17/D-18 explicitly says the domain is the trust boundary and TUI advisory
  checks are optional.
- In a sysop workspace where every tab is sysop-only, the advisory check is redundant
  with the screen-level `ShellVisibility.sysop_visible?/1` gate.
- Phase 1 D-25 ("stale current_user snapshot must not retain operator powers after
  sysop action") is already handled by the domain-layer `Bodyguard.permit/4` call.

**If wrong:** Row-level disable states ("archive this board is denied because it has
live subscriptions") would need per-row advisory checks. Phase 2's actions are all
atomic "sysop permitted at site scope" cases so this doesn't apply.

**My correction:** _(leave blank to accept)_

---

## 12. Testing strategy — integration for domain, render-only for TUI

**Confidence:** Confident

**Assumption:** New tests live in:
- `test/foglet_bbs/config_test.exs` — extend existing file for new keys/accessors
  (`invite_generation_per_user_limit`).
- `test/foglet_bbs/boards/boards_test.exs` — extend for `update_category/3` +
  `archive_category/2` + actor-first `create_category/2`.
- `test/foglet_bbs/tui/screens/sysop_test.exs` — extend for render-output assertions and
  key-handling smoke tests.

TUI tests use the existing `Foglet.TUI.RenderHelpers`
(`test/support/foglet/tui/render_helpers.ex`) for `collect_text_values/1` and build
`%Foglet.TUI.App{}` structs directly (`sysop_test.exs:9-17`). All persistence tests use
`FogletBbs.DataCase, async: false` because the `:foglet_config` ETS table is
process-global (see `config_test.exs:3`).

**Why this way:**
- Existing test layout mirrors `lib/` paths per `CONVENTIONS.md:42-49`.
- `config_test.exs` already covers `put/3` happy / forbidden / unknown_key /
  invalid_value paths — new keys just mean new assertions.
- `sysop_test.exs` already demonstrates the render + handle_key pattern with a built-in
  state struct (no Repo dependency).

**If wrong:** Adding a `test/foglet_bbs/tui/screens/sysop/` directory for per-tab
submodule tests (matching the per-tab file layout) is also fine — follows the
`new_thread_test.exs` pattern, just more files.

**My correction:** _(leave blank to accept)_

---

## 13. Scope boundary — SITE tab is config-only, no site-identity editing

**Confidence:** Confident

**Assumption:** Phase 2's SITE tab edits ONLY schematized runtime config values. It
does NOT expose:
- Site name / MOTD / login banner (those would require new unschematized keys — out of
  scope per `REQUIREMENTS.md:81`).
- USERS tab content — stays as the Phase 0 scaffold (`sysop_test.exs:96`:
  "User administration will arrive in a later phase").
- Invite GENERATION / REDEMPTION UI — that is Phase 3 (persistence) / Phase 4
  (shared INVITES tab activation). Phase 2 only persists INVT-06/07 as config POLICY.

**Why this way:**
- The four explicit success criteria (ROADMAP:63-67) are: config edit, invite policy
  config, board/category CRUD, system details — none mention site identity or USERS.
- ROADMAP v2 `SYSO-06` (`REQUIREMENTS.md:67`) explicitly defers "additional runtime
  settings such as oneliner policy, theme allowlist, and retention windows until they
  have typed runtime consumers" — proving the "only schematized-and-live-wired"
  discipline is a milestone invariant.

**If wrong:** Adding a `site_name` field editor is an unschematized key exposed to
sysops — directly violates success criterion 1. USERS-tab edits conflict with Phase 8
scope.

**My correction:** _(leave blank to accept)_

---

## Summary — decisions locked (2026-04-23)

| #  | Area                                         | Decision                                                             |
|----|----------------------------------------------|----------------------------------------------------------------------|
|  1 | Config form introspects `Schema.entries/0`   | ✅ (a) Hard-coded `@site_keys` / `@limits_keys` partition             |
|  2 | SITE vs LIMITS partition                     | ✅ (a) Split by type (booleans+enums → SITE, integers → LIMITS)       |
|  3 | INVT-07 encoding — one key or two            | ✅ (a) One key, sentinel `0 = unlimited`                              |
|  4 | `Config.put/3` + inline errors / modal       | ✅ Accepted                                                           |
|  5 | ETS invalidation only, no PubSub             | ✅ Accepted                                                           |
|  6 | Category CRUD inside `Foglet.Boards`         | ✅ (a) Extend `Foglet.Boards`, no new module                          |
|  7 | Archive doesn't stop Board Server            | ✅ Accepted                                                           |
| **8** | **BOARDS tab create/edit workflow**      | 🔀 **Corrected — use `Modal.Form` from Phase 1.1, NOT inline sub-step** |
|  9 | SYSTEM tab = read-only, manual refresh       | ✅ (a) Snapshot-on-enter + `r` to re-sample                           |
| 10 | Per-tab submodules under `sysop/`            | ✅ (a) Per-tab submodules; revised per §8 correction                  |
| 11 | No advisory `permit?/4`; domain is boundary  | ✅ Accepted                                                           |
| 12 | Extend existing test files                   | ✅ Accepted                                                           |
| 13 | No site identity, no USERS, no invite UI     | ✅ Accepted                                                           |

**Next steps:**
1. Insert **Phase 1.1: Modal.Form primitive** into ROADMAP.md between Phase 1 and Phase 2.
2. Run `/gsd-spec-phase 1.1` → `/gsd-discuss-phase 1.1` → `/gsd-plan-phase 1.1` →
   `/gsd-execute-phase 1.1` on that phase.
3. After Phase 1.1 merges, return here: write `02-CONTEXT.md` referencing the shipped
   `Foglet.TUI.Widgets.Modal.Form` module, then run `/gsd-plan-phase 2`.
