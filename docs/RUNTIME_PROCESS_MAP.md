# Runtime process map

This is the maintained map for Foglet's live SSH/TUI runtime boundaries. Keep it
focused on process ownership, restart expectations, and test evidence; deeper
module prose belongs in module docs or narrower runtime docs such as
`docs/DOOR_RUNTIME.md`.

Source verification for FOG-833: `docs/ARCHITECTURE.md` already described the
SSH/TUI split and `docs/DOOR_RUNTIME.md` covered the door-specific slice, but no
single repo document tied SSH daemon -> channel handler -> Raxol lifecycle /
dispatcher -> TUI app -> PubSub forwarder -> session -> board/chat/door
processes with a test matrix.

## Process / supervision map

```
FogletBbs.Supervisor (:one_for_one)
├─ FogletBbs.Repo
├─ Phoenix.PubSub name: FogletBbs.PubSub
├─ Foglet.TUI.MinuteClock
├─ Foglet.Accounts.RedemptionThrottle
├─ Registry name: Foglet.BoardRegistry
├─ Foglet.Boards.Supervisor                 # DynamicSupervisor
│  └─ Foglet.Boards.Server × board          # one per non-archived/created board
├─ Registry name: Foglet.Sessions.Registry
├─ Foglet.Sessions.Supervisor               # DynamicSupervisor
│  └─ Foglet.Sessions.Session × user/guest  # one live logical session
├─ Foglet.Doors.Supervisor                  # DynamicSupervisor
│  └─ Foglet.Doors.Runner × active door     # temporary handoff process
├─ Foglet.Sessions.BoardScreen
├─ Registry name: Foglet.BoardChat.Ephemeral.Registry
├─ Foglet.BoardChat.Ephemeral.Supervisor    # DynamicSupervisor
│  └─ Foglet.BoardChat.Ephemeral.Room × board
├─ FogletBbsWeb.Endpoint
└─ Foglet.SSH.Supervisor                    # included when start_ssh_daemon=true
   ├─ Foglet.SSH.RateLimiter                # ETS-backed SSH connection limiter
   └─ Foglet.SSH.DaemonOwner                # owns :ssh.daemon/2 ref
      └─ Erlang :ssh daemon / connection workers
         └─ Foglet.SSH.CLIHandler × channel # :ssh_server_channel callback module
            ├─ Foglet.Sessions.Session pid  # started/replaced before TUI setup
            └─ Raxol.Core.Runtime.Lifecycle × channel
               └─ Raxol.Core.Runtime.Events.Dispatcher
                  ├─ Foglet.TUI.App         # app model/update/render boundary
                  └─ Foglet.TUI.PubSubForwarder
                     # custom subscription process linked to Dispatcher
```

Raxol lifecycle/dispatcher children are owned by Raxol, not Foglet's top-level
supervisor. `Foglet.SSH.CLIHandler` stores the lifecycle/dispatcher pids and
traps exits so SSH channel cleanup remains Foglet-owned.

## Boundary ownership

| Boundary | Owner / source modules | Runtime expectation |
| --- | --- | --- |
| Application boot | `lib/foglet_bbs/application.ex` | Initializes ETS-backed config and SSH pubkey stash before supervisors start; starts base children first, then optional SSH supervisor; boots board servers after the tree is up. |
| SSH daemon | `Foglet.SSH.Supervisor`, `Foglet.SSH.DaemonOwner`, `Foglet.SSH.HostKey`, `Foglet.SSH.KeyCB` | `DaemonOwner` owns the `:ssh.daemon/2` ref and exits on unexpected linked daemon exits so `Foglet.SSH.Supervisor` restarts it. Host key/system-dir failures fail fast. |
| SSH channel | `Foglet.SSH.CLIHandler` | One callback state per SSH channel. It correlates stashed pubkeys, starts/replaces a session, starts Raxol on PTY, forwards data/resize, and tears down lifecycle/session/connection counters on EOF, closed, terminate, or lifecycle crash. |
| Raxol lifecycle / dispatcher | Raxol `Lifecycle` / `Dispatcher`; Foglet entrypoint `Foglet.TUI.App` | One lifecycle/dispatcher per SSH channel. Names are derived from a per-channel session id so concurrent channels do not collide. Dispatcher receives SSH input and subscription messages and invokes `Foglet.TUI.App`. |
| TUI app | `Foglet.TUI.App`, `Foglet.TUI.App.*`, `Foglet.TUI.Command`, screen modules | Owns current screen, modal routing, app/session context, subscription wiring, and command/task dispatch. Screen reducers stay pure and request effects; App interprets effects at the runtime boundary. |
| PubSub forwarding | `Foglet.TUI.PubSubForwarder`, `Foglet.PubSub` | A Raxol custom subscription GenServer subscribes to Phoenix.PubSub topics and forwards each message as `{:subscription, msg}` to the Dispatcher. Its lifetime is linked to Dispatcher, not independently supervised. |
| Logical session | `Foglet.Sessions.Supervisor`, `Foglet.Sessions.Session`, `Foglet.Sessions.Registry` | Authenticated sessions are unique by user id. A new login replaces the old session and waits for shutdown before starting/promoting the new owner. Guest sessions are unregistered until promotion. |
| Board server | `Foglet.Boards.Supervisor`, `Foglet.Boards.Server`, `Foglet.BoardRegistry`, `Foglet.Boards` | One GenServer per live board owns per-board message-number allocation. Board servers are started at boot for eligible boards and when boards are created. Crashes are restarted by the dynamic supervisor and counters reconstruct from Postgres. |
| Board chat | `Foglet.BoardChat`, `Foglet.BoardChat.Permanent`, `Foglet.BoardChat.Ephemeral.Supervisor`, `Foglet.BoardChat.Ephemeral.Room` | Permanent chat writes rows and broadcasts via PubSub without a per-room process. Ephemeral chat starts one transient room process per board on demand; normal idle shutdown is not restarted. |
| Door runner | `Foglet.Doors.Supervisor`, `Foglet.Doors.Runner`, `Foglet.Doors.PTYAdapter`, `Foglet.TUI.App.Effects` | Door launch is an App-interpreted effect, not a screen spawn. Each runner is `restart: :temporary`; normal exit, crash, timeout, or disconnect is surfaced to the session and must not restart behind the user's back. |

## Boundary and failure-path test matrix

| Boundary / failure path | Expected behavior | Test evidence |
| --- | --- | --- |
| SSH daemon options and daemon safety | daemon uses `Foglet.SSH.CLIHandler`, key callback, connection caps/backlog/algorithms; test env disables auto-daemon startup | `test/foglet_bbs/ssh/supervisor_test.exs` |
| SSH daemon system-dir / host-key failures | invalid daemon system directory fails startup with safe diagnostics instead of accepting a broken daemon | `test/foglet_bbs/ssh/daemon_owner_test.exs` |
| SSH pubkey stash and login routing | offered public keys are stashed by auth callback and resolved by channel setup without trusting SSH auth alone | `test/foglet_bbs/ssh/key_cb_test.exs`, `test/foglet_bbs/ssh/key_login_routing_smoke_test.exs` |
| SSH channel input forwarding | raw SSH data is converted into Raxol key events for the channel dispatcher | `test/foglet_bbs/ssh/cli_handler_test.exs` |
| SSH channel resize forwarding | `window_change` updates Raxol and notifies the logical session | `test/foglet_bbs/ssh/cli_handler_test.exs`, `test/foglet_bbs/tui/app_test.exs` resize cases |
| SSH channel cleanup | EOF/closed/terminate/lifecycle EXIT stops lifecycle/session work, closes the channel as needed, and decrements the connection counter once | `test/foglet_bbs/ssh/cli_handler_test.exs` |
| SSH back-pressure / connection limiting | CLIHandler connection cap and per-peer rate limiter reject excess connection attempts without a central bottleneck | `test/foglet_bbs/ssh/cli_handler_test.exs`, `test/foglet_bbs/ssh/rate_limiter_test.exs` |
| Concurrent Raxol lifecycle / dispatcher | each SSH connection gets a distinct lifecycle/dispatcher identity; concurrent sessions do not collide in globally registered Raxol names | `test/foglet_bbs/ssh/concurrent_lifecycle_test.exs` |
| TUI App startup and routing | App initializes session context, routes screen events, dispatches tasks/effects, and handles quit paths through App-owned runtime boundaries | `test/foglet_bbs/tui/app_test.exs` |
| PubSub forwarder subscription wiring | App declares custom PubSubForwarder subscriptions and refreshes/reroutes topic messages through Raxol subscriptions | `test/foglet_bbs/tui/app_test.exs` PubSubForwarder cases |
| Session one-session replacement | duplicate authenticated sessions replace the old process; promotion from guest enforces the same registry slot | `test/foglet_bbs/sessions/session_test.exs`, `test/foglet_bbs/sessions/supervisor_test.exs` |
| Board server lifecycle and sequencing | board creation/boot starts a board server; all thread/post message numbers are allocated by the board server | `test/foglet_bbs/boards/board_server_test.exs`, `test/foglet_bbs/boards/boards_test.exs`, `test/foglet_bbs/threads/threads_test.exs`, `test/foglet_bbs/posts/posts_test.exs` |
| Board server crash/reconstruction | board server can recover its message-number counter from persisted board data after restart | `test/foglet_bbs/boards/board_server_test.exs` |
| Board chat permanent path | permanent chat persists messages and logs/broadcasts PubSub failures without leaking private payloads | `test/foglet_bbs/board_chat/persistence_isolation_test.exs`, `test/foglet_bbs/privacy_safe_pubsub_failure_logging_test.exs` |
| Board chat ephemeral room | ephemeral room starts on demand, keeps bounded recent messages, and loses in-memory-only state on room stop | `test/foglet_bbs/board_chat/ephemeral_room_test.exs`, `test/foglet_bbs/board_chat/persistence_isolation_test.exs` |
| Chat TUI subscription/use of board chat | chat screen loads history through the context and consumes `{:board_chat, :new_message, msg}` events from the PubSub/App path | `test/foglet_bbs/tui/screens/chat_room_test.exs`, `test/foglet_bbs/tui/guest_mode_runtime_test.exs` |
| Door launch runtime boundary | screen reducers emit launch effects; App effects start supervised runners, keeping OS/native process work outside reducers | `test/foglet_bbs/doors_test.exs`, `test/foglet_bbs/tui/app_test.exs`, `test/foglet_bbs/tui/screens/door_list_test.exs` |
| Door runner exit, crash, timeout, disconnect, resize | runner reports exits to the session owner, cleans up ports/context files, propagates resize, and is not restarted by OTP for session-level outcomes | `test/foglet_bbs/doors/runner_test.exs`; details in `docs/DOOR_RUNTIME.md` |

Current gap assessment: no new test gap was introduced or found for the named
FOG-802 boundaries. The matrix above intentionally points to existing focused
runtime tests instead of adding duplicate docs-only tests.

## Update rule

When changing any boundary above, update this file in the same PR as the runtime
change if one of these changes: process owner, supervisor/restart behavior,
message path, cleanup/failure behavior, or focused test evidence.
