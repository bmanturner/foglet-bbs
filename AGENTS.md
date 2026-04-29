# Foglet BBS Agent Context

Foglet BBS is an SSH-first bulletin board system. The primary product
experience is the terminal UI served over SSH. Phoenix is infrastructure for
endpoint, PubSub, telemetry, LiveDashboard, and future structured clients; do
not add end-user browser workflows unless the architecture docs are updated to
make that product surface intentional.

Use `rtk` as the shell command prefix in this repo, for example
`rtk mix test` or `rtk git status`.

## Read First

Consult the narrowest relevant docs before non-trivial changes:

- `docs/DATA_MODEL.md` before touching schemas, migrations, associations, or
  persistence invariants.
- Before TUI/Raxol work. For widgets, also read
  `docs/raxol/getting-started/WIDGET_GALLERY.md` and
  `lib/foglet_bbs/tui/widgets/README.md`.

## Boundaries

`Foglet.*` is the application/domain namespace:

- `Foglet.Accounts`: users, auth, roles, invites, tokens, SSH keys, deletion.
- `Foglet.Boards`: categories, boards, subscriptions, read pointers,
  per-board servers.
- `Foglet.Threads`: thread queries, thread read pointers, thread moderation.
- `Foglet.Posts`: post queries, replies, edits, soft deletion.
- `Foglet.Config`: runtime configuration and ETS-backed caching.
- `Foglet.Authorization`: Bodyguard policies and operator scopes.
- `Foglet.Sessions.*`: live session identity and one-session-per-user behavior.
- `Foglet.SSH.*`: Erlang `:ssh` daemon/channel integration.
- `Foglet.TUI.*`: Raxol app, screens, state, and widgets.

`FogletBbs.*` and `FogletBbsWeb.*` are Phoenix infrastructure. Keep domain
workflows in contexts, not controllers, SSH callbacks, or TUI render functions.

## Persistence And Contexts

Postgres is authoritative for durable state. ETS and processes are ephemeral and
must be reconstructable after restart.

Use context modules as public boundaries. Contexts own transactions,
authorization checks, preload choices, PubSub side effects, and cross-schema
invariants. Schemas own changesets, associations, and data-shape rules.

Programmatically set foreign keys on structs before changeset construction; do
not add fields such as `user_id` to `cast/3` just to make callers convenient.
Preload associations in the query when renderers or serializers will access
them later.

## Core Invariants

Per-board message numbers are stable and important:

- Thread and post creation must route through `Foglet.Boards.Server`.
- The board server is the single writer for message-number allocation.
- Soft-deleted posts keep their message numbers; do not fill gaps.
- Moving a thread updates denormalized `board_id` on posts, but existing
  message numbers remain historical.

Use `Foglet.Boards.scope_for/1`, `Foglet.Threads.scope_for/1`, and
`Foglet.Posts.scope_for/1` for authorization scope shapes. Do not duplicate
scope derivation in screens or widgets.

Read pointers are monotonic persisted user state. Advance them through the
owning context and keep UI-local scroll/read state separate.

## Authorization

`Foglet.Authorization` implements `Bodyguard.Policy`.

Use `Bodyguard.permit/4` before domain side effects, `Bodyguard.permit?/4` only
for advisory UI rendering, and `Foglet.Authorization.scopes_for/2` for filtering
operator-visible data. Hidden or disabled UI is never authorization; context
mutations must still check policy.

Stable scope shapes are `:site` and `{:board, board_id}`.

## Runtime Config

`Foglet.Config` is a read-through ETS cache over the `configuration` table.

- Use `get!/1`, `get/2`, and `fetch/1` for reads.
- Use `put!/3` only for trusted setup paths such as seeds, tests, and Mix tasks.
- Use actor-aware `put/3` for interactive TUI or future API writes.
- Add typed accessors for schematized keys; do not scatter string keys.
- Keep secrets in environment/runtime config, not DB-backed config.

## SSH And TUI

`Foglet.SSH.CLIHandler` owns the SSH channel lifecycle: peer/auth context,
session start or promotion, Raxol lifecycle startup, input/resize forwarding,
and cleanup. Keep UI behavior in `Foglet.TUI.App` and screens.

`Foglet.TUI.App` owns global UI state, current screen, modal routing, PubSub
subscription wiring, commands/tasks, and routing messages to screens. Screen
modules own screen-local rendering and key handling. Complex screen state
belongs in a sibling state module such as `screens/post_reader/state.ex`.

Widgets are reusable primitives. Stateful widgets expose `init/1`,
`handle_event/2`, and `render/2`; stateless widgets expose render functions.
Route colors through `Foglet.TUI.Theme`, pass theme explicitly, and keep render
functions pure over already-loaded state.

### Inspecting The TUI

`mix foglet.tui.render <screen>` renders any TUI screen as plain text so you
can "see" the layout without an SSH client. The renderer drives the same
`Raxol.UI.Layout.Engine` the live TUI uses, paints positioned `:text` and
`:box` elements onto a 2D character grid, and prints the result. Output is
ANSI-stripped (no color/bold) so it diffs cleanly across runs.

```
rtk mix foglet.tui.render main_menu
rtk mix foglet.tui.render board_list --width 132 --height 50
rtk mix foglet.tui.render --list             # list available screens
rtk mix foglet.tui.render login --no-frame   # omit the alignment ruler
```

Defaults: `--width 80 --height 24`. Authenticated screens are populated with
a synthetic in-memory user (`@alice`, sysop role) and stub board / thread /
post fixtures from `Foglet.TUI.RenderFixtures` — no Repo, no SSH, no PubSub.
This is for visual inspection, not behaviour assertions; for those, use
`test/foglet_bbs/tui/layout_smoke_test.exs` patterns.

## Workflows

For domain mutations: start at the owning context, add changeset fields only for
caller-settable data, authorize actor-triggered side effects, use
`Repo.transact/1` for multi-row invariants, preload what consumers need, and add
focused tests under the mirrored `test/foglet_bbs/...` path.

For TUI flows: keep global navigation in `Foglet.TUI.App`, screen-local state in
the screen or sibling `state.ex`, data/mutations in domain contexts,
off-process work in `Foglet.TUI.Command`/Raxol commands, and reusable display in
widgets.

For runtime config: add the key spec in `Foglet.Config.Schema`, seed defaults,
add a typed accessor, use `Config.put/3` for actor-aware writes, and test
validation, persistence, cache invalidation, and consuming UI.

For migrations/schemas: read `docs/DATA_MODEL.md`, generate with
`mix ecto.gen.migration name_using_underscores`, use `Foglet.Schema`, and keep
migration, schema, changeset, context, fixtures, and tests aligned.

## Testing And Finish Line

DO NOT WRITE BULLSHIT TESTS THAT TEST FOR THE PRESENCE OR ABSENCE OF TEXT.

Use `start_supervised!/1` for processes in tests. Avoid `Process.sleep/1` and
`Process.alive?/1`; synchronize with monitors, explicit messages, or
`:sys.get_state/1`.

Run `mix precommit` when code changes are complete and fix any issues. It runs
compile with warnings as errors, formatter, Credo, Sobelow, and Dialyzer.
