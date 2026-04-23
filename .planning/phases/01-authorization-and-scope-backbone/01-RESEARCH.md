# Phase 01: Authorization and Scope Backbone - Research

**Researched:** 2026-04-23
**Domain:** Elixir/Phoenix actor-aware, scope-aware authorization policy seam
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01:** `Foglet.Authorization` at `lib/foglet_bbs/authorization.ex`. Top-level `Foglet.*` context, not nested.

**D-02:** Public API:
- `authorize(actor, action, scope) :: :ok | {:error, :forbidden}`
- `can?(actor, action, scope) :: boolean()`

No per-action predicates. Every call routes through `authorize/3` / `can?/3`.

**D-03:** No `can_lock_thread?/2`-style helpers.

**D-04:** Actor is `Foglet.Accounts.User.t() | nil`. `nil` = guest → `{:error, :forbidden}`.

**D-05:** Callers pass the live `%User{}` from `Foglet.TUI.App.current_user`, not a `Session.role` snapshot.

**D-06:** Scope = `:site | {:board, Ecto.UUID.t()}`.

**D-07:** Caller synthesizes scope from operation data; policy does not DB-resolve resources.

**D-08:** Per-domain `scope_for/1` helpers:
- `Foglet.Threads.scope_for(thread) :: {:board, board_id}`
- `Foglet.Posts.scope_for(post) :: {:board, board_id}`
- `Foglet.Boards.scope_for(board) :: {:board, board.id}`
- Sysop ops use `:site` directly.

**D-09:** `scopes_for(actor, action) :: [scope]` — returns a list (multi-board moderator invariant).

**D-10:** Future `board_moderators` join table (v2); seam must not require API change.

**D-11:** Actions are flat atoms in a central allowlist.

**D-12:** Phase 1 allowlist includes ALL eventual actions (thread/post atoms defined now, guards added in Phase 8):
```
:lock_thread, :unlock_thread, :sticky_thread, :unsticky_thread, :move_thread, :delete_thread,
:delete_post, :edit_post_as_mod, :hide_oneliner,
:create_board, :update_board, :archive_board,
:create_category, :update_category, :archive_category,
:edit_config, :generate_invite, :revoke_invite
```

**D-13:** Unknown action atom → `{:error, :forbidden}` + `Logger.warning`. No raise.

**D-14:** `:ok` | `{:error, :forbidden}`. Pure — no raises, no side effects.

**D-15:** Guarded domain functions return `{:error, :forbidden}` alongside existing error tuples.

**D-16:** Guards MUST NOT raise. Forbidden is a runtime condition, not a programming error.

**D-17:** Domain context function is the real trust boundary. Every guarded function: actor first arg → `authorize/3` before side effects → return tuple on reject.

**D-18:** TUI may call `can?/3` for advisory rendering (defense-in-depth). Domain check is authoritative.

**D-19:** Phase 1 adds `authorize/3` calls ONLY to functions with v1.1 callers:
- `Foglet.Config.put!/3` → gains actor as first argument (currently `put!(key, value, updated_by_id \\ nil)`)
- `Foglet.Boards.create_board/update_board/archive_board` — new `actor` first arg
- `Foglet.Categories.create_category/update_category/archive_category` — new (Phase 2)
- `Foglet.Accounts.generate_invite/revoke_invite` — new (Phase 3)
- `Foglet.Oneliners.hide/...` — new (Phase 8)

**D-20:** Pre-existing thread/post operator functions NOT signature-changed in Phase 1. Action atoms exist in allowlist; `authorize/3` call added in Phase 8.

**D-21:** `scopes_for/2` returns `[:site]` for both `:sysop` and `:mod` in v1.1 (no board-scoped mods yet). `[]` for all others.

**D-22:** Phase 1 does NOT build scope-filtered list query helpers. Deferred to Phase 8.

**D-23:** `scopes_for/2` call signature and return shape are frozen. v2 join-table rewrite must not change the API.

**D-24:** `authorize/3` rejects at the top, before role dispatch:
- `nil` (guest)
- `%User{deleted_at: dt}` when `dt != nil`
- `%User{status: :suspended}`
- `%User{status: :pending}`

**D-25:** Stale `current_user` with an active session must not retain operator powers. Policy is the last line of defense.

**D-26:** `test/foglet_bbs/authorization_test.exs` — full `(role, status, action, scope) → result` matrix.

**D-27:** Every domain function gaining an actor arg gets a "forbidden path" test in its existing context test file. One forbidden test per guarded function.

**D-28:** Guest/nil/deleted/suspended/pending paths live in the matrix test only.

### Claude's Discretion

- Exact naming of action atoms if D-12 needs to grow or split during planning.
- Exact return shape of `scopes_for/2` for guest/no-operator actors (contract: empty list).
- Whether `scope_for/1` helpers live in each domain module or a single `Foglet.Authorization.Scope` helper (prefer per-domain to match `Foglet.*` conventions).
- Exact `Logger.warning` message format for unknown action atoms.

### Deferred Ideas (OUT OF SCOPE)

- Adding actor-first signature changes + `authorize/3` to `Threads.lock_thread`, `unlock_thread`, `sticky_thread`, `unsticky_thread`, `move_thread`, `delete_thread`, `Posts.delete_post`, `Posts.edit_post` (deferred to Phase 8).
- Scope-filtered list query helpers (`Threads.list_for_moderation/2`, etc.) — Phase 8.
- `board_moderators` join table + many-to-many relation on `%User{}`/`%Board{}` — v2/MODR-06.
- `mix foglet.user.promote` going through the policy — future conversation.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MODR-02 | Moderation workspace only shows actions and data for scopes the current operator is authorized to manage. | `scopes_for(actor, action)` seam (D-21/D-23) provides the scope list that Phase 8's workspace uses for data-visibility filtering. Phase 1 introduces the function; filtering helpers come in Phase 8. |
| MODR-03 | Moderation actions exposed in v1.1 are enforced through actor-aware authorization rather than screen-only visibility checks. | `Foglet.Authorization.authorize/3` embedded in domain context functions (D-17) is the direct implementation. The TUI advisory layer (`can?/3`) and `ShellVisibility` remain in place but are no longer the enforcement layer. |
</phase_requirements>

---

## Summary

Phase 1 introduces a centralized, pure authorization policy module (`Foglet.Authorization`) that becomes the real trust boundary for all operator operations. The prior state — documented in `.planning/codebase/CONCERNS.md` lines 212–218 — is that domain functions like `Threads.lock_thread/1` and `Posts.delete_post/2` have no authorization layer and operate on whoever calls them. Phase 1 closes that gap for the subset of functions that will have live TUI callers by v1.1, and pre-defines the action atom allowlist for the remainder.

The design is entirely hand-rolled — no authorization library is added as a dependency. This is the correct call for this codebase: the decisions are already locked (D-01 through D-28), the required API is tiny (`authorize/3`, `can?/3`, `scopes_for/2`), and the existing codebase has all the structural precedents needed (tagged-tuple returns, atom allowlists, function-clause policy matrices in `InvitesSurface.visible?/2`). External libraries like Bodyguard (last released March 2024, v2.4.3) and let_me (active, v2.0.0 released March 2026) provide no benefit over a 100-line hand-rolled module when the decision space is fully specified in CONTEXT.md.

The key technical insight for implementation: the policy matrix is a `cond` or function-clause dispatch inside `authorize/3` that first rejects invalid actors (nil/deleted/suspended/pending) and then pattern-matches on `{role, action, scope}`. The `scopes_for/2` function returns a list from day one even though v1.1 mods are always site-scope — this preserves the API contract that v2's board_moderators join table will satisfy without caller changes.

**Primary recommendation:** Build `Foglet.Authorization` as a single module with a compile-time `@valid_actions` module attribute (atom list), a top-of-`authorize/3` guard clause rejecting invalid actors, and function-clause-based role dispatch matching on `{role, action, scope}`. Use `InvitesSurface.visible?/2`'s four-clause safe-default structure as the template. Wire `scope_for/1` helpers as single-line delegators in their respective domain modules.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Authorization enforcement | Domain (context functions) | — | All callers (TUI, Mix tasks, future API, tests) go through context functions. Policy must live where all call paths converge. |
| Authorization advisory (UI hide/grey) | TUI layer (`can?/3`) | — | Rendering only; domain check is authoritative (D-17/D-18). |
| Actor resolution | TUI / Session layer | — | `Foglet.TUI.App.current_user` holds the live `%User{}`. Policy receives it; does not fetch it. |
| Scope synthesis | Call site (domain module helpers) | — | `scope_for/1` in each domain module constructs the tagged tuple from the resource. Policy is pure; no DB access. |
| Scope listing (data visibility) | Domain (`scopes_for/2`) | — | Returns the list of scopes an actor can see; Phase 8 uses this to filter queries. |
| Action atom definition | `Foglet.Authorization` | — | Centralized allowlist — single source of truth, compile-time validated. |

---

## Standard Stack

### Core

No new dependencies. This phase is entirely in-process Elixir.

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| (none) | — | No auth library added | Design fits cleanly in ~100 lines; external libraries add indirection with no benefit given fully-specified decisions (D-01 to D-28). |

[VERIFIED: mix.exs — no bodyguard, canada, let_me, canary, or permit in current deps]

### Libraries Evaluated and Rejected

| Library | Hex Version | Last Release | Verdict |
|---------|------------|--------------|---------|
| bodyguard | 2.4.3 | March 2024 [VERIFIED: hex.pm] | No update in 13+ months. Would add `@behaviour Bodyguard.Policy` indirection; no benefit for a fixed 2-function API. |
| let_me | 2.0.0 | March 2026 [VERIFIED: hex.pm] | Actively maintained. DSL approach adds learning curve. Return type `{:error, :unauthorized}` conflicts with locked D-14 (`:forbidden`). Would require wrapping. |
| canada | — | Abandoned [ASSUMED] | Not actively maintained. Predicate-only model conflicts with D-03. |
| permit | — | Active [CITED: curiosum.com/blog/authorization-access-control-elixirconf] | Full ABAC system; heavyweight for a 3-role, 2-scope model. Adds Permit.Ecto/Phoenix deps. |

### Supporting Tools (already in project)

| Library | Purpose | Usage in this phase |
|---------|---------|---------------------|
| ExUnit | Testing | Matrix tests, forbidden-path tests (D-26/D-27) |
| FogletBbs.DataCase | Test setup | `async: true` for pure policy tests |

---

## Architecture Patterns

### System Architecture Diagram

```
  TUI Layer (advisory only)          Domain Layer (authoritative)
  ┌──────────────────────┐           ┌─────────────────────────────────────────┐
  │  Moderation / Sysop  │           │  Foglet.Boards.create_board(actor, ...) │
  │  Shell renders tabs  │           │    1. authorize(actor, :create_board,   │
  │  using can?/3        │──────────▶│          :site)                         │
  │  for grey-out only   │           │    2. If :ok → Repo.insert(...)         │
  └──────────────────────┘           │    3. If {:error, :forbidden} → return  │
                │                    └───────────────┬─────────────────────────┘
                │                                    │
                ▼                                    ▼
  ┌──────────────────────┐           ┌─────────────────────────────────────────┐
  │ Foglet.Authorization │◀──────────│ Foglet.Authorization.authorize/3        │
  │                      │           │                                         │
  │  @valid_actions [    │           │  Guard 1: nil/deleted/suspended/pending │
  │    :create_board,    │           │  → {:error, :forbidden}                 │
  │    :edit_config,     │           │                                         │
  │    :lock_thread, ... │           │  Dispatch: {role, action, scope}        │
  │  ]                   │           │  :sysop, _, :site → :ok                 │
  │                      │           │  :sysop, _, {:board, _} → :ok           │
  │  authorize/3         │           │  :mod, :sysop_action, _ → {:error, ...} │
  │  can?/3              │           │  :mod, :mod_action, :site → :ok         │
  │  scopes_for/2        │           │  _, _, _ → {:error, :forbidden}         │
  └──────────────────────┘           └─────────────────────────────────────────┘
                                                     │
                                          ┌──────────┴──────────┐
                                          │  scope_for/1        │
                                          │  (per domain module)│
                                          │                     │
                                          │  Threads.scope_for  │
                                          │  Posts.scope_for    │
                                          │  Boards.scope_for   │
                                          └─────────────────────┘
```

### Recommended Project Structure

```
lib/foglet_bbs/
├── authorization.ex          # NEW: Foglet.Authorization — authorize/3, can?/3, scopes_for/2
├── boards.ex                 # CHANGE: create_board/update_board/archive_board gain actor first arg
│                             #         + scope_for/1 helper added
├── config.ex                 # CHANGE: put!/3 gains actor first arg (currently put!(key, value, updated_by_id))
├── threads.ex                # CHANGE: scope_for/1 helper added (no signature change to existing ops)
└── posts.ex                  # CHANGE: scope_for/1 helper added (no signature change to existing ops)

test/foglet_bbs/
├── authorization_test.exs    # NEW: full policy matrix
├── boards/boards_test.exs    # CHANGE: add forbidden-path test for guarded functions
└── config/config_test.exs    # CHANGE: add forbidden-path test for Config.put!/3 with actor
```

### Pattern 1: The Authorization Module Shape

**What:** A single module containing the full policy matrix as function clauses, with a compile-time action allowlist.

**When to use:** Always — this is the only authorization module.

**Example:**
```elixir
# Source: InvitesSurface.visible?/2 in lib/foglet_bbs/tui/screens/shared/invites_surface.ex
# (structural template — adapting the 4-clause safe-default function-clause matrix)

defmodule Foglet.Authorization do
  @moduledoc """
  Actor-aware, scope-aware authorization policy for operator actions.

  The domain context function is the real trust boundary (D-17).
  The TUI may call can?/3 for advisory rendering only (D-18).
  See .planning/phases/01-authorization-and-scope-backbone/01-CONTEXT.md.
  """

  alias Foglet.Accounts.User

  # ---------- Action Allowlist ----------

  @valid_actions [
    # Thread operator actions (guards added in Phase 8 per D-20)
    :lock_thread, :unlock_thread, :sticky_thread, :unsticky_thread,
    :move_thread, :delete_thread,
    # Post operator actions (guards added in Phase 8 per D-20)
    :delete_post, :edit_post_as_mod,
    # Oneliner moderation (guard added in Phase 8, MODR-05)
    :hide_oneliner,
    # Board/Category lifecycle (guarded now — Phase 2 is a live caller)
    :create_board, :update_board, :archive_board,
    :create_category, :update_category, :archive_category,
    # Sysop config (guarded now — Phase 2 is a live caller)
    :edit_config,
    # Invite ops (guarded now — Phase 3 is a live caller)
    :generate_invite, :revoke_invite
  ]

  @type actor :: User.t() | nil
  @type action :: atom()
  @type scope :: :site | {:board, Ecto.UUID.t()}

  # ---------- Public API ----------

  @doc """
  Authorize an actor to perform an action in a scope.
  Returns :ok on success, {:error, :forbidden} on rejection.
  Pure — no side effects, no DB access.
  """
  @spec authorize(actor(), action(), scope()) :: :ok | {:error, :forbidden}

  # Guard 1: guest (D-24)
  def authorize(nil, _action, _scope), do: {:error, :forbidden}

  # Guard 2: deleted user (D-24)
  def authorize(%User{deleted_at: deleted_at}, _action, _scope)
      when not is_nil(deleted_at),
      do: {:error, :forbidden}

  # Guard 3: suspended user (D-24)
  def authorize(%User{status: :suspended}, _action, _scope), do: {:error, :forbidden}

  # Guard 4: pending user (D-24)
  def authorize(%User{status: :pending}, _action, _scope), do: {:error, :forbidden}

  # Unknown action: safe default (D-13)
  def authorize(_actor, action, _scope) when action not in @valid_actions do
    require Logger
    Logger.warning("[Foglet.Authorization] Unknown action atom: #{inspect(action)}")
    {:error, :forbidden}
  end

  # Sysop: permitted for all valid actions at any scope
  def authorize(%User{role: :sysop}, _action, _scope), do: :ok

  # Mod: site-scope actions (v1.1 all mods are site-scope, D-21)
  def authorize(%User{role: :mod}, action, :site)
      when action in [:create_board, :update_board, :archive_board,
                      :create_category, :update_category, :archive_category,
                      :generate_invite, :revoke_invite, :hide_oneliner,
                      :lock_thread, :unlock_thread, :sticky_thread,
                      :unsticky_thread, :move_thread, :delete_thread,
                      :delete_post, :edit_post_as_mod],
      do: :ok

  # Mod: board-scope actions (same action set, any board)
  def authorize(%User{role: :mod}, action, {:board, _board_id})
      when action in [:lock_thread, :unlock_thread, :sticky_thread,
                      :unsticky_thread, :move_thread, :delete_thread,
                      :delete_post, :edit_post_as_mod, :hide_oneliner],
      do: :ok

  # Mod: sysop-only actions
  def authorize(%User{role: :mod}, :edit_config, _scope), do: {:error, :forbidden}

  # Default deny (D-13 catch-all mirrors InvitesSurface.visible?/2 final clause)
  def authorize(_actor, _action, _scope), do: {:error, :forbidden}

  @doc """
  Advisory boolean wrapper for view-layer use (D-18).
  Returns true when authorize/3 returns :ok.
  """
  @spec can?(actor(), action(), scope()) :: boolean()
  def can?(actor, action, scope) do
    authorize(actor, action, scope) == :ok
  end

  @doc """
  Returns the list of scopes an actor is authorized to operate over for a
  given action. Returns [] for guests and regular users.

  In v1.1 all mods are site-scope (no board_moderators join table yet).
  v2 rewrites this to query board_moderators without changing the call signature
  or return shape (D-23).
  """
  @spec scopes_for(actor(), action()) :: [scope()]
  def scopes_for(nil, _action), do: []
  def scopes_for(%User{deleted_at: deleted_at}, _action) when not is_nil(deleted_at), do: []
  def scopes_for(%User{status: status}, _action) when status in [:suspended, :pending], do: []
  def scopes_for(%User{role: :sysop}, _action), do: [:site]
  def scopes_for(%User{role: :mod}, _action), do: [:site]
  def scopes_for(_actor, _action), do: []
end
```

### Pattern 2: Domain Function — Actor-First Signature

**What:** Guarded domain context functions take actor as the first argument, call `authorize/3`, and return `{:error, :forbidden}` before any side effect.

**When to use:** Every context function being guarded in Phase 1 (D-19 list).

**Example:**
```elixir
# Boards.create_board — updated signature (D-19)
# Source: pattern from Foglet.Accounts.authenticate_by_password/2 (nil/deleted guard)
# and existing Boards.create_board/2 in lib/foglet_bbs/boards.ex

@doc "Create a board in a category. Actor must be authorized for :create_board at :site scope."
@spec create_board(Foglet.Accounts.User.t() | nil, String.t(), map()) ::
        {:ok, Board.t()} | {:error, Ecto.Changeset.t()} | {:error, :forbidden}
def create_board(actor, category_id, attrs) do
  with :ok <- Foglet.Authorization.authorize(actor, :create_board, :site) do
    # existing insertion logic unchanged
    result =
      %Board{category_id: category_id}
      |> Board.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, board} ->
        case BoardSupervisor.start_board(board.id) do
          {:ok, _pid} -> {:ok, board}
          {:error, {:already_started, _pid}} -> {:ok, board}
          {:error, reason} ->
            require Logger
            Logger.error("Failed to start Board Server for #{board.slug}: #{inspect(reason)}")
            {:ok, board}
        end
      error -> error
    end
  end
end
```

### Pattern 3: scope_for/1 Helper

**What:** One-line delegating functions that synthesize a scope tagged tuple from a domain struct.

**When to use:** At the call site in TUI or context code to avoid hardcoding `{:board, thread.board_id}` inline.

**Example:**
```elixir
# In lib/foglet_bbs/threads.ex
# Source: D-08 from CONTEXT.md

@doc "Returns the authorization scope for a thread — the board it belongs to."
@spec scope_for(Thread.t()) :: {:board, Ecto.UUID.t()}
def scope_for(%Thread{board_id: board_id}), do: {:board, board_id}

# In lib/foglet_bbs/posts.ex
@spec scope_for(Post.t()) :: {:board, Ecto.UUID.t()}
def scope_for(%Post{board_id: board_id}), do: {:board, board_id}

# In lib/foglet_bbs/boards.ex
@spec scope_for(Board.t()) :: {:board, Ecto.UUID.t()}
def scope_for(%Board{id: id}), do: {:board, id}
```

### Pattern 4: Config.put! — Actor Thread-Through

**What:** `Config.put!/3` currently takes `(key, value, updated_by_id \\ nil)`. The actor flows in as the first argument; the existing `updated_by_id` field is set from `actor.id`.

**Why:** This avoids adding a 4th argument. The authorization check gates the write; the `updated_by_id` audit trail is a separate concern already in the signature.

**Example:**
```elixir
# In lib/foglet_bbs/config.ex — new actor-first overload
@spec put!(Foglet.Accounts.User.t() | nil, String.t(), term()) :: :ok
def put!(actor, key, value) when is_binary(key) do
  with :ok <- Foglet.Authorization.authorize(actor, :edit_config, :site) do
    put!(key, value, actor && actor.id)
  end
end

# Original put!/3 remains unchanged for boot-time seed calls
# (seeds use put!(key, value) or put!(key, value, nil) — no actor context)
```

**Note for planner:** `Config.put!/3` currently raises on failure (`Foglet.Config.InvalidValueError`, `Foglet.Config.UnknownKeyError`) — these are not authorization errors. The actor-first variant should return `{:error, :forbidden}` from the `with` short-circuit but let the existing raises propagate for invalid key/value errors. The Phase 2 caller (sysop TUI) must handle both the tuple return and the raise paths, or the actor-first variant should be a new `put/4` that returns a tagged tuple for everything. This is a discretion call for the planner — flag it.

### Pattern 5: Matrix Test Structure

**What:** `for` comprehension over a data table, generating individual ExUnit tests. Each row = one named test case.

**When to use:** The authorization policy matrix (D-26).

**Example:**
```elixir
# test/foglet_bbs/authorization_test.exs
# Source: matrix pattern from https://engineering.legendsoflearning.com/posts/matrix-testing-in-elixir/
# Structural template from InvitesSurface.visible?/2 four-clause matrix

defmodule Foglet.AuthorizationTest do
  use FogletBbs.DataCase, async: true

  alias Foglet.Authorization
  alias Foglet.Accounts.User

  @sysop %User{role: :sysop, status: :active, deleted_at: nil}
  @mod %User{role: :mod, status: :active, deleted_at: nil}
  @user %User{role: :user, status: :active, deleted_at: nil}
  @suspended %User{role: :mod, status: :suspended, deleted_at: nil}
  @pending %User{role: :mod, status: :pending, deleted_at: nil}
  @deleted %User{role: :mod, status: :active, deleted_at: ~U[2026-01-01 00:00:00Z]}

  # Matrix: {label, actor, action, scope, expected_result}
  @matrix [
    # Sysop
    {"sysop :edit_config :site", @sysop, :edit_config, :site, :ok},
    {"sysop :create_board :site", @sysop, :create_board, :site, :ok},
    {"sysop :lock_thread board", @sysop, :lock_thread, {:board, "uuid"}, :ok},
    # Mod — permitted
    {"mod :create_board :site", @mod, :create_board, :site, :ok},
    {"mod :lock_thread :site", @mod, :lock_thread, :site, :ok},
    {"mod :lock_thread board", @mod, :lock_thread, {:board, "uuid"}, :ok},
    # Mod — forbidden (sysop-only actions)
    {"mod :edit_config :site", @mod, :edit_config, :site, {:error, :forbidden}},
    # Regular user — always forbidden
    {"user :create_board :site", @user, :create_board, :site, {:error, :forbidden}},
    # Invalid actor states
    {"nil actor", nil, :create_board, :site, {:error, :forbidden}},
    {"suspended mod", @suspended, :create_board, :site, {:error, :forbidden}},
    {"pending mod", @pending, :create_board, :site, {:error, :forbidden}},
    {"deleted mod", @deleted, :create_board, :site, {:error, :forbidden}},
    # Unknown action
    {"unknown action", @sysop, :nonexistent_action, :site, {:error, :forbidden}},
  ]

  describe "authorize/3 policy matrix" do
    for {label, actor, action, scope, expected} <- @matrix do
      test label do
        assert Authorization.authorize(unquote(Macro.escape(actor)), unquote(action), unquote(Macro.escape(scope))) ==
                 unquote(Macro.escape(expected))
      end
    end
  end

  describe "can?/3 wraps authorize/3" do
    test "returns true when authorize/3 returns :ok" do
      assert Authorization.can?(@sysop, :create_board, :site) == true
    end

    test "returns false when authorize/3 returns {:error, :forbidden}" do
      assert Authorization.can?(nil, :create_board, :site) == false
    end
  end

  describe "scopes_for/2" do
    test "sysop returns [:site]" do
      assert Authorization.scopes_for(@sysop, :create_board) == [:site]
    end

    test "mod returns [:site] in v1.1" do
      assert Authorization.scopes_for(@mod, :lock_thread) == [:site]
    end

    test "regular user returns []" do
      assert Authorization.scopes_for(@user, :create_board) == []
    end

    test "nil actor returns []" do
      assert Authorization.scopes_for(nil, :create_board) == []
    end

    test "suspended mod returns []" do
      assert Authorization.scopes_for(@suspended, :lock_thread) == []
    end
  end
end
```

**Note on `unquote(Macro.escape(...))` for structs:** When the data table contains structs, they must be quoted with `Macro.escape/1` before unquoting into the generated test body. Plain `unquote/1` works for atoms and simple values. [VERIFIED: Elixir compile-time comprehension pattern from https://engineering.legendsoflearning.com/posts/matrix-testing-in-elixir/]

### Anti-Patterns to Avoid

- **TUI-only authorization:** Checking visibility in `ShellVisibility` or `can?/3` without a corresponding domain-level `authorize/3` call. The domain check is authoritative; TUI is advisory. [CITED: hexdocs.pm/phoenix_live_view/security-model.html]
- **Screen-level role checks that duplicate the policy:** Adding `if user.role == :sysop` inside a LiveView/TUI handler instead of routing through `authorize/3`. Creates drift when the policy changes.
- **Forgetting to re-check on reconnect:** In long-lived SSH/TUI sessions, the `current_user` snapshot in App state can become stale. The domain-level check using the live struct is the last line of defense (D-25). Not a Phase 1 action item, but the design choice of using `%User{}` over a `Session.role` snapshot (D-05) directly addresses this.
- **Raising on forbidden:** Authorization failure is a runtime condition from valid input, not a programming error. `authorize/3` must return `{:error, :forbidden}`, never raise (D-16). The `put!/3` naming is a pre-existing convention; the new actor-first variant uses a non-bang name (`put/4`) or wraps the raise in a `with` chain.
- **`Macro.escape/1` omitted in matrix test for struct actors:** Without it, struct literals in a comprehension `for` are not carried correctly into generated test bodies. See Pattern 5 note above.
- **Action atoms not in the allowlist silently passing:** The safe default must be the last catch-all clause returning `{:error, :forbidden}`. Unknown atoms must not fall through to `:ok`.
- **`scopes_for/2` returning a bare atom instead of a list:** The contract is always `[scope()]`, even for single-scope cases. `[:site]` not `:site`. This ensures v2's multi-board assignment is backward-compatible.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Policy matrix dispatch | Custom if/else chains in each domain function | Function-clause dispatch in `Foglet.Authorization.authorize/3` | Single central allowlist; adding a new action requires changing one module. |
| Role hierarchy | Explicit `role >= :mod` comparisons | Pattern-match on `%User{role: :sysop}` / `%User{role: :mod}` with function clauses | Flat 3-role hierarchy with no numeric ordering; pattern matching is more explicit and doesn't invent a comparison that the domain doesn't define. |
| Permission caching | ETS-cached policy results | No caching — pure function | Policy is a pure in-memory computation. Caching introduces invalidation complexity with no measurable gain for a 3-role, 2-scope model. |
| Board moderator resolution | Inline DB queries inside `authorize/3` | `scopes_for/2` return value consumed by caller | Keeps the policy pure and testable without DB; caller resolves scopes before calling authorize. |
| Guard duplication in test | Per-test actor setup | Shared module attributes `@sysop`, `@mod`, `@user` etc. | Reduces test noise; ensures all tests use the same baseline struct. |

---

## Common Pitfalls

### Pitfall 1: Config.put!/3 — Bang Naming vs. Tuple Return

**What goes wrong:** `Config.put!/3` currently raises for invalid key/value (the `!` convention). Adding authorization to it creates a mixed return contract: `{:error, :forbidden}` from authorization, but raises from validation errors. A caller using `with :ok <- Config.put!(actor, key, value)` will crash on validation errors.

**Why it happens:** The `!` suffix was applied to the existing function before authorization was in scope.

**How to avoid:** Introduce `Config.put/4 :: :ok | {:error, :forbidden} | {:error, :invalid_value} | {:error, :unknown_key}` as the actor-aware variant that returns tagged tuples for everything. Keep `put!/3` as-is for boot-time seed calls (no actor). Phase 2 TUI callers use `put/4`. This is a discretion call for the planner (noted in Claude's Discretion above).

**Warning signs:** A `with :ok <- Foglet.Config.put!(actor, key, val)` expression in Phase 2 code — the `!` variant raises; `with` does not rescue.

---

### Pitfall 2: Forgetting to Propagate Forbidden Through `with` Chains

**What goes wrong:** A domain function calls `authorize/3` inside a `Repo.transact/1` → `with` chain, but the `{:error, :forbidden}` tuple is not in the `with`'s `else` clause, so it is returned from the `with` block unnested and `Repo.transact` wraps it in `{:ok, {:error, :forbidden}}`.

**Why it happens:** `Repo.transact/1` wraps any return value from the function in `{:ok, val}` — the `with` short-circuit returns `{:error, :forbidden}` from inside the transaction function, making `Repo.transact` return `{:ok, {:error, :forbidden}}`.

**How to avoid:** Perform the `authorize/3` check BEFORE entering `Repo.transact/1`. The authorization is a pure check with no DB access — there is no reason to run it inside a transaction.

```elixir
# WRONG — authorization inside Repo.transact wraps the {:error, :forbidden}
def archive_board(actor, board_id) do
  Repo.transact(fn ->
    with :ok <- Authorization.authorize(actor, :archive_board, :site),  # BUG
         %Board{} = board <- Repo.get!(Board, board_id) do
      board |> Board.archive_changeset() |> Repo.update()
    end
  end)
end

# CORRECT — authorization before transaction
def archive_board(actor, board_id) do
  with :ok <- Authorization.authorize(actor, :archive_board, :site) do
    Repo.transact(fn ->
      board = Repo.get!(Board, board_id)
      board |> Board.archive_changeset() |> Repo.update()
    end)
  end
end
```

**Warning signs:** `{:ok, {:error, :forbidden}}` returned from a domain function — the `Repo.transact` double-wrapping tells you the check ran inside the transaction.

---

### Pitfall 3: Matrix Test — Structs in `for` Comprehension

**What goes wrong:** Using bare struct literals in a `for` comprehension data table and then `unquote`-ing them into test bodies produces a compile error or incorrect struct at runtime.

**Why it happens:** The `for` comprehension executes at compile time. Struct values are AST nodes, not plain terms, and `unquote/1` alone does not handle them correctly.

**How to avoid:** Wrap struct values in `Macro.escape/1` inside the generated test body via `unquote(Macro.escape(actor))`. Alternatively, build the data table using module attributes that reference helper functions, and call those helpers at runtime inside the test body (no `unquote` needed). The module attribute approach is simpler and avoids macro complexity entirely:

```elixir
# Simpler alternative — call helper at runtime, no Macro.escape needed
@matrix [
  {:sysop, :edit_config, :site, :ok},
  {:mod, :edit_config, :site, {:error, :forbidden}},
  {nil, :edit_config, :site, {:error, :forbidden}},
]

defp actor_fixture(:sysop), do: %User{role: :sysop, status: :active, deleted_at: nil}
defp actor_fixture(:mod), do: %User{role: :mod, status: :active, deleted_at: nil}
defp actor_fixture(nil), do: nil

describe "authorize/3 matrix" do
  for {actor_key, action, scope, expected} <- @matrix do
    @actor_key actor_key
    @action action
    @scope scope
    @expected expected
    test "#{actor_key} #{action} #{inspect(scope)}" do
      actor = actor_fixture(@actor_key)
      assert Authorization.authorize(actor, @action, @scope) == @expected
    end
  end
end
```

**Warning signs:** Compile errors mentioning "cannot unquote" or tests that pass unexpectedly because the actor struct was compared to a malformed AST node.

---

### Pitfall 4: `scopes_for/2` Returns Atom Instead of List

**What goes wrong:** An implementation clause returns `:site` instead of `[:site]`. Callers in Phase 8 that use `Enum.member?(scopes, scope)` will raise because `Enum.member?/2` does not accept an atom.

**Why it happens:** The natural write for "sysop has site scope" is `def scopes_for(...), do: :site`. The list contract is easy to miss.

**How to avoid:** Every clause of `scopes_for/2` returns a list. Enforce this via `@spec scopes_for(actor(), action()) :: [scope()]` — Dialyzer will catch a bare atom return.

**Warning signs:** A Dialyzer warning about `scopes_for/2` return type not matching `[scope()]`.

---

### Pitfall 5: Stale `current_user` in Long-Lived TUI Session

**What goes wrong:** A sysop downgrades a moderator to `:user` role. The moderator's active TUI session still holds the old `%User{role: :mod}` in its App state. If that `current_user` is passed to `authorize/3`, the demoted user retains moderator powers until reconnect.

**Why it happens:** The TUI is a long-lived Raxol process. The `current_user` held in `TUI.App` state is a snapshot from login. It does not auto-refresh on role changes from the sysop side.

**How to avoid (Phase 1 scope):** The domain-level check is the last line of defense. Phase 1 does not need to solve the full stale-session problem — that belongs in session management — but the architecture choice of passing the live `%User{}` to `authorize/3` (D-05) ensures that if the session ever refreshes the `current_user` snapshot (e.g., via a PubSub message), the authorization immediately reflects the new role without any code change.

**What NOT to do:** Authorize from `Session.role` (a snapshot). Role changes would have no effect until a new session is created.

**Warning signs:** Calls to `authorize(session.role, ...)` or `authorize(%{role: session_role}, ...)` — these accept a non-`%User{}` struct and bypass the type system.

---

### Pitfall 6: The "Forbidden Path" Test Gap

**What goes wrong:** Tests for `Boards.create_board/3` (with actor) only test the success path. A regression that removes the `authorize/3` call silently passes all tests.

**Why it happens:** New actor-arg tests are added as "it works with an authorized actor" without adding "it fails with an unauthorized actor."

**How to avoid (D-27):** Every test describe for a guarded function includes at least one test asserting `{:error, :forbidden}` when a regular user or `nil` is passed. One test per function is the minimum; the full combinatorics live in the matrix.

**Warning signs:** A `describe "create_board/3"` block with no test matching `{:error, :forbidden}`.

---

## Code Examples

### Complete `Foglet.Authorization` module skeleton

```elixir
# lib/foglet_bbs/authorization.ex
# Source: structural template from InvitesSurface.visible?/2 (function-clause matrix)
# and authenticate_by_password/2 (nil/deleted guard cond pattern)

defmodule Foglet.Authorization do
  @moduledoc """
  Actor-aware, scope-aware authorization policy for operator actions.

  The domain context function is the real trust boundary (D-17).
  The TUI may call can?/3 for advisory rendering only (D-18).

  Public API:
    * authorize/3 — called from every guarded domain function before side effects
    * can?/3 — called from TUI screens for advisory rendering (grey-out, hide)
    * scopes_for/2 — returns scopes an actor may operate over; consumed by Phase 8

  See .planning/phases/01-authorization-and-scope-backbone/01-CONTEXT.md for all decisions.
  """

  alias Foglet.Accounts.User

  @valid_actions [
    :lock_thread, :unlock_thread, :sticky_thread, :unsticky_thread,
    :move_thread, :delete_thread,
    :delete_post, :edit_post_as_mod,
    :hide_oneliner,
    :create_board, :update_board, :archive_board,
    :create_category, :update_category, :archive_category,
    :edit_config,
    :generate_invite, :revoke_invite
  ]

  @type actor :: User.t() | nil
  @type action :: atom()
  @type scope :: :site | {:board, Ecto.UUID.t()}

  @spec authorize(actor(), action(), scope()) :: :ok | {:error, :forbidden}

  # Invalid actor guards (D-24) — checked before any role or action dispatch
  def authorize(nil, _action, _scope), do: {:error, :forbidden}
  def authorize(%User{deleted_at: d}, _action, _scope) when not is_nil(d), do: {:error, :forbidden}
  def authorize(%User{status: :suspended}, _action, _scope), do: {:error, :forbidden}
  def authorize(%User{status: :pending}, _action, _scope), do: {:error, :forbidden}

  # Unknown action (D-13) — safe default, warning, no raise
  def authorize(_actor, action, _scope) when action not in @valid_actions do
    require Logger
    Logger.warning("[Foglet.Authorization] Unknown action atom: #{inspect(action)} — returning forbidden")
    {:error, :forbidden}
  end

  # Sysop: permitted for all valid actions at any scope
  def authorize(%User{role: :sysop}, _action, _scope), do: :ok

  # Mod: site-scope — all non-sysop-only actions
  def authorize(%User{role: :mod}, :edit_config, _scope), do: {:error, :forbidden}

  def authorize(%User{role: :mod}, action, :site)
      when action in @valid_actions,
      do: :ok

  # Mod: board-scope — subset of actions (not sysop lifecycle ops)
  def authorize(%User{role: :mod}, action, {:board, _board_id})
      when action in [:lock_thread, :unlock_thread, :sticky_thread, :unsticky_thread,
                      :move_thread, :delete_thread, :delete_post, :edit_post_as_mod,
                      :hide_oneliner],
      do: :ok

  # Safe default deny (D-13, mirrors InvitesSurface.visible?/2 final clause)
  def authorize(_actor, _action, _scope), do: {:error, :forbidden}

  @spec can?(actor(), action(), scope()) :: boolean()
  def can?(actor, action, scope), do: authorize(actor, action, scope) == :ok

  @spec scopes_for(actor(), action()) :: [scope()]
  def scopes_for(nil, _action), do: []
  def scopes_for(%User{deleted_at: d}, _action) when not is_nil(d), do: []
  def scopes_for(%User{status: status}, _action) when status in [:suspended, :pending], do: []
  def scopes_for(%User{role: :sysop}, _action), do: [:site]
  def scopes_for(%User{role: :mod}, _action), do: [:site]
  def scopes_for(_actor, _action), do: []
end
```

### Forbidden-path test in a domain context test file

```elixir
# test/foglet_bbs/boards/boards_test.exs — additions only
describe "create_board/3 authorization (D-27)" do
  test "returns {:error, :forbidden} for a regular user" do
    category = category_fixture()
    user = user_fixture()  # role: :user by default

    assert {:error, :forbidden} =
             Foglet.Boards.create_board(user, category.id, %{slug: "test", name: "Test"})
  end

  test "returns {:error, :forbidden} for nil actor (guest)" do
    category = category_fixture()

    assert {:error, :forbidden} =
             Foglet.Boards.create_board(nil, category.id, %{slug: "test", name: "Test"})
  end
end
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| TUI visibility checks as the only gate | Domain-level `authorize/3` as the real trust boundary | This phase | Non-TUI callers (Mix tasks, tests, future API) are also protected. |
| `ShellVisibility` role checks duplicated in each screen | `ShellVisibility` remains for rendering; `authorize/3` gates mutations | This phase | Separation of concerns; rendering and enforcement are no longer conflated. |
| `Bodyguard.Policy` behaviour (external lib) | Hand-rolled function-clause dispatch (no dep) | N/A (never adopted) | No new dependency; full control over return contract. |
| `on_mount` hook as sole Phoenix LiveView auth location | Domain function as auth location; `on_mount` / TUI mount for advisory | Current SOTA [CITED: hexdocs.pm/phoenix_live_view/security-model.html] | Context-level auth works regardless of the entry point (SSH TUI, future Channel client, Mix task). |

**Deprecated/outdated for this codebase:**
- `bodyguard` v2.4.3: last released March 2024; adds behaviour overhead with no benefit given locked design decisions.
- Per-action predicate helpers (`can_lock_thread?/2`): rejected by D-03 in CONTEXT.md — disperses the policy across helpers instead of centralizing it.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `Mod` role in v1.1 is permitted for all operator actions except `:edit_config`. | Architecture Patterns, Pattern 1 | If mods should also be forbidden from board lifecycle ops (create/archive board), the `authorize/3` matrix needs an additional restrict clause. Planner should confirm the mod action set before implementing. |
| A2 | `Config.put!/3` callers in seeds.exs use the `put!(key, value)` or `put!(key, value, nil)` form without an actor. | Pitfall 1 | If seeds.exs uses an actor-first variant, adding a new `put/4` overload may conflict. Read seeds.exs before implementing. |
| A3 | Boards/Category CRUD functions (`create_board`, `update_board`, `archive_board`, `create_category`, `update_category`, `archive_category`) do not yet have actor arguments. | Standard Stack | If any already have an actor argument (e.g., from intermediate work), the "add actor first arg" task is already partially done. |

**If this table is empty:** All claims in this research were verified or cited — no user confirmation needed. (Table is not empty — A1, A2, A3 above are ASSUMED from CONTEXT.md and code inspection.)

---

## Open Questions

1. **Mod action set boundary**
   - What we know: Sysop gets all actions; regular user gets none. Mod gets operator actions but not `:edit_config`.
   - What's unclear: Should mods be allowed to `:create_board`, `:update_board`, `:archive_board`, `:create_category`, `:update_category`, `:archive_category`? These are board lifecycle ops; BBS convention typically gates board creation at sysop only.
   - Recommendation: Treat board lifecycle ops as sysop-only (remove them from the mod allowlist in `authorize/3`). The CONTEXT.md decisions do not explicitly specify this boundary, but REQUIREMENTS.md's "Sysop can create, update, list, and archive categories and boards" (SYSO-03) implies sysop ownership. The planner should make this explicit before Wave 0.

2. **Config.put! naming and return contract**
   - What we know: Current `put!/3` raises for invalid key/value. Actor-aware authorization should return `{:error, :forbidden}`.
   - What's unclear: Does the Phase 2 TUI caller need to handle raises or tuples? Which convention wins?
   - Recommendation: Add `Config.put/4` (non-bang, actor-first, returns tagged tuples for all failure modes) and leave `put!/3` unchanged for boot-time seed paths. Phase 2 uses `put/4`. This isolates the raise contract to a trusted caller context (seeds, Mix tasks).

---

## Environment Availability

Step 2.6: SKIPPED (no external dependencies identified — this phase introduces no new libraries, binaries, services, or runtimes).

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit (built-in Elixir, no separate version pin) |
| Config file | `test/test_helper.exs` |
| Quick run command | `mix test test/foglet_bbs/authorization_test.exs` |
| Full suite command | `mix test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MODR-02 | `scopes_for/2` returns `[:site]` for sysop and mod, `[]` for others | unit | `mix test test/foglet_bbs/authorization_test.exs` | ❌ Wave 0 |
| MODR-03 | `authorize/3` returns `{:error, :forbidden}` for unauthorized actors; domain functions propagate it | unit | `mix test test/foglet_bbs/authorization_test.exs` | ❌ Wave 0 |
| MODR-03 | `Boards.create_board/3` with actor guards the insertion | unit | `mix test test/foglet_bbs/boards/boards_test.exs` | ✅ (file exists, cases to add) |
| MODR-03 | `Config.put!/3` (or new actor variant) guards config writes | unit | `mix test test/foglet_bbs/config/config_test.exs` | ✅ (file exists, cases to add) |

### Sampling Rate

- **Per task commit:** `mix test test/foglet_bbs/authorization_test.exs --failed`
- **Per wave merge:** `mix test`
- **Phase gate:** `mix test` green + `mix precommit` green before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `test/foglet_bbs/authorization_test.exs` — covers MODR-02 and MODR-03 policy matrix
- [ ] `test/foglet_bbs/boards/boards_test.exs` — add forbidden-path tests for `create_board/3`, `update_board/3`, `archive_board/2`
- [ ] `test/foglet_bbs/config/config_test.exs` — add forbidden-path test for actor-aware config put

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | Authentication is already handled by Phase 0 SSH layer / `Foglet.Accounts.authenticate_by_password/2` |
| V3 Session Management | Partial | Phase 1's D-25 (stale session defense) is a session concern; the defense is at the policy layer. Full session management deferred. |
| V4 Access Control | Yes | `Foglet.Authorization.authorize/3` is the ASVS V4 control — actor-aware, checked at the domain function trust boundary |
| V5 Input Validation | No | Action atoms are checked via `@valid_actions` guard — closest thing to input validation in a pure authorization layer |
| V6 Cryptography | No | No cryptographic operations in this phase |

### Known Threat Patterns for this Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Screen-only authorization bypass (regular user calls domain function directly) | Elevation of Privilege | `authorize/3` in domain function, not TUI layer (D-17) |
| Stale session role escalation (sysop demotes a mod; session retains old role) | Elevation of Privilege | Policy uses live `%User{}` from App state, not `Session.role` snapshot (D-05) |
| Unknown action atom silently granted | Elevation of Privilege | Unknown action → `{:error, :forbidden}` + `Logger.warning` (D-13) — no pass-by-default |
| Authorization bypass via transaction wrapping | Tampering | Perform `authorize/3` before `Repo.transact` — never inside it (Pitfall 2) |
| Suspended/deleted user retaining operator access | Elevation of Privilege | Top-of-`authorize/3` guards on `nil`, `deleted_at`, `status` (D-24) |

---

## Sources

### Primary (HIGH confidence)

- [VERIFIED: /Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/shared/invites_surface.ex] — four-clause function-clause policy matrix used as structural template
- [VERIFIED: /Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/accounts.ex] — `authenticate_by_password/2` nil/deleted guard pattern used as precedent for D-24
- [VERIFIED: /Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/config.ex] — `put!/3` current signature confirming `(key, value, updated_by_id \\ nil)`
- [VERIFIED: /Users/brendan.turner/Dev/personal/foglet_bbs/mix.exs] — no authorization library in current deps
- [CITED: hexdocs.pm/phoenix_live_view/security-model.html] — domain function as auth location; UI-only auth as anti-pattern
- [CITED: hex.pm/packages/bodyguard] — v2.4.3, last published March 2024
- [CITED: hex.pm/packages/let_me] — v2.0.0, published March 2026

### Secondary (MEDIUM confidence)

- [CITED: engineering.legendsoflearning.com/posts/matrix-testing-in-elixir/] — `for` comprehension + `unquote` pattern for matrix tests in ExUnit
- [CITED: curiosum.com/blog/authorization-access-control-elixirconf] — Permit library and ABAC approach (evaluated and rejected for this codebase)

### Tertiary (LOW confidence)

- [ASSUMED] `canada` library is abandoned — not verified via hex.pm in this session; omit or verify independently.

---

## Metadata

**Confidence breakdown:**
- Standard Stack: HIGH — verified by codebase inspection (no auth lib present); lock/no-lib decision is in CONTEXT.md
- Architecture: HIGH — all major decisions are locked in CONTEXT.md; research confirms they match Elixir ecosystem SOTA
- Pitfalls: HIGH — Pitfalls 1, 2, 4, 5, 6 verified against actual codebase code; Pitfall 3 verified via matrix test pattern research
- Test pattern: HIGH — ExUnit matrix pattern verified; `Macro.escape` caveat verified via ecosystem source

**Research date:** 2026-04-23
**Valid until:** 2026-07-23 (stable domain — Phoenix + Elixir authorization patterns are mature)
