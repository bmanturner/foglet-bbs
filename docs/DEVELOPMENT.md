<!-- generated-by: gsd-doc-writer -->
# Development

Working notes for contributors actively writing Foglet code. Read
`GETTING-STARTED.md` first for prerequisites and first-run setup. This document
assumes the app boots, the database is migrated, and you can SSH into the BBS.

For the high-level system shape see `ARCHITECTURE.md`. For schema and
persistence invariants see `DATA_MODEL.md`. For runtime configuration see
`CONFIGURATION.md`.

## Project layout

```
lib/
  foglet_bbs/              # Foglet.* domain (application/business logic)
    accounts/              # users, auth, roles, invites, tokens, SSH keys
    authorization.ex       # Bodyguard policies / operator scopes (single file)
    boards/                # categories, boards, subscriptions, server.ex
    config/                # runtime config schema + ETS cache
    moderation/            # post/thread moderation
    oneliners/             # one-liner feature
    posts/                 # post queries, replies, edits, soft delete
    sessions/              # live session identity, supervisor
    ssh/                   # :ssh daemon, channel handler, host keys
    threads/               # thread queries, read pointers
    tui/                   # Raxol app, screens, widgets, theme
      app.ex               # global UI state and routing
      screens/             # one module per screen (e.g. board_list.ex)
      widgets/             # reusable display primitives
      theme.ex
  foglet_bbs_web/          # FogletBbsWeb.* — Phoenix endpoint, telemetry,
                           #   LiveDashboard. Infrastructure only.
  foglet_bbs.ex            # FogletBbs.* root infra module
  mix/tasks/               # Foglet.* mix tasks (user.create, doctor, etc.)
test/foglet_bbs/           # mirrors lib/foglet_bbs/
docs/                      # ARCHITECTURE, DATA_MODEL, CONFIGURATION, raxol/
priv/repo/                 # migrations and seeds
vendor/raxol/              # vendored Raxol TUI framework
```

## Domain boundaries

`Foglet.*` is the domain namespace. `FogletBbs.*` and `FogletBbsWeb.*` are
Phoenix infrastructure (endpoint, PubSub, telemetry, LiveDashboard). Domain
workflows live in contexts — never in controllers, SSH callbacks, or TUI
render functions.

| Context | Owns |
|---|---|
| `Foglet.Accounts` | users, auth, roles, invites, tokens, SSH keys, deletion |
| `Foglet.Boards` | categories, boards, subscriptions, read pointers, per-board servers |
| `Foglet.Threads` | thread queries, read pointers, thread moderation |
| `Foglet.Posts` | post queries, replies, edits, soft deletion |
| `Foglet.Config` | runtime configuration + ETS cache |
| `Foglet.Authorization` | Bodyguard policies, operator scopes |
| `Foglet.Sessions.*` | live session identity, one-session-per-user |
| `Foglet.SSH.*` | Erlang `:ssh` daemon and channel handler |
| `Foglet.TUI.*` | Raxol app, screens, state, widgets |

When in doubt, the smallest sensible API surface is a context function.
Schemas own changesets and association rules; contexts own transactions,
authorization, preloads, PubSub side effects, and cross-schema invariants.

## Build & quality commands

From `mix.exs` aliases:

| Command | What it runs |
|---|---|
| `mix setup` | `deps.get`, `ecto.setup`, install git hooks |
| `mix ecto.setup` | `ecto.create`, `ecto.migrate`, run `priv/repo/seeds.exs` |
| `mix ecto.reset` | drop and recreate the dev DB |
| `mix test` | creates and migrates the test DB, seeds config, runs the suite |
| `mix precommit` | the finish line — see below |

The `precommit` alias chains:

1. `compile --warnings-as-errors`
2. `deps.unlock --unused`
3. `format`
4. `credo --strict`
5. `sobelow --exit Low`
6. `dialyzer`

Run `mix precommit` whenever code changes are complete and fix every
issue it surfaces. CI runs the same checks; passing locally avoids round trips.

## Code style

- Formatter: Elixir's built-in `mix format` (config in `.formatter.exs`).
- Static analysis: Credo (`--strict`), Sobelow (`--exit Low`), Dialyxir.
- Compile under `--warnings-as-errors`; do not commit code with warnings.
- All four tools are wired into `mix precommit`; configure your editor to run
  `mix format` on save.

## Domain mutation workflow

Mirror this shape for every state-changing operation:

1. **Start at the owning context.** Add a public function such as
   `Foglet.Posts.create_reply/2`. Keep callers (TUI, controllers, mix tasks)
   thin.
2. **Cast only caller-settable fields.** Programmatically set foreign keys
   (`user_id`, `board_id`, `thread_id`) on the struct *before* changeset
   construction; do not add them to `cast/3` for caller convenience.
3. **Authorize side effects.** Call `Bodyguard.permit(Foglet.Authorization,
   action, actor, params)` before mutating. `Bodyguard.permit?/4` is for
   advisory UI only — disabled or hidden UI is never authorization.
4. **Use transactions for multi-row invariants.** Wrap with `Repo.transact/1`
   (or `Ecto.Multi` when you need named steps).
5. **Preload in the query.** If a renderer or serializer will touch an
   association, preload it where the data is fetched, not in the consumer.
6. **Emit PubSub from the context.** Side effects belong with the mutation,
   not in the screen that triggered it.
7. **Test under the mirrored path.** New code in `lib/foglet_bbs/posts/` gets
   tests in `test/foglet_bbs/posts/`.

### The per-board message-number invariant

Per-board message numbers are stable, monotonic, and historically meaningful.
Soft-deleted posts keep their numbers — gaps are intentional.

- **Thread and post creation must route through `Foglet.Boards.Server`** (see
  `lib/foglet_bbs/boards/server.ex`). The Server is the single writer that
  increments `boards.next_message_number` and inserts in one `Ecto.Multi`.
- On init, the Server reconciles `next_message_number` against
  `MAX(message_number)` from posts.
- Moving a thread updates the denormalized `board_id` on its posts but
  preserves the original message numbers.

If you find yourself inserting a post or thread directly via `Repo`, stop —
go through `Foglet.Boards.Server`.

### Authorization

`Foglet.Authorization` implements `Bodyguard.Policy`. Two stable scope shapes:

- `:site` — global / sysop scope.
- `{:board, board_id}` — board-local scope.

Use `Foglet.Authorization.scopes_for/2` to derive the operator-visible set
when filtering lists. Do not duplicate scope derivation in screens or widgets.

## Migrations & schemas

Read `docs/DATA_MODEL.md` before touching schemas, migrations, associations,
or persistence invariants.

```bash
mix ecto.gen.migration name_using_underscores
```

Conventions:

- Use `Foglet.Schema` (in `lib/foglet_bbs/schema.ex`) as the schema base — it
  sets the primary-key and timestamp conventions.
- Keep migration, schema, changeset, context function, fixture, and test in
  sync within a single PR. A schema change without a fixture/test update is
  almost always a bug waiting to happen.
- Do not write data migrations that depend on application code paths;
  re-derive in SQL or use a dedicated mix task.

## Runtime config workflow

`Foglet.Config` is a read-through ETS cache over the `configuration` table.
See `docs/CONFIGURATION.md` for the full key catalog.

To add a config key:

1. Add the typed key spec in `Foglet.Config.Schema`
   (`lib/foglet_bbs/config/schema.ex`).
2. Seed a default in `priv/repo/seeds/config.exs` (or wherever defaults live
   for your key class).
3. Add a typed accessor on `Foglet.Config` rather than scattering string keys
   across call sites.
4. Use `Foglet.Config.put/3` for actor-aware writes (TUI, future API);
   `Foglet.Config.put!/3` is reserved for trusted setup paths (seeds, tests,
   mix tasks).
5. Test validation, persistence, cache invalidation, and any consuming UI.

Secrets stay in environment / runtime config — not in the DB-backed
`configuration` table.

## User-facing copy workflow

Read `docs/VOICE_AND_TONE.md` before adding or changing labels, prompts,
empty states, denials, confirmations, operator task help, or public docs.

For every new user-facing feature, make an explicit guest decision:

1. Can guests see the surface at all?
2. If visible, is it read-only or can it mutate state?
3. Is the denial copy short, useful, and free of implementation details?
4. Is the backend mutation protected even if the UI hides the action?
5. Are tests or render evidence covering the guest path?

Guest Mode is a deliberate read-only product state, not a synonym for `nil`
user. Do not rely on copy to explain a confusing interaction; prefer a clearer
terminal-native flow, then use copy to confirm what the user can do.

## TUI / Raxol workflow

Read `docs/raxol/getting-started/QUICKSTART.md` and
`docs/raxol/getting-started/WIDGET_GALLERY.md` before TUI work. For widgets,
also read `lib/foglet_bbs/tui/widgets/README.md`.

State ownership:

- **Global UI state** lives in `Foglet.TUI.App`
  (`lib/foglet_bbs/tui/app.ex`): current screen, modal routing, PubSub
  subscriptions, command dispatch.
- **Screen-local state** lives in the screen module
  (`lib/foglet_bbs/tui/screens/<name>.ex`). For complex screens, factor a
  sibling `state.ex` (e.g. `screens/post_reader/state.ex`).
- **Data and mutations** live in domain contexts. Screens call contexts;
  they do not call `Repo` directly.
- **Off-process work** runs through `Foglet.TUI.Command` or Raxol commands —
  not inline in `handle_event/2`.
- **Reusable display** goes in `lib/foglet_bbs/tui/widgets/`. Stateful
  widgets expose `init/1`, `handle_event/2`, `render/2`; stateless widgets
  expose render functions only.

Route colors through `Foglet.TUI.Theme` and pass theme explicitly. Render
functions stay pure over already-loaded state — no data fetching mid-render.

The SSH side: `Foglet.SSH.CLIHandler`
(`lib/foglet_bbs/ssh/cli_handler.ex`) owns the channel lifecycle (peer/auth
context, session start/promotion, Raxol startup, input/resize forwarding,
cleanup). Keep UI behavior in `Foglet.TUI.App` and screens — not in the
channel handler.

## Testing conventions

The full reference is `docs/TESTING.md`. The hard rules:

- Use `start_supervised!/1` for every process started under test.
- **Do not** use `Process.sleep/1` to wait for async work.
- **Do not** use `Process.alive?/1` as a synchronization primitive.
- Synchronize with monitors, explicit messages, or `:sys.get_state/1`.
- Mirror `lib/foglet_bbs/...` paths in `test/foglet_bbs/...`.
- The `mix test` alias creates and migrates the test DB and seeds config
  before running, so `mix test` is the canonical local test command.

## Pointers
- `docs/ARCHITECTURE.md` — system overview, supervision tree, data flow.
- `docs/DATA_MODEL.md` — schemas, associations, persistence invariants.
- `docs/CONFIGURATION.md` — config keys and runtime settings.
- `docs/TESTING.md` — test framework, fixtures, sync patterns.
- `docs/raxol/getting-started/` — Raxol concepts and widget gallery.
- `lib/foglet_bbs/tui/widgets/README.md` — widget authoring guide.
