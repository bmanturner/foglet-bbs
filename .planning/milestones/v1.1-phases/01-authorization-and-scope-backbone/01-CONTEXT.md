# Phase 1: Authorization and Scope Backbone - Context

**Gathered:** 2026-04-23 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Introduce an actor-aware, scope-aware authorization policy seam (`Foglet.Authorization`)
enforced at domain context functions. In v1.1, guard only operator operations that have
a live caller landing in this milestone (sysop config writes, board/category lifecycle,
invite generation/revocation, oneliner hide). Pre-define action atoms for the remaining
operator operations so Phase 8 can activate their guards as a mechanical diff. Support
`:site` and `{:board, board_id}` scopes today; the seam must accept multi-board moderator
assignment in v2 without API changes.

This phase ships the plumbing, not operator UI behavior. Phase 8 is where the Moderation
workspace wires real mod actions on top of this seam.

</domain>

<decisions>
## Implementation Decisions

### Policy Module Shape
- **D-01:** A new context-style module `Foglet.Authorization` lives at
  `lib/foglet_bbs/authorization.ex`. It is a top-level `Foglet.*` context, not nested
  under a domain module. It implements `@behaviour Bodyguard.Policy`. A new dependency
  `{:bodyguard, "~> 2.4"}` is added to `mix.exs`.
- **D-02:** Public call convention (matching Bodyguard's argument order — action first):
  - `Bodyguard.permit(Foglet.Authorization, action, actor, scope) :: :ok | {:error, :forbidden}`
  - `Bodyguard.permit?(Foglet.Authorization, action, actor, scope) :: boolean()`
  - `Foglet.Authorization.scopes_for(actor, action) :: [scope]` — data-visibility helper,
    not a Bodyguard callback.

  Internally, the module implements the `@callback authorize(action, user, params)` from
  `Bodyguard.Policy`. `params` carries our scope tagged tuple. The callback always returns
  `:ok` or `{:error, :forbidden}` explicitly — never bare `:error` — so `Bodyguard.permit/4`'s
  coercion passes the reason through unchanged (preserving D-14). Callers MUST go through
  `Bodyguard.permit/4` / `permit?/4`; direct invocation of the callback is reserved for the
  test harness and is discouraged in application code.
- **D-03:** No per-action predicates (no `can_lock_thread?/2` style helpers). Every call
  routes through `Bodyguard.permit/4` or `Bodyguard.permit?/4` with an action atom so the
  allowlist stays centralized.

### Actor Representation
- **D-04:** Actor is `Foglet.Accounts.User.t() | nil`. `nil` means guest and falls through
  to `{:error, :forbidden}` for every operator action. No separate `Actor` struct is
  introduced in this phase.
- **D-05:** Callers pass the live `%User{}` held in `Foglet.TUI.App.current_user`, not a
  projection from `Foglet.Sessions.Session.role` (which can drift from `User.role` after
  a role change).

### Scope Representation
- **D-06:** Scope is a tagged tuple with exactly two shapes today:
  `:site | {:board, Ecto.UUID.t()}`.
- **D-07:** The **caller** synthesizes scope from the operation's data; the policy does not
  DB-resolve resources. Example:
  `Bodyguard.permit(Foglet.Authorization, :lock_thread, user, {:board, thread.board_id})`.
- **D-08:** Each domain module exposes a `scope_for/1` helper so synthesis is consistent:
  - `Foglet.Threads.scope_for(thread) :: {:board, board_id}`
  - `Foglet.Posts.scope_for(post) :: {:board, board_id}`
  - `Foglet.Boards.scope_for(board) :: {:board, board.id}`
  - Sysop-only operations (config writes, etc.) use `:site` directly; no helper needed.

### Multi-Board Moderator Support (forward-looking invariant)
- **D-09:** A moderator must be assignable to multiple boards in v2 (MODR-06). The seam
  supports this natively today:
  - `scopes_for(actor, action) :: [scope]` returns a **list** of scopes.
  - A mod on boards X, Y, Z yields `[{:board, "X"}, {:board, "Y"}, {:board, "Z"}]`.
  - A sysop yields `[:site]`. A non-operator user yields `[]`.
- **D-10:** The future `board_moderators` schema will be a many-to-many join table
  (one row per (user_id, board_id) pair), NOT a `moderated_boards :: [board_id]` column
  on `users`. `scopes_for/2`'s v2 implementation reads from that join table without any
  API change to callers.

### Action Representation
- **D-11:** Actions are flat atoms in a central allowlist inside `Foglet.Authorization`.
  Namespaced strings (`"threads.lock"`) and tuples (`{:threads, :lock}`) are rejected in
  favor of matching the codebase's existing `:atom` idiom for enumerated domain values
  (`@valid_roles`, `@valid_statuses`, `Foglet.TUI.Screens.Domain.@supported_keys`).
- **D-12:** The Phase 1 allowlist includes **all** actions the milestone will eventually
  use, whether or not Phase 1 guards them yet (see D-19):

  ```
  # Thread operator actions (atoms defined now; guards added in Phase 8 per D-19)
  :lock_thread, :unlock_thread, :sticky_thread, :unsticky_thread,
  :move_thread, :delete_thread

  # Post operator actions (atoms defined now; guards added in Phase 8 per D-19)
  :delete_post, :edit_post_as_mod

  # Oneliner moderation (atom defined now; guard added in Phase 8, MODR-05)
  :hide_oneliner

  # Board/Category lifecycle (guarded in Phase 1 — Phase 2 is a live caller)
  :create_board, :update_board, :archive_board,
  :create_category, :update_category, :archive_category

  # Sysop config (guarded in Phase 1 — Phase 2 is a live caller)
  :edit_config

  # Invite ops (guarded in Phase 1 — Phase 3 is a live caller)
  :generate_invite, :revoke_invite
  ```

- **D-13:** An unknown action atom returns `{:error, :forbidden}` and emits
  `Logger.warning` — a safe default implemented as a callback clause (guarded by the
  `@valid_actions` allowlist) that mirrors `InvitesSurface.visible?/2`'s catch-all clause.
  It does NOT raise. Bodyguard does not validate actions at compile time; the runtime
  catch-all is the defense.

### Return Contract
- **D-14:** Success returns `:ok`. Failure returns `{:error, :forbidden}`. Both are pure —
  no raises, no side effects. The callback always returns `{:error, :forbidden}` explicitly
  (never bare `:error`) so `Bodyguard.permit/4` preserves the reason. This slots into the
  `{:error, :not_found}`, `{:error, :invalid_credentials}` convention documented in
  `.planning/codebase/CONVENTIONS.md`.
- **D-15:** Domain functions that adopt the guard return `{:error, :forbidden}` in
  addition to their existing error tuples; the tagged-tuple shape stays consistent.
- **D-16:** Guards MUST NOT raise. Authorization failure is a runtime condition from valid
  input, not a programming error, so the bang-variant convention (`Repo.get!/2`) does not
  apply. Callers use `Bodyguard.permit/4`, never `Bodyguard.permit!/5` (which raises
  `Bodyguard.NotAuthorizedError`).

### Enforcement Surface — Defense-in-Depth
- **D-17:** The domain context function is the **real trust boundary**. Every guarded
  context function takes the actor as its first argument and calls
  `Bodyguard.permit(Foglet.Authorization, action, actor, scope)` before side effects. On
  `{:error, :forbidden}` the function returns the tuple and performs no mutation.
- **D-18:** The TUI **may** also call `Bodyguard.permit?(Foglet.Authorization, action, actor, scope)`
  for advisory rendering (grey-out keybars, hide menu entries, present "not available"
  columns). The TUI check is advisory; the domain check is authoritative. This is
  defense-in-depth: any code path that produces `{:ok, ...}` from a guarded context
  function MUST have passed the policy, regardless of the caller (TUI, Mix task, test
  harness, future SSH key command, future structured API client).

### v1.1 Guard Scope — Option (a)
- **D-19:** Phase 1 adds the actual `Bodyguard.permit/4` call and signature changes to
  ONLY the context functions whose callers land in v1.1:
  - `Foglet.Config.put!(key, value, actor)` — used by Phase 2
  - `Foglet.Boards.create_board/update_board/archive_board` (new `actor` first arg)
  - `Foglet.Categories.create_category/update_category/archive_category` (new, Phase 2)
  - `Foglet.Accounts.generate_invite/revoke_invite` (new, Phase 3)
  - `Foglet.Oneliners.hide/...` (new, Phase 8 uses this; signature created with actor
    arg from day one when the module is introduced)
- **D-20:** Pre-existing thread/post operator functions (`Threads.lock_thread`,
  `unlock_thread`, `sticky_thread`, `unsticky_thread`, `move_thread`, `delete_thread`,
  `Posts.delete_post`, `Posts.edit_post` when editor ≠ author) are **not** signature-changed
  in Phase 1. Their action atoms exist in the allowlist (D-12), but the
  `Bodyguard.permit/4` call is added later when Phase 8 wires real TUI callers in the
  Moderation workspace.
  - **Why safe:** no v1.1 TUI caller invokes these today, so no new exposure is opened up
    between Phase 1 merging and Phase 8 guarding them. `.planning/codebase/CONCERNS.md`
    flags the latent risk; it is acknowledged and deferred to Phase 8.

### Data-Visibility Seam (MODR-02)
- **D-21:** `Foglet.Authorization.scopes_for(actor, action) :: [scope]` exists from
  Phase 1. In v1.1 it returns:
  - `[:site]` for `%User{role: :sysop}`
  - `[:site]` for `%User{role: :mod}` (v1.1 has no board-scoped mods; all mods are
    site-scope today)
  - `[]` for any other actor (regular user or guest)
- **D-22:** Phase 1 does **not** build scope-filtered list query helpers (no
  `Threads.list_for_moderation/2`, no `Posts.list_for_moderation/2`). Those helpers
  belong in Phase 8 when a real Moderation workspace caller exists, to avoid
  speculative-code drift.
- **D-23:** v2's `board_moderators` join table rewrite of `scopes_for/2` MUST NOT change
  its call signature or return shape. That is the "no API rewrite" invariant from the
  phase success criterion.

### Guest / Suspended / Deleted User Handling
- **D-24:** The `authorize/3` callback rejects the following actors at the top, before any
  role or action dispatch:
  - `nil` (guest session)
  - `%User{deleted_at: dt}` when `dt != nil`
  - `%User{status: :suspended}`
  - `%User{status: :pending}`
- **D-25:** A stale `current_user` snapshot in an active TUI session must not retain
  operator powers after sysop action. The policy is the last line of defense; the Session
  layer's disconnect-on-suspend behavior (if any) is complementary, not a substitute.

### Test Strategy
- **D-26:** A dedicated matrix test file at `test/foglet_bbs/authorization_test.exs`
  enumerates the full `(role, status, action, scope) → :ok | {:error, :forbidden}` matrix.
  Tests run with `async: true` using `FogletBbs.DataCase` (no DB required for pure policy
  assertions beyond user fixtures).
- **D-27:** Every domain function that gains an actor argument also receives a
  "forbidden path" test added to its existing context test file (e.g.,
  `test/foglet_bbs/boards/boards_test.exs`). One test per guarded function suffices;
  the matrix file covers the full role/status/scope combinatorics globally.
- **D-28:** Guest/nil/deleted/suspended/pending paths live in the matrix test, not
  scattered across domain tests.

### Claude's Discretion
- Exact naming of action atoms if the set in D-12 needs to grow or split during planning
  (e.g., should `:edit_config` become `:edit_config_{key}`? stay flat for now unless
  planner finds a reason).
- Exact return shape of `scopes_for/2` when the actor is a guest or has no operator role —
  the contract is "an empty list means nothing", as long as it is a list.
- Whether `scope_for/1` helpers live in each domain module or in a single
  `Foglet.Authorization.Scope` helper — prefer per-domain to match `Foglet.*` context
  conventions, but the planner may consolidate if duplication appears.
- The exact `Logger.warning` message format for unknown action atoms.
- Whether to enable `Bodyguard.scope/4` for Ecto query scoping in Phase 1 (by implementing
  `Bodyguard.Schema`'s `scope/3` callback on relevant domain schemas) or defer that to
  Phase 8 when moderation list queries have a real caller. Prefer defer — YAGNI — unless
  the planner sees a concrete Phase 1 caller.
- The module-level `error:` option for `Bodyguard.Policy` — leaving it at default is fine
  because the callback returns `{:error, :forbidden}` explicitly; configuring
  `use LetMe.Policy, error: :forbidden` is NOT applicable (that's a different library).
  If a future `Bodyguard.permit!/5` raise path is needed, set `Bodyguard.NotAuthorizedError`
  options explicitly at the call site.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Scope and Requirements
- `.planning/ROADMAP.md` — Phase 1 goal, success criteria, `:site` and `{:board, board_id}`
  scope shapes, and no-API-rewrite invariant.
- `.planning/REQUIREMENTS.md` — MODR-02 (scope-filtered visibility) and MODR-03
  (actor-aware enforcement, not screen-only checks).
- `.planning/PROJECT.md` — terminal-first constraints; "Authorization" constraint block
  calling for future board-scoped moderator support.

### Prior Phase Continuity
- `.planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md` — D-02
  explicitly defers real actor-aware authz to Phase 1; ShellVisibility is a visibility
  helper only.
- `.planning/phases/00-screen-shells-and-shared-surface-primitives/00-RESEARCH.md` — Pitfall 3
  / T-00-02 ("menu visibility is not authorization") — this phase closes that.
- `.planning/phases/01-authorization-and-scope-backbone/01-ASSUMPTIONS-REVIEW.md` — the
  assumptions file this CONTEXT supersedes; keep for audit trail only.

### Codebase Conventions
- `.planning/codebase/CONVENTIONS.md` — tagged-tuple error conventions, `?`-suffix
  predicates, one-module-per-file, atom allowlist pattern, `use Foglet.Schema` boilerplate.
- `.planning/codebase/CONCERNS.md` §"Authorization gap" (lines ~212-218) — documents the
  exact problem this phase exists to fix (`Threads.lock_thread/1`, `Posts.delete_post/2`
  have no authorization layer).
- `.planning/codebase/ARCHITECTURE.md` — context-module layer, session/role plumbing,
  `FogletBbs.Application` supervision tree (no new supervised processes needed for this
  phase).

### Architecture Docs
- `docs/ARCHITECTURE.md` — module-boundary split between `Foglet.*` (domain/TUI) and
  `FogletBbs.*` (Phoenix infra); context-module conventions.
- `docs/DATA_MODEL.md` — User schema authoritative field list (to confirm `role`,
  `status`, `deleted_at` semantics for D-24).

### External Library Documentation
- `hexdocs.pm/bodyguard/readme.html` — `Bodyguard.permit/4`, `Bodyguard.permit?/4`,
  `Bodyguard.permit!/5`, `Bodyguard.scope/4`. Read this before implementing the callback
  or changing how domain functions invoke authorization.
- `hexdocs.pm/bodyguard/Bodyguard.Policy.html` — the `@callback authorize(action, user, params)`
  contract, return-value coercion rules, and the default `:unauthorized` reason (which we
  override by returning `{:error, :forbidden}` explicitly from every callback clause).

### Relevant Source Files
- `lib/foglet_bbs/accounts/user.ex` — `@valid_roles [:user, :mod, :sysop]`,
  `@valid_statuses [:active, :pending, :suspended]`.
- `lib/foglet_bbs/accounts.ex` — `authenticate_by_password/2` precedent for the
  nil/deleted/suspended/pending rejection pattern (D-24).
- `lib/foglet_bbs/sessions/session.ex` — session-layer role snapshot (to document why
  D-05 prefers `User.t()` over this).
- `lib/foglet_bbs/tui/app.ex` — `current_user: User.t() | nil` contract.
- `lib/foglet_bbs/tui/screens/shell_visibility.ex` — existing visibility-only helper to
  leave in place; D-18 pairs it with `Bodyguard.permit?/4` for advisory render decisions
  rather than replacing it.
- `lib/foglet_bbs/tui/screens/shared/invites_surface.ex` — policy matrix to mirror in
  D-26 test structure; its final `def visible?(_, _), do: false` clause is the precedent
  for D-13's safe-default catch-all.
- `lib/foglet_bbs/threads.ex`, `lib/foglet_bbs/posts.ex`, `lib/foglet_bbs/boards.ex` —
  current signatures of functions that will either change (Boards/Config/Accounts in
  Phase 1) or have action atoms reserved for Phase 8 (Threads, Posts).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`Foglet.TUI.Screens.ShellVisibility`** — stays in place as a rendering-only predicate.
  Its call sites (MainMenu, Moderation/Sysop defensive re-check) do not change. The TUI
  may adopt `Bodyguard.permit?/4` in addition when a richer render decision is needed.
- **`Foglet.TUI.Screens.Shared.InvitesSurface.visible?/2`** — existing visibility policy
  matrix. Phase 1 mirrors its shape (function-clause matrix with safe-default catch-all)
  for the authorization matrix, and its test file becomes the template for
  `test/foglet_bbs/authorization_test.exs`.
- **`Foglet.Accounts.authenticate_by_password/2`** — precedent for the nil/deleted
  rejection pattern used in D-24.
- **`FogletBbs.DataCase`** — existing test support module the matrix tests use.

### Established Patterns
- **Context-module layout:** `Foglet.Authorization` at `lib/foglet_bbs/authorization.ex`,
  one module per file, `@moduledoc` required, public functions carry `@spec`. Matches
  `Foglet.Accounts`, `Foglet.Config`, `Foglet.Boards` structure exactly.
- **Tagged-tuple errors:** `:ok | {:error, :forbidden}` reuses the `{:error, atom()}`
  convention. No new tuple shape invented.
- **Atom allowlists:** `@valid_roles`, `@valid_statuses`, `Config.Schema` all use
  compile-time atom lists with validation at the edge. The action allowlist follows the
  same pattern.
- **`?`-suffix predicates:** `Bodyguard.permit?/4` naturally follows the
  `Credo.Check.Readability.PredicateFunctionNames` convention already enforced in this
  codebase — no hand-rolled `can?/3` is introduced because the boolean wrapper is
  provided by Bodyguard.
- **Defensive re-checks:** Moderation/Sysop screens already defensively re-check their
  own visibility in `render/1` (see Phase 0 D-02). `Bodyguard.permit?/4` can be used there
  too without changing the render contract.

### Integration Points
- **`Foglet.Config.put!/3`** — Phase 1 adds an `actor` argument (or requires callers to
  pre-authorize); current callers pass an `updated_by_id` so the actor is already flowing.
- **`Foglet.Boards.create_board` / `update_board` / `archive_board`** — new signatures
  take an actor first arg. Category CRUD is new in Phase 2 and will be born with the
  actor-first signature.
- **`Foglet.Accounts.generate_invite` / `revoke_invite`** — new functions in Phase 3;
  born guarded.
- **`Foglet.Oneliners.hide/...`** — new context introduced in Phase 7 (oneliners) and
  extended in Phase 8 (hide); the hide function is born guarded.
- **TUI shell screens** — Moderation/Sysop may optionally adopt `Bodyguard.permit?/4` for
  keybar and tab-content rendering decisions. This is advisory (per D-18), not required
  for Phase 1 success criteria.
- **Mix tasks (`mix foglet.user.promote`)** — future change: when the task is revisited,
  `Accounts.update_role/2` should gain the actor-first signature. Out of Phase 1 scope
  but the action atom `:promote_user` could be added to the allowlist here if the planner
  wants — otherwise deferred until a real caller exists.

</code_context>

<specifics>
## Specific Ideas

- Multi-board moderator assignment is a confirmed product invariant for v2 (MODR-06). The
  seam design must keep this supported — see D-09 and D-10. The discussion question from
  the user ("a moderator will be able to be assigned moderator to more than one board,
  yes?") is answered affirmatively and encoded as the `scopes_for/2` list-return contract.
- The existing `InvitesSurface.visible?/2` four-clause policy matrix is a good structural
  template for the matrix test in D-26 — its shape is exactly the kind of table-driven
  layout the authorization matrix needs.

</specifics>

<deferred>
## Deferred Ideas

### Deferred to Phase 8 (Moderation Workspace Population and Scope-Aware Operations)
- Adding actor-first signature changes + `Bodyguard.permit/4` calls to pre-existing
  operator functions: `Threads.lock_thread`, `unlock_thread`, `sticky_thread`,
  `unsticky_thread`, `move_thread`, `delete_thread`, `Posts.delete_post`, `Posts.edit_post`
  when editor ≠ author (D-20). Action atoms for these are defined in D-12 now so Phase 8
  is a mechanical "add the guard line" diff.
- Scope-filtered list query helpers (`Threads.list_for_moderation/2`,
  `Posts.list_for_moderation/2`, etc.). No v1.1 caller exists (D-22).

### Deferred to v2 / MODR-06
- `board_moderators` join table schema + many-to-many relation on `%User{}` /
  `%Board{}`. The `scopes_for/2` function's implementation change to read from this
  table. The contract is frozen now (D-23).
- Board-scoped moderator assignment UI in the Sysop workspace.

### Deferred to a future conversation
- Should `mix foglet.user.promote` and related Mix tasks also go through the policy
  (`:promote_user` action)? Currently sysop-Mix-tasks are a trusted operator path by
  design. Revisit if a non-sysop-executable administrative Mix task emerges.

### Reviewed Todos (not folded)
None — no open todos matched Phase 1 scope (verified via `gsd-sdk query todo.match-phase 1`).

</deferred>

---

*Phase: 01-authorization-and-scope-backbone*
*Context gathered: 2026-04-23*
*Mode: assumptions*
