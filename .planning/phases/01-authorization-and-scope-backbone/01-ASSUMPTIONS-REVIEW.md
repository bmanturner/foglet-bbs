# Phase 1: Authorization and Scope Backbone — Assumptions Review

> **Purpose:** Review these assumptions, mark any you want to correct, then let me know.
> I'll turn the confirmed set into `01-CONTEXT.md` (locked decisions for the planner).
>
> **How to use:** For each area below, either accept the assumption or write a correction
> inline under **My correction:**. When you're done, say "looks good" or send the file back.

**Phase goal (ROADMAP.md):** Operator actions are gated by actor-aware, scope-aware policy
before sysop and moderation surfaces gain real behavior.

**Requirements:** MODR-02, MODR-03
**Success Criteria:**
1. Operator actions enforced through actor-aware authorization, not screen-only visibility.
2. Authz seam supports at least `:site` and `{:board, board_id}` scopes.
3. Unauthorized operator actions return explicit forbidden results, not silent success.

**UI hint:** no — this is plumbing. Phase 8 wires real mod actions on top.

---

## 1. Policy Module Location & Shape

**Confidence:** Likely

**Assumption:** A single context-style module `Foglet.Authorization` at
`lib/foglet_bbs/authorization.ex`. Public API:
- `authorize(actor, action, scope) :: :ok | {:error, :forbidden}`
- `can?(actor, action, scope) :: boolean()` (boolean companion for view-layer reuse)

No per-action predicates (`can_lock_thread?/2`) — every call routes through `authorize/3`
with an action atom.

**Why this way:**
- Existing contexts follow this shape: `Foglet.Accounts`, `Foglet.Boards`, `Foglet.Config`.
- No authz library in `mix.exs` (no `bodyguard`, `canada`, `canary`).
- Phase 0's `ShellVisibility` already split visibility from authorization deliberately.

**If wrong:** Per-action predicates force every callsite to know the action-name mapping —
a central `authorize/3` collapses dispatch into one table.

**My correction:** _(leave blank to accept)_

---

## 2. Actor Representation

**Confidence:** Confident

**Assumption:** Actor is `Foglet.Accounts.User.t() | nil`. `nil` means guest and falls
through to forbidden. No separate `Actor` struct.

**Why this way:**
- `Foglet.TUI.App` already carries `current_user: User.t() | nil`.
- `Foglet.Sessions.Session.role` is a denormalized snapshot that can drift from
  `User.role` after a role change — using the live `%User{}` avoids that drift.
- Domain functions already accept raw `%User{}` where needed.

**If wrong:** A `%{user_id:, role:}` map matches `Session` state but loses type safety and
reintroduces drift risk.

**My correction:** _(leave blank to accept)_

---

## 3. Action Representation

**Confidence:** Likely

**Assumption:** Actions are flat atoms in a central allowlist inside `Foglet.Authorization`:

```
:lock_thread, :unlock_thread, :sticky_thread, :unsticky_thread, :move_thread,
:delete_thread, :delete_post, :edit_post_as_mod, :hide_oneliner,
:create_board, :update_board, :archive_board,
:create_category, :update_category, :archive_category,
:edit_config, :generate_invite, :revoke_invite
```

Unknown action atoms return `{:error, :forbidden}` + `Logger.warning` (safe default, not raise).

**Why this way:**
- Codebase idiom is flat atoms for enumerated domain values: `@valid_roles`,
  `@valid_statuses`, `Foglet.TUI.Screens.Domain.@supported_keys`.
- `InvitesSurface.visible?/2` already uses a safe-default catch-all.

**If wrong:** Alternatives are namespaced atoms (`:"threads.lock"`) or grouped tuples
(`{:threads, :lock}`). Same action count, different ergonomics.

**My correction:** _(leave blank to accept)_

---

## 4. Scope Representation

**Confidence:** Confident

**Assumption:** Scope is a tagged tuple, passed as the third argument:

```elixir
@type scope :: :site | {:board, Ecto.UUID.t()}
```

The **caller synthesizes** scope from the operation's data. Example:

```elixir
Foglet.Authorization.authorize(user, :lock_thread, {:board, thread.board_id})
```

Each domain module gets a small `scope_for/1` helper for consistency:

```elixir
Foglet.Threads.scope_for(thread) #=> {:board, "..."}
Foglet.Posts.scope_for(post)     #=> {:board, "..."}
Foglet.Boards.scope_for(board)   #=> {:board, board.id}
```

Phase 1 does NOT teach the policy to DB-resolve resources.

**Why this way:**
- ROADMAP success criterion locks `:site` and `{:board, board_id}` shapes exactly.
- Tagged tuples match existing codebase patterns (`{:via, Registry, ...}`, PubSub event tuples).
- Pure policy mirrors how `ShellVisibility.invites_visible?/2` takes a pre-resolved
  `session_context` instead of re-reading config.

**If wrong:** Passing a resource (`authorize(user, :lock_thread, thread)`) makes the policy
impure and harder to test. A `%Scope{}` struct adds ceremony for only two cases today.

**My correction:** _(leave blank to accept)_

---

## 5. Return Contract

**Confidence:** Confident

**Assumption:**
- Success: `:ok`
- Failure: `{:error, :forbidden}`
- `can?/3` wraps for boolean use (`:ok` → `true`, `{:error, :forbidden}` → `false`)
- Domain functions that gain a guard return `{:error, :forbidden}` in addition to their
  existing error tuples
- Pure — no raises, no side effects

**Why this way:**
- `.planning/codebase/CONVENTIONS.md` documents `{:error, :not_found}`,
  `{:error, :invalid_credentials}` — `:forbidden` slots in without a new shape.
- `?`-suffix predicates are Credo-enforced.
- Not raising respects the "bang = failure is programming error" convention; an
  unauthorized request is a runtime condition, not a bug.

**If wrong:** Richer failure `{:error, {:forbidden, action, scope}}` could feed Phase 8's
future audit log. Additive change — reversible.

**My correction:** _(leave blank to accept)_

---

## 6. Enforcement Surface (biggest design call)

**Confidence:** Likely

**Assumption:** The domain context function is the **real trust boundary**.

Each guarded domain function takes the actor as its first argument:
```elixir
# Before:
Threads.lock_thread(thread)
Posts.delete_post(post, reason)
Boards.create_board(category_id, attrs)

# After:
Threads.lock_thread(actor, thread)
Posts.delete_post(actor, post, reason)
Boards.create_board(actor, category_id, attrs)
```

The domain function itself calls `Foglet.Authorization.authorize/3` and returns
`{:error, :forbidden}` on reject.

The TUI may **also** call `can?/3` for advisory rendering (grey out keybars, hide menu
entries), but the domain check is authoritative. Defense-in-depth.

**Why this way:**
- `.planning/codebase/CONCERNS.md:212-218` flagged the exact problem: "`Threads.lock_thread/1`,
  `Posts.delete_post/2` have no authorization layer — they operate on whoever calls them."
- TUI-only authz leaves `mix foglet.user.promote`, tests, and future callers bypassed.
- Context-only means the UI can't grey out disallowed actions without duplicating predicates.

**If wrong:** TUI-only is faster to ship but leaves non-TUI callers silently bypassing authz.

**My correction:** _(leave blank to accept)_

---

## 7. Which Operations Get Guarded in v1.1 ⚠️ MOST WORTH CONFIRMING

**Confidence:** Unclear — this is a **scope-boundary call only you can make**.

### Option (a) — **Guard only operations with v1.1 callers** (recommended default)

Phase 1 guards ONLY:
- `Config.put!` (used in Phase 2)
- `Boards.create_board`, `update_board`, `archive_board` + Category CRUD (used in Phase 2)
- `Accounts.generate_invite`, `revoke_invite` — new in Phase 3
- `Oneliners.hide` — new in Phase 8

The pre-existing thread/post ops (`lock_thread`, `sticky_thread`, `move_thread`,
`delete_thread`, `delete_post`, etc.) are **NOT** signature-changed in Phase 1. The
action atoms get defined now in the Authorization allowlist; Phase 8 adds the actual
`authorize/3` call when the Moderation workspace wires real callers.

**Pros:** Smaller Phase 1 diff, tighter scope, no speculative signature churn.
**Cons:** The thread/post ops stay unguarded between now and Phase 8 — but they have no
TUI callers today either, so in practice nothing new opens up.

### Option (b) — **Defensive backfill: guard every operator action now**

Phase 1 also changes signatures on all pre-existing thread/post operator functions
(lock/unlock/sticky/unsticky/move/delete-thread, delete-post, edit-post-as-mod). Adds
~6 signature changes + corresponding test updates. Phase 8 only wires UI to already-guarded
functions.

**Pros:** Closes the latent risk from CONCERNS.md immediately. Phase 8 is a pure UI phase.
**Cons:** Larger Phase 1 diff; test updates on functions that no live caller invokes yet.

**My choice:** _( a / b )_

**My correction / extra notes:**

---

## 8. Data-Visibility vs Action Authorization (MODR-02)

**Confidence:** Likely

**Assumption:** Phase 1 introduces `Foglet.Authorization.scopes_for(actor, action) :: [scope]`
returning the list of scopes an actor may operate over.

In v1.1 it returns `[:site]` for mods and sysops (since no board-scoped mods exist yet).
Implementation swaps later — v2 will consult a future `board_moderators` join table
without changing the call site.

Phase 1 does **NOT** build scope-filtered list queries (e.g., `Threads.list_for_moderation/2`).
Those belong in Phase 8 when a real caller exists.

**Why this way:**
- MODR-02 has no visible effect in v1.1 (only site-scope mods) but the seam must not
  paint Phase 8 into a corner.
- No `board_moderators` schema exists yet — `Foglet.Boards.Board` has only a `postable_by`
  enum, no moderator join.
- Mirrors Phase 0's D-07 pattern (scaffold shared INVITES surface now, activate later).

**If wrong:** Preemptive scope-filtered helpers without callers drift into dead code.

**My correction:** _(leave blank to accept)_

---

## 9. Guest / Suspended / Deleted User Handling

**Confidence:** Likely

**Assumption:** `authorize/3` explicitly rejects these at the top, before role-based
dispatch:
- `nil` (guest — no session or unauthenticated)
- `%User{deleted_at: dt}` when `dt != nil`
- `%User{status: :suspended}`
- `%User{status: :pending}`

**Why this way:**
- `Accounts.authenticate_by_password/2` already gates on `is_nil(user.deleted_at)`.
- A sysop-suspended user with a still-active session must not retain operator powers
  until disconnect — policy is the last line of defense.
- Explicit nil/deleted/suspended branches at the top of `authorize/3` are cheap and match
  the defensive `cond` pattern in `authenticate_by_password/2`.

**If wrong:** Pure role-based matching is shorter; the Session layer would need to
force-disconnect on suspend to close the stale-session window. Belt-and-suspenders at the
policy layer is cheap insurance.

**My correction:** _(leave blank to accept)_

---

## 10. Test Strategy

**Confidence:** Confident

**Assumption:**
- `test/foglet_bbs/authorization_test.exs` holds the **policy matrix** — table-driven
  tests enumerating `(role, status, action, scope) → :ok | {:error, :forbidden}`.
- Each domain function that gains an actor arg gets a small "forbidden path" test in its
  existing context test file (e.g., `test/foglet_bbs/threads/threads_test.exs`).
- Guest/nil/suspended paths live in the matrix test, not scattered across domain tests.
- `async: true`, `FogletBbs.DataCase`, mirroring `accounts_test.exs`.

**Why this way:**
- `test/foglet_bbs/` mirrors `lib/foglet_bbs/` one-to-one per CONVENTIONS.md.
- Matrix tests are already an idiom — `InvitesSurface.visible?/2`'s four-clause policy
  matrix is begging for a matching table test.
- Co-located forbidden-path tests keep regression pressure where the regression would occur.

**If wrong:** Dropping either the matrix or the per-context tests loses one axis of
regression coverage.

**My correction:** _(leave blank to accept)_

---

## Summary of what you need to decide

| # | Area | Confidence | Your action |
|---|------|------------|-------------|
| 1 | Policy module shape | Likely | Accept or pick per-action predicates |
| 2 | Actor = `%User{}` | Confident | Accept or pick session-map |
| 3 | Actions = flat atoms | Likely | Accept or pick namespaced |
| 4 | Scope = tagged tuple, caller-synthesized | Confident | Accept or pick resource-in-policy |
| 5 | Return `:ok / {:error, :forbidden}` | Confident | Accept or pick richer failure |
| 6 | Enforce in domain (defense-in-depth) | Likely | Accept or pick TUI-only |
| **7** | **v1.1 guard scope** | **Unclear** | **Pick (a) or (b)** |
| 8 | `scopes_for/2` seam, no list helpers yet | Likely | Accept or pick preemptive helpers |
| 9 | Policy rejects guest/deleted/suspended/pending | Likely | Accept or pick role-only |
| 10 | Matrix test + per-context forbidden tests | Confident | Accept or pick single-layer |

**Next:** Edit this file with your corrections (or just tell me "all accepted, option (a)
for #7") and I'll write `01-CONTEXT.md` with the final decisions.
