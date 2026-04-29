# Coding Conventions

**Analysis Date:** 2026-04-29

Foglet BBS is an Elixir 1.17 / Phoenix 1.8 application with two strict
namespace layers: `Foglet.*` for domain code under `lib/foglet_bbs/`, and
`FogletBbs.*` / `FogletBbsWeb.*` for Phoenix infrastructure. Conventions below
are extracted from `.formatter.exs`, `.credo.exs`, `mix.exs`, and the actual
shape of `lib/foglet_bbs/**`.

## Naming Patterns

**Modules — namespace split (AGENTS.md §Boundaries):**

- `Foglet.<Domain>` — application domain. Examples: `Foglet.Accounts`,
  `Foglet.Boards`, `Foglet.Threads`, `Foglet.Posts`, `Foglet.Authorization`,
  `Foglet.Sessions.Session`, `Foglet.SSH.CLIHandler`, `Foglet.TUI.App`.
- `FogletBbs.*` / `FogletBbsWeb.*` — Phoenix/OTP plumbing. Examples:
  `FogletBbs.Application`, `FogletBbs.Repo`, `FogletBbsWeb.Endpoint`.
- Domain workflows MUST live in `Foglet.*` contexts, never in controllers,
  SSH callbacks, or TUI render functions.

**Files:**

- snake_case `.ex` files mirror PascalCase modules:
  `lib/foglet_bbs/boards/board.ex` → `Foglet.Boards.Board`.
- Tests mirror source paths under `test/`:
  `lib/foglet_bbs/boards/server.ex` → `test/foglet_bbs/boards/board_server_test.exs`.
- Mix tasks: `lib/mix/tasks/foglet.<task>.ex` (dotted task names like
  `mix foglet.tui.render`).
- Migrations: `priv/repo/migrations/<timestamp>_<snake_case_name>.exs`,
  generated via `mix ecto.gen.migration name_using_underscores`.

**Functions:**

- snake_case (Credo `Readability.FunctionNames` enforced).
- Predicates end in `?`: `can_post?/2` in `lib/foglet_bbs/posting_policy.ex`,
  `chrome_frame_element?/1`, `account_visible?/1` in
  `lib/foglet_bbs/tui/screens/shell_visibility.ex`.
- Bang variants for raise-on-error: `get_thread!/1`, `get_post!/1`,
  `start_supervised!/1` (tests).

**Variables and atoms:**

- snake_case throughout (Credo `Readability.VariableNames` enforced).
- Status / role enums use bare atoms: `:user`, `:mod`, `:sysop`,
  `:active`, `:pending`, `:suspended`, `:rejected`.
- Authorization scopes are tagged tuples or atoms:
  `:site` and `{:board, board_id}` (see `Foglet.Authorization` typespec).

**Module attributes:**

- Configurable defaults declared at the top with `@default_*` /
  `@<thing>_min` / `@<thing>_max` constants. Example:
  `lib/foglet_bbs/accounts/user.ex` declares `@handle_format`, `@handle_min`,
  `@handle_max`, `@password_min`, `@password_max`, `@valid_roles`,
  `@valid_statuses`, `@default_timezone`. Widget README §D-08 codifies this.

## Code Style

**Formatting (`.formatter.exs`):**

```elixir
[
  import_deps: [:ecto, :ecto_sql, :phoenix],
  subdirectories: ["priv/*/migrations"],
  inputs: ["*.{ex,exs}", "{config,lib,test}/**/*.{ex,exs}", "priv/*/seeds.exs"]
]
```

- `mix format` is part of `mix precommit` and runs over all `.ex` / `.exs`
  files plus generated migrations.
- Always run `mix format` before committing.

**Linting (`.credo.exs`, `strict: true`):**

- Max line length 120 (`Readability.MaxLineLength`).
- Max nesting depth 4 (`Refactor.Nesting`).
- TODO comments cause Credo to fail (`exit_status: 2`); FIXME enabled too.
- `IO.inspect`, `IEx.pry`, `dbg` are warnings — never ship them.
- Disabled checks worth knowing: `Readability.Specs` (specs not required on
  every function), `Design.AliasUsage` (Phoenix-generated noise),
  `Readability.StrictModuleLayout`.

**Static analysis:**

- Dialyzer with `flags: [:error_handling, :underspecs, :unmatched_returns,
  :unknown]` (`mix.exs:14-17`). New public functions should carry `@spec`
  annotations to keep dialyzer green.
- Sobelow runs on web entry points (`lib/foglet_bbs_web/router.ex`) at
  threshold "low".

## Import Organization

**Order observed across `lib/foglet_bbs/`:**

1. `use` directives (e.g. `use Foglet.Schema`, `use GenServer`,
   `use ExUnit.CaseTemplate`).
2. `import` directives, with `import Ecto.Query, warn: false` very common.
3. `require` directives (typically `require Logger`).
4. `alias` directives, alphabetized within the module
   (Credo `Readability.AliasOrder` enforced). Example, `lib/foglet_bbs/posts.ex:13-19`:

```elixir
alias Foglet.Accounts.User
alias Foglet.Boards
alias Foglet.Boards.Board
alias Foglet.PostingPolicy
alias Foglet.Posts.{Edit, Post}
alias Foglet.Threads.Thread
alias FogletBbs.Repo
```

- Multi-aliases (`alias Foo.{A, B}`) are used when 2+ submodules from the
  same parent are needed.
- No path aliases — pure module names.

## Context Patterns

**Contexts are public boundaries.** Cross-context calls go through the
context module (e.g., `Foglet.Accounts.register_user/1`,
`Foglet.Boards.create_board/3`), never directly into schemas or `Repo`.

**Each context owns:**

- Transactions via `Repo.transact/1` or `Ecto.Multi`.
- Authorization checks (see "Authorization Usage" below).
- Preload choices for renderers/serializers.
- PubSub side effects.
- Cross-schema invariants.

**Schemas own:**

- `schema "<table>" do ... end` block, associations, virtual fields.
- Changesets (`changeset/2`, `creation_changeset/2`, `edit_changeset/2`,
  `archive_changeset/1`, etc.).
- Field-level validations.

**Foreign-key convention (CRITICAL — AGENTS.md):** Set FKs on the struct
*before* changeset construction, never via `cast/3`. Example pattern from
`lib/foglet_bbs/boards/server.ex:128-136`:

```elixir
%Post{
  message_number: message_number,
  board_id: board_id,
  thread_id: thread_id,
  user_id: user_id
}
|> Post.creation_changeset(attrs)
```

The `creation_changeset/2` itself only casts caller-settable fields:

```elixir
# lib/foglet_bbs/posts/post.ex:40-50
def creation_changeset(post, attrs) do
  post
  |> cast(attrs, [:body, :reply_to_id])  # ← FKs deliberately absent
  |> validate_required([:body])
  |> ...
end
```

Mirror this for every new schema. Never put `*_id` fields in `cast/3` just
because it's convenient.

**Per-board message-number invariant (AGENTS.md §Core Invariants):**

- Thread and post creation MUST route through `Foglet.Boards.Server`
  (`lib/foglet_bbs/boards/server.ex`) — the single writer for message-number
  allocation.
- Soft-deleted posts keep their message numbers; do not fill gaps.
- Moving a thread updates denormalized `board_id` on posts but message numbers
  remain historical.

**Repo usage:**

- `import Ecto.Query, warn: false` at the top of each context.
- Use `Foglet.QueryHelpers` for shared filters
  (e.g. `QueryHelpers.not_archived/1` in `lib/foglet_bbs/boards.ex:42`).
- Dual-arity context functions: an internal `create_x/1` for trusted seeds
  and a public actor-aware `create_x(actor, attrs)` that calls
  `Bodyguard.permit/4` first. See `lib/foglet_bbs/boards.ex:52-73`.

## Changeset Patterns

**Multiple named changesets per schema** for distinct mutation paths. Example
from `lib/foglet_bbs/accounts/user.ex`:

- `registration_changeset/2` — full registration with password hashing.
- `password_changeset/2` — password reset only.
- `role_changeset/2` — role transitions.
- `confirm_changeset/1` — sets `confirmed_at`.
- `profile_changeset/2` — profile fields, never touches handle/email/password.

**Defensive scoping** of single-field changesets:
`Foglet.Boards.Board.archive_changeset/1` (`lib/foglet_bbs/boards/board.ex:75-79`)
only casts `:archived` so `archive_*` paths cannot mutate other fields.

**Validation idioms:**

- `validate_required/2` then `validate_length/3`, `validate_format/3`,
  `validate_inclusion/3`, `validate_number/3`.
- DB constraints mirrored: `unique_constraint/2`, `foreign_key_constraint/2`,
  `check_constraint/3`. Always add a matching changeset constraint when the
  migration declares one (`boards.ex:53-58`).
- `unsafe_validate_unique/3` for early UX feedback before the DB constraint.

**Schema defaults — `Foglet.Schema` macro (`lib/foglet_bbs/schema.ex`):**

```elixir
defmacro __using__(_) do
  quote do
    use Ecto.Schema
    import Ecto.Changeset
    @primary_key {:id, Ecto.UUID, autogenerate: true}
    @foreign_key_type Ecto.UUID
    @timestamps_opts [type: :utc_datetime_usec]
  end
end
```

**Use `use Foglet.Schema` for every new Ecto schema.** It pins UUID v7
primary keys, UUID FKs, and microsecond UTC timestamps per
`docs/DATA_MODEL.md` §Conventions.

## Error Handling

**Tagged-tuple results everywhere:** `{:ok, value}` / `{:error, reason}`.
Reasons are atoms (`:forbidden`, `:not_found`, `:posting_not_allowed`,
`:thread_locked`) or `Ecto.Changeset.t()`.

**`with` for happy-path composition:**

```elixir
# lib/foglet_bbs/boards.ex:67-73
def create_category(actor, attrs) do
  with :ok <- Bodyguard.permit(Foglet.Authorization, :create_category, actor, :site) do
    %Category{}
    |> Category.changeset(attrs)
    |> Repo.insert()
  end
end
```

**`Repo.transact/1`** for multi-row invariants where ordering or rollback
matters (`lib/foglet_bbs/posts.ex:104-115`).

**`Ecto.Multi`** when downstream operations need named results
(`lib/foglet_bbs/boards/server.ex:117-155`).

**Logger:**

- `require Logger` then `Logger.warning/1`, `Logger.info/1`, etc.
- Bracketed module tags: `"[Foglet.Authorization] Unknown action atom: ..."`
  (`lib/foglet_bbs/authorization.ex:99-101`).

## Authorization Usage (Bodyguard)

`Foglet.Authorization` (`lib/foglet_bbs/authorization.ex`) implements
`Bodyguard.Policy`. Callers MUST use `Bodyguard.permit/4` or
`Bodyguard.permit?/4` — never the `authorize/3` callback directly.

**Three call patterns:**

| Where | Call | Purpose |
|-------|------|---------|
| Domain context, before any side effect | `Bodyguard.permit(Foglet.Authorization, action, actor, scope)` | Trust boundary — returns `:ok` or `{:error, :forbidden}`. |
| TUI rendering only | `Bodyguard.permit?(Foglet.Authorization, action, actor, scope)` | Advisory — for graying out / hiding UI. NEVER a security boundary. |
| Operator-visible data filtering | `Foglet.Authorization.scopes_for(actor, action)` | Returns the list of scopes the actor can operate over. |

**Hidden / disabled UI is never authorization** — context mutations must
still re-check policy. `Foglet.TUI.Screens.ShellVisibility` predicates
(`lib/foglet_bbs/tui/screens/shell_visibility.ex`) are visibility hints
only.

**Stable scope shapes:** `:site` and `{:board, board_id}`. Use the
`scope_for/1` helpers from each context to construct scopes:

- `Foglet.Boards.scope_for(%Board{})` → `{:board, id}`
- `Foglet.Threads.scope_for(%Thread{})` → `{:board, board_id}`
- `Foglet.Posts.scope_for(%Post{})` → `{:board, board_id}`

Do not duplicate scope derivation in screens or widgets.

**Action allowlist:** Every action atom MUST appear in `@valid_actions`
(`lib/foglet_bbs/authorization.ex:27-47`). Unknown actions log a warning and
return `{:error, :forbidden}` (D-13 catch-all).

**Actor invariants:** `nil`, soft-deleted, suspended, pending, and rejected
users are forbidden everywhere. These guards run BEFORE role dispatch
(`authorization.ex:88-95`).

## Runtime Configuration

`Foglet.Config` (`lib/foglet_bbs/config.ex`) is a read-through ETS cache
over the `configuration` table.

- Reads: `Config.get!/1`, `Config.get/2`, `Config.fetch/1`.
- Writes (trusted): `Config.put!/3` for seeds, tests, Mix tasks.
- Writes (interactive): `Config.put/3` (actor-aware).
- Schematized keys live in `Foglet.Config.Schema`. Add typed accessors
  (e.g. `Foglet.Config.registration_mode/0`) — never scatter string keys
  through call sites.
- Secrets stay in environment / runtime config, NOT in DB-backed config.

## TUI Conventions

See `lib/foglet_bbs/tui/SCREEN_CONTRACT.md` for the canonical screen contract
and `lib/foglet_bbs/tui/widgets/README.md` for the widget catalog.

**Layer ownership:**

- `Foglet.SSH.CLIHandler` (`lib/foglet_bbs/ssh/cli_handler.ex`) owns the SSH
  channel lifecycle: peer/auth context, session start/promotion, Raxol
  startup, input/resize forwarding, cleanup.
- `Foglet.TUI.App` (`lib/foglet_bbs/tui/app.ex`) owns global UI state, the
  current screen, modal routing, PubSub subscription wiring, commands/tasks,
  and message routing to screens.
- Screen modules under `lib/foglet_bbs/tui/screens/` own screen-local
  rendering and key handling.
- Complex screen state lives in a sibling state module
  (e.g., `Foglet.TUI.Screens.MainMenu.State`).
- Off-process work goes through `Foglet.TUI.Command` / Raxol commands —
  never block the render loop.

**Screen behaviour callbacks (`Foglet.TUI.Screen`):**

- `init/1` receives a `Foglet.TUI.Context` and returns screen-local state.
  Never perform durable writes here.
- `update/3` is the screen reducer: `(message, state, context) -> {state, effects}`.
- `render/2` is pure: it consumes already-loaded state plus context and
  returns a Raxol view tree.
- Optional `subscriptions/2` for PubSub wiring.

**Widget conventions (`lib/foglet_bbs/tui/widgets/README.md`):**

- Stateful widgets expose `init/1`, `handle_event/2`, `render/2`. Stateless
  widgets expose `render/*` only.
- Live under `lib/foglet_bbs/tui/widgets/<bucket>/<name>.ex` — buckets are
  `chrome/`, `composer/`, `display/`, `input/`, `list/`, `modal/`, `post/`,
  `progress/`, `workspace/`. The flat `compose.ex` and `modal.ex` predate the
  bucket layout and stay flat (D-11).
- Cite decision IDs in `@moduledoc` (e.g. `D-07`, `D-09`, `D-13`, `D-14`,
  `D-16`).
- Route ALL colors through `Foglet.TUI.Theme`
  (`lib/foglet_bbs/tui/theme.ex`) slots. Never write `:red`, `:green`,
  `:cyan`, `:yellow`, `:blue`, `:magenta`, `:white`, `:black` atoms directly.
  Theme hygiene is enforced by the catalog smoke test
  (`test/foglet_bbs/tui/widgets/catalog_smoke_test.exs`).
- Pass theme explicitly via a `theme:` keyword argument; never read the
  theme from process state inside a widget.
- `@default_*` / `@on_marker` / similar module-constant defaults declared
  at the top of every widget file (D-08).
- Ship every new widget with a D-18 test (theme hygiene + smoke render) under
  `test/foglet_bbs/tui/widgets/<bucket>/`.

## Comments

**When to comment:**

- Cite decision IDs from planning docs (`D-05`, `D-06`, `D-08`, `BOARD-06`,
  `MODR-02`) so readers can find the context. Search any context module for
  `D-` to see the pattern.
- Mark intentional invariants — see `Foglet.Posts.Post` (`post.ex:1-10`)
  explaining why `body_tsv` is omitted from the schema.
- Note non-obvious ordering — see `Foglet.Authorization` ordering comments
  about mod-vs-sysop denies happening before allowlists.

**`@moduledoc`** is required (Credo `Readability.ModuleDoc` enforced).
Document the public API surface, what consumes it, and which planning phase
introduced the module.

**`@doc`** every public function. Keep it terse — one line is fine when the
function name is self-explanatory.

## Function Design

**Pipelines** dominate. The shape `data |> changeset() |> Repo.insert()` and
`changeset |> validate_x() |> validate_y() |> unique_constraint()` is the
norm.

**Pattern matching** in function heads is preferred over `case` / `cond`
when dispatching on type or status. See `Foglet.Authorization.authorize/3`
clauses (`lib/foglet_bbs/authorization.ex:88-126`) for textbook role/scope
dispatch.

**Multi-arity context functions** for actor-aware vs trusted callers
(see "Context Patterns" above).

**`@spec` typespecs** on every public context function and Bodyguard policy
function. Examples in `lib/foglet_bbs/posts.ex` and `authorization.ex`.

## Module Design

**Exports:** Every public function gets `@doc` plus `@spec`. Private helpers
go below the `# ---------- ... ----------` section banner used throughout
context modules (see `lib/foglet_bbs/posts.ex` for the canonical layout).

**No barrel files.** Each module is imported by full name.

**Section banners** mark module substructure:

```elixir
# ---------- Authorization scope helper (D-08) ----------
# ---------- Post creation (BOARD-03) ----------
# ---------- Post queries ----------
# ---------- Post editing (BOARD-04) ----------
# ---------- Post soft-delete (BOARD-11) ----------
```

Use these to keep context modules navigable as they grow past ~200 lines.

---

*Convention analysis: 2026-04-29*
