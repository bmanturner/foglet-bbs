%{
  title: "Development",
  weight: 20
}
---

This page is for contributors working on Foglet itself. If you are running a
BBS, start with the installation, configuration, and operations docs instead.
This page names test helpers, render tools, and local QA fixtures that should
not appear in normal operator instructions.

Foglet is an SSH-first bulletin board system. Phoenix provides infrastructure:
endpoint, PubSub, telemetry, LiveDashboard, health checks, and the public docs
surface. Do not add end-user browser workflows unless the architecture changes
make that surface intentional.

## Local setup

Install the toolchain from `.tool-versions`, then fetch dependencies and prepare
the database:

```bash
mix deps.get
mix ecto.setup
```

`mix ecto.setup` creates the database, runs migrations, and runs the seed files.
It writes development data. Do not point it at production.

Run the app locally with:

```bash
mix phx.server
```

The SSH daemon and Phoenix endpoint start from the application supervision tree.
Use the configured SSH port when connecting with your local SSH client.

## Project layout

```text
lib/
  foglet_bbs/              Foglet.* domain code
    accounts/              users, auth, roles, invites, tokens, SSH keys
    boards/                categories, boards, subscriptions, board servers
    board_chat/            permanent and ephemeral board chat backends
    config/                runtime config schema and ETS cache
    posts/                 post queries, replies, edits, soft deletion
    sessions/              live session identity and presence
    ssh/                   Erlang :ssh daemon and channel handling
    threads/               thread queries, read pointers, moderation
    tui/                   Raxol app, screens, widgets, theme
  foglet_bbs_web/          Phoenix infrastructure and docs surface
  mix/tasks/               Foglet-specific operator/contributor tasks
priv/docs/                 public NimblePublisher docs
priv/repo/                 migrations and seeds
test/                      ExUnit tests mirroring lib/
vendor/raxol/              vendored TUI framework
```

`Foglet.*` owns application and domain behavior. `FogletBbs.*` and
`FogletBbsWeb.*` are infrastructure namespaces. Keep workflows in contexts;
controllers, SSH callbacks, Mix tasks, and TUI screens should stay thin.

## Build and quality commands

The main commands are Mix aliases from `mix.exs`:

| Command | Use |
|---|---|
| `mix setup` | Fetch dependencies, prepare the dev database, install hooks. |
| `mix ecto.setup` | Create, migrate, and seed the dev database. |
| `mix ecto.reset` | Drop and recreate the dev database. This wipes local dev data. |
| `mix test` | Prepare the test database and run ExUnit. |
| `mix precommit` | Compile with warnings as errors, check unused deps, format, Credo, Sobelow, Dialyzer. |

Run focused tests while developing. Run `mix precommit` before handing code to
review. It is slower because Dialyzer is part of the finish line.

## Test layout and rules

Foglet uses ExUnit. Repo tests use the Ecto SQL sandbox through the project case
templates:

| Case template | Use it for |
|---|---|
| `FogletBbs.DataCase` | Contexts, schemas, board servers, Mix tasks, and other tests that touch the Repo. |
| `FogletBbsWeb.ConnCase` | Phoenix controller and Plug tests. |
| `ExUnit.Case` | Pure modules, many TUI widget tests, and code that does not touch the Repo. |

Common commands:

```bash
mix test
mix test test/foglet_bbs/boards/boards_test.exs
mix test test/foglet_bbs/boards/boards_test.exs:42
mix test --only some_tag
```

Process tests need explicit synchronization:

- Start processes with `start_supervised!/1`.
- Do not use `Process.sleep/1` as a test strategy.
- Do not use `Process.alive?/1` as proof of behavior.
- Synchronize with monitors, explicit messages, Registry lookups, or
  `:sys.get_state/1` when inspecting GenServer state is appropriate.

If a spawned process needs the test database connection, allow it through the
SQL sandbox. Board server tests are the canonical example.

## Domain change checklist

Use this shape for state-changing work:

1. Start at the owning context, such as `Foglet.Boards`, `Foglet.Threads`, or
   `Foglet.Posts`.
2. Cast only caller-settable fields. Set foreign keys on structs before building
   changesets.
3. Authorize actor-triggered side effects with `Bodyguard.permit/4`.
4. Use transactions for multi-row invariants.
5. Preload associations in the query when renderers need them.
6. Emit PubSub side effects from the context or backend that owns the mutation.
7. Add focused tests under the mirrored `test/foglet_bbs/...` path.

Per-board message numbers are stable and meaningful. Thread and post creation
must route through `Foglet.Boards.Server`, which is the single writer for message
number allocation. Soft-deleted posts keep their numbers; gaps are expected.

## Runtime config changes

`Foglet.Config` is a read-through ETS cache over the `configuration` table.
When adding a schematized key:

1. Add the typed key spec in `Foglet.Config.Schema`.
2. Seed a default in the appropriate seed file.
3. Add a typed accessor on `Foglet.Config`.
4. Use actor-aware `Foglet.Config.put/3` for interactive writes.
5. Reserve `Foglet.Config.put!/3` for trusted setup paths such as seeds, tests,
   and Mix tasks.
6. Test validation, persistence, cache invalidation, and the consuming surface.

Keep secrets in environment/runtime configuration, not DB-backed config rows.

## User-facing copy changes

Read `docs/VOICE_AND_TONE.md` before changing labels, prompts, empty states,
denials, confirmations, Mix task help text, or public docs.

For every user-facing feature, make the guest path explicit:

1. Can guests see this surface?
2. If visible, is it read-only?
3. What denial copy appears when a guest cannot act?
4. Does the backend mutation reject the action even if the UI hides it?
5. Is there test, render, or QA evidence for the guest path?

Do not use copy to patch over a confusing flow. Make the terminal interaction
hard to misuse, then use short copy to confirm what the caller can do.

## TUI and Raxol work

Before non-trivial TUI work, read the Raxol quickstart and widget gallery under
`docs/raxol/`. For widgets, also read `lib/foglet_bbs/tui/widgets/README.md`.

Ownership rules:

- `Foglet.TUI.App` owns global UI state, routing, modal dispatch, PubSub
  subscriptions, and command dispatch.
- Screens own screen-local state and rendering.
- Complex screen state belongs in a sibling state module.
- Data loading and mutations belong in domain contexts.
- Off-process work runs through `Foglet.TUI.Command` or Raxol commands.
- Widget render functions stay pure over already-loaded state.
- Colors route through `Foglet.TUI.Theme`.

### Render a screen without SSH

Use the render task to inspect TUI layout as plain text:

```bash
mix foglet.tui.render --list
mix foglet.tui.render main_menu
mix foglet.tui.render board_list --width 132 --height 50
mix foglet.tui.render login --no-frame
```

The renderer uses synthetic in-memory fixtures for authenticated screens. It is
for visual inspection and layout diffs, not behavior assertions.

### Drive the live SSH TUI locally

For flow QA, install the Node harness dependencies and run the SSH harness
against a local Foglet instance:

```bash
npm install
npm run ssh:harness -- --user sysop --password 'seedpassword123!'
```

The development seeds include local QA accounts for sysop, moderator, and member
flows. Keep those seeded credentials in contributor/testing docs only. Do not
copy them into public operator setup pages, production runbooks, screenshots, or
issue comments that could be mistaken for real deployment guidance.

Inside the harness, useful commands include:

```text
screen
key enter
key tab
key up
type hello
resize 100x30
```

Prefer scripted harness runs for repeatable QA evidence.

## Public docs work

Public docs live under `priv/docs/<category>/<page>.md` and are compiled by the
NimblePublisher docs surface. Each file starts with Elixir map frontmatter:

```elixir
%{
  title: "Page title",
  weight: 10
}
---
```

Use `docs/PUBLIC_DOCUMENTATION_OUTLINE.md` for the taxonomy, but verify behavior
against source before documenting it. Existing files under `docs/` are useful
source material; they are not more authoritative than current code.

Keep out of public operator docs:

- Paperclip, GSD, internal planning, and review artifacts.
- Secrets, tokens, real database URLs, real host keys, and private data.
- QA seeded credentials unless the page is explicitly contributor/testing-only.
- Roadmap-only promises without a clear unsupported/experimental label.
- Agent-only shell conventions.

After changing public docs, at least compile or otherwise exercise the docs
surface. If the Elixir toolchain is unavailable, say that checks were not run and
label the work as static inspection only.
