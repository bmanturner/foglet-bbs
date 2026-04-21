# Requirements — phase-03-screen-audit (v1.0.2)

**Workstream goal:** Audit each of the 9 TUI screens for idiomatic Elixir correctness and maximal use of `Foglet.TUI.Widgets.*` primitives + `Foglet.TUI.Theme`, while preserving layout sparseness for upcoming milestones (M4 Presence, M5 Chat, M6 DMs/Notifications, M9 Search/Oneliners).

**Core principle:** This is a **restraint workstream** — the audit removes, consolidates, or swaps; it does not add. Every screen must leave the workstream at **equal or lower line count** AND **equal or lower visible row count** (hard rule, see `AUDIT-16`).

**Phase count:** 10 phases total (Phase 0 prelude + Phases 1–9 per-screen). Execution order: `0 → 1 → 2 → 3 → (4+5+6) → (7+8) → 9`. Phases 2 and 3 are **serialized** (no longer parallel) because both touch `app.ex` wizard-dispatch paths during the top-level wizard-state migration (see `AUDIT-13` documented exceptions).

**Research basis:** `research/SUMMARY.md` + `research/ARCHITECTURE.md §3.1–§3.2` (HIGH confidence, grounded in first-hand reads of all 9 screens).

---

## v1.0.2 Requirements

### Audit-wide (Phase 0 + cross-cutting rubric applied to every per-screen phase)

#### Phase 0 — Cross-cutting extractions

- [ ] **AUDIT-01**: `Foglet.TUI.Theme.from_state/1` extracts the 9 inlined `(Map.get(state, :session_context) || %{}) |> Map.get(:theme)` chains across screens, `screen_frame.ex`, `size_gate.ex`, and `app.ex` modal overlay. Returns a `%Theme{}` with documented fallback when session_context is absent.
- [ ] **AUDIT-02**: `Foglet.TUI.Screens.Domain.get/2` extracts the 7 inlined `get_in(session_context, [:domain, :<key>])` patterns in `board_list.ex`, `thread_list.ex`, `post_reader.ex` (×3), `post_composer.ex`, and `new_thread.ex`. Supported keys: `:boards | :threads | :posts | :markdown`. Returns `{:ok, module} | {:error, :not_configured}` so callers can pattern-match instead of probing for `nil`.
- [ ] **AUDIT-03**: Phase 0 ships with per-function tests exercising (a) happy-path resolution, (b) missing `session_context` fallback, (c) missing `:domain` key fallback. `mix precommit` is green post-extraction.
- [ ] **AUDIT-04**: After Phase 0 lands, grep gates #7 (no `{80, 24}` inline outside a `@default_terminal_size` module attribute), #8 (no inlined theme extraction), and #9 (no inlined `get_in(ctx, [:domain, …])`) return **zero** across `lib/foglet_bbs/tui/screens/*.ex`.

#### Per-Phase Definition of Done (applies to every Phases 1–9)

- [ ] **AUDIT-05**: **Grep gates** — the following rg patterns return zero on the audited screen file:
  1. `:red|:green|:cyan|:yellow|:blue|:magenta|:white|:black` (named color atoms; D-07/D-09)
  2. `"#[0-9a-fA-F]{6}"` (hex literals)
  3. `\\e\[|\\x1b` (raw ANSI escapes)
  4. `%\{.*theme.*\|` (theme-struct mutation)
  5. `box style.*border` (nested border inside ScreenFrame)
  6. `IO\.(write|puts|inspect)` (direct terminal writes)
  7. `\{80, 24\}` (inlined terminal-size default; post-Phase-0 must live in a `@default_terminal_size` attribute if still needed)
  8. `\(Map\.get\(state, :session_context\) \|\| %\{\}\) \|> Map\.get\(:theme\)` (inlined theme extraction; replaced by `Theme.from_state/1`)
  9. `get_in\(ctx, \[:domain` (inlined domain lookup; replaced by `Screens.Domain.get/2`)
- [ ] **AUDIT-06**: **Behavioral invariants** — `handle_key/2` clause source order preserved; `render/*` functions are pure reads (no state mutation under any `defp render_*`); `handle_key/2` never inspects `state.modal` (modal dispatch belongs to `App.global_key_handler/2`); any existing `%{state | modal: m}` write paired with `screen_state: %{}` reset preserves the reset.
- [ ] **AUDIT-07**: **Widget contract** — every widget invocation in the screen passes `theme: theme` explicitly; D-14 stateful widget state is hoisted to `state.screen_state[:<screen>]`; D-16 stateless widgets never appear in `screen_state`.
- [ ] **AUDIT-08**: **Chrome contract** — `ScreenFrame.render/4` wraps the screen's content; `StatusBar` and `KeyBar` are reached only through `ScreenFrame`; modals use the `%{type:, message:}` shape.
- [ ] **AUDIT-09**: **`with`-chain refactor where a nested `case {:ok, _}|{:error, _}` chain exists** — `login.ex:267-308`, `register.ex:232-280`, `post_composer.ex:252-306` specifically. Result of each `with` clause preserves the prior happy/error branches exactly.
- [ ] **AUDIT-10**: **Loading-state widget adoption** — where the screen performs a real async op that presents a "Loading…" text today (`board_list.ex` load_boards, `thread_list.ex` load_threads, `post_reader.ex` load_posts + flush_read_pointers), evaluate `Widgets.Progress.Spinner` (indeterminate) or `Widgets.Display.Progress` (determinate). Adopt the spinner if the op takes >1 render frame AND its completion observable; otherwise keep plain text. **MUST NOT** add a spinner to decorate an instant operation (anti-affordance 6).
- [ ] **AUDIT-11**: **Loading / empty-state phrasing normalization** — within the screen's own file, unify loading/empty text phrasing per the canonical strings: `"Loading…"` (ellipsis char, not `...`), `"No boards yet"`, `"No threads yet"`, `"No posts yet"`, `"Nothing to show"`. Row-count delta is zero.
- [ ] **AUDIT-12**: **Dead-code audit of public domain hooks** — in any screen with a public `load_*/N` or `flush_*/N` function (`board_list.ex`, `thread_list.ex`, `post_reader.ex`), run `rg -w <function> test/ lib/` to determine whether it is called. If called only by tests, mark `@doc false` + explanatory comment. If uncalled anywhere, delete.
- [ ] **AUDIT-13**: **Scope fence** — the phase's git diff touches exactly ONE screen file (+ its test file). Any touch of `app.ex`, `size_gate.ex`, `chrome/*.ex`, `theme.ex`, or another screen causes the phase to split. **Documented exceptions:**
  - (a) **Phase 0** touches all 9 screens + `screen_frame.ex` + `size_gate.ex` + `app.ex` modal overlay for the cross-cutting extractions.
  - (b) **Phase 2 (Register)** may modify `app.ex` at the wizard-state field declaration (`app.ex:53-56`) and the Register wizard-dispatch path (`app.ex:354-361`, `:submit_step` / `:cancel_step` routing) strictly to migrate `state.register_wizard` into `state.screen_state[:register]`. Any other `app.ex` touch still violates the fence.
  - (c) **Phase 3 (Verify)** may modify `app.ex` at the wizard-state field declaration (`app.ex:74-75`) and the Verify dispatch path strictly to migrate `state.verify_state` into `state.screen_state[:verify]`. Any other `app.ex` touch still violates the fence.
- [ ] **AUDIT-14**: **No new shared modules** beyond the two Phase-0 extractions (`Foglet.TUI.Theme.from_state/1`, `Foglet.TUI.Screens.Domain`). File-scoped helpers (e.g. `verify.ex`'s `default_verify_state/0`) are fine.
- [ ] **AUDIT-15**: **CI gate** — `mix precommit` green end-to-end after the phase's commit (not just `mix test` on the screen's test file). No new `@dialyzer` / `credo:disable` / `sobelow_skip` suppressions. Exception: `register.ex`'s existing `apply/3` suppression for the not-yet-defined `consume_invite_code` is preserved verbatim.
- [ ] **AUDIT-16**: **Size delta ≤ 0** — both (a) screen-file line count and (b) visible row count in the rendered screen are less-than-or-equal their pre-phase values. Any increase triggers a roadmap discussion; default is rollback to scope.
- [ ] **AUDIT-17**: **Protected layout regions** — the phase MUST NOT add content in regions reserved for upcoming milestones:
  | Screen | Region reserved for |
  |---|---|
  | `main_menu` | M4 last-callers/news, M6 notification badge, M9 oneliners |
  | `board_list` | M4 presence count, M6 mention/DM badges (row gutters) |
  | `thread_list` | M5 chat indicator, M6 mention highlight, M7 mod tags |
  | `post_reader` | Header strip (max density); footer reserved for M6 reply-tree, M9 upvote |
  | `post_composer` / `new_thread` | Below char counter reserved for M6 @handle autocomplete |
  | `login` / `register` / `verify` | Below error line (gateways stay minimal forever) |
- [ ] **AUDIT-18**: **Canonical screen section order** — every per-screen phase reorders (or confirms) the audited screen module to match the 10-section canonical layout defined in `research/ARCHITECTURE.md §3.1`:
  1. Aliases + imports (always: `Theme`, `ScreenFrame`, any widgets)
  2. Module attributes (`@menu_keys`, `@max_attempts`, `@default_terminal_size`, etc.)
  3. Screen-state initialiser (public) — `init_screen_state/1`
  4. Public `render/1`
  5. Public `handle_key/2`
  6. Public domain-hook callbacks (ONLY if still called by `App.update/2` after AUDIT-12 resolves dead-code — most screens delegate via command tuples)
  7. Private key handlers (`handle_<step>_key/3`, `move_selection/2`, etc.)
  8. Private render helpers (`render_<section>/N`)
  9. Private state plumbing (`get_ss/1`, `put_ss/2`, `default_ss/0`, etc.)
  10. Private domain plumbing (`domain_module/2`, `format_error/1`, etc.)

  Deviations are permitted but MUST be documented in the screen's `@moduledoc` with rationale. Examples: MainMenu's intentional statelessness (no §3), PostReader's `render_cache` warming plumbing at `:77-82` (sits in §9 state plumbing, not §8 render helpers, because it mutates state).
- [ ] **AUDIT-19**: **`init_screen_state/1` adoption** — every per-screen phase either (a) exposes a public `@spec init_screen_state(keyword()) :: map()` function that returns the screen's default `screen_state[:<screen>]` entry, or (b) documents in the moduledoc that the screen is **intentionally stateless** (no `screen_state[:<screen>]` key). Top-level struct fields on `state` (other than `:screen_state`) are NOT an acceptable storage location after Phases 2 and 3 complete.

#### Anti-affordances (audit-wide — no phase may introduce these)

- [ ] **AUDIT-20**: Workstream-wide `rg 'box style.*border' lib/foglet_bbs/tui/screens/` returns zero after the final phase.
- [ ] **AUDIT-21**: `Display.Table` not used for 2-3 row cases; `Input.Tabs` not used where one logical mode exists or a Tab keybind already affords navigation; `Input.Button` not used in place of `text/2` for non-interactive menu rows; `Input.Checkbox` / `Input.RadioGroup` / `Input.Menu` / `Display.Tree` / `SmartList` are not introduced (existing use sites may remain).
- [ ] **AUDIT-22**: No ASCII banners, decorative dividers, session-info panels, sidebars, or two-pane splits added to any screen.

---

### Phase 1 — Login screen

- [ ] **LOGIN-01**: Hand-rolled handle + password inputs (`login.ex:196-226` + handlers `:76-124`) are replaced with two `Widgets.Input.TextInput` instances, one configured with `mask: "*"` for the password field. Visual drift from the current `█` cursor style is **accepted per explicit user decision** — the precedent applies to Phases 2 (Register) and 7 (NewThread).
- [ ] **LOGIN-02**: Deleted: `format_input_line/3`, `input_fg/2`, `focus_style/1`, `mask_password/1`, `drop_last_grapheme/1`, `append_to_focused/2`, and the entire `handle_form_key/2` family — superseded by the TextInput widgets' own state + event handling.
- [ ] **LOGIN-03**: Login's focused-field state is hoisted to `state.screen_state[:login]` with `:focused_field` + the two TextInput sub-states per D-14. `init_screen_state/1` is added (it is missing today).
- [ ] **LOGIN-04**: The nested `case {:ok, _}|{:error, _}` authentication chain (`login.ex:267-308`) is rewritten as a `with` chain. Happy/error branches are preserved bit-for-bit.
- [ ] **LOGIN-05**: `Foglet.Config` calls during render (`registration_mode/1`) are confirmed to hit the ETS cache (see Foglet.Config — read-through cached). No render-path change required, but documented in CONTEXT.
- [ ] **LOGIN-06**: Rubric items `AUDIT-05..22` pass; `mix precommit` green; line count and visible row count both decrease (projected 347→~150).

### Phase 2 — Register screen

- [x] **REGISTER-01**: Single-line wizard input (`register.ex:43-48`) is replaced with `Widgets.Input.TextInput` per Phase 1 precedent, with `mask_char` swapped to `*` for the `:password` and `:confirm` wizard steps.
- [x] **REGISTER-02**: Wizard step dispatcher is audited for clarity — prefer multi-clause `render_step/2` + pattern-matched step atoms over a large `case`. No new abstractions beyond what already exists.
- [x] **REGISTER-03**: The nested `case {:ok, _}|{:error, _}` registration chain (`register.ex:232-280`) is rewritten as a `with` chain.
- [x] **REGISTER-04**: The existing `apply(Foglet.Accounts, :consume_invite_code, …)` + `function_exported?/3` guard with its `credo:disable` is preserved verbatim (documented inherited decision — consumer module may not exist yet).
- [x] **REGISTER-05**: Rubric items `AUDIT-05..22` pass; `mix precommit` green; line count deviation accepted (developer override 2026-04-21 — structural increase from 4-field wizard, see 02-VERIFICATION.md).
- [x] **REGISTER-06**: **Top-level `state.register_wizard` → `state.screen_state[:register]` migration.** The field declared at `app.ex:53-56` is removed; the wizard-dispatch path at `app.ex:354-361` (`:submit_step` / `:cancel_step` routing) is rewritten to read/write through `state.screen_state[:register]`. Phase 2 operates under the documented AUDIT-13 scope-fence exception (b). **Watch List:**
  - (i) `:submit_step` self-dispatch semantics preserved — submitting the current step still round-trips through `App.update/2` to advance the wizard.
  - (ii) Modal-close `screen_state: %{}` reset behavior preserved — after a wizard-initiated modal closes, the wizard state must not survive if the modal was a cancellation confirm.
  - (iii) Key-dispatch ordering in wizard steps preserved — source-order dependencies in `register.ex:handle_key/2` clauses are load-bearing (Pitfall 6).
  - (iv) Tests MUST cover the full wizard round-trip (handle → email → password → confirm → submit) post-migration, plus the cancel-during-step flow.

### Phase 3 — Verify screen

- [ ] **VERIFY-01**: The 6-char `[ABC___]` buffer (`verify.ex:55, 138-147`) is explicitly **kept hand-rolled**, with its moduledoc citing 07 D-02 (TextInput cannot mask/render the 6-slot layout without a custom renderer, and TextInput's internal `box` would conflict with the slot visualization). This is an inherited exception, not re-litigated.
- [ ] **VERIFY-02**: A file-local `default_verify_state/0` private helper consolidates the 7 duplicated default-state map literals.
- [ ] **VERIFY-03**: Two-cooldown logic (resend cooldown + attempt cooldown) is left structurally intact; any restructure MUST preserve the 5-attempt lockout semantics verified in `phase-03-polish` Phase 03.
- [ ] **VERIFY-04**: Rubric items `AUDIT-05..22` pass; `mix precommit` green; line count decreases.
- [ ] **VERIFY-05**: **Top-level `state.verify_state` → `state.screen_state[:verify]` migration.** The field declared at `app.ex:74-75` is removed; the verify-dispatch path in `app.ex` (analogous to Register's) is rewritten to read/write through `state.screen_state[:verify]`. Phase 3 operates under the documented AUDIT-13 scope-fence exception (c). **Watch List:**
  - (i) 5-attempt lockout semantics preserved — attempt counter must survive migration and still trigger lockout at the same threshold.
  - (ii) Resend cooldown feedback preserved — user sees cooldown remainder, not silent no-op or DB spam.
  - (iii) Modal-close reset behavior preserved.
  - (iv) Tests MUST cover the attempt-lockout flow and the resend-cooldown flow post-migration as round-trips.

### Phase 4 — MainMenu screen

- [ ] **MENU-01**: Theme extraction + domain-module lookup use the Phase 0 helpers. No other structural change.
- [ ] **MENU-02**: `@menu_keys` + `@menu_items` duplication (`main_menu.ex:9-13, 28-32`) is **kept** as an inherited decision — load-bearing because render and KeyBar use different format needs; documented in moduledoc.
- [ ] **MENU-03**: `[L]/[R]/[Q]` letter-shortcut menu rows stay as plain `text/2` calls (inherited decision — `SelectionList` wrong, `Button` wrong, `text/2` is correct).
- [ ] **MENU-04**: Rubric items `AUDIT-05..22` pass with **special sparseness scrutiny** — main_menu is 58 LoC and has the largest share of reserved layout regions (M4/M6/M9). `AUDIT-16` size delta ≤ 0 is strictly enforced.
- [ ] **MENU-05**: MainMenu's `@moduledoc` documents **"intentionally stateless — no `screen_state[:main_menu]` key"** with a note that future contributors should NOT add a default hash reflexively. This is the documented AUDIT-19 deviation for MainMenu (per ARCHITECTURE §3.2 #4).

### Phase 5 — BoardList screen

- [ ] **BOARDS-01**: Theme + domain lookups use Phase 0 helpers.
- [ ] **BOARDS-02**: `load_boards/1` (`board_list.ex:86-91`) — run dead-code audit per `AUDIT-12`. Result: delete, or `@doc false` + comment.
- [ ] **BOARDS-03**: Loading text → evaluate `Widgets.Progress.Spinner` per `AUDIT-10` (load_boards is an async op).
- [ ] **BOARDS-04**: `SelectionList`/`ListRow` usage audited — no change expected (research flagged as correctly applied).
- [ ] **BOARDS-05**: Rubric items `AUDIT-05..22` pass; `mix precommit` green.

### Phase 6 — ThreadList screen

- [ ] **THREADS-01**: Theme + domain lookups use Phase 0 helpers.
- [ ] **THREADS-02**: **Correctness fix** — `thread_list.ex:136, 140` `function_exported?(threads_mod, :list_threads, 2)` / `(…, 1)` are guarded with `Code.ensure_loaded/1` first. Test added asserting the 2-arity path is selected when it exists.
- [ ] **THREADS-03**: `load_threads/2` (`thread_list.ex:128-147`) — run dead-code audit per `AUDIT-12`.
- [ ] **THREADS-04**: `Threads.list_threads/2` preload of `:created_by` is verified — the thread-row `ListRow` renders depend on it; test asserts `created_by.handle` is present on returned rows.
- [ ] **THREADS-05**: Loading text → evaluate spinner per `AUDIT-10`.
- [ ] **THREADS-06**: Two-pass sticky+recency sort (`thread_list.ex:159-179`) is **kept** as an inherited decision — naive `desc` + `nil` would crash/misorder.
- [ ] **THREADS-07**: Rubric items `AUDIT-05..22` pass; `mix precommit` green.

### Phase 7 — NewThread screen

- [ ] **NEWTHREAD-01**: Title-line input with `█` cursor (`new_thread.ex:124-128`) migrates to `Input.TextInput` per Phase 1 precedent.
- [ ] **NEWTHREAD-02**: Body composer continues to use `Foglet.TUI.Widgets.Compose` + `MultiLineInput` — inherited decision (Phase-5 D-13; re-entry guards load-bearing).
- [ ] **NEWTHREAD-03**: Theme + domain + `{80,24}` → Phase 0 helpers + `@default_terminal_size` attribute.
- [ ] **NEWTHREAD-04**: The load-bearing `# NOTE: source order` comment at `new_thread.ex:307-314` is **preserved** — any reformatter touch must not strip it.
- [ ] **NEWTHREAD-05**: Rubric items `AUDIT-05..22` pass; `mix precommit` green; line count decreases.

### Phase 8 — PostComposer screen

- [ ] **COMPOSER-01**: Theme + domain + `{80,24}` → Phase 0 helpers + `@default_terminal_size` attribute.
- [ ] **COMPOSER-02**: The nested `case {:ok, _}|{:error, _}` publish chain (`post_composer.ex:252-306`) is rewritten as a `with` chain.
- [ ] **COMPOSER-03**: **Add** the missing `# NOTE: source order matters for handle_key/2 clauses — do not reorder` comment above `post_composer.ex:82-110` (Phase 7 precedent; currently only `new_thread.ex` has it).
- [ ] **COMPOSER-04**: `Compose` + `MultiLineInput` inherited — no migration.
- [ ] **COMPOSER-05**: Rubric items `AUDIT-05..22` pass; `mix precommit` green.

### Phase 9 — PostReader screen

- [ ] **READER-01**: Theme + domain lookups use Phase 0 helpers (3 call sites in this screen — the densest).
- [ ] **READER-02**: `load_posts/2` (`:158-181`) and `flush_read_pointers/2` (`:197-209`) — run dead-code audit per `AUDIT-12`.
- [ ] **READER-03**: Loading text → evaluate spinner per `AUDIT-10` for both load + flush.
- [ ] **READER-04**: `PostCard` + `MarkdownBody` + `Viewport` pipeline is **kept** as an inherited decision (07 D-12/D-13). Any change here exits the audit scope.
- [ ] **READER-05**: Render-path purity is scrutinized most carefully here — this screen has the most complex render (`render_post_content/*` family; line-width cache at `:77-82`). No `put_in` / `%{state | …}` permitted inside any `defp render_*`.
- [ ] **READER-06**: Rubric items `AUDIT-05..22` pass; `mix precommit` green. Line count reduction here is smaller than other phases — PostReader is mostly already where we want it.
- [ ] **READER-07**: PostReader's `@moduledoc` documents the **load-absorb pattern** — `advance_post`/`scroll_post` return `{:update, state, []}` when `state.posts == []` to absorb keys during loading (see `post_reader.ex:343-347, 379-383`). Currently undocumented behavior (per ARCHITECTURE §3.2 #5). This is the documented AUDIT-18 deviation-note entry for PostReader.

---

## Future Requirements (deferred)

- [ ] **FUT-01**: Extraction of a `Foglet.TUI.Constants` module for `{80, 24}` and other cross-screen constants — deferred because per-screen `@default_terminal_size` is the right granularity today (Pitfall 13 — 13 occurrences is below the hoist bar).
- [ ] **FUT-02**: `Foglet.TUI.Screens` behaviour with `init_screen_state/1` + `render/1` + `handle_key/2` callbacks — deferred because implicit conformance is clearer than behaviour-by-compilation at 9 screens.
- [ ] **FUT-03**: Extend `Input.TextInput` with a `█`-block cursor style — deferred; visual drift from block cursor to whatever TextInput renders is accepted per user decision for Phase 1.
- [ ] **FUT-04**: Pagination for PostReader (`load_posts/2` currently loads all posts up-front) — deferred to a future milestone when post-count growth makes this real.
- [ ] **FUT-05**: Normalize `{:terminate, :user_quit}` vs `{:terminate, :logout}` across Login and MainMenu — cosmetic, deferred.

## Out of Scope (explicit exclusions)

- **Any new functionality or new screen** — this is a polish audit only.
- **Any widget library addition or modification** beyond Phase 0's two extractions.
- **Any change to the App dispatcher, size gate, screen chrome, theme, or modal plumbing** beyond the three documented AUDIT-13 exceptions (Phase 0 extractions, Phase 2 Register wizard-state migration, Phase 3 Verify wizard-state migration).
- **Any layout addition to a reserved region** (`AUDIT-17`) — those belong to Milestones 4/5/6/9.
- **Feature flags, A/B toggles, or deprecation shims.** If a change is worth making, it lands; if not, it doesn't.
- **Snapshot testing of rendered ANSI output.** Explicitly rejected in STACK.md — upcoming milestones will mutate every screen's layout and snapshot churn would be punitive.
- **Cross-AI / external reviews.** `/gsd-review` is not run for this workstream; `/gsd-code-review` per phase is sufficient.

## Locked Decisions

Inherited from `phase-03-polish` (see its REQUIREMENTS.md "Locked Decisions") and extended here:

- Adoption of `Input.TextInput` in Login (and consequently Register, NewThread) with accepted visual drift from the `█`-block cursor — **locked by user** at workstream creation.
- Phase 0 extracts `Foglet.TUI.Theme.from_state/1` and `Foglet.TUI.Screens.Domain.get/2`, no other shared modules.
- `Foglet.Config` reads on the render path are safe — the module caches via ETS read-through (`lib/foglet_bbs/config.ex`); no pre-audit gap closure required.
- `Verify` screen keeps its hand-rolled 6-char buffer (07 D-02 inheritance).
- Loading-state widget adoption is **evaluated per screen** against the anti-affordance rule (no spinner on instant ops) — not forced uniformly.
- Phrasing normalization is scoped to the audited screen's own file — no cross-screen sweep commit.
- **Top-level wizard-state migration is IN scope** — locked by user, overriding the research recommendation to defer. `state.register_wizard` migrates to `state.screen_state[:register]` in Phase 2; `state.verify_state` migrates to `state.screen_state[:verify]` in Phase 3. Each phase carries a documented AUDIT-13 scope-fence exception and a Watch List covering wizard-dispatch semantics, modal-close reset, key-dispatch ordering, and round-trip tests.
- **Canonical 10-section screen layout (ARCHITECTURE §3.1)** is applied as `AUDIT-18`; deviations documented in moduledoc (MainMenu intentional statelessness via `MENU-05`, PostReader render_cache plumbing + load-absorb pattern via `READER-07`, etc.).
- **Phase 2 and Phase 3 are serialized** (no longer parallel). Both phases modify `app.ex` wizard-dispatch paths; concurrent work would conflict. Phase 3 also inherits any wizard-dispatch pattern established in Phase 2.

## Traceability

Every per-phase requirement ID maps to exactly one phase below. The audit-wide rubric (`AUDIT-05..22`) is **inherited by every phase** and checked at each phase's verification step — it is not mapped to a single phase.

### Phase-to-requirement mapping

| Phase | Screen / Focus | Requirements delivered |
|-------|----------------|------------------------|
| 0 | Cross-cutting extractions (prelude) | AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04 |
| 1 | Login | LOGIN-01, LOGIN-02, LOGIN-03, LOGIN-04, LOGIN-05, LOGIN-06 |
| 2 | Register | REGISTER-01, REGISTER-02, REGISTER-03, REGISTER-04, REGISTER-05, REGISTER-06 |
| 3 | Verify | VERIFY-01, VERIFY-02, VERIFY-03, VERIFY-04, VERIFY-05 |
| 4 | MainMenu | MENU-01, MENU-02, MENU-03, MENU-04, MENU-05 |
| 5 | BoardList | BOARDS-01, BOARDS-02, BOARDS-03, BOARDS-04, BOARDS-05 |
| 6 | ThreadList | THREADS-01, THREADS-02, THREADS-03, THREADS-04, THREADS-05, THREADS-06, THREADS-07 |
| 7 | NewThread | NEWTHREAD-01, NEWTHREAD-02, NEWTHREAD-03, NEWTHREAD-04, NEWTHREAD-05 |
| 8 | PostComposer | COMPOSER-01, COMPOSER-02, COMPOSER-03, COMPOSER-04, COMPOSER-05 |
| 9 | PostReader | READER-01, READER-02, READER-03, READER-04, READER-05, READER-06, READER-07 |

### Requirement-to-phase lookup

| Requirement | Phase | Status |
|-------------|-------|--------|
| AUDIT-01 | Phase 0 | Pending |
| AUDIT-02 | Phase 0 | Pending |
| AUDIT-03 | Phase 0 | Pending |
| AUDIT-04 | Phase 0 | Pending |
| AUDIT-05 | Inherited rubric (Phases 1–9) | Pending |
| AUDIT-06 | Inherited rubric (Phases 1–9) | Pending |
| AUDIT-07 | Inherited rubric (Phases 1–9) | Pending |
| AUDIT-08 | Inherited rubric (Phases 1–9) | Pending |
| AUDIT-09 | Inherited rubric (Phases 1, 2, 8 — other phases pass trivially) | Pending |
| AUDIT-10 | Inherited rubric (Phases 5, 6, 9 — other phases pass trivially) | Pending |
| AUDIT-11 | Inherited rubric (Phases 1–9) | Pending |
| AUDIT-12 | Inherited rubric (Phases 5, 6, 9 — other phases pass trivially) | Pending |
| AUDIT-13 | Inherited rubric (Phases 1–9; Phase 0 + Phase 2 + Phase 3 carry documented exceptions) | Pending |
| AUDIT-14 | Inherited rubric (Phases 1–9) | Pending |
| AUDIT-15 | Inherited rubric (Phases 1–9) | Pending |
| AUDIT-16 | Inherited rubric (Phases 1–9) | Pending |
| AUDIT-17 | Inherited rubric (Phases 1–9) | Pending |
| AUDIT-18 | Inherited rubric (Phases 1–9) — canonical section order | Pending |
| AUDIT-19 | Inherited rubric (Phases 1–9) — `init_screen_state/1` adoption | Pending |
| AUDIT-20 | Workstream-wide anti-affordance (verified at final phase) | Pending |
| AUDIT-21 | Inherited anti-affordance (Phases 1–9) | Pending |
| AUDIT-22 | Inherited anti-affordance (Phases 1–9) | Pending |
| LOGIN-01..LOGIN-06 | Phase 1 | Pending |
| REGISTER-01..REGISTER-06 | Phase 2 | Verified 2026-04-21 |
| VERIFY-01..VERIFY-05 | Phase 3 | Pending |
| MENU-01..MENU-05 | Phase 4 | Pending |
| BOARDS-01..BOARDS-05 | Phase 5 | Pending |
| THREADS-01..THREADS-07 | Phase 6 | Pending |
| NEWTHREAD-01..NEWTHREAD-05 | Phase 7 | Pending |
| COMPOSER-01..COMPOSER-05 | Phase 8 | Pending |
| READER-01..READER-07 | Phase 9 | Pending |

### Coverage Validation

- **Total per-phase requirement IDs:** 51 (LOGIN ×6 + REGISTER ×6 + VERIFY ×5 + MENU ×5 + BOARDS ×5 + THREADS ×7 + NEWTHREAD ×5 + COMPOSER ×5 + READER ×7 = 51)
- **Total audit-wide Phase-0 IDs:** 4 (AUDIT-01..04)
- **Total inherited rubric IDs:** 18 (AUDIT-05..22) — checked at every per-screen phase
- **Orphaned requirements:** 0 ✓
- **Duplicated requirements (mapped to >1 phase):** 0 ✓
- **FUT-01..05:** deferred (v2 scope; tracked in Deferred Items of STATE.md)

**Coverage: 55/55 v1.0.2 requirements mapped** (51 per-phase + 4 Phase-0) **+ 18 inherited rubric items** applied at every per-screen phase. 100% ✓

---

*Last updated: 2026-04-21 — amended after Phase 0 discuss-phase surfaced gaps in canonical layout (§3.1) coverage; added AUDIT-18 / AUDIT-19 / REGISTER-06 / VERIFY-05 / MENU-05 / READER-07, documented AUDIT-13 scope-fence exceptions for Phases 2 and 3, serialized Phase 2 → Phase 3.*
