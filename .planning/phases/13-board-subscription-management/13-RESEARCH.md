# Phase 13: Board Subscription Management - Research

**Researched:** 2026-04-24
**Domain:** Elixir/Phoenix/Ecto SSH-first terminal board subscription management
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Treat `.planning/phases/13-board-subscription-management/13-SPEC.md` as the canonical source of requirements, boundaries, constraints, and acceptance criteria for Phase 13.
- **D-02:** The user-facing board directory must be a single terminal category tree showing subscribed and unsubscribed active boards together with inline subscription status; do not replace this with split subscribed/unsubscribed tabs.
- **D-03:** Category nodes must support collapse and expand, and `Enter` on a board leaf must continue to open the focused board's thread list.
- **D-04:** Board subscription management belongs in `Foglet.Boards` or another owning domain context, not in TUI screens, Mix task database code, or direct `Repo` calls from callers.
- **D-05:** Extend the existing subscription surface with context APIs for listing active boards with per-user subscription state, subscribing to an active board, and unsubscribing from a subscribed board.
- **D-06:** Subscription changes must preserve the existing row-presence model in `board_subscriptions`: subscribing inserts or keeps a row, and unsubscribing from an allowed board deletes the row.
- **D-07:** Add a persisted board-level column that marks whether a board subscription is required and therefore cannot be unsubscribed by users or by the break-glass task.
- **D-08:** The required-subscription flag is valid only when `default_subscription` is true; schema, changeset, context, Sysop board-management, and tests must enforce this relationship.
- **D-09:** Users are allowed to unsubscribe down to zero board subscriptions. The unsubscribe blocker is the board's required-subscription policy, not a minimum remaining subscription count.
- **D-10:** Unsubscribe from a required board must return a structured forbidden or validation result and leave the `board_subscriptions` row intact.
- **D-11:** Add subscribe and unsubscribe actions to the board directory as focused-board commands separate from `Enter`, because `Enter` remains the open-board action.
- **D-12:** The board directory should refresh after subscribe or unsubscribe and provide clear terminal feedback about the result.
- **D-13:** Preserve unread-count display for subscribed boards where available; unsubscribed board rows do not need unread counters.
- **D-14:** The directory should list only active, non-archived boards in non-archived categories.
- **D-15:** Phase 13 satisfies sysop/operator subscription adjustment through a break-glass Mix task, not through full Sysop `USERS` terminal subscription management.
- **D-16:** The Mix task must route through the same `Foglet.Boards` context rules as the user-facing terminal path and must not bypass active-board or required-subscription enforcement.
- **D-17:** The task should support listing a user's board subscriptions plus subscribing and unsubscribing that user from a board, with explicit output for unknown user, unknown board, archived board, required-board unsubscribe, and success cases.
- **D-18:** Board-list and new-thread empty states must stop telling users to ask a sysop for subscriptions.
- **D-19:** Empty states should distinguish no active boards available from no subscribed boards yet, and should point users to the real board-directory subscription action when active unsubscribed boards exist.

### Claude's Discretion
- Exact column name for the required-subscription flag, provided its meaning is clear and it is documented in schema/data-model docs.
- Exact subscribe/unsubscribe key bindings and terminal feedback wording, provided `Enter` remains open-board and copy is honest.
- Exact context function names and tagged tuple shapes, provided tests can distinguish success, forbidden required-board unsubscribe, unknown user/board, archived board, and validation failures.
- Exact Mix task name and option shape, provided it follows existing `mix foglet.*` task style and documents list/subscribe/unsubscribe usage.

### Deferred Ideas (OUT OF SCOPE)
- Full Sysop `USERS` terminal subscription management - explicitly out of scope for Phase 13; use the Mix task.
- Bulk subscription assignment by role or cohort - v2 requirement ADMN-02.
- Subscription-based notifications, webhooks, email digests, or notification delivery - outside Phase 13 board membership scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SUBS-01 | User can view subscribed and unsubscribed active boards in a board directory or equivalent board-management flow. | Use a `Foglet.Boards` directory snapshot plus `Display.Tree`; `BoardList` currently loads subscribed boards only. [VERIFIED: `.planning/REQUIREMENTS.md`, `lib/foglet_bbs/tui/screens/board_list.ex`] |
| SUBS-02 | User can subscribe to an active board from the terminal UI. | Add a focused-board command that dispatches an App async command to a context mutation. [VERIFIED: `lib/foglet_bbs/tui/app.ex`, `lib/foglet_bbs/boards.ex`] |
| SUBS-03 | User can unsubscribe from a board when doing so will not break required access assumptions. | Enforce `required_subscription` in the context before deleting the row. [VERIFIED: `.planning/phases/13-board-subscription-management/13-CONTEXT.md`] |
| SUBS-04 | Sysop can inspect or adjust a user's board subscriptions from the Sysop surface or a break-glass Mix task. | Implement a `mix foglet.board_subscriptions` style task that calls `Foglet.Boards` APIs. [VERIFIED: `lib/mix/tasks/foglet.user.create.ex`] |
| SUBS-05 | Empty board-list and new-thread states tell the user what action is actually available, instead of pointing to nonexistent sysop work. | Replace current sysop-directed copy in BoardList and NewThread with state-aware copy. [VERIFIED: `lib/foglet_bbs/tui/screens/board_list.ex`, `lib/foglet_bbs/tui/screens/new_thread.ex`] |
</phase_requirements>

## Summary

Phase 13 should extend the existing `Foglet.Boards` context as the authoritative subscription boundary, not add database logic in screens or Mix tasks. [VERIFIED: `CLAUDE.md`, `13-CONTEXT.md`] The current system already uses a row-presence subscription model with a unique `(user_id, board_id)` index, `subscribe/2`, `subscribe_to_defaults/1`, `list_subscribed_boards/1`, unread counts, and read pointers. [VERIFIED: `docs/DATA_MODEL.md`, `lib/foglet_bbs/boards.ex`, `priv/repo/migrations/20260418000008_create_board_subscriptions.exs`]

The most important implementation move is to introduce a context-returned board directory snapshot that contains active categories, active boards, per-user subscription state, required-subscription state, and unread counts only for subscribed boards. [VERIFIED: `13-SPEC.md`, `lib/foglet_bbs/boards.ex`] The TUI should render that snapshot through the existing `Foglet.TUI.Widgets.Display.Tree`, preserving `Enter` as leaf activation and adding separate subscribe/unsubscribe keys. [VERIFIED: `13-CONTEXT.md`, `lib/foglet_bbs/tui/widgets/display/tree.ex`]

**Primary recommendation:** Use `Foglet.Boards` APIs plus Ecto constraints for subscription rules; use App async commands and `Display.Tree` for the terminal workflow; use a Mix task only as a thin operator adapter. [VERIFIED: `CLAUDE.md`, `lib/foglet_bbs/tui/app.ex`, `lib/mix/tasks/foglet.user.create.ex`]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Active board directory snapshot | API / Backend domain context | Database / Storage | `Foglet.Boards` owns category, board, subscription, unread-count, and preload decisions. [VERIFIED: `CLAUDE.md`, `lib/foglet_bbs/boards.ex`] |
| Required-subscription policy | Database / Storage | API / Backend domain context | The rule needs a persisted `boards` column plus schema/context validation so all callers share one invariant. [VERIFIED: `13-CONTEXT.md`, `docs/DATA_MODEL.md`] |
| User subscribe/unsubscribe | API / Backend domain context | Browser / Client equivalent: TUI screen | Context mutates rows and enforces active-board/required-board rules; TUI only dispatches commands and renders feedback. [VERIFIED: `CLAUDE.md`, `13-CONTEXT.md`] |
| Category tree interaction | Browser / Client equivalent: TUI screen/widget | API / Backend domain context | Tree expansion, cursor state, and key handling are terminal UI state; board data comes from the context. [VERIFIED: `lib/foglet_bbs/tui/widgets/display/tree.ex`, `CLAUDE.md`] |
| Operator break-glass adjustment | API / Backend domain context | CLI adapter | Mix task parses args and prints results; context remains the rule boundary. [VERIFIED: `13-CONTEXT.md`, `lib/mix/tasks/foglet.user.create.ex`] |
| Empty/new-thread copy | Browser / Client equivalent: TUI screens | API / Backend domain context | Screens need enough loaded state to distinguish no active boards from no subscriptions; data classification comes from context. [VERIFIED: `13-SPEC.md`, `lib/foglet_bbs/tui/screens/new_thread.ex`] |

## Project Constraints (from CLAUDE.md)

- Foglet is SSH-first and terminal UI is the primary product surface; do not add end-user browser workflows. [VERIFIED: `CLAUDE.md`]
- Use `rtk` as the shell command prefix in this repo. [VERIFIED: `CLAUDE.md`]
- Read `docs/DATA_MODEL.md` before schema, migration, association, or persistence-invariant changes. [VERIFIED: `CLAUDE.md`]
- Domain workflows belong in `Foglet.*` contexts, not Phoenix controllers, SSH callbacks, TUI render functions, or Mix task database code. [VERIFIED: `CLAUDE.md`]
- Postgres is authoritative for durable state; ETS/process state must be reconstructable after restart. [VERIFIED: `CLAUDE.md`]
- Contexts own transactions, authorization checks, preload choices, PubSub side effects, and cross-schema invariants. [VERIFIED: `CLAUDE.md`]
- Programmatically set foreign keys on structs before changeset construction; do not add foreign keys to `cast/3` only for caller convenience. [VERIFIED: `CLAUDE.md`]
- Use `Foglet.Boards.scope_for/1`, `Foglet.Threads.scope_for/1`, and `Foglet.Posts.scope_for/1` for authorization scope shapes. [VERIFIED: `CLAUDE.md`]
- Hidden/disabled UI is never authorization; context mutations must still check policy where authorization applies. [VERIFIED: `CLAUDE.md`]
- TUI global navigation belongs in `Foglet.TUI.App`; screen-local state belongs in screens or sibling state modules; reusable display belongs in widgets. [VERIFIED: `CLAUDE.md`]
- Route colors through `Foglet.TUI.Theme`, pass theme explicitly, and keep render functions pure over already-loaded state. [VERIFIED: `CLAUDE.md`]
- Use `start_supervised!/1` for processes in tests and avoid `Process.sleep/1` / `Process.alive?/1`. [VERIFIED: `CLAUDE.md`]
- Run `mix precommit` when changes are complete. [VERIFIED: `CLAUDE.md`]

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Elixir / Mix | 1.19.5 | Runtime, custom Mix task implementation, ExUnit execution | Local project runtime; Mix tasks implement `run/1` after `use Mix.Task`. [VERIFIED: `elixir --version`, CITED: `https://hexdocs.pm/mix/main/Mix.Task.html`] |
| Ecto / Ecto SQL | 3.13.5 | Migrations, schema changesets, constraints, transactions, upserts/deletes | Existing data layer; Ecto maps DB constraints into changeset errors and supports `on_conflict` idempotent inserts. [VERIFIED: `mix.lock`, CITED: `https://hexdocs.pm/ecto/Ecto.Changeset.html`, CITED: `https://hexdocs.pm/ecto/Ecto.Repo.html`] |
| Postgrex / PostgreSQL | Postgrex 0.22.0 / psql 14.20 local | Postgres adapter and durable subscription storage | Existing adapter and authoritative storage model. [VERIFIED: `mix.lock`, `psql --version`, `docs/DATA_MODEL.md`] |
| Bodyguard | 2.4.3 | Actor-aware authorization for context side effects | Existing project policy module uses `Bodyguard.permit/4`; Bodyguard docs define `permit/4` as returning `:ok` or `{:error, reason}`. [VERIFIED: `mix.lock`, `lib/foglet_bbs/authorization.ex`, CITED: `https://hexdocs.pm/bodyguard/Bodyguard.html`] |
| Raxol / Foglet Tree widget | path dependency + Raxol components 2.4.0 locked | Terminal UI tree, screen rendering, command-driven app updates | Existing SSH-first TUI stack; `Display.Tree` already wraps Raxol tree with theme routing and expand/collapse. [VERIFIED: `mix.exs`, `mix.lock`, `lib/foglet_bbs/tui/widgets/display/tree.ex`] |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| ExUnit + Ecto SQL Sandbox | Elixir 1.19.5 / Ecto SQL 3.13.5 | Context, schema, TUI, and Mix task tests | Use for all Phase 13 automated coverage; data tests use SQL sandbox owner setup. [VERIFIED: `test/test_helper.exs`, `test/support/data_case.ex`] |
| OptionParser | Elixir 1.19.5 | Mix task argument parsing | Use strict switches and positional args for list/subscribe/unsubscribe commands. [VERIFIED: local Elixir version, CITED: `https://hexdocs.pm/elixir/OptionParser.html`] |
| Foglet.TUI.Command | local | Off-process DB work from Raxol update loop | Use for subscribe/unsubscribe refresh tasks; App already uses it for board loads. [VERIFIED: `lib/foglet_bbs/tui/app.ex`] |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `Foglet.Boards` context APIs | Direct `Repo` calls in BoardList or Mix task | Rejected by project constraints; it would duplicate active-board and required-board rules outside the owning context. [VERIFIED: `CLAUDE.md`, `13-CONTEXT.md`] |
| `Display.Tree` | Custom tree navigation in `BoardList` | Rejected because the existing widget already provides expand/collapse, visible-node calculation, cursor state, and documented node-shape pitfalls. [VERIFIED: `lib/foglet_bbs/tui/widgets/display/tree.ex`] |
| Mix break-glass task | Full Sysop `USERS` terminal management | Rejected by locked Phase 13 scope; full Sysop user subscription UI is deferred. [VERIFIED: `13-CONTEXT.md`] |
| Minimum-one-subscription rule | Required-subscription board flag | Rejected by user decision; users may unsubscribe to zero boards. [VERIFIED: `13-CONTEXT.md`, `13-DISCUSSION-LOG.md`] |

**Installation:**
```bash
# No new dependency installation is recommended for Phase 13.
rtk mix deps.get
```
[VERIFIED: `mix.exs`, `mix.lock`]

**Version verification:** Package versions above are from `mix.lock`, local `elixir --version`, local `mix --version`, and local `psql --version` on 2026-04-24. [VERIFIED: command outputs]

## Architecture Patterns

### System Architecture Diagram

```text
SSH key/input
  -> Foglet.SSH.CLIHandler
  -> Foglet.TUI.App update loop
  -> BoardList screen key handling
     -> Display.Tree handles cursor / expand / collapse
     -> leaf Enter? -> App dispatches {:load_threads, board_id}
     -> subscribe key? -> App async command -> Foglet.Boards.subscribe_user_to_board(...)
     -> unsubscribe key? -> App async command -> Foglet.Boards.unsubscribe_user_from_board(...)
  -> Foglet.Boards context
     -> Bodyguard/site checks where operator board-management side effects apply
     -> active board + non-archived category checks
     -> required_subscription decision point
        -> required? return {:error, :required_subscription} and keep row
        -> allowed? insert/delete board_subscriptions row
     -> reload directory snapshot
  -> BoardList renders refreshed tree + feedback

Operator CLI
  -> mix foglet.board_subscriptions ...
  -> OptionParser strict parsing
  -> Foglet.Accounts lookup + Foglet.Boards context call
  -> explicit shell output / non-zero exit
```
[VERIFIED: `lib/foglet_bbs/tui/app.ex`, `lib/foglet_bbs/tui/screens/board_list.ex`, `lib/foglet_bbs/boards.ex`, `lib/mix/tasks/foglet.user.create.ex`]

### Recommended Project Structure
```text
lib/
├── foglet_bbs/
│   ├── boards.ex                         # public subscription directory and mutation APIs
│   ├── boards/board.ex                   # required_subscription field + changeset validation
│   └── tui/
│       ├── app.ex                        # async load/subscribe/unsubscribe commands and results
│       └── screens/
│           ├── board_list.ex             # tree state, render, key handling, feedback
│           ├── board_list/state.ex       # use if tree/feedback state becomes non-trivial
│           ├── new_thread.ex             # honest empty state
│           └── sysop/boards_view.ex      # board form exposes required_subscription
├── mix/tasks/foglet.board_subscriptions.ex # break-glass operator task
priv/repo/migrations/
└── *_add_required_subscription_to_boards.exs
test/
├── foglet_bbs/boards/boards_test.exs
├── foglet_bbs/tui/screens/board_list_test.exs
├── foglet_bbs/tui/screens/new_thread_test.exs
├── foglet_bbs/tui/screens/sysop_test.exs
└── mix/tasks/foglet.board_subscriptions_test.exs
```
[VERIFIED: `.planning/codebase/STRUCTURE.md`, existing file paths]

### Pattern 1: Context-Owned Directory Snapshot
**What:** Add one context function, for example `Boards.board_directory_for(user)`, returning category groups with board entries that include `subscribed?`, `required_subscription`, and `unread_count` for subscribed boards. [VERIFIED: `13-CONTEXT.md`, `lib/foglet_bbs/boards.ex`]

**When to use:** Use for BoardList rendering and empty-state classification; do not make BoardList combine `list_boards/0`, `list_subscriptions/1`, and `unread_counts/1` itself. [VERIFIED: `CLAUDE.md`]

**Example:**
```elixir
# Source: existing Foglet.Boards query style + Ecto.Query.
@spec board_directory_for(Foglet.Accounts.User.t() | nil) :: [map()]
def board_directory_for(nil), do: []

def board_directory_for(%{id: user_id}) do
  subscribed = subscribed_board_ids(user_id)
  unread = unread_counts(user_id)

  list_boards()
  |> Enum.group_by(& &1.category)
  |> Enum.map(fn {category, boards} ->
    %{
      category: category,
      boards:
        Enum.map(boards, fn board ->
          %{
            board: board,
            subscribed?: MapSet.member?(subscribed, board.id),
            required_subscription?: board.required_subscription,
            unread_count: if(MapSet.member?(subscribed, board.id), do: Map.get(unread, board.id, 0), else: nil)
          }
        end)
    }
  end)
end
```
[VERIFIED: `lib/foglet_bbs/boards.ex`, CITED: `https://hexdocs.pm/ecto/Ecto.Query.html` via Ecto docs family]

### Pattern 2: Constraint Backstop Plus Changeset Validation
**What:** Add `required_subscription :boolean, null: false, default: false` and a DB check constraint equivalent to `required_subscription = false OR default_subscription = true`; mirror it in `Board.changeset/2` with a clear changeset error. [VERIFIED: `13-CONTEXT.md`, CITED: `https://hexdocs.pm/ecto/Ecto.Changeset.html`]

**When to use:** Use both validation and DB constraint because context/UI feedback needs clear errors, while the DB constraint protects imports, tasks, and future callers. [CITED: `https://hexdocs.pm/ecto/Ecto.Changeset.html`]

**Example:**
```elixir
# Source: Ecto.Changeset check_constraint/3 docs and local Board.changeset style.
def changeset(board, attrs) do
  board
  |> cast(attrs, [:slug, :name, :description, :display_order, :readable_by,
                  :postable_by, :archived, :default_subscription,
                  :required_subscription, :category_id])
  |> validate_required([:slug, :name, :category_id])
  |> validate_required_subscription()
  |> check_constraint(:required_subscription,
    name: :boards_required_subscription_requires_default_subscription,
    message: "requires default subscription"
  )
end
```
[VERIFIED: `lib/foglet_bbs/boards/board.ex`, CITED: `https://hexdocs.pm/ecto/Ecto.Changeset.html`]

### Pattern 3: Thin Mix Task Adapter
**What:** Use `Mix.Tasks.Foglet.BoardSubscriptions` with `use Mix.Task`, `@shortdoc`, `@moduledoc`, `OptionParser.parse!/2`, `Application.ensure_all_started(:foglet_bbs)`, and context calls. [VERIFIED: `lib/mix/tasks/foglet.user.create.ex`, CITED: `https://hexdocs.pm/mix/main/Mix.Task.html`, CITED: `https://hexdocs.pm/elixir/OptionParser.html`]

**When to use:** Use for SUBS-04 only; it must list, subscribe, and unsubscribe but must not call `Repo.insert/delete` directly. [VERIFIED: `13-CONTEXT.md`]

**Example:**
```elixir
# Source: local mix task style + OptionParser docs.
def run(args) do
  {:ok, _} = Application.ensure_all_started(:foglet_bbs)

  {opts, rest} = OptionParser.parse!(args, strict: [user: :string, board: :string])

  case rest do
    ["list"] -> list_user(opts)
    ["subscribe"] -> subscribe_user(opts)
    ["unsubscribe"] -> unsubscribe_user(opts)
    _ -> usage_exit()
  end
end
```
[VERIFIED: `lib/mix/tasks/foglet.user.create.ex`, CITED: `https://hexdocs.pm/elixir/OptionParser.html`]

### Anti-Patterns to Avoid
- **Direct Repo from TUI or Mix task:** Duplicates context rules and violates project boundaries. [VERIFIED: `CLAUDE.md`, `13-CONTEXT.md`]
- **Two subscribed/unsubscribed tabs:** Contradicts locked D-02 and acceptance criteria. [VERIFIED: `13-CONTEXT.md`, `13-SPEC.md`]
- **Unread counts for unsubscribed boards:** Spec says preserve unread counts for subscribed boards; unsubscribed rows do not need them. [VERIFIED: `13-CONTEXT.md`]
- **Minimum remaining subscription count:** User explicitly rejected this; zero subscriptions are allowed. [VERIFIED: `13-CONTEXT.md`, `13-DISCUSSION-LOG.md`]
- **Tree nodes as structs/keyword lists:** `Display.Tree` documents map node shape; wrong shapes crash Raxol matching. [VERIFIED: `lib/foglet_bbs/tui/widgets/display/tree.ex`]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Tree cursor / expand-collapse state | Custom flattened list with manual parent/child math | `Foglet.TUI.Widgets.Display.Tree` | Existing widget already wraps Raxol tree state and visible-node rendering. [VERIFIED: `lib/foglet_bbs/tui/widgets/display/tree.ex`] |
| Idempotent subscribe | Manual pre-check then insert | `Repo.insert(..., on_conflict: :nothing, conflict_target: [:user_id, :board_id])` through `Foglet.Boards.subscribe*` | Ecto supports upserts; pre-checks race. [VERIFIED: `lib/foglet_bbs/boards.ex`, CITED: `https://hexdocs.pm/ecto/Ecto.Repo.html`] |
| Required/default policy integrity | TUI-only disabling or task-only validation | Board changeset validation plus DB check constraint | Ecto docs state DB constraints provide race-free correctness and changeset conversion. [CITED: `https://hexdocs.pm/ecto/Ecto.Changeset.html`] |
| CLI parsing | Hand parsing `args` strings | `OptionParser.parse!/2` with strict switches | Official OptionParser supports strict typed switches and raises on invalid options. [CITED: `https://hexdocs.pm/elixir/OptionParser.html`] |
| Authorization gate plumbing | Direct role checks in screens | Existing `Foglet.Authorization` + `Bodyguard.permit/4` where side effects require actor authorization | Bodyguard is the project policy boundary for context side effects. [VERIFIED: `lib/foglet_bbs/authorization.ex`, CITED: `https://hexdocs.pm/bodyguard/Bodyguard.html`] |

**Key insight:** The hard part is not inserting/deleting subscription rows; it is keeping subscription visibility, required-board policy, active-board filtering, unread counts, TUI refresh, and operator actions consistent through one context boundary. [VERIFIED: `13-SPEC.md`, `CLAUDE.md`, `lib/foglet_bbs/boards.ex`]

## Common Pitfalls

### Pitfall 1: `on_conflict: :nothing` Return Shape
**What goes wrong:** A duplicate subscribe can return `{:ok, struct}` even though no new row was inserted, and returned data may not mirror the database. [CITED: `https://hexdocs.pm/ecto/Ecto.Repo.html`]
**Why it happens:** Ecto upserts map to database conflict handling and may not report whether insert or conflict path happened. [CITED: `https://hexdocs.pm/ecto/Ecto.Repo.html`]
**How to avoid:** Treat subscribe as idempotent success and reload the directory from the database after mutation. [VERIFIED: `13-CONTEXT.md`, `lib/foglet_bbs/boards.ex`]
**Warning signs:** Tests assert the returned subscription struct rather than the persisted row/directory state. [VERIFIED: `13-SPEC.md`]

### Pitfall 2: Required Policy Only in UI
**What goes wrong:** Mix task or future API can unsubscribe required boards if the rule only disables a TUI key. [VERIFIED: `13-CONTEXT.md`]
**Why it happens:** UI affordances are advisory, not authorization or data integrity. [VERIFIED: `CLAUDE.md`]
**How to avoid:** Enforce required-board blocking in `Foglet.Boards.unsubscribe...` and add a DB check for `required_subscription` validity. [VERIFIED: `13-CONTEXT.md`, CITED: `https://hexdocs.pm/ecto/Ecto.Changeset.html`]
**Warning signs:** Tests only cover BoardList and not the context or Mix task. [VERIFIED: `13-SPEC.md`]

### Pitfall 3: New Directory Query Drops Archived Category Filtering
**What goes wrong:** Archived boards or boards in archived categories appear as subscribable. [VERIFIED: `13-CONTEXT.md`]
**Why it happens:** `list_subscribed_boards/1` currently joins category and filters both board/category archived flags; new queries must preserve that. [VERIFIED: `lib/foglet_bbs/boards.ex`]
**How to avoid:** Reuse `list_boards/0` filtering semantics or centralize an active-board query helper. [VERIFIED: `lib/foglet_bbs/boards.ex`]
**Warning signs:** Tests create archived boards/categories and the directory still renders them. [VERIFIED: `13-SPEC.md`]

### Pitfall 4: Tree Node Shape Drift
**What goes wrong:** Tree rendering or key handling crashes when nodes are structs or keyword lists. [VERIFIED: `lib/foglet_bbs/tui/widgets/display/tree.ex`]
**Why it happens:** `Display.Tree` expects maps with `:id`, `:label`, `:children`, and optional `:data`. [VERIFIED: `lib/foglet_bbs/tui/widgets/display/tree.ex`]
**How to avoid:** Build explicit map nodes and keep board/category structs inside `:data`. [VERIFIED: `lib/foglet_bbs/tui/widgets/display/tree.ex`]
**Warning signs:** Tests bypass `Display.Tree.handle_event/2` and only assert text rendering. [VERIFIED: `13-SPEC.md`]

### Pitfall 5: NewThread Empty State Needs Active Board Knowledge
**What goes wrong:** NewThread cannot distinguish "no active boards exist" from "you have no subscribed boards yet". [VERIFIED: `13-SPEC.md`, `lib/foglet_bbs/tui/screens/new_thread.ex`]
**Why it happens:** App currently loads only `list_subscribed_boards/1` for new-thread. [VERIFIED: `lib/foglet_bbs/tui/app.ex`]
**How to avoid:** Load an empty-state summary or directory availability signal alongside subscribed boards. [VERIFIED: `13-SPEC.md`]
**Warning signs:** Copy is changed textually but still cannot branch correctly in tests. [VERIFIED: `13-SPEC.md`]

## Code Examples

Verified patterns from official sources and local code:

### DB Check Constraint Migration
```elixir
# Source: Ecto.Changeset check_constraint/3 docs + local migration style.
def change do
  alter table(:boards) do
    add :required_subscription, :boolean, null: false, default: false
  end

  create constraint(
           :boards,
           :boards_required_subscription_requires_default_subscription,
           check: "required_subscription = false OR default_subscription = true"
         )
end
```
[CITED: `https://hexdocs.pm/ecto/Ecto.Changeset.html`, VERIFIED: `priv/repo/migrations/20260418000007_create_boards.exs`]

### Context Unsubscribe Shape
```elixir
# Source: local context tagged tuple style.
@spec unsubscribe(String.t(), String.t()) ::
        {:ok, :unsubscribed}
        | {:error, :not_found}
        | {:error, :board_archived}
        | {:error, :required_subscription}
        | {:error, Ecto.Changeset.t()}
def unsubscribe(user_id, board_id) do
  with {:ok, board} <- fetch_active_board(board_id),
       false <- board.required_subscription || {:error, :required_subscription},
       %Subscription{} = sub <- Repo.get_by(Subscription, user_id: user_id, board_id: board_id) do
    Repo.delete(sub)
    {:ok, :unsubscribed}
  else
    nil -> {:error, :not_found}
    {:error, reason} -> {:error, reason}
  end
end
```
[VERIFIED: `lib/foglet_bbs/boards.ex`, `13-CONTEXT.md`]

### Tree Event Routing
```elixir
# Source: Foglet.TUI.Widgets.Display.Tree API.
{tree, action} = Tree.handle_event(key_event, ss.tree)

case action do
  :node_activated -> open_focused_board(state, tree)
  :node_expanded -> update_tree(state, tree)
  :node_collapsed -> update_tree(state, tree)
  nil -> update_tree(state, tree)
end
```
[VERIFIED: `lib/foglet_bbs/tui/widgets/display/tree.ex`]

### App Async Command
```elixir
# Source: existing App load command pattern.
task =
  Foglet.TUI.Command.task(:subscribe_board, fn ->
    {:board_subscription_changed, boards_mod.subscribe(user.id, board_id)}
  end)

{state, [task]}
```
[VERIFIED: `lib/foglet_bbs/tui/app.ex`]

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Subscribed-only board list | All active authorized boards in one category tree with inline status | Locked in Phase 13 spec/context on 2026-04-24 | Planner must replace `BoardList` list shape, not merely add buttons. [VERIFIED: `13-SPEC.md`, `13-CONTEXT.md`] |
| Sysop-directed empty copy | Honest copy pointing to board directory subscription action when active boards exist | Locked in Phase 13 spec/context on 2026-04-24 | App must load enough state to distinguish empty causes. [VERIFIED: `13-SPEC.md`] |
| `default_subscription` means initially subscribed only | Add separate `required_subscription` policy constrained by `default_subscription` | Locked in Phase 13 spec/context on 2026-04-24 | Defaults and non-unsubscribable policy are no longer conflated. [VERIFIED: `13-CONTEXT.md`] |
| Potential minimum-one-board rule | Users may unsubscribe down to zero boards | Corrected in discussion log on 2026-04-24 | Do not implement "last subscription" blockers. [VERIFIED: `13-DISCUSSION-LOG.md`] |

**Deprecated/outdated:**
- `BoardList` copy "Ask your sysop to subscribe you" is outdated for Phase 13. [VERIFIED: `lib/foglet_bbs/tui/screens/board_list.ex`, `13-SPEC.md`]
- `NewThread` copy "Ask your sysop to subscribe you" is outdated for Phase 13. [VERIFIED: `lib/foglet_bbs/tui/screens/new_thread.ex`, `13-SPEC.md`]
- Direct subscribed-only `Boards.list_subscribed_boards/1` as the board directory data source is outdated for Phase 13. [VERIFIED: `lib/foglet_bbs/tui/app.ex`, `13-SPEC.md`]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|

All claims in this research were verified from local project files, command output, or official docs cited below; no `[ASSUMED]` claims are intentionally included. [VERIFIED: research process]

## Open Questions

1. **Exact key bindings for subscribe/unsubscribe**
   - What we know: `Enter` must remain open-board, and subscribe/unsubscribe must be separate focused-board commands. [VERIFIED: `13-CONTEXT.md`]
   - What's unclear: Whether project UX prefers `s`/`u`, `+`/`-`, or another binding. [VERIFIED: `13-CONTEXT.md` marks exact bindings as discretion]
   - Recommendation: Use `s` for subscribe and `u` for unsubscribe unless conflicts appear in `BoardList`; document in key bar and tests. [VERIFIED: `lib/foglet_bbs/tui/screens/board_list.ex` current key map]

2. **Exact return atom for required-board unsubscribe**
   - What we know: Tests must distinguish required-board unsubscribe from success, unknowns, archived board, and validation failures. [VERIFIED: `13-CONTEXT.md`]
   - What's unclear: The exact atom is discretionary. [VERIFIED: `13-CONTEXT.md`]
   - Recommendation: Use `{:error, :required_subscription}` because it names the policy and maps cleanly to TUI/task copy. [VERIFIED: existing tagged tuple style in `.planning/codebase/CONVENTIONS.md`]

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Elixir | Build, tests, Mix task | ✓ | 1.19.5 | None needed. [VERIFIED: `elixir --version`] |
| Mix | Build, tests, custom task | ✓ | 1.19.5 | None needed. [VERIFIED: `mix --version`] |
| PostgreSQL client | Ecto test DB interaction | ✓ | psql 14.20 | Docker compose may provide DB service if local service is absent. [VERIFIED: `psql --version`, `docker-compose.yml`] |
| Docker | Optional local Postgres service | ✓ | 29.0.1 | Use existing local Postgres if running. [VERIFIED: `docker --version`, `docker-compose.yml`] |
| Raxol vendor dependency | TUI rendering | ✓ | local path dependency | None; already in repo. [VERIFIED: `mix.exs`, `vendor/raxol`] |

**Missing dependencies with no fallback:**
- None found. [VERIFIED: command outputs]

**Missing dependencies with fallback:**
- None found. [VERIFIED: command outputs]

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | ExUnit with Ecto SQL Sandbox. [VERIFIED: `test/test_helper.exs`, `test/support/data_case.ex`] |
| Config file | `test/test_helper.exs`; Mix aliases in `mix.exs`. [VERIFIED: `test/test_helper.exs`, `mix.exs`] |
| Quick run command | `rtk mix test test/foglet_bbs/boards/boards_test.exs test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/screens/new_thread_test.exs test/mix/tasks/foglet.board_subscriptions_test.exs` [VERIFIED: existing test layout] |
| Full suite command | `rtk mix precommit` [VERIFIED: `CLAUDE.md`, `mix.exs`] |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| SUBS-01 | Directory renders subscribed/unsubscribed active boards in collapsible category tree | TUI screen/unit + context | `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs` | ✅ update existing. [VERIFIED: file exists] |
| SUBS-02 | User subscribes from terminal UI and directory refreshes | TUI/App + context | `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/app_test.exs` | ✅ update existing. [VERIFIED: files exist] |
| SUBS-03 | Required board unsubscribe blocked; non-required delete succeeds | context/schema | `rtk mix test test/foglet_bbs/boards/boards_test.exs` | ✅ update existing. [VERIFIED: file exists] |
| SUBS-04 | Mix task list/subscribe/unsubscribe and error cases | Mix task integration | `rtk mix test test/mix/tasks/foglet.board_subscriptions_test.exs` | ❌ Wave 0 create. [VERIFIED: `test/mix/tasks` exists] |
| SUBS-05 | Empty board-list/new-thread copy points to real action | TUI screen/unit | `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/screens/new_thread_test.exs` | ✅ update existing. [VERIFIED: files exist] |

### Sampling Rate
- **Per task commit:** Run the narrow command for touched test files. [VERIFIED: project test layout]
- **Per wave merge:** `rtk mix test test/foglet_bbs/boards/boards_test.exs test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/screens/new_thread_test.exs test/foglet_bbs/tui/app_test.exs test/mix/tasks/foglet.board_subscriptions_test.exs` [VERIFIED: test layout]
- **Phase gate:** `rtk mix precommit` green before `/gsd-verify-work`. [VERIFIED: `CLAUDE.md`, `mix.exs`]

### Wave 0 Gaps
- [ ] `test/mix/tasks/foglet.board_subscriptions_test.exs` - covers SUBS-04. [VERIFIED: file absent from `rg`/test tree]
- [ ] Add fixtures for required boards and unsubscribed active board directory cases if existing `BoardsFixtures` is insufficient after schema change. [VERIFIED: `test/support/boards_fixtures.ex`]

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | no new auth mechanism | Reuse existing authenticated SSH session and Accounts user identity. [VERIFIED: `CLAUDE.md`, `lib/foglet_bbs/tui/app.ex`] |
| V3 Session Management | no new session mechanism | Reuse `Foglet.Sessions.*`; do not store subscription state in session as authority. [VERIFIED: `CLAUDE.md`] |
| V4 Access Control | yes | Context-level enforcement in `Foglet.Boards`; Bodyguard remains policy mechanism for operator board-management side effects. [VERIFIED: `CLAUDE.md`, `lib/foglet_bbs/authorization.ex`] |
| V5 Input Validation | yes | Ecto changesets, DB constraints, and `OptionParser.parse!/2` strict parsing. [CITED: `https://hexdocs.pm/ecto/Ecto.Changeset.html`, CITED: `https://hexdocs.pm/elixir/OptionParser.html`] |
| V6 Cryptography | no | No cryptographic changes in Phase 13. [VERIFIED: `13-SPEC.md`] |

### Known Threat Patterns for Elixir/Ecto TUI + Mix Task Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Unauthorized operator adjustment | Elevation of privilege | Route all mutations through context APIs and Bodyguard where actor authorization is required; Mix task must not call Repo directly. [VERIFIED: `CLAUDE.md`, `13-CONTEXT.md`] |
| Required-board unsubscribe bypass | Tampering | Enforce in context and DB-backed policy; verify Mix task uses same API. [VERIFIED: `13-CONTEXT.md`] |
| Archived board subscription | Tampering / information disclosure | Context checks active board and non-archived category before subscribe/unsubscribe/list. [VERIFIED: `13-CONTEXT.md`, `lib/foglet_bbs/boards.ex`] |
| Invalid CLI args causing unsafe behavior | Tampering | Use strict `OptionParser.parse!/2`, explicit unknown-user/board handling, and non-zero exits. [CITED: `https://hexdocs.pm/elixir/OptionParser.html`, VERIFIED: `13-CONTEXT.md`] |
| Race on duplicate subscribe | Tampering / reliability | Use unique index and Ecto `on_conflict: :nothing` idempotent insert. [VERIFIED: `priv/repo/migrations/20260418000008_create_board_subscriptions.exs`, CITED: `https://hexdocs.pm/ecto/Ecto.Repo.html`] |

## Sources

### Primary (HIGH confidence)
- `CLAUDE.md` - SSH-first boundary, context ownership, persistence, TUI, testing, and precommit constraints. [VERIFIED]
- `.planning/phases/13-board-subscription-management/13-SPEC.md` - canonical Phase 13 requirements and acceptance criteria. [VERIFIED]
- `.planning/phases/13-board-subscription-management/13-CONTEXT.md` - locked decisions and deferred scope. [VERIFIED]
- `.planning/REQUIREMENTS.md` - SUBS-01 through SUBS-05. [VERIFIED]
- `docs/DATA_MODEL.md` - board and subscription persistence model. [VERIFIED]
- `lib/foglet_bbs/boards.ex`, `lib/foglet_bbs/boards/board.ex`, `lib/foglet_bbs/boards/subscription.ex` - existing context/schema behavior. [VERIFIED]
- `lib/foglet_bbs/tui/app.ex`, `lib/foglet_bbs/tui/screens/board_list.ex`, `lib/foglet_bbs/tui/screens/new_thread.ex`, `lib/foglet_bbs/tui/widgets/display/tree.ex` - TUI integration and tree widget behavior. [VERIFIED]
- `lib/mix/tasks/foglet.user.create.ex` - existing break-glass Mix task style. [VERIFIED]
- `https://hexdocs.pm/ecto/Ecto.Changeset.html` - constraints, check constraints, unique/foreign key constraints. [CITED]
- `https://hexdocs.pm/ecto/Ecto.Repo.html` - `insert/2`, `on_conflict`, `conflict_target`, upsert return caveats. [CITED]
- `https://hexdocs.pm/bodyguard/Bodyguard.html` and `https://hexdocs.pm/bodyguard/Bodyguard.Policy.html` - `permit/4` and policy behavior. [CITED]
- `https://hexdocs.pm/mix/main/Mix.Task.html` - Mix task behavior, `run/1`, `@shortdoc`. [CITED]
- `https://hexdocs.pm/elixir/OptionParser.html` - strict CLI parsing and `parse!/2`. [CITED]

### Secondary (MEDIUM confidence)
- None. [VERIFIED: no secondary-only claims used]

### Tertiary (LOW confidence)
- None. [VERIFIED: no tertiary-only claims used]

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - versions verified from `mix.lock` and local runtime commands; API behavior checked in official HexDocs. [VERIFIED]
- Architecture: HIGH - phase decisions and existing code all point to the same context/TUI/Mix task boundaries. [VERIFIED]
- Pitfalls: HIGH - pitfalls are grounded in existing code, locked spec decisions, and official Ecto/OptionParser/Bodyguard docs. [VERIFIED]

**Research date:** 2026-04-24
**Valid until:** 2026-05-24 for local architecture decisions; verify dependency docs again if dependencies are upgraded. [VERIFIED: current project lockfile date context]
