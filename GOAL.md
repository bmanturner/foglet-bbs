# Foglet BBS — TUI Developer Experience Goals

## North Star

Make continued development of Foglet BBS smoother, cheaper, and less risky.
Every goal in this document is justified by one question: does this make adding
the next screen, widget, or feature easier than the last one was?

The TUI is the product surface. Phoenix, PubSub, telemetry, and web endpoints
are infrastructure. Developer friction in `lib/foglet_bbs/tui/` compounds with
every new feature, so reducing that friction has outsized leverage.

This plan is intentionally practical: prefer helpers and contracts that match
the current Raxol view-tree architecture over importing Ratatui's buffer model
directly. Ratatui is useful as design inspiration, not as an API blueprint.

## Current Baseline

Before starting any goal, assume this is already true and preserve it unless a
later goal explicitly changes it:

- Screens implement `Foglet.TUI.Screen`.
- `update/3` already returns `{state, effects}`.
- `Foglet.TUI.Effect` already names runtime effects.
- `Foglet.TUI.App.Effects` already interprets effect values.
- `lib/foglet_bbs/tui/SCREEN_CONTRACT.md` is the current screen contract.
- `lib/foglet_bbs/tui/widgets/README.md` is the current widget authoring guide.
- `Foglet.TUI.ScrollKeys` already defines the vertical arrow plus `j`/`k`
  convention.
- `Foglet.TUI.AsciiRenderer` and `mix foglet.tui.render` already provide
  manual visual inspection.
- `mix foglet.tui.render` remains valuable for ad-hoc inspection and should not
  be removed by this plan.

## Execution Rules

Work one goal at a time. Each goal should leave the codebase better even if the
next goal never happens.

For each goal:

- Read `AGENTS.md`, `lib/foglet_bbs/tui/SCREEN_CONTRACT.md`, and the narrowest
  relevant widget or screen docs before changing code.
- Keep domain logic in the owning `Foglet.*` contexts.
- Keep render functions pure over already-loaded state.
- Update documentation in the same change as code.
- Add focused tests proportional to the change.
- Run targeted tests during development and `rtk mix precommit` before
  considering the goal complete.
- Do not add browser/web user workflows; the SSH TUI remains the product
  surface.

## Phase 1 — Additive Foundations

These goals are additive and should not require a fleet-wide screen conversion.
Existing screens keep working while new helpers are introduced and proven.

### Goal 1 — TUI Documentation Hub

**Why this comes first:** The plan needs one stable place to teach developers
where to look. Today the screen contract and widget guide exist, but there is
no `lib/foglet_bbs/tui/README.md` index tying the TUI architecture together.

**What we build:** Create `lib/foglet_bbs/tui/README.md` as a short developer
entry point that links to the authoritative documents rather than duplicating
them.

**Acceptance criteria:**

- `lib/foglet_bbs/tui/README.md` exists.
- It links to `SCREEN_CONTRACT.md`, `widgets/README.md`, `docs/TESTING.md`,
  `docs/raxol/getting-started/WIDGET_GALLERY.md`, and the `mix foglet.tui.render`
  usage in `AGENTS.md`.
- It explains the current high-level boundaries: App shell, screens, effects,
  widgets, theme, and render/testing tools.
- It names the rule that `mix foglet.tui.render` is for manual inspection and
  buffer/screen tests are for regression.
- It does not duplicate detailed contracts that already live elsewhere.

---

### Goal 2 — Constraint Layout Helpers

**Why this matters:** Manual width and height arithmetic makes screen edits
fragile. Developers should be able to express "header/body/footer" and "sidebar
plus content" layouts without updating scattered magic numbers.

**What we build:** `Foglet.TUI.Layout`, a small deterministic layout helper
that works with the current Raxol render tree. It returns plain rect structs or
maps that can be consumed by render helpers and tests.

Supported constraints:

- `{:length, n}` — exactly `n` cells when space allows.
- `{:min, n}` — at least `n` cells, eligible for leftover space.
- `:min` — sugar for `{:min, 0}`.
- `{:max, n}` — at most `n` cells.
- `{:percent, p}` — `p` percent of parent, deterministically rounded.
- `{:fill, weight}` — share leftover space by weight.

**Acceptance criteria:**

- `Foglet.TUI.Layout` exposes `vertical/2`, `horizontal/2`, and `center/2`.
- The module defines or documents the rect shape it accepts and returns.
- Doctests or unit tests cover every supported constraint type.
- Over-constrained input is clipped deterministically and emits a dev/test
  warning without crashing.
- Under-constrained input leaves trailing space empty rather than stretching
  the last child unexpectedly.
- Property tests verify that fitting constraints produce non-overlapping child
  rects inside the parent.
- One low-risk existing render path adopts the helper as a proof point.
- `lib/foglet_bbs/tui/README.md` includes a compact worked example.

---

### Goal 3 — Styled Text Composition Helpers

**Why this matters:** Styled text construction is currently spread across raw
Raxol calls and local helper code. New screens need a small, obvious way to
compose styled runs while still routing colors through `Foglet.TUI.Theme`.

**What we build:** `Foglet.TUI.Text`, with lightweight `Span`, `Line`, and
`Text` value types plus conversion into the Raxol view-tree structures used by
the current renderer.

**Acceptance criteria:**

- `Span`, `Line`, and `Text` support `new/1`, `new/2`, `append/2`, `fg/2`,
  `bg/2`, `bold/1`, `dim/1`, `italic/1`, and `underline/1` where those styles
  are supported by the existing renderer.
- Style helpers accept theme atoms and resolve them through
  `Foglet.TUI.Theme`. Raw color values are allowed only where existing widget
  contracts already permit them.
- Rendering a composed value produces the same Raxol tree or ASCII output as
  the equivalent current hand-written code for at least three representative
  styled regions.
- One existing screen or widget migrates a small styled region as a proof point.
- A static check or focused test prevents raw ANSI escape codes from being
  introduced in screen modules.
- `lib/foglet_bbs/tui/README.md` documents when to use these helpers instead
  of direct Raxol `text/2` calls.

---

### Goal 4 — Key Binding Helpers

**Why this matters:** Key handling should be consistent across screens without
copy-pasting raw key tuple matches. The existing `ScrollKeys` helper is a good
start; this goal generalizes it carefully.

**What we build:** `Foglet.TUI.KeyBinding`, a small helper module that wraps or
extends `Foglet.TUI.ScrollKeys` rather than duplicating it.

Named bindings:

- `scroll_up?` / `scroll_down?` — current arrow plus `j`/`k` convention.
- `page_up?` / `page_down?` — PageUp/PageDown plus any intentionally supported
  alternate keys.
- `home?` / `end?`.
- `submit?` — Enter with no conflicting modifiers.
- `cancel?` — Escape plus the documented composer fallback where appropriate.
- `help?` — `?` and any supported function-key shape.

**Acceptance criteria:**

- The module explicitly documents text-input and search contexts where
  character keys such as `j` and `k` must remain typed input.
- Existing `ScrollKeys` users either remain valid or are migrated through a
  compatibility path; do not break current tests.
- At least two scrollable screens use the helper for common movement.
- Tests cover modifier handling, including that control-modified character
  keys do not accidentally count as plain movement.
- `SCREEN_CONTRACT.md` or `lib/foglet_bbs/tui/README.md` documents canonical
  key binding conventions.

---

### Goal 5 — Buffer Snapshot Test Helper

**Why this matters:** `mix foglet.tui.render` is useful for humans and agents,
but tests need a reusable assertion helper with good diffs. The current
`layout_smoke_test.exs` is valuable but too large to be the default pattern for
new screen tests.

**What we build:** `Foglet.TUI.Test` helpers built on `Foglet.TUI.AsciiRenderer`
and existing screen fixtures.

Example shape:

```elixir
import Foglet.TUI.Test

screen =
  render_screen(Foglet.TUI.Screens.MainMenu, state,
    context: context,
    width: 80,
    height: 24
  )

assert_screen screen, ~B"""
...
"""
```

**Acceptance criteria:**

- `render_screen/3` or equivalent renders through the same Raxol layout path as
  production and `mix foglet.tui.render`.
- `assert_screen/2` compares whole buffers and prints a useful row-by-row diff
  on failure.
- A `~B` sigil or equivalent keeps multiline expected buffers readable and has
  explicit trailing-whitespace behavior.
- At least three tests use the helper for meaningful whole-buffer states.
- New tests replace or complement existing coverage without adding brittle
  single-fragment text-presence tests.
- `docs/TESTING.md` documents when to use behavior tests, buffer snapshots, and
  manual `mix foglet.tui.render` inspection.

---

## Phase 2 — Pilot And Plan Revision

### Goal 6 — Pilot the New Patterns on `DoorList`

**Why this comes before architecture-wide changes:** The first five goals add
helpers. Before converting the codebase or reshaping cross-cutting contracts,
prove those helpers on one real screen and use the observed friction to revise
the rest of this plan.

`DoorList` is the pilot because it is medium sized, has navigation, guest
denial behavior, modal confirmation, runtime effects, and visual render
surface, but it is smaller than `PostReader`, `Sysop`, or `MainMenu`.

**What we do:**

- Convert `DoorList` to use the new layout helper where layout math exists.
- Convert eligible styled text to `Foglet.TUI.Text` where it improves clarity.
- Convert common movement/cancel/submit handling to `Foglet.TUI.KeyBinding`.
- Add buffer snapshot coverage for at least two meaningful visual states.
- Preserve existing launch-door, guest-denial, modal, and navigation behavior.
- Keep render pure over already-loaded state.

**Evidence to collect before and after the pilot:**

- `rtk rg -n "ScrollKeys|KeyBinding|%\\{key:|key: :|char:" lib/foglet_bbs/tui/screens/door_list.ex`
- `rtk rg -n "@.*width|@.*height|terminal_size|reader_width|width:|height:" lib/foglet_bbs/tui/screens/door_list.ex`
- `rtk rg -n "Effect\\.|open_modal|modal_submit|dismiss_modal" lib/foglet_bbs/tui/screens/door_list.ex`
- `rtk rg -n "Config\\.|Repo\\.|PubSub|send\\(|Process\\.|Task\\.|System\\." lib/foglet_bbs/tui/screens/door_list.ex`
- Relevant targeted tests for `DoorList`.
- `rtk mix foglet.tui.render door_list --width 80 --height 24` and at least one
  wider render for manual inspection.
- A short review of the diff: which helper reduced code, which helper added
  ceremony, and which pattern was ambiguous.

**Acceptance criteria:**

- `DoorList` behavior remains unchanged except for intentional internal
  simplification.
- Targeted tests for `DoorList` pass.
- `rtk mix precommit` passes before the goal is complete.
- `GOAL.md` is revised based on pilot findings before moving to Goal 7.

**Permission and instructions to revise the rest of this file:**

The agent executing Goal 6 is explicitly authorized to edit Goals 7 and later
inside this `GOAL.md`. Do this after the pilot code and tests are complete, not
before.

Derive revisions only from concrete pilot evidence:

- Search results listed above.
- Test failures or test complexity encountered during the pilot.
- The actual diff produced by the pilot.
- Places where the pilot required repeated adapter code.
- Places where a proposed helper made code harder to read.
- Existing architecture documents that contradicted this plan.

When revising the remaining goals:

- Delete acceptance criteria that the pilot proves are already done.
- Split any goal that the pilot shows is too large to complete safely.
- Reorder later goals if the pilot shows a dependency is wrong.
- Narrow or remove any helper that added more ceremony than clarity.
- Add specific file paths and examples where the pilot found unexpected
  friction.
- Preserve the north star, SSH-first product boundary, and `mix foglet.tui.render`
  manual-inspection workflow.
- Do not relax authorization, persistence, render-purity, or testing rules from
  `AGENTS.md`.

Add a `## Pilot Findings` section immediately below this goal when revising the
plan. Include the date, commit hash if available, files changed, tests run, and
the specific changes made to later goals.

## Pilot Findings

Date: 2026-05-14

Commit hash: pending for the pilot commit; previous completed helper commit was
`c5228e3c`.

Files changed during the pilot:

- `lib/foglet_bbs/tui/screens/door_list.ex`
- `test/foglet_bbs/tui/screens/door_list_test.exs`
- `GOAL.md`

Evidence collected:

- `rtk rg -n "ScrollKeys|KeyBinding|%\\{key:|key: :|char:" lib/foglet_bbs/tui/screens/door_list.ex`
  showed `DoorList` now uses `Foglet.TUI.KeyBinding` for movement and submit,
  with no remaining `ScrollKeys` dependency.
- `rtk rg -n "@.*width|@.*height|terminal_size|reader_width|width:|height:" lib/foglet_bbs/tui/screens/door_list.ex`
  showed the wide list/detail split uses `Foglet.TUI.Layout.horizontal/2`, while
  the existing `detail_width/1` cap remains a small local policy calculation.
- `rtk rg -n "Effect\\.|open_modal|modal_submit|dismiss_modal" lib/foglet_bbs/tui/screens/door_list.ex`
  showed App-owned modal routing and launch effects are preserved.
- `rtk rg -n "Config\\.|Repo\\.|PubSub|send\\(|Process\\.|Task\\.|System\\." lib/foglet_bbs/tui/screens/door_list.ex`
  returned no matches, so render/reducer code did not gain persistence,
  process, PubSub, or system side effects.
- `rtk mix test test/foglet_bbs/tui/screens/door_list_test.exs test/foglet_bbs/tui/buffer_snapshot_test.exs`
  passed after adding the empty-catalog buffer snapshot.
- `rtk mix foglet.tui.render door_list --width 80 --height 24 --no-frame`
  preserved the compact single-column render.
- `rtk mix foglet.tui.render door_list --width 120 --height 36 --no-frame`
  preserved the wide list/detail render.

Specific pilot results:

- `Foglet.TUI.Layout` reduced the wide-panel width handoff, but it did not
  eliminate all local sizing policy. Small policy helpers such as
  `detail_width/1` are still clearer than forcing every cap into generic layout
  constraints.
- `Foglet.TUI.Text` is useful where a render helper composes styled runs or
  repeated theme-slot options. For simple one-node text, direct Raxol `text/2`
  remains clearer and should stay acceptable.
- `Foglet.TUI.KeyBinding` clarified modifier handling and submit/movement
  semantics. Elixir guards cannot call these predicates, so converted screens
  may still need shape guards that delegate to `KeyBinding` inside the clause.
- `Foglet.TUI.Test` buffer snapshots are valuable for whole-screen visual
  states, but snapshots that include chrome must freeze `session_context.clock_now`
  and user time-format preferences to avoid minute-by-minute churn.
- App-owned modal routing was not a source of friction for `DoorList`; its
  confirmation and guest-denial flows remained simpler as App-owned modals.

Plan revisions from this pilot:

- Goal 10 should not require converting an App-owned modal merely to prove the
  concept. Convert only a genuinely screen-local form/confirmation where the
  pilot-style evidence shows App routing is ceremony.
- Goal 11 should treat `Foglet.TUI.Text` as a multi-run/repeated-style helper,
  not as a mandatory replacement for every simple `text/2` call.
- Goal 12 should document fixed-clock snapshot setup as a naming/update
  convention for buffer snapshots.

---

## Phase 3 — Cross-Cutting Refinements

These goals should be revalidated and possibly revised by Goal 6 before work
starts.

### Goal 7 — Reduce Effect Coupling

**Why this matters:** Effects already exist, but some effect values still carry
redundant screen identity and some App interpretation remains more specific
than the ideal screen/runtime boundary.

**What we improve:** Simplify effect APIs and routing only where the pilot or
current code shows real friction.

Potential targets:

- Reduce repeated `screen_key` arguments for screen-scoped tasks where App can
  infer the active screen safely.
- Clarify when `Effect.session/1` is appropriate versus a more specific effect.
- Remove per-screen branches from App effect handling where screen-owned
  callbacks or subscriptions are the cleaner boundary.
- Document the lifecycle from screen effect to App interpretation to screen
  result.

**Acceptance criteria:**

- `Foglet.TUI.Effect` remains the single public effect constructor module.
- Any changed effect API has compatibility handled in one deliberate step; no
  mixed old/new effect style remains in converted call sites.
- App effect interpretation becomes more generic or better documented; it does
  not merely move coupling to a different module.
- `SCREEN_CONTRACT.md` and `docs/ARCHITECTURE.md` document the final effect
  lifecycle.
- Tests cover task result routing, navigation, modal-related effects that
  remain App-owned, PubSub publishing, and session effects touched by the
  change.

---

### Goal 8 — Clarify Widget State Ownership

**Why this matters:** Some widgets are stateless render helpers, while others
wrap Raxol component state inside a widget struct. That can be reasonable, but
the authoring model should be explicit so screens do not need ad-hoc adapter
code.

**What we improve:** Establish a Raxol-compatible widget state contract. Do not
force a direct `area, buffer` API unless the pilot proves the renderer layer
itself needs to change.

Preferred contract:

- Render-only widgets accept data plus `theme:` options and return Raxol view
  trees.
- Stateful widgets expose a public state struct or clearly named state wrapper.
- Screens own widget state fields in their screen state.
- Widget event handlers are pure `(event, widget_state) -> {widget_state, action}`.
- Widgets return semantic actions; screens decide which effects to emit.

**Acceptance criteria:**

- `lib/foglet_bbs/tui/widgets/README.md` documents the final contract with one
  render-only example and one stateful example.
- At least two stateful widgets are audited against the contract.
- Any widget changed by this goal keeps backward-compatible behavior for current
  screens or migrates all call sites in the same change.
- Screens no longer need repeated wrapping/unwrapping boilerplate for the
  audited widgets.
- Tests verify event handling, render idempotence for same state/input, and
  semantic actions for changed widgets.

---

### Goal 9 — Enforce Render Purity

**Why this matters:** Render functions should be predictable and cheap. The
existing screen contract says render must not query persistence, mutate state,
subscribe, start tasks, or perform durable writes. Make that rule easier to
trust.

**What we build:** A practical enforcement layer using tests, static checks, or
a Credo rule. Prefer a rule that catches known dangerous calls over an
impossible claim that every transitive function call can be proven pure.

**Acceptance criteria:**

- A render-purity check covers screen render modules and top-level screen
  `render/2` functions.
- The check rejects known side-effecting calls in render paths, including
  `Repo`, `Config.put`, `Config.get` where it would hit persistence, PubSub,
  `Effect.task`, process spawning, direct `send`, and durable context
  mutations.
- Any existing violations are moved to `init/1`, `update/3`, task effects, or
  precomputed state.
- `SCREEN_CONTRACT.md` documents how to handle caches, derived render models,
  and expensive formatting without mutating during render.
- Tests or lint coverage fail when a new obvious render-side effect is added.

---

### Goal 10 — Simplify Modal Ownership

**Why this matters:** Some modal flows are screen-local form interactions, while
others are app-global runtime messages such as guest denial or task failure.
Treating all modals as App-routed concepts can make screen-local flows harder
to reuse, but removing App modal ownership entirely would lose useful global
behavior.

**What we improve:** Split modal ownership explicitly.

- App-owned modals remain for global runtime concerns.
- Screen-owned modals are allowed for local forms, confirmations, and reusable
  widget-like interactions.
- Screen-owned modals route events through the owning screen reducer and return
  semantic actions.
- App routing should not be involved when a modal is purely local to the active
  screen.

**Acceptance criteria:**

- `SCREEN_CONTRACT.md` defines App-owned versus screen-owned modal flows.
- At least one genuinely screen-local modal flow is converted away from App
  submit routing only if concrete evidence shows this reduces coupling; the
  `DoorList` pilot did not justify converting App-owned confirmation or
  guest-denial modals.
- App-owned modal behavior remains covered by tests.
- Converted modal flows preserve keyboard behavior, validation errors, cancel
  behavior, and visual overlay behavior.
- The final pattern is documented in `lib/foglet_bbs/tui/README.md` with a
  concise example.

---

## Phase 4 — Screen Rollout

### Goal 11 — Convert Remaining Screens Incrementally

**Why this comes after the pilot and cross-cutting refinements:** Once the
helpers and contracts are proven, apply them to the rest of the TUI in small
screen-focused changes.

**Suggested order after `DoorList`:**

1. `board_list` and `thread_list` — representative scrollable list screens.
2. `online_now` — list plus reporting/profile modal behavior.
3. `main_menu` — broad integration surface and oneliner flows.
4. `moderation` — modal-heavy operator workflow.
5. `sysop` — deepest tabbed/operator workflow.
6. `account` — multi-tab account workflow.
7. `post_reader` — high-value but complex; convert after patterns have proven
   stable elsewhere.
8. Remaining screens.

Goal 6 may revise this order based on pilot findings.

**Per-screen acceptance criteria:**

- Uses layout helpers where they remove real manual cell math.
- Uses text helpers for multi-run rows or repeated theme-slot styling; simple
  one-node `text/2` calls may remain direct Raxol calls when clearer.
- Uses key binding helpers for common movement, submit, cancel, and help.
- Keeps render pure under the render-purity check.
- Has focused behavior tests for reducer logic that changes.
- Has buffer snapshot coverage for major visual states where snapshots add
  value.
- Uses the documented modal ownership pattern.
- Does not move domain authorization or persistence logic into TUI modules.

**Completion criteria:**

- Every screen in `lib/foglet_bbs/tui/screens/` has been audited against the
  per-screen checklist.
- Any intentionally unconverted screen has a documented reason in
  `lib/foglet_bbs/tui/README.md` or a tracked follow-up.
- `docs/TESTING.md`, `SCREEN_CONTRACT.md`, and `widgets/README.md` reflect the
  final patterns.

---

### Goal 12 — Consolidate Testing and Manual Inspection Workflow

**Why this matters:** A better DX plan should make verification easier, not
replace one bulky test file with another opaque convention.

**What we improve:** Make the preferred test and inspection workflow explicit.

**Acceptance criteria:**

- `docs/TESTING.md` describes:
  - reducer/behavior tests,
  - widget unit tests,
  - buffer snapshot tests,
  - layout smoke tests,
  - `mix foglet.tui.render` manual inspection,
  - SSH harness QA.
- Large smoke tests are split or annotated if they are difficult to maintain.
- Snapshot tests have naming, fixture, and update conventions.
- Snapshot tests that include chrome freeze `session_context.clock_now` and user
  time-format preferences so snapshots do not churn with wall-clock time.
- `mix foglet.tui.render` remains documented as the fastest way to inspect a
  screen manually without SSH.
- `AGENTS.md` remains accurate about TUI inspection and finish-line testing.

---

## Cross-Cutting Non-Goals

Do not do these as part of this plan:

- Add end-user browser workflows.
- Replace Raxol with a Ratatui-like buffer renderer.
- Introduce a Cassowary-style layout solver.
- Add macro-heavy component abstractions unless a completed goal proves plain
  modules cannot express the needed contract.
- Remove `mix foglet.tui.render`.
- Move authorization, persistence, or PubSub ownership out of domain contexts
  into screens or widgets.

## Risk And Rollback

Phase 1 goals are additive and should be independently revertable until adopted.

Goal 6 is the safety valve. If the pilot shows a helper is too ceremonial or a
later goal is aimed at the wrong problem, revise this file immediately before
continuing.

Phase 3 and Phase 4 changes should be screen- or contract-scoped. Avoid one
giant fleet-wide rewrite unless the pilot demonstrates that a cut-over is safer
than incremental migration.

When rollback is needed, prefer reverting the smallest completed goal or
screen-level conversion. Do not leave parallel old/new patterns undocumented.

## References

Internal:

- `AGENTS.md`
- `docs/ARCHITECTURE.md`
- `docs/TESTING.md`
- `docs/DATA_MODEL.md`
- `docs/raxol/getting-started/WIDGET_GALLERY.md`
- `lib/foglet_bbs/tui/SCREEN_CONTRACT.md`
- `lib/foglet_bbs/tui/widgets/README.md`
- `lib/foglet_bbs/tui/ascii_renderer.ex`
- `lib/foglet_bbs/tui/scroll_keys.ex`
- `lib/foglet_bbs/tui/effect.ex`
- `lib/foglet_bbs/tui/app/effects.ex`

External inspiration:

- Ratatui layout concepts
- Ratatui text and style concepts
- Ratatui testing concepts
- The Elm Architecture / command-and-subscription style update loops
