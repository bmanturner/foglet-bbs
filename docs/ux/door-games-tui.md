# Door Games TUI UX Specification (FOG-480 / FOG-517)

Status: design handoff for the canonical FOG-480 integration branch.
Owner: TUI UX Designer.
Branch: `fog-480-door-games`.
Baseline inspected: `3bbf60f6eed27f08f324d749204ac52949b75732`.

## Source verification

Committed baseline inspection found no existing Door Games terminal surface on the canonical branch. After this handoff started, the shared worktree also showed concurrent untracked Door runtime files under `lib/foglet_bbs/doors/` and `test/foglet_bbs/doors_test.exs`; those are not TUI-owned and were not modified here. Relevant current architecture:

- `lib/foglet_bbs/tui/screens/main_menu.ex` owns the authenticated main-menu command descriptors and keyboard routing.
- `lib/foglet_bbs/tui/app.ex` owns the known screen set, route state, modal routing, and effect interpretation.
- `lib/foglet_bbs/tui/effect.ex` is the explicit reducer-to-runtime boundary.
- `lib/foglet_bbs/tui/SCREEN_CONTRACT.md` requires screens to keep render pure and request runtime/domain work through effects.
- `lib/foglet_bbs/tui/widgets/README.md` documents existing list, modal, chrome, and optional wide-terminal inspector widgets that fit this flow.

Do not spawn door processes inside screen reducers. The selector may request launch; App/runtime/SSH session code must interpret an explicit door-launch effect or session message and own PTY handoff, resize, cleanup, and return.

## User goal

An authenticated caller should discover that games are available, choose a game without memorizing commands, understand that launching hands the full terminal to that game, and return to Foglet without a garbled terminal or lost place.

## Failure modes to design against

- User launches a full-screen program unexpectedly and thinks Foglet crashed.
- Door names/descriptions crowd the main menu or push key hints off 80x24.
- Selector depends on typing a slug, id, runtime type, or other magic value.
- A door exits, crashes, times out, or disconnects without a clear return message.
- Reducer-level process spawning bypasses App/session ownership and loses resize/disconnect cleanup.
- Cramped terminals show partial panels, clipped confirm text, or hidden escape affordances.

## Interaction alternatives considered

### Alternative 1: selector list with launch confirmation

Flow: main menu `D` opens a Door Games selector. Up/Down moves. Enter opens a confirmation modal. Enter confirms launch; Esc cancels.

Pros:
- Fastest terminal-native path.
- Discoverable; no magic values.
- Easy to verify with existing render and SSH harness patterns.
- Keeps high-risk launch behind one explicit confirmation.

Cons:
- Long descriptions need careful wrapping/truncation.
- Rich metadata must be compact or moved to a side panel at wide widths.

### Alternative 2: detail/preview screen before launch

Flow: main menu `D` opens a catalog. Enter opens a per-door detail screen with Launch/Back actions.

Pros:
- Best when external/classic doors have complex warnings, docs, or duration metadata.
- Gives each door room for richer copy and compatibility notes.

Cons:
- Extra step for simple games.
- More screen and state surface for the first slice.
- Adds another place where back/return state can drift.

### Alternative 3: command palette / search-first picker

Flow: main menu `D` or `/` opens a filter box; user types a game name.

Pros:
- Scales to large catalogs.

Cons:
- Overbuilt for first slice.
- Requires users to know or guess names.
- Text input is more fragile than a simple list for a small initial catalog.

## Chosen pattern

Use Alternative 1 for the first slice: a single Door Games selector screen with an optional wide-terminal details panel, followed by an explicit confirmation modal before launch.

Why this is good enough for Foglet:
- It preserves the old-network BBS feeling: pick from a visible list, press a key, enter the door.
- It is safe by default: users see a warning before Foglet gives the terminal to another program.
- It keeps the first implementation narrow while leaving a clear upgrade path to a detail screen when the catalog grows.
- It aligns with existing Foglet TUI architecture: main-menu destination, screen-local selector state, pure render, and explicit App/runtime effects.

## TUI interaction map

### Main menu entry

Visible only for authenticated users when at least one door is visible to that user.

Destination row:
- Key: `D`
- Label: `Door Games`
- Glyph suggestion: `◆` or `♜`; use theme-routed color, not hardcoded colors.
- Placement: after `Compose` and before account/operator destinations so it reads as a general BBS destination, not a sysop/admin tool.

Do not show a disabled `Door Games` row when no visible doors exist. Empty catalog is handled if a race occurs after navigation.

Primary key behavior:
- `D` / `d`: navigate to `:door_list` and request visible door load.
- Existing Up/Down main-menu oneliner selection should remain unchanged.
- Main-menu command bar should not list every route; only expose the current primary affordances.

### Door selector screen

Route: `:door_list`.
Screen-local state:
- `status`: `:loading | :loaded | :empty | {:error, reason}`.
- `doors`: loaded visible doors in display order.
- `selected_index`: cursor row; preserved across redraws and clamped after reload.
- `return_to`: previous Foglet screen/route params, defaulting to `:main_menu`.
- `last_exit`: optional return banner after a door exits.

Layout at 80x24:
- Existing `ScreenFrame` chrome.
- Breadcrumb/title: `Foglet > Door Games`.
- One-line intro: tells users these programs may take over the terminal after confirmation.
- Single bordered list region occupying the body.
- Rows use two text lines maximum:
  - line 1: selected marker, display name, compact runtime badge if available.
  - line 2: description clipped or wrapped to the list inner width.
- Bottom command bar: `↑/↓ Select`, `Enter Launch`, `Esc Back`.

Layout at cramped width, e.g. 64x20:
- Hide the optional details panel.
- Keep one column only.
- Truncate long names with ellipsis within the actual row width.
- Keep descriptions to one clipped/wrapped line.
- Keep command bar restrained: `Enter Launch`, `Esc Back`; selection is still supported but may be omitted from the keybar if width is tight.

Layout at wide width, e.g. >= 110 columns:
- Optional split body:
  - left selector list, minimum useful width 44.
  - right details panel using a stable width budget around 36-44 columns.
- Sidebar/details panel remains anchored on the right; it must not jump when selected row text changes.
- Details panel may show description, runtime style, time limit, and safety note.

Text policy:
- Names: truncate with ellipsis inside row width.
- Descriptions: wrap or clip by actual region width; never overflow borders.
- Runtime metadata: human labels only, e.g. `Native`, `External`, `Classic`; never expose internal atoms as shipped copy.
- Error/helper text wraps inside the body/modal width.

Table/list contract:
- Use a selection list/list-row pattern, not a dense table, for the first slice.
- Selected row treatment should be visually clear through existing theme-selected styling.
- Keep row alignment stable: marker column, name column, optional right badge.
- Long cells never push badges or borders out of bounds.

Scrolling model:
- If visible doors exceed viewport rows, selector owns `selected_index` and `scroll_offset`.
- Up/Down moves one row; PageUp/PageDown optional only if already supported by the chosen list widget.
- A simple position hint such as `3/12` may appear in the header or footer when scrolling is active.

Cursor/focus model:
- Focus starts on the first visible door.
- Focus remains on the selected door through reload/redraw when the same door id remains present; otherwise clamp to nearest row.
- Hide the terminal cursor in selector and confirm states unless the selected widget needs it.

### Confirmation modal

Triggered by Enter on a selected door.

Modal intent:
- Warn that Foglet will hand the terminal to the selected game until it exits.
- Confirm launch without requiring a typed slug or id.

Modal layout:
- Max width: min(68, terminal_width - 6).
- Body wraps within the modal; no border overflow.
- Buttons/actions: `Enter Launch`, `Esc Cancel`.
- If the selected door has known risk metadata, show one concise line, not a long manual.

Suggested draft copy for implementation/content review:
- Title: `Launch Door Game?`
- Body: `Foglet will hand this terminal to {door_name}. When the game exits, you'll return here.`
- Safety line for external/classic doors: `If it stops responding, disconnecting will clean up the session.`

Content Designer owns final wording if this copy becomes shipped public language.

### Launch handoff

Reducer output:
- On confirm, selector emits an explicit door-launch request, e.g. `Effect.session({:launch_door, door_id, return_to})` or a dedicated `Effect.door_launch/2` added to `Foglet.TUI.Effect`.
- Preferred implementation shape is a dedicated effect if door launch becomes a first-class App runtime operation; a session effect is acceptable for the first internal boundary only if App/session interpretation remains explicit and tested.

Runtime obligations outside TUI UX scope but required by the flow:
- Save return route and selected door id before handoff.
- Stop/hide normal TUI rendering while the door owns the PTY.
- Forward terminal input/output and resize events to the door runner.
- On exit, timeout, crash, or disconnect, clean up the process tree and restore a sane terminal mode.

### Return / exit states

On normal exit:
- Return to the door selector if possible, preserving selection and showing a one-line success banner: `{door_name} ended. You're back in Foglet.`
- If selector state cannot be restored, return to main menu with a concise banner.

On crash/error:
- Return to selector or main menu with an error banner: `{door_name} stopped unexpectedly. You're back in Foglet.`
- Include a generic next action such as `Try again later or contact the sysop.` only when useful.

On timeout:
- Return with a timeout banner: `{door_name} timed out. You're back in Foglet.`

On disconnect:
- No interactive banner is required during disconnect, but next login may show nothing unless product later wants audit-visible session history. Cleanup is mandatory.

## Empty/loading/error states

Loading:
- Body: small spinner or plain `Loading door games...`.
- Keybar: `Esc Back` only.

Empty:
- If reached because config changed after the main-menu gate: `No door games are available right now.`
- Keybar: `Esc Back`.
- Do not tell users to type ids or contact sysop unless configuration/admin UX adds a real path.

Load error:
- `Unable to load door games.` plus concise reason only if safe and user-meaningful.
- Keybar: `R Retry`, `Esc Back`.

No selected row:
- Enter is inert.
- Keybar should not show `Enter Launch` in empty/error states.

## Render acceptance scenarios

Implementation should add render coverage for:

1. Main menu with at least one visible door at 80x24: `Door Games` row is present and command layout remains stable.
2. Main menu with no visible doors at 80x24: `Door Games` row is absent.
3. Door selector loading at 80x24 and 64x20: no border overflow, only back affordance.
4. Door selector with normal content at 80x24: selected row, description, launch/back keybar visible.
5. Door selector with long name/description at 80x24 and 64x20: truncation/wrapping stays inside borders.
6. Door selector empty state at 80x24: no launch affordance.
7. Door selector error state at 80x24: retry/back affordances visible.
8. Confirmation modal at 80x24 and 64x20: body wraps inside border; Enter/Esc actions visible.
9. Return banner after normal exit/crash/timeout: message appears without shifting selector columns.
10. Wide terminal, e.g. 120x30: right details panel is anchored and does not jump across selection changes.

## SSH harness acceptance scenarios

QA should verify after implementation:

1. With `FOGLET_ENABLE_DEMO_DOORS` absent, log in as a seeded user and confirm
   the main menu omits `Door Games`; pressing `D` does nothing visible.
2. With `FOGLET_ENABLE_DEMO_DOORS=true`, log in as a seeded user, reach the
   main menu, and confirm `D` opens Door Games.
3. Use Down/Up to select a door; Enter opens confirm; Esc cancels and returns focus to same row.
4. Confirm launch of native/demo door; door takes terminal; exit returns to Foglet selector with banner.
5. Confirm launch of external demo door; exit returns to Foglet selector with banner.
6. Resize while selector is open and while a door is running; selector redraws cleanly and running door receives or degrades gracefully on resize.
7. Crash/timeout fixture returns to Foglet with clear message and no garbled terminal.
8. Disconnect during a running door leaves no orphaned process and next login starts in a sane TUI state.

## Implementation handoff

Recommended files/modules to touch:
- Add a `:door_list` route/screen under `lib/foglet_bbs/tui/screens/door_list*`.
- Add door visibility gating to main-menu command descriptors only after `Foglet.Doors` exposes visible doors or a cheap `visible_doors?` accessor.
- Add an explicit effect/session handoff in `Foglet.TUI.Effect` / `Foglet.TUI.App.Effects` / session runtime as chosen by CTO/OTP.
- Use existing `ScreenFrame`, `CommandBar`, list rows, modal, and optional `Workspace.Inspector`-style details panel rather than creating a custom full-screen layout from scratch.

## Tradeoffs and residual risks

- The chosen selector+confirm pattern is intentionally smaller than a detail screen. If early door metadata is dense or safety warnings are long, promote selected-door details to a full detail screen before shipping.
- Gating the main-menu entry on visible doors is best for users but requires a cheap visibility query or cached runtime config. If the query is not cheap, prefer App/screen load with a hidden main-menu row until the door registry has a safe accessor.
- External/classic door terminal handoff can break UX even if selector screens render well. TUI UX signoff must include SSH harness evidence after runtime implementation.
- Draft copy above is UX placeholder; Content Designer should review shipped wording if implementation changes public copy.

## Follow-up backlog

None created by this design artifact. Potential future polish, not blocking the first slice: searchable/filterable catalog once a site has enough doors to make arrow navigation slow.
