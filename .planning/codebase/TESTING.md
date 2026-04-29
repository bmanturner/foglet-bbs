# Testing Patterns

**Analysis Date:** 2026-04-29

Foglet BBS uses ExUnit with a Postgres-backed sandbox for the domain layer,
in-process synthetic state for TUI rendering, and `start_supervised!/1` for
every GenServer under test. The hard rules from `AGENTS.md` §Testing govern
all new tests:

- **Do not write tests that assert on the presence or absence of UI text.**
- **Do not use `Process.sleep/1` or `Process.alive?/1`.** Synchronize with
  `Process.monitor/1` + `assert_receive`, explicit messages, or
  `:sys.get_state/1`.
- **Always use `start_supervised!/1`** for processes; never `start_link` raw
  in tests.

## Test Framework

**Runner:**

- ExUnit (built into Elixir 1.17, see `mix.exs:8`).
- Property tests via `:stream_data` (`mix.exs:61`) using `ExUnitProperties`.
- No separate assertion library — ExUnit's `assert` / `refute` /
  `assert_receive` / `assert_raise` cover everything.

**Test setup files:**

- `test/test_helper.exs` (`test_helper.exs:1-3`):
  ```elixir
  ExUnit.start(exclude: [:pending])
  Ecto.Adapters.SQL.Sandbox.mode(FogletBbs.Repo, :manual)
  ```
- Test config: `config/test.exs` — fast Argon2 (`t_cost: 1, m_cost: 8`),
  `:logger` at `:warning`, `start_ssh_daemon: false` so tests drive SSH
  through `start_supervised!/1`.

**Run commands:**

```bash
rtk mix test                             # Run all tests (creates+migrates DB, seeds config)
rtk mix test test/foglet_bbs/boards/    # Run a directory
rtk mix test test/foglet_bbs/boards/board_server_test.exs:86  # Single test by line
rtk mix test --only pending             # Tests tagged @tag :pending are excluded by default
rtk mix precommit                       # Full gauntlet: warnings-as-errors, format, Credo, Sobelow, Dialyzer
```

The `test` alias in `mix.exs:85-90` runs `ecto.create --quiet`,
`ecto.migrate --quiet`, `run priv/repo/seeds/config.exs`, then `test`. The
`config.exs` seed file ensures the runtime config table is populated before
any test boots.

## Test File Organization

**Mirrored directory layout:** Tests under `test/foglet_bbs/` mirror source
under `lib/foglet_bbs/`.

```
lib/foglet_bbs/boards/server.ex            → test/foglet_bbs/boards/board_server_test.exs
lib/foglet_bbs/authorization.ex             → test/foglet_bbs/authorization_test.exs
lib/foglet_bbs/sessions/session.ex          → test/foglet_bbs/sessions/session_test.exs
lib/foglet_bbs/tui/app.ex                   → test/foglet_bbs/tui/app_test.exs
lib/foglet_bbs/tui/widgets/list/list_row.ex → test/foglet_bbs/tui/widgets/list/list_row_test.exs
```

**Top-level test directories:**

- `test/foglet_bbs/` — domain tests (Accounts, Boards, Threads, Posts,
  Sessions, SSH, TUI, Authorization, Config, Markdown, etc.).
- `test/foglet_bbs_web/` — Phoenix web tests.
- `test/mix/` — Mix task tests.
- `test/support/` — shared test helpers and fixtures, compiled only for the
  `:test` env (see `mix.exs:38`).

**Naming:** `<source>_test.exs`, with module name `Foglet.<Source>Test`.
Credo enforces `Warning.WrongTestFilename`.

## Test Cases (`test/support/`)

**`FogletBbs.DataCase` (`test/support/data_case.ex`)** — for DB-backed tests:

```elixir
use FogletBbs.DataCase, async: true   # async OK because of per-test Sandbox owner
# or
use FogletBbs.DataCase, async: false  # required for tests that touch shared services
                                      # (Board Server registry, ETS config cache mutations)
```

It auto-imports `Ecto`, `Ecto.Changeset`, `Ecto.Query`, aliases `Repo`, and
provides `errors_on/1` for changeset-error assertions:

```elixir
assert {:error, changeset} = Foglet.Boards.create_category(%{name: ""})
assert "can't be blank" in errors_on(changeset).name
```

**`FogletBbsWeb.ConnCase` (`test/support/conn_case.ex`)** — for Phoenix
controller tests; sets up `Phoenix.ConnTest`, builds a fresh conn, runs the
sandbox.

**`ExUnit.Case`** — for pure-data tests (no DB, no shared processes). Used in
`test/foglet_bbs/authorization_test.exs`,
`test/foglet_bbs/sessions/session_test.exs`,
`test/foglet_bbs/tui/widgets/list/list_row_test.exs`,
`test/foglet_bbs/tui/screens/shell_visibility_test.exs`.

## Sandbox Pattern (Critical for GenServer Tests)

`Ecto.Adapters.SQL.Sandbox.mode(:manual)` is set globally in
`test_helper.exs`. Every DB-touching test gets its own per-test owner
through `DataCase.setup_sandbox/1`. When a test starts a GenServer that
makes its own DB calls, the GenServer process needs explicit access:

```elixir
# test/foglet_bbs/boards/board_server_test.exs:31-42
defp start_server!(board_id, extra_id \\ nil) do
  sup_id = {:board_server, board_id, extra_id}

  pid =
    start_supervised!(
      {Server, board_id: board_id},
      id: sup_id
    )

  Sandbox.allow(Repo, self(), pid)
  {pid, sup_id}
end
```

Tests that start a Board Server through `Foglet.Boards.create_board/3`
(which auto-supervises a Server) use a sibling helper:

```elixir
# test/foglet_bbs/boards/boards_test.exs:32-36
defp allow_board_server!(board_id) do
  [{pid, _}] = Registry.lookup(Foglet.BoardRegistry, board_id)
  Sandbox.allow(Repo, self(), pid)
  pid
end
```

**`board_fixture/2` does NOT call `Sandbox.allow` automatically** — see the
note in `test/support/boards_fixtures.ex:21-31`. Call `allow_board_server!`
yourself when the test will drive thread/post creation.

## Process Synchronization Patterns

The repo follows AGENTS.md §Testing strictly. Patterns to copy:

**`Registry.lookup/2` proves liveness** without `Process.alive?/1`:

```elixir
# test/foglet_bbs/boards/board_server_test.exs:54-55
assert [{^pid, nil}] = Registry.lookup(Foglet.BoardRegistry, board.id)
```

**`:sys.get_state/1` flushes async casts and inspects state**:

```elixir
# test/foglet_bbs/boards/board_server_test.exs:120-122
%{next_number: n} = :sys.get_state(pid)
assert n == 1
```

```elixir
# test/foglet_bbs/sessions/session_test.exs:103-107
:ok = Session.heartbeat(user_id)
_ = :sys.get_state(Session.via_tuple(user_id))  # drain mailbox
later = Session.get_state(user_id).last_seen_at
```

**`Process.monitor/1` + `assert_receive {:DOWN, ...}`** for shutdown checks:

```elixir
# test/foglet_bbs/sessions/supervisor_test.exs:30-39
ref = Process.monitor(old_pid)
{:ok, new_pid} = Sup.start_session(user_id: user_id, handle: "alice2", role: :user)
assert_receive {:DOWN, ^ref, :process, ^old_pid, _}, 3_000
```

```elixir
# test/foglet_bbs/sessions/session_test.exs:91-95
ref = Process.monitor(pid)
send(pid, :replaced_by_new_session)
assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000
```

**`assert_receive` with explicit timeouts** (1_000–3_000 ms) for any
inter-process message expectation. Never use `Process.sleep/1` to "give the
GenServer a chance to handle" something — flush with `:sys.get_state/1`
instead.

## Fixtures and Factories

**Domain fixtures** (`test/support/`) — thin wrappers around real context
functions, with `System.unique_integer([:positive])` for unique strings:

- **`FogletBbs.AccountsFixtures` (`test/support/accounts_fixtures.ex`):**
  - `valid_user_attributes/1` returns a map with unique handle/email/password.
  - `user_fixture/1` calls `Foglet.Accounts.register_user/1`.
  - `invite_fixture/1,2` overloaded on `User` struct vs map.
  - `ssh_key_fixture/2` calls `Foglet.Accounts.register_ssh_key/2`.
  - `user_token_fixture/2` builds + inserts an email token.

- **`FogletBbs.BoardsFixtures` (`test/support/boards_fixtures.ex`):**
  - `category_fixture/1`, `board_fixture/2`, `thread_fixture/3`,
    `post_fixture/3` all delegate to the real context functions, ensuring
    the message-number invariant holds.
  - `valid_board_attributes/1`, `valid_thread_attributes/1`,
    `valid_post_attributes/1` for changeset-shape tests.

- **Inline insert helpers** (`test/foglet_bbs/boards/board_server_test.exs:15-29`)
  bypass authz when the test cares only about Server behaviour:
  ```elixir
  defp insert_category!, do: %Category{} |> Category.changeset(%{...}) |> Repo.insert!()
  defp insert_board!(category), do: %Board{} |> Board.changeset(%{...}) |> Repo.insert!()
  ```

- **Plain-struct actors** (no DB) for authorization tests
  (`test/foglet_bbs/authorization_test.exs:13-23`):
  ```elixir
  defp actor(:sysop), do: %User{role: :sysop, status: :active, deleted_at: nil}
  defp actor(:mod),   do: %User{role: :mod,   status: :active, deleted_at: nil}
  ```

**Test doubles / fakes** (`test/support/`) — used to break boundaries in TUI
tests without spinning up the full stack:

- `Foglet.TUI.FakeAccounts` (`test/support/fake_accounts.ex`) — process
  dictionary–configured stub. Sends `{:list_user_status_admin_targets, user}`
  to the test owner so call-site assertions can fire without observing UI
  text.
- `Foglet.TUI.FakeModeration`, `Foglet.TUI.FakeOneliners` — same pattern.

**Fixtures convention:** Always go through the real context API for the happy
path. Direct `Repo.insert!` is reserved for tests that need to bypass policy
or invariants intentionally.

## TUI Render Fixtures and Inspection Tooling

`Foglet.TUI.RenderFixtures` (`lib/foglet_bbs/tui/render_fixtures.ex`) is
**production code** (not under `test/support/`) because the
`mix foglet.tui.render` task uses it. It builds synthetic in-memory `%App{}`
state for any of the canonical screens — no Repo, no SSH, no PubSub.

```
@screens ~w(login register verify main_menu board_list thread_list
            post_reader post_composer new_thread account moderation sysop)a
```

**`mix foglet.tui.render` (`lib/mix/tasks/foglet.tui.render.ex`)** renders any
TUI screen as plain text so you (or an agent) can inspect layout without an
SSH client. Use this during TUI development:

```bash
rtk mix foglet.tui.render main_menu                       # default 80×24
rtk mix foglet.tui.render board_list --width 132 --height 50
rtk mix foglet.tui.render --list                          # list available screens
rtk mix foglet.tui.render login --no-frame                # omit alignment ruler
```

The synthetic user is `@alice` (sysop role); board/thread/post fixtures come
from `Foglet.TUI.RenderFixtures`. Output is ANSI-stripped so it diffs
cleanly. Use this for **visual inspection**, not behavioural assertions.

**Snapshot files in `test/foglet_bbs/tui/render_snapshots/`** (e.g.
`main_menu.txt`, `board_list.txt`, `thread_list.txt`, `post_reader.txt`,
`account.txt`) are committed reference renders for human review of layout
changes. They are not loaded as test assertions.

## The Layout Smoke Test Pattern

`test/foglet_bbs/tui/layout_smoke_test.exs` (~104 KB) is the canonical
regression net for screen rendering. It drives every layout-intensive screen
through the same `Raxol.UI.Layout.Engine.apply_layout/2` pipeline the live
TUI uses, then asserts on **positioned element geometry** — never on the
literal text of UI labels.

**The pattern (`layout_smoke_test.exs:46-88`):**

1. `use FogletBbs.DataCase, async: false` because the ETS config cache is
   shared.
2. Seed the config cache in `setup` so render paths that hit
   `Foglet.Config.get/2` don't crash without a DB checkout:
   ```elixir
   setup do
     Config.init_cache()
     :ets.insert(:foglet_config, {"registration_mode", "open"})
     :ets.insert(:foglet_config, {"email_verify_resend_cooldown_seconds", 60})
     :ok
   end
   ```
3. Build a `Foglet.TUI.Context.t()` and call `App.view/1` (or screen-specific
   helpers like `render_login/1`).
4. Pass the resulting tree through `Engine.apply_layout/2` at canonical
   sizes (`{64,22}`, `{80,24}`, `{132,50}`).
5. Walk the positioned list with `text_elements/1` /
   `content_text_elements/1` (filtering out chrome) to extract `{x, y, text}`
   tuples.
6. Assert geometric properties: distinct y rows for stacked children,
   `display_width` ≤ width, expected ordering, etc.

**What this test catches:** the regression where the old `box(children: ...)`
DSL stacked all children at the same y, so the last child overwrote previous
ones. Geometry-based assertions catch that immediately while text-presence
assertions would not.

**Per-screen smoke tests** under `test/foglet_bbs/tui/screens/<screen>_test.exs`
follow the same shape: drive the screen through render at multiple sizes,
assert on geometric and contract properties (focus, key handling, effect
emission), never on the literal label strings.

## TUI Render-Tree Walker Helpers

Three shared modules under `test/support/foglet/tui/` exist because every
widget test was duplicating the same DFS walkers:

- **`Foglet.TUI.WidgetHelpers`** (`test/support/foglet/tui/widget_helpers.ex`)
  - `flatten_text/1` — concatenate all `:content` / `:text` leaves in
    document order.
  - `color_atom_leaked?/2` — word-boundary regex that catches a leaked color
    atom like `:red` while ignoring legitimate slot names like
    `:hovered_red`. Powers the theme-hygiene contract.
  - `color_names/0` — the eight core color atoms widgets must never emit.
  - `text_runs/1`, `assert_text_run/3` — locate a text node by content and
    assert on its style keywords.

- **`Foglet.TUI.RenderHelpers`** (`test/support/foglet/tui/render_helpers.ex`)
  - `collect_text_values/1` — DFS-ordered list of `:text`-node `:content`
    strings. Used for relative-ordering assertions in screen tests
    (Account, MainMenu, Moderation, Sysop, InvitesSurface).

- **`Foglet.TUI.LayoutSmokeHelpers`** (`test/support/foglet/tui/layout_smoke_helpers.ex`)
  - `set_active_tab/2` — activate a named tab inside an operator-screen
    state struct before rendering. Used by Phase 25 tab-contract smoke tests.

Wire in by adding `import Foglet.TUI.WidgetHelpers` (or whichever helper
module) at the top of the test module.

## Catalog Smoke Test (Theme Hygiene)

`test/foglet_bbs/tui/widgets/catalog_smoke_test.exs` renders one widget from
each bucket through a common theme and asserts:

1. Every render returns non-nil.
2. The combined serialized tree contains no hardcoded color atom (per
   `WidgetHelpers.color_atom_leaked?/2`).
3. Switching the theme produces a different combined render (catches
   widgets that ignore their `theme:` argument).

This catches the regression where individual widget hygiene tests pass but a
new widget added without a `build_*_theme/1` helper leaks colors when
composed. Add new buckets / widgets here when you create them.

## Authorization Test Matrix

`test/foglet_bbs/authorization_test.exs` is the canonical example of a
**data-driven matrix** for policy modules:

```elixir
@matrix [
  {:sysop, :create_board,  :site, :ok},
  {:mod,   :lock_thread,   :site, :ok},
  {:mod,   :create_board,  :site, {:error, :forbidden}},
  {:user,  :generate_invite, :site, :ok},
  ...
]

for {actor_key, action, scope, expected} <- @matrix do
  @tag actor_key: actor_key, action: action, scope: scope, expected: expected
  test "#{actor_key} #{action} #{inspect(scope)} -> #{inspect(expected)}", %{...} do
    assert Bodyguard.permit(Authorization, action, actor(actor_key), scope) == expected
  end
end
```

Use this pattern (compile-time `for`-generated tests with `@tag` metadata)
whenever a module has a finite policy/decision matrix worth exhaustive
coverage.

## Property Tests

GenServer concurrency invariants get property tests. Example from
`test/foglet_bbs/boards/board_server_test.exs:161-203`:

```elixir
use FogletBbs.DataCase, async: false
use ExUnitProperties

property "message numbers are monotonically sequential under concurrent inserts" do
  check all(count <- integer(2..6), max_runs: 5) do
    # ... start board, run `count` concurrent inserts ...
    expected = Enum.to_list(1..length(numbers))
    assert numbers == expected
    stop_supervised!(sup_id)
  end
end
```

`max_runs:` is kept low (3–5) when each iteration provisions DB rows; bump
it for in-memory invariants.

## Coverage

**No coverage threshold is enforced.** `mix.exs` contains no `:test_coverage`
config and `mix precommit` does not run coverage. Run coverage manually:

```bash
rtk mix test --cover
```

Aim for high coverage on `Foglet.<Domain>` contexts and the Bodyguard policy.
TUI screen modules are covered by the layout smoke test plus per-screen
geometric tests; do not chase line coverage on render functions with
text-presence assertions.

## What NOT to Do

- **Do not assert on UI text.** This is repeated in `AGENTS.md` and reflects
  hard experience: text-presence tests churn endlessly during copy edits and
  miss real layout regressions. Assert on positioned geometry (`x`, `y`,
  `display_width`), on emitted effects, on changeset/struct shape, or on
  process state via `:sys.get_state/1`.
- **Do not use `Process.sleep/1`.** Synchronize with `:sys.get_state/1`,
  `Process.monitor/1` + `assert_receive`, or `send/2` + `assert_receive`.
- **Do not use `Process.alive?/1`.** A successful `Registry.lookup/2`,
  `GenServer.call/2`, or `:sys.get_state/1` already proves liveness — and
  `Process.alive?/1` introduces a TOCTOU race.
- **Do not raw `start_link` a process in a test.** Use `start_supervised!/1`
  so ExUnit tears the process down between tests.
- **Do not put non-test fixtures in `lib/`.** `Foglet.TUI.RenderFixtures` is
  the documented exception because the `mix foglet.tui.render` task needs
  it; everything else lives under `test/support/`.

## Common Patterns

**Async testing pattern:**

```elixir
use FogletBbs.DataCase, async: true   # OK — Sandbox owner is per-test

# For tests touching shared ETS, Registry, or DynamicSupervisor:
use FogletBbs.DataCase, async: false
use ExUnit.Case, async: false
```

**Error testing:**

```elixir
assert {:error, changeset} = Foglet.Boards.create_category(%{name: ""})
assert "can't be blank" in errors_on(changeset).name

assert {:error, :forbidden} =
         Foglet.Boards.create_category(%User{role: :user, status: :active}, %{name: "X"})
```

**Log capture:**

```elixir
import ExUnit.CaptureLog

log = capture_log(fn ->
  assert {:error, :forbidden} =
           Bodyguard.permit(Authorization, :unknown, actor(:sysop), :site)
end)
assert log =~ "Unknown action atom"
```

(See `test/foglet_bbs/authorization_test.exs:103-118`.)

---

*Testing analysis: 2026-04-29*
