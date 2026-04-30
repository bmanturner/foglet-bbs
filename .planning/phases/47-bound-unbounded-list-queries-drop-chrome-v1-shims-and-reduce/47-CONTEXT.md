# Phase 47: Bound Unbounded List Queries, Drop Chrome V1 Shims, and Reduce App + Large Screen Modules - Context

**Gathered:** 2026-04-30 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 47 closes the three residual debt items called out in
`.planning/codebase/CONCERNS.md` after Phase 46 — locked by 47-SPEC.md's seven
falsifiable requirements:

1. **Bound unbounded list queries.** Delete `Foglet.Posts.list_posts/1`
   entirely; migrate `Foglet.TUI.Screens.PostReader.load_posts/2` to
   `Foglet.Posts.list_reader_window/2`. Bound `Foglet.Threads.list_threads/{1,2}`
   with a default page-size of 50 (centralised module attribute), reserving a
   cursor-shaped `opts` keyword list for future paging work but not implementing
   cursors in this phase.
2. **Drop Chrome V1 shims.** Remove the V1 code paths in
   `Foglet.TUI.Widgets.Chrome.{KeyBar, ScreenFrame, StatusBar}` and delete
   `Foglet.TUI.Widgets.Chrome.Normalizer` entirely; migrate the remaining V1
   call sites in screen modules to V2 grouped command bars.
3. **Reduce App + Login.** Extract `Foglet.TUI.App.ScreenStates` and
   `Foglet.TUI.App.SessionAlias` from `Foglet.TUI.App`, dropping App below
   400 lines. Decompose `Foglet.TUI.Screens.Login` along the Phase 43
   PostReader pattern (per-mode reducer modules + sibling `state.ex`),
   dropping `login.ex` below 300 lines.

Out of scope (locked by SPEC §Boundaries): a paginated `list_posts_page/2`,
cursor-based scrolling pagination in `ThreadList` TUI, decomposition of any
other large screen modules, removal of the two `:no_match` Account form
ignore entries (Phase 46 D-06), and anything outside `Foglet.TUI.*`,
`Foglet.Posts`, and `Foglet.Threads`.
</domain>

<decisions>
## Implementation Decisions

### PostReader Window Anchor Selection

- **D-01:** `Foglet.TUI.Screens.PostReader.load_posts/2` becomes a thin shim
  over the existing `update(:load, …)` path. Anchor selection reuses the
  already-shipped helpers in `post_reader.ex:567-609` (`load_direction/1`,
  `selected_index_after_window_load/3`).
- **D-02:** Anchor mapping rules:
  1. **Read pointer present** → call `Foglet.Posts.list_reader_window/2`
     with `direction: :around, around_message_number: <pointer>`. The
     `:around` direction already exists in `posts.ex:145-152` and is the
     correct primitive — no new direction keyword is added to Posts.
  2. **No read pointer** → fall through to `direction: :initial`.
  3. **`load_intent: :jump_last`** → fall through to `direction: :last`.
- **D-03:** Do NOT add a new `direction: :read_pointer` keyword to
  `list_reader_window/2`, and do NOT have the screen call into
  `Foglet.Threads.get_thread_read_pointer/2` itself. The Posts option API
  surface is unchanged in this phase; the read-pointer lookup remains where
  it already lives in the load path.
- **D-04:** `selected_index_after_window_load/3` is reused as-is to land the
  selected index back on the read-pointer message_number after the windowed
  load completes — this is what makes the "200 posts + pointer at 150"
  acceptance test (R2) pass.

### Threads Pagination API

- **D-05:** Add a new `list_threads/3` of shape
  `(board_id, user_id_or_nil, opts \\ [])`. Keep the existing arity-1 and
  arity-2 forms; both delegate to the arity-3 form with `opts: []`. This
  matches the Phase 44 `Foglet.Posts.list_reader_window/2` precedent
  (trailing keyword list with explicit `Keyword.get/3` defaults) and avoids
  breaking every current caller.
- **D-06:** `opts` reserves three keys for future cursor work — `:limit`,
  `:after`, `:before`. **Phase 47 implements only `:limit`.** `:after` and
  `:before` are documented in `@doc` as reserved-for-future-use but are NOT
  validated, parsed, or rejected at runtime. No stub validator is added —
  doing so would conflict with SPEC R3's "Phase 47 only uses default
  options at call sites" and add untested code paths.
- **D-07:** Page-size constant lives in `Foglet.Threads` as
  `@page_size 50` plus a public `def default_page_size, do: @page_size`.
  The bounded query references `@page_size` (not the literal `50`). Per
  SPEC R4 acceptance, `grep -n "50" lib/foglet_bbs/threads.ex` should
  return only the constant declaration.
- **D-08:** Page size is NOT a `Foglet.Config` key — it is module-level
  hard-coded. Any future move to runtime config is a separate phase.
- **D-09:** Result ordering preserved (most recent activity first); the
  unread-aware join is unchanged. `LIMIT` is applied at the SQL layer,
  verified via `Ecto.Adapters.SQL.to_sql/3` in the acceptance test.

### Chrome V1 Deletion Order

- **D-10:** Five-step deletion order (preserves a green compile at every
  step):
  1. Migrate the surviving V1 call sites — `board_list.ex:230`,
     `moderation.ex:175,205`, `account/render.ex:50`,
     `post_reader/render.ex:37`, `thread_list.ex:136` — to emit V2 grouped
     command bars (using `CommandBar.normalize_groups/1` directly or a
     small helper).
  2. Remove the `Normalizer.commands/1` fallback branch in
     `screen_frame.ex:198-204` and the explicit `Normalizer` alias at
     `screen_frame.ex:27`.
  3. Delete `Foglet.TUI.Widgets.Chrome.KeyBar` (it is now an unreferenced
     Normalizer→CommandBar shim per `key_bar.ex:23-25`).
  4. Delete `Foglet.TUI.Widgets.Chrome.Normalizer` entirely.
  5. Remove the V1 "legacy title string" branch `normalize_chrome/2`
     clause at `screen_frame.ex:191-196` and the legacy-title arity at
     `status_bar.ex:37`.
- **D-11:** The `@key_hints` text affordances rendered in
  `invites_surface.ex` and `account/ssh_keys_surface.ex` are NOT V1
  chrome — they render as `text(@key_hints, …)` inside the screen body,
  not in chrome. They are out of scope per SPEC R5 (which scopes the
  four chrome modules only).
- **D-12:** SPEC R5 acceptance grep
  (`grep -rn "{[^,]\\+, *\"[^\"]\\+\"}" lib/foglet_bbs/tui/screens/`)
  must return zero hits matching the legacy keybar tuple shape after
  step 1. This is the regression check after each call-site migration.

### Login Mode-Machine Refactor

- **D-13:** `Foglet.TUI.Screens.Login.State` stays as a **map** keyed by
  `:sub`. It is NOT converted to a tagged-union struct. Existing
  `Map.merge(local_state, %{…})` writes (`login.ex:101, 116, 127, 139,
  147`) are preserved as-is — these write only some keys of the active
  sub-state shape and rely on map-merge tolerance. SPEC R7 requires
  "existing login screen tests pass without modification beyond
  import-path adjustments," which a struct rewrite would likely violate.
- **D-14:** Four per-mode reducer modules at
  `lib/foglet_bbs/tui/screens/login/{menu,login_form,reset_request,reset_consume}.ex`,
  each exposing:
  - `handle_key/2` — for keyboard event reducers.
  - `handle_task_result/3` — for the corresponding async task result.
  Sub-state constructors (`LoginState.login_form/0`, `reset_request/0`,
  `reset_consume/0`) stay in `state.ex`; the mode modules consume them.
- **D-15:** Top-level `login.ex` `update/3` keeps the existing four-way
  `case LoginState.sub(state)` dispatch in `reduce_key/2`
  (`login.ex:157-164`). Each branch becomes a one-line delegate to the
  corresponding mode module's `handle_key/2`. The catch-all
  `update(_message, local_state, …)` clause at `login.ex:154` stays at
  the top level.
- **D-16:** Task-result handlers (`{:task_result, :login, …}`,
  `{:task_result, :reset_request, …}`, `{:task_result, :reset_token, …}`)
  route by **task atom**, not by current `:sub`. Each task atom maps to
  exactly one mode module:
  - `:login` → `LoginForm.handle_task_result/3`
  - `:reset_request` → `ResetRequest.handle_task_result/3`
  - `:reset_token` → `ResetConsume.handle_task_result/3`
  This preserves today's behavior where a delayed reset-request result
  arriving after the user navigated back to `:menu` still sets
  `state.message` (which menu render reads).
- **D-17:** If the `:contract_supertype` `.dialyzer_ignore.exs` entry for
  `login.ex` becomes unnecessary after the refactor, remove it; otherwise
  keep it with a refreshed inline rationale citing Phase 47. Do not chase
  the entry by adding speculative `@spec`s — only remove if naturally
  resolved.

### App.ScreenStates and App.SessionAlias Extraction

- **D-18:** `Foglet.TUI.App.ScreenStates` owns the existing
  `state.screen_state` map (note: the field is singular `:screen_state` per
  `app.ex:58, 68`; SPEC's "screen_states" is paraphrase, not a literal
  rename). The field is NOT renamed — doing so would force migration of 30+
  pattern-match call sites across `lib/` and `test/` (e.g., `post_reader.ex:471`,
  `login/state.ex:88, 107, 113`) and exceeds the SPEC's "no behavior
  change" constraint.
- **D-19:** `App.ScreenStates` exposes `get/2`, `put/3`, `update/4`, and
  `delete/2`, each operating on `%Foglet.TUI.App{}`. The existing public
  delegators on `App` (`screen_state_for/2`, `put_screen_state/3` at
  `app.ex:103-114`) are kept as thin pass-throughs to `App.ScreenStates`.
  Most inline manipulation today lives in `App.Routing` (`routing.ex:53`),
  so this extraction is partly a move *out of `Routing`* into the new
  module rather than out of `App` directly.
- **D-20:** `App.SessionAlias` owns:
  - The `:set_user` `do_update` clause (`app.ex:270-272`).
  - The `:promote_session` `do_update` clause (`app.ex:384-412`, ~29 lines).
  - The `:session_replaced` clause (`app.ex:369-378`).
  - The `session_context` `Map.put` aliasing helpers used by the above.
  `App` keeps thin one-line delegating `do_update` clauses for each of
  these three messages — the public callback boundary is unchanged.
- **D-21:** `App.ScreenStates` must be < 100 lines, `App.SessionAlias`
  must be < 80 lines, and `app.ex` must drop below 400 lines (currently
  483) per SPEC R6 acceptance. `wc -l` checks are run after each
  extraction commit.

### Test Migration

- **D-22:** **Posts:** Delete the `list_posts/1` implementations from all
  fixture mods — `post_reader_test.exs:11, 62, 78, 114` (including
  `BoundedFakePosts`'s `def list_posts(_), do: raise(…)` regression-guard
  line, which itself contains `.list_posts` and would fail SPEC R1's grep)
  and `app_test.exs:55-89`. Migrate fixture mods to implement
  `list_reader_window/2` only.
- **D-23:** Delete `posts_test.exs:410-450` (the `list_posts/1`
  tombstone-semantics tests) outright — Phase 44 D-13/D-14 already locked
  the equivalent tombstone behavior coverage through `list_reader_window/2`
  (`44-CONTEXT.md:78-85`). Do not migrate; that would duplicate Phase 44
  coverage.
- **D-24:** **Threads:** Keep all existing `list_threads/2` tests (they
  pass through arity-3 with `opts: []`). Add new tests for SPEC R3 (75
  threads → 50 returned, ordered most-recent-first, `LIMIT 50` in generated
  SQL via `Ecto.Adapters.SQL.to_sql/3`) and SPEC R4
  (`Foglet.Threads.default_page_size() == 50`).
- **D-25:** **Chrome V1:** Tests asserting V1 `{key, description}` tuple
  shapes or "legacy title string" behavior are deleted, NOT skipped or
  migrated. The SPEC R5 "V1 fixture tests deleted (not skipped)"
  constraint is explicit.
- **D-26:** **App extractions:** New unit tests at
  `test/foglet_bbs/tui/app/screen_states_test.exs` and
  `test/foglet_bbs/tui/app/session_alias_test.exs`, mirroring the
  existing `test/foglet_bbs/tui/app/{routing,modal}_test.exs` precedent.
  Each must be focused (per SPEC R6's "dedicated unit test" requirement).

### Claude's Discretion

- Naming details for internal helpers within each new module (e.g.,
  `App.ScreenStates.get/2` vs `.fetch/2`) — pick the shape that
  best mirrors the existing `App.Routing` / `App.Modal` API style.
- Exact file/test ordering inside the phase plan — the dependency
  ordering between requirements is a planning concern (likely R1+R2 first,
  then R3+R4, then R5, then R6, then R7), but specific commit ordering
  within each requirement is left to the planner.

### Folded Todos

None — `gsd-sdk query todo.match-phase 47` returned zero matches.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `.planning/phases/47-bound-unbounded-list-queries-drop-chrome-v1-shims-and-reduce/47-SPEC.md` — locked spec (7 requirements, 16 acceptance checkboxes)
- `.planning/codebase/CONCERNS.md` — residual tech-debt items targeted by this phase
- `.planning/phases/46-domain-cleanup-and-final-quality-gate/46-CONTEXT.md` — Phase 46 dialyzer baseline / `.dialyzer_ignore.exs` invariant
- `.planning/phases/44-bounded-state-and-soft-deletes/44-CONTEXT.md` — `list_reader_window/2` cursor semantics, message_number anchoring (D-13/D-14 tombstone coverage)
- `.planning/phases/43-postreader-decomposition/43-CONTEXT.md` (or equivalent) — PostReader per-mode/render decomposition pattern that Login refactor follows
- `.planning/phases/42-app-runtime-extraction/42-CONTEXT.md` — `App.{Routing, Modal, Effects, Subscriptions}` extraction precedent
- `lib/foglet_bbs/posts.ex` — `list_reader_window/2` API at `:107, :145-152`
- `lib/foglet_bbs/threads.ex` — current `list_threads/{1,2}` at `:106-152`
- `lib/foglet_bbs/tui/app.ex` — `:screen_state` field at `:58, 68`; `:set_user`/`:promote_session` clauses at `:270-272, 384-412`; `:session_replaced` at `:369-378`
- `lib/foglet_bbs/tui/screens/post_reader.ex` — `load_posts/2` shim at `:298-337`; window-anchor helpers at `:567-609`
- `lib/foglet_bbs/tui/screens/post_reader/state.ex` — Phase 43 sibling-state pattern
- `lib/foglet_bbs/tui/screens/login.ex` and `lib/foglet_bbs/tui/screens/login/state.ex` — current 606-line target; `:sub`-keyed map shape
- `lib/foglet_bbs/tui/widgets/chrome/{normalizer,key_bar,screen_frame,status_bar}.ex` — V1 shim modules
- `docs/DATA_MODEL.md` — Posts/Threads schema invariants (per AGENTS.md, read before context-layer changes)
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`Foglet.Posts.list_reader_window/2`** (`posts.ex:107, 145-152`) —
  already supports `direction: :around, around_message_number: …`, which
  is the exact primitive needed for the `load_posts/2` migration. No new
  Posts API surface required.
- **`PostReader.load_direction/1` and `selected_index_after_window_load/3`**
  (`post_reader.ex:567-609`) — anchor-aware index landing logic from
  Phase 44. Reused by `load_posts/2` after migration.
- **Phase 43 PostReader sibling-module layout** —
  `lib/foglet_bbs/tui/screens/post_reader/{state,render}.ex` (with
  per-mode helpers as private functions). Direct template for Login
  decomposition.
- **`Foglet.TUI.App.{Routing, Modal, Effects, Subscriptions}`** —
  Phase 42 precedent for `App.*` extraction. New `App.ScreenStates` and
  `App.SessionAlias` follow the same module-namespace and delegation
  shape.
- **`Foglet.TUI.Widgets.Chrome.CommandBar.normalize_groups/1`** — V2
  primitive that the migrated screen call sites emit into. No new helper
  needed beyond a possibly-shared "tuple list → groups" converter (and
  even that may be unnecessary if call-site migrations build groups
  directly).
- **`BoundedFakePosts` and `FakeThreads`** test fixtures — fixture-mod
  indirection pattern that the SPEC R2 acceptance leverages.

### Established Patterns

- **Trailing keyword opts on context functions** (Phase 44 precedent in
  `Posts.list_reader_window/2`) — explicit `Keyword.get/3` with default;
  reserved keys documented in `@doc` but not validated until implemented.
- **`message_number`-anchored cursors** (Phase 44 D-08, `44-CONTEXT.md`)
  — stable across tombstones; do not switch to `inserted_at` or `OFFSET`.
- **Module-level `@page_size` constants** (no Phase 44 precedent for
  Threads but matches the codebase's `@xxx` attribute style; cf.
  `Posts.@reader_window_size`).
- **Single-writer board servers** (AGENTS.md core invariant) — Phase 47
  does not touch `Foglet.Boards.Server` write paths; bounded threads
  query is read-only.
- **Sibling per-screen state modules** (Phase 43) — `state.ex` lives next
  to the screen module under a `screens/<screen>/` directory.
- **Public delegators on parent + concrete logic in child** (Phase 42
  `App.Routing`) — preserves the public API while moving implementation.

### Integration Points

- `PostReader.load_posts/2` ↔ `Posts.list_reader_window/2` — only
  Phase-47 consumer requiring API change is the screen seam itself.
- `ThreadList` ↔ `Threads.list_threads/{2,3}` — `thread_list.ex:268-272`
  and `app_test.exs:23-49` are the only consumers; both pass through the
  arity-2 → arity-3 delegation transparently.
- Chrome V2 grouped command bars ↔ five screen call sites — all in
  `lib/foglet_bbs/tui/screens/` per the deletion-order plan (D-10).
- `App.ScreenStates` ↔ `App.Routing` — Routing currently owns most map
  manipulation (`routing.ex:53`); ScreenStates partly replaces that
  inline logic.
- `App.SessionAlias` ↔ `App.Subscriptions` (heartbeat/topic refresh on
  user change) — unchanged subscription wiring; SessionAlias only owns
  the user/session aliasing data plumbing, not the topic refresh.
- `.dialyzer_ignore.exs` ↔ Login refactor — the `:contract_supertype`
  entry for `login.ex` may become unnecessary; check after refactor and
  remove only if naturally resolved (D-17).
</code_context>

<specifics>
## Specific Ideas

- "Read pointer present → `:around` with `around_message_number`" is the
  one specific primitive choice; everything else falls out of existing
  patterns.
- Test files `screen_states_test.exs` and `session_alias_test.exs` are
  named to mirror `routing_test.exs` / `modal_test.exs` exactly — keeps
  the `test/foglet_bbs/tui/app/` directory discoverable and consistent.
- Per-mode reducer module names — `Login.Menu`, `Login.LoginForm`,
  `Login.ResetRequest`, `Login.ResetConsume` — match the `:sub` atom names
  in `LoginState` (`login/state.ex:13-32`) directly.
</specifics>

<deferred>
## Deferred Ideas

- **Cursor-based `ThreadList` scrolling** — domain layer reserves
  `:after`/`:before` keys but TUI still renders only the first page in
  this phase (locked SPEC §Out of scope).
- **`Foglet.Config` key for page size** — page size is a module-level
  constant in Phase 47; runtime configuration is a future phase.
- **Tagged-union `LoginState` struct** (Alt 1 of D-13) — better Dialyzer
  signal but high test churn risk; revisit only if `:contract_supertype`
  proves recurrent across multiple screens.
- **Decomposition of `post_reader.ex`, `main_menu.ex`, `boards_view.ex`,
  `modal/form.ex`, `cli_handler.ex`** — CONCERNS.md classifies these as at
  natural size or addressed by previous phases (locked SPEC §Out of scope).
- **Removal of the two Account form `:no_match` ignore entries** — Phase
  46 D-06 explicitly retained these as defensive Phase-25 fallbacks;
  revisit only when those forms themselves are refactored.
- **Stub validation for `Threads.list_threads/3` `:after`/`:before`
  keys** (Alt 3 of D-05/D-06) — explicitly NOT added in this phase per
  SPEC R3's "Phase 47 only uses default options at call sites."
- **Renaming `:screen_state` field to `:screen_states`** (Alt 2 of D-18)
  — explicitly NOT done; 30+ call-site migration cost violates SPEC's
  "no behavior change" constraint.

### Reviewed Todos (not folded)

None — todo matcher returned zero matches for Phase 47.
</deferred>
