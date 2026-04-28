# Feature Research: v2.0 TUI Runtime Shell & Screen Update Loops

## Table Stakes

| Feature | Why it matters |
|---------|----------------|
| Screen `init/update/render` contract | Makes local state ownership explicit and removes the need for App to know every screen's internals. |
| Explicit effect model | Screens request outside-world work without performing it directly or returning opaque App messages. |
| Generic App effect interpreter | Keeps process/session/task/modal concerns in one runtime shell. |
| Screen-local state structs | Replaces anonymous maps with module-owned state shapes and better compile-time friction. |
| Async result ownership | The screen that requested `:load_boards` or `:load_posts` consumes the matching loaded/error message. |
| Route context | Navigation can carry board/thread/origin data without growing top-level App fields forever. |
| Full screen migration | The milestone is not done until every current screen uses the new pattern. |
| Regression coverage | Existing SSH/TUI behavior must survive the refactor. |

## Differentiators

| Feature | Why it helps |
|---------|--------------|
| Targeted task results | `{:task, id, fun}` can declare a target route/screen so stale async results do not mutate the wrong state. |
| Effect batching | Screens can return multiple effects, such as navigate then load, without smuggling behavior through App clauses. |
| Screen runtime tests | Tests can assert pure reducer outputs without booting the whole App. |
| App shell invariants | Tests can guard that `App` contains generic effect handling and no screen-specific loaded-result branches. |

## Anti-Features

| Anti-feature | Reason |
|--------------|--------|
| Moving domain writes into screens | Screens should request effects; contexts still own authorization and persistence. |
| A global mutable screen store | The goal is clearer ownership, not a different central bag. |
| Big visual redesign | Render output should stay behaviorally equivalent unless a screen needs minimal adaptation. |
| Product feature creep | Full migration is already large enough. |

## Existing Screen Groups

- Auth/onboarding: Login, Register, Verify.
- Home/social: MainMenu and oneliners.
- BBS flow: BoardList, ThreadList, PostReader, PostComposer, NewThread.
- User workbench: Account.
- Operator workbenches: Moderation, Sysop.

## Done Means

`Foglet.TUI.App` normalizes messages, handles size gate/modal precedence, routes to screens, stores the current route and screen states, interprets effects, and renders through `screen.render(state, ctx)`. It should not know how BoardList resets a tree, how PostReader warms a cache, how Sysop slots load, or how Login consumes auth results.
