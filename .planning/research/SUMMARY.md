# Research Summary: v2.0 TUI Runtime Shell & Screen Update Loops

## Stack Additions

No external stack additions are needed. Build this with internal modules:

- `Foglet.TUI.Context`
- `Foglet.TUI.Effect`
- revised `Foglet.TUI.Screen`
- optional `Foglet.TUI.ScreenRuntime` compatibility/registry helper

## Feature Table Stakes

- Screen-owned `init/update/render` contract.
- Explicit effect model.
- Generic App effect interpreter.
- First-class screen-local state structs.
- Screen-owned async result handling.
- Full migration across Login, Register, Verify, MainMenu, BoardList, ThreadList, PostReader, PostComposer, NewThread, Account, Moderation, and Sysop.
- Regression coverage for behavior, effects, App-shell invariants, and render smoke.

## Architecture Direction

Keep `Foglet.TUI.App` as the Raxol process shell. It should normalize messages, enforce SizeGate/modal precedence, build `Foglet.TUI.Context`, route messages to the active screen, store route/screen states, interpret generic effects, own subscriptions/session/runtime concerns, and render through the active screen.

Move screen-local state and async-result handling into screen modules. The screen that emits a task effect should handle its loaded/error result in `update/3`.

## Watch Out For

- Do not move domain side effects into screens.
- Do not let effects become screen-specific App commands.
- Preserve modal and SizeGate precedence.
- Treat PubSub and route context deliberately during migration.
- Migrate operator workbenches only after simpler screens prove the contract.

## Recommended Build Order

1. Contract, context, effect interpreter, and compatibility adapter.
2. Auth/home pilot migration.
3. BBS flow migration.
4. Account workbench migration.
5. Moderation/Sysop workbench migration.
6. App shell cleanup and compatibility removal.
7. Verification, docs, and precommit.
