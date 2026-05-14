<!-- generated-by: gsd-doc-writer -->
# Testing

This document describes how Foglet BBS is tested: the framework, layout, fixtures, and
the patterns specific to OTP processes, the per-board Board Server, the Bodyguard
authorization policy, the Raxol TUI, and break-glass Mix tasks.

## Test framework and setup

Foglet BBS uses **ExUnit** (the testing framework that ships with Elixir 1.17). Property
tests use **`stream_data`** via `ExUnitProperties` (`mix.exs` `:stream_data`, declared
`only: [:dev, :test]`).

Setup before running tests for the first time:

```bash
mix deps.get
mix ecto.create
mix ecto.migrate
```

The `mix test` alias in `mix.exs` runs `ecto.create --quiet`, `ecto.migrate --quiet`,
and the test-config seed (`run priv/repo/seeds/config.exs`) before invoking ExUnit, so
in normal use you only need to run `mix test`.

`test/test_helper.exs` starts ExUnit with `exclude: [:pending]` and puts the Ecto SQL
sandbox in `:manual` mode, meaning every test must check out a connection (handled
automatically by `FogletBbs.DataCase` and `FogletBbsWeb.ConnCase`).

## Running tests

```bash
# Full suite
mix test

# A single file
mix test test/foglet_bbs/authorization_test.exs

# A single test by line number
mix test test/foglet_bbs/authorization_test.exs:104

# Only tests tagged with a specific tag
mix test --only some_tag
```

### Partitioned tests in CI

`config/test.exs` reads `MIX_TEST_PARTITION` to derive a partition-specific database
name:

```elixir
database: "foglet_bbs_test#{System.get_env("MIX_TEST_PARTITION")}"
```

To run partition N of M in CI:

```bash
MIX_TEST_PARTITION=1 mix test --partitions 4
```

Each partition needs its own database (`foglet_bbs_test1`, `foglet_bbs_test2`, ...).

## Test layout

```
test/
├── test_helper.exs                # ExUnit start + sandbox :manual mode
├── foglet_bbs/                    # Mirrors lib/foglet_bbs/ and lib/foglet/
│   ├── accounts/
│   ├── boards/                    # board_server_test.exs, boards_test.exs
│   ├── threads/
│   ├── posts/
│   ├── sessions/
│   ├── ssh/
│   ├── moderation/
│   ├── oneliners/
│   ├── config/
│   ├── authorization/             # (currently empty placeholder dir)
│   ├── authorization_test.exs     # Bodyguard policy matrix
│   ├── config_test.exs
│   ├── markdown_test.exs
│   ├── accounts_verify_code_test.exs
│   └── tui/
│       ├── app_test.exs
│       ├── command_test.exs
│       ├── layout_smoke_test.exs
│       ├── presentation_test.exs
│       ├── size_gate_test.exs
│       ├── text_width_test.exs
│       ├── theme_test.exs
│       ├── screens/               # one *_test.exs per screen
│       └── widgets/               # chrome, composer, display, input,
│                                  # list, modal, post, progress, workspace
├── foglet_bbs_web/                # Phoenix controller/conn tests
│   └── controllers/
├── mix/
│   └── tasks/                     # Break-glass Mix task tests
└── support/                       # Compiled into :test (see mix.exs elixirc_paths)
    ├── data_case.ex
    ├── conn_case.ex
    ├── accounts_fixtures.ex
    ├── boards_fixtures.ex
    ├── fake_moderation.ex
    ├── fake_oneliners.ex
    └── foglet/
        └── tui/
            ├── widget_helpers.ex      # flatten_text/1, color_atom_leaked?/2,
            │                          # text_runs/1, assert_text_run/3
            ├── render_helpers.ex      # collect_text_values/1 (DFS document order)
            ├── layout_smoke_helpers.ex
            └── layout_smoke/
                ├── account_helper.ex
                ├── moderation_helper.ex
                └── sysop_helper.ex
```

`mix.exs` sets `elixirc_paths(:test)` to `["lib", "test/support"]`, so anything under
`test/support/` is compiled and importable from test modules.

## Test cases

Two `ExUnit.CaseTemplate` modules cover most tests:

| Case template | When to use | Sandbox behavior |
|---|---|---|
| `FogletBbs.DataCase` | Tests that touch the Repo (contexts, schemas, Mix tasks, board servers) | SQL sandbox; `async: true` uses an isolated owner, `async: false` uses shared mode |
| `FogletBbsWeb.ConnCase` | Phoenix controller / Plug tests; provides `conn` in the context | Same sandbox setup as `DataCase`, plus `Phoenix.ConnTest.build_conn/0` |

Tests that do not touch the Repo (most TUI widget tests) use plain
`use ExUnit.Case, async: true`.

## TUI behavior, buffer, and inspection tests

Use the narrowest TUI test that protects the behavior:

- Reducer and context tests should call `init/1`, `update/3`, and focused state
  helpers directly when the invariant is about behavior, effects, authorization
  routing, validation, or state transitions.
- Widget unit tests should call the widget `render/*` or
  `init/1` + `handle_event/2` + `render/2` contract directly when the invariant
  belongs to a reusable widget.
- Buffer snapshot tests can import `Foglet.TUI.Test` and use
  `render_screen/3`, `render_fixture/2`, `assert_screen/2`, and `~B` when the
  invariant is the whole rendered buffer at a known terminal size. `~B` removes
  heredoc indentation and one surrounding newline, but it does not trim trailing
  row whitespace.
- Layout smoke tests remain for broad cross-screen size contracts and layout
  engine regressions that are easier to express structurally than as snapshots.
- Manual inspection with `rtk mix foglet.tui.render <screen>` is the fastest way
  to review layout while developing; it is evidence for humans, not a
  regression assertion by itself.
- SSH harness QA is for live terminal workflows, authentication/session
  behavior, and permission gates that need a running Foglet instance.

Avoid single-fragment text-presence tests for visual behavior. Prefer reducer
assertions for behavior, widget assertions for reusable primitives, or
whole-buffer snapshots when exact layout and chrome are the thing being pinned.

### Buffer snapshot conventions

Use buffer snapshots for stable, user-visible screen states, not for every render
branch. Name snapshot tests after the state they freeze, for example
`"renders empty catalog"` or `"renders launch confirmation modal"`, and keep them
near the behavior tests for the same screen. New screen snapshots should import
`Foglet.TUI.Test` and render either a focused screen state with `render_screen/3`
or one of the synthetic manual-inspection fixtures with `render_fixture/2`.

When a snapshot includes chrome, freeze every clock-sensitive input in the
context. Set `session_context.clock_now` to a fixed `DateTime`, and set the
user's time-format preference fields that the chrome or screen reads. This keeps
snapshots from changing with wall-clock time or local preference defaults. Use
the smallest terminal size that proves the layout, usually `80x24`, and add a
second wider snapshot only when the responsive behavior is the invariant.

Update snapshots intentionally. First run `rtk mix foglet.tui.render <screen>`
for quick visual inspection when the fixture exists, then update the `~B`
expected buffer only after confirming the visual change is intended. Prefer a
new snapshot for a meaningfully different state over widening one expected
buffer until it becomes hard to read.

### Layout smoke coverage

`test/foglet_bbs/tui/layout_smoke_test.exs` is broad integration coverage for
the Raxol layout engine and the highest-risk screen shells. It is intentionally
not the default pattern for new screen work. Add focused reducer, widget, or
buffer snapshot tests first; extend the smoke test only when the change touches
cross-screen layout contracts, chrome placement, or size behavior that is
awkward to express as one exact buffer.

When the smoke file grows, keep related helper code in
`test/support/foglet/tui/layout_smoke/` and add comments to new sections that
explain the layout invariant being protected. If a new screen needs several
fixtures or tab states, prefer a per-screen support helper over another large
inline setup block.

## Ecto sandbox

`FogletBbs.DataCase.setup_sandbox/1` is the single sandbox entry point used by both
`DataCase` and `ConnCase`:

```elixir
def setup_sandbox(tags) do
  pid = Ecto.Adapters.SQL.Sandbox.start_owner!(FogletBbs.Repo, shared: not tags[:async])
  on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
end
```

- `use FogletBbs.DataCase, async: true` -> isolated owner, no shared mode.
- `use FogletBbs.DataCase, async: false` -> **shared mode**. Required when the test
  spawns processes (e.g. a `Foglet.Boards.Server`) that must read/write the same
  connection the test owns.

When you start a process under `start_supervised!/1` in an `async: true` test that
needs DB access, explicitly grant it with `Ecto.Adapters.SQL.Sandbox.allow/3`. The
board server tests show the canonical pattern:

```elixir
defp start_server!(board_id, extra_id \\ nil) do
  pid = start_supervised!({Server, board_id: board_id}, id: {:board_server, board_id, extra_id})
  Sandbox.allow(Repo, self(), pid)
  {pid, {:board_server, board_id, extra_id}}
end
```

## OTP and process testing rules

These rules are enforced across the test suite:

- **Use `start_supervised!/1`** for every process you start in a test. ExUnit shuts it
  down at the end of the test, which keeps the supervision tree clean across runs.
- **Avoid `Process.sleep/1`.** Synchronize on observable state instead.
- **Avoid `Process.alive?/1`.** Prove liveness through observable side effects (a
  Registry lookup, a returned reply, a received message).
- **Synchronize with monitors, explicit messages, or `:sys.get_state/1`** for GenServers.

Example (from `test/foglet_bbs/boards/board_server_test.exs`): the test asserts the
server is alive by looking it up in `Foglet.BoardRegistry`, and it inspects internal
state via `:sys.get_state(pid)`:

```elixir
assert [{^pid, nil}] = Registry.lookup(Foglet.BoardRegistry, board.id)
%{next_number: n} = :sys.get_state(pid)
assert n == 1
```

## Per-board message-number invariants

Per-board message numbers are a core invariant (see `docs/ARCHITECTURE.md`). They are tested in
`test/foglet_bbs/boards/board_server_test.exs`. The pattern is:

1. Insert a category and board directly via the schemas (the test owns the DB
   connection).
2. Start a `Foglet.Boards.Server` under `start_supervised!/1`, scoped by an `id` that
   includes `board_id` so multiple servers in one test do not collide.
3. Call `Sandbox.allow(Repo, self(), pid)` to let the server see uncommitted rows.
4. Drive thread/post creation through `Server.create_thread/3` and
   `Server.create_post/4` (never directly through schemas), then assert
   `message_number` values and that `:sys.get_state(pid).next_number` advances only on
   success.

There is also a `stream_data` property test that verifies monotonic sequential
allocation under repeated inserts:

```elixir
property "message numbers are monotonically sequential under concurrent inserts" do
  check all(count <- integer(2..6), max_runs: 5) do
    # ... start server, create thread, create N replies, assert numbers == 1..N+1
  end
end
```

## Authorization tests

`Foglet.Authorization` is a `Bodyguard.Policy`. The canonical test
(`test/foglet_bbs/authorization_test.exs`) drives a **policy matrix** of
`{actor_key, action, scope, expected}` tuples through `Bodyguard.permit/4`:

```elixir
@matrix [
  {:sysop, :edit_config, :site, :ok},
  {:mod,   :lock_thread, {:board, @board_id}, :ok},
  {:mod,   :edit_config, :site, {:error, :forbidden}},
  {:user,  :create_board, :site, {:error, :forbidden}},
  # ...
]

for {actor_key, action, scope, expected} <- @matrix do
  @tag actor_key: actor_key, action: action, scope: scope, expected: expected
  test "#{actor_key} #{action} #{inspect(scope)} -> #{inspect(expected)}", %{...} do
    actor = actor(actor_key)
    assert Bodyguard.permit(Authorization, action, actor, scope) == expected
  end
end
```

Conventions:

- **Actors are plain `%User{}` structs**, not DB rows. The test runs
  `async: true` and never hits the Repo. Only fields the policy reads (`role`,
  `status`, `deleted_at`) are populated.
- Cover invalid actor states explicitly: `nil`, `:suspended`, `:pending`, `:rejected`,
  soft-deleted (`deleted_at` set).
- Test the boolean wrapper `Bodyguard.permit?/4` and the scope helper
  `Foglet.Authorization.scopes_for/2` separately.
- Unknown action atoms log a warning and return `{:error, :forbidden}`; assert this
  with `ExUnit.CaptureLog`.

When testing context functions that perform `Bodyguard.permit/4` internally, build the
appropriate `%User{}` struct directly (or use `AccountsFixtures.user_fixture/1` if a
real DB-backed user is needed).

## TUI tests

Raxol screen and widget tests live under `test/foglet_bbs/tui/`. They render the widget
or screen to a Raxol render tree and make assertions about the resulting structure.

### Shared TUI helpers (`test/support/foglet/tui/`)

| Helper | Purpose |
|---|---|
| `Foglet.TUI.WidgetHelpers.flatten_text/1` | Concatenates every `:content`/`:text` leaf in a render tree into one string for substring assertions. |
| `Foglet.TUI.WidgetHelpers.color_atom_leaked?/2` | Word-boundary regex to detect a leaked color atom (e.g. `:red`) in a serialized tree, without false positives on `:hovered_red` or `"red-30"`. |
| `Foglet.TUI.WidgetHelpers.text_runs/1` | Returns text-bearing nodes in document order for targeted style-run checks. |
| `Foglet.TUI.WidgetHelpers.assert_text_run/3` | Asserts a text run with given content has matching style keys. |
| `Foglet.TUI.WidgetHelpers.color_names/0`, `milestone_glyphs/0` | The canonical lists used by hygiene tests. |
| `Foglet.TUI.RenderHelpers.collect_text_values/1` | Returns every `:text`-node `:content` in DFS document order (preserves ordering for tab-label assertions). |
| `Foglet.TUI.LayoutSmokeHelpers.set_active_tab/2` | Activates a tab by label string on a screen state struct (used by Phase 25 size-contract smoke tests). |
| `Foglet.TUI.LayoutSmoke.{Account,Moderation,Sysop}Helper` | Per-screen layout-smoke fixtures. |

### Widget tests

Widget tests use plain `use ExUnit.Case, async: true` and exercise pure render
functions. Pattern (from `test/foglet_bbs/tui/widgets/list/smart_list_test.exs`):

```elixir
defmodule Foglet.TUI.Widgets.List.SmartListTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers,
    only: [flatten_text: 1, color_atom_leaked?: 2, color_names: 0, assert_text_run: 3]

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.List.SmartList

  defp theme, do: Theme.default()

  test "single-select default values" do
    st = SmartList.init(options: [{"A", 1}, {"B", 2}])
    assert st.multiple == false
    # ...
  end
end
```

Stateful widgets are tested via their `init/1`, `handle_event/2`, and `render/2`
contracts; stateless widgets are tested by calling render functions directly and
inspecting the returned tree.

### Screen and App tests

Screen tests live in `test/foglet_bbs/tui/screens/` and the App-level test in
`test/foglet_bbs/tui/app_test.exs`. They typically:

- Inject **fakes** for domain modules by passing a `domain:` map in context, e.g.
  `%{domain: %{oneliners: Foglet.TUI.FakeOneliners, moderation: Foglet.TUI.FakeModeration}}`.
  The fakes (`test/support/fake_oneliners.ex`, `test/support/fake_moderation.ex`) send
  messages to the test process so assertions can verify exactly what the screen
  called.
- Use `Foglet.TUI.RenderHelpers.collect_text_values/1` to assert both presence and
  ordering of labels in the DFS-walked render tree.
- Keep render pure. `test/foglet_bbs/tui/render_purity_test.exs` scans render
  entry points and render/surface modules for obvious side effects. Seed
  `Foglet.Config` only for reducer/task tests that intentionally exercise
  config-backed behavior; render paths should receive already-loaded config
  decisions through screen state or `session_context`.

## Mix task tests

Break-glass Mix tasks (`mix foglet.user.*`, `mix foglet.users.*`,
`mix foglet.invites.*`, `mix foglet.verification.inspect`,
`mix foglet.reset_token.inspect`, `mix foglet.reset_token.expire`,
`mix foglet.qa.mode`, `mix foglet.board_subscriptions`) are tested
under `test/mix/tasks/`. The pattern (from
`test/mix/tasks/foglet_user_create_test.exs`):

```elixir
use FogletBbs.DataCase, async: false
import ExUnit.CaptureIO

setup do
  Mix.shell(Mix.Shell.IO)  # so capture_io can see Mix.shell output
  :ok
end

test "creates a user given --handle --email --password" do
  output =
    capture_io(fn ->
      Mix.Tasks.Foglet.User.Create.run(["--handle", "x", "--email", "x@x", "--password", "..."])
    end)

  assert output =~ "Created user"
end
```

Failure modes are tested with `catch_exit` against `{:shutdown, 1}` and
`capture_io(:stderr, fn -> ... end)` for usage messages.

## Fixtures and factories

Fixtures (not factories — there is no ExMachina) live under `test/support/`:

- `FogletBbs.AccountsFixtures` — `valid_user_attributes/1`, `user_fixture/1`,
  `invite_fixture/1,2`, `ssh_key_fixture/2`, `user_token_fixture/2`,
  `default_ssh_public_key/0`. All routed through `Foglet.Accounts` public functions
  so changeset and side-effect logic exercises the real path.
- `FogletBbs.BoardsFixtures` — `category_fixture/1`, `board_fixture/2`,
  `thread_fixture/3`, `post_fixture/3`, `user_fixture/1`,
  `valid_board_attributes/1`, `valid_thread_attributes/1`,
  `valid_post_attributes/1`. `board_fixture/2` calls `Foglet.Boards.create_board/3`
  with a synthetic sysop actor so the authorization guard is satisfied.

**Important:** `thread_fixture/3` and `post_fixture/3` require a running
`Foglet.Boards.Server` for the board (because that GenServer is the single writer for
message numbers). Tests that use these helpers must `start_supervised!/1` the server
and `Sandbox.allow/3` it before calling the fixtures.

Conventions:

- Use `System.unique_integer([:positive])` to generate unique slugs, handles, emails.
- Pass an `overrides`/`attrs` map as the last argument to override defaults.
- Fixtures return `{:ok, struct}` from the underlying context call and unwrap to the
  struct (raising on `:error`) — they are not meant for negative-path tests.

## Coverage and quality gates

There is **no coverage threshold configured** (no `:test_coverage` config in
`mix.exs` and no `.nycrc`/`c8` equivalents — Elixir uses `mix test --cover`, which is
not enabled by default in this project).

Quality is enforced through the `precommit` alias (`mix.exs`):

```elixir
precommit: [
  "compile --warnings-as-errors",
  "deps.unlock --unused",
  "format",
  "credo --strict",
  "sobelow --exit Low",
  "dialyzer"
]
```

Run it whenever code changes are complete:

```bash
mix precommit
```

## CI integration

CI runs on every push and pull request via `.github/workflows/ci.yml`. The job
provisions Postgres 16, installs Erlang/Elixir from `.tool-versions` (strict
match), caches `deps`, `_build`, and the Dialyzer PLT, then runs the full
quality pipeline:

```
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix hex.audit
mix sobelow --exit Low
mix dialyzer
mix test
```

The test step uses `DATABASE_URL=ecto://postgres:postgres@localhost/foglet_bbs_test`.
`MIX_TEST_PARTITION` support is wired into `config/test.exs` but not currently
used by the workflow — partitioning can be added without code changes.

A `core.hooksPath` of `.githooks` is configured by `mix setup` (`mix.exs`
aliases) so local pre-commit / pre-push hooks under `.githooks/` will run if
present.
