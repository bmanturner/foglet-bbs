# Pitfalls Research: v2.0 TUI Runtime Shell & Screen Update Loops

## Pitfalls And Prevention

| Pitfall | Risk | Prevention |
|---------|------|------------|
| Big-bang App rewrite | Breaks multiple flows at once and makes regressions hard to localize. | Split phases by screen families and keep each slice verifiable without making an old-screen fallback path a deliverable. |
| Synchronous domain work in screen reducers | Blocks the Raxol lifecycle process and violates context boundaries. | Screens return task effects; App runs tasks off-process. |
| Stale async results | A load result may arrive after navigation and update the wrong screen state. | Include task ids and optional target route/screen metadata; screens ignore results that no longer match their state. |
| Route params leaking back into App globals | The refactor may rename `current_board` to another global instead of fixing ownership. | Route context and screen state own board/thread/post data unless truly global. |
| Modal precedence drift | Existing modal keys must keep taking precedence over active screen keys. | Preserve App-level modal routing before screen dispatch. |
| SizeGate behavior drift | Hidden screens must not mutate state while too-small gate is active. | Keep SizeGate short-circuit in App before screen dispatch. |
| PubSub subscription gaps | Moving screen ownership can break topic selection for boards/threads/posts. | Derive subscriptions from route/context and screen-declared interests. |
| Account/Sysop nested forms regress | Operator workbenches have complex tab/form/subview state. | Migrate them after contract and task effects are stable; keep focused tests for forms and tab lifecycle slots. |
| Tests become shape-only | Refactor tests can accidentally assert callback existence without behavior. | Require behavior tests for reducer outputs, effect interpretation, async result handling, and render smoke. |
| App remains central by another name | Effects become opaque tuples that App still pattern matches as screen-specific commands. | Keep effect types generic; screen-specific result handling happens in screen update functions. |

## Warning Signs

- `Foglet.TUI.App` still contains clauses like `{:boards_loaded, _}`, `{:posts_loaded, _}`, or `{:sysop_users_loaded, _}` after the relevant screen phase completes.
- Screens return whole App structs instead of local state plus effects.
- New screen state is introduced as untyped maps without a state module.
- Tests pass while a representative SSH/TUI render path cannot be rendered through `mix foglet.tui.render`.
- A screen directly calls Repo or context mutation functions during `update/3` instead of returning task effects.
