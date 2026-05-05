# Door Games QA Strategy and Evidence Matrix (FOG-480 / FOG-518)

Status: QA strategy handoff for the canonical Door Games integration branch.
Owner: QA Engineer.
Branch: `fog-480-door-games`.
Baseline inspected: `3bbf60f6eed27f08f324d749204ac52949b75732`.
Parent: FOG-480.

## Source verification

Current canonical branch kickoff SHA is `3bbf60f6eed27f08f324d749204ac52949b75732`. The branch is ready for specialists to land Door Games work, but QA signoff cannot run until implementation owners hand off a runnable SHA with native and external demo doors wired into the SSH/TUI flow.

This strategy intentionally covers release evidence, not implementation design. It should be updated only when the shipped user path or test harness surface changes.

FOG-910 adds a deployment switch for bundled demo/test doors:
`FOGLET_ENABLE_DEMO_DOORS`. QA must verify both modes. With the variable absent,
empty, or false-like, bundled demo/test doors are hidden and the main menu should
not advertise `Door Games` unless another browsable door exists. With the
variable set to `true`, `1`, or `yes`, the bundled demo/test doors are available
for launch-path verification. This is not a Sysop SITE setting and is not stored
in `Foglet.Config`.

## Acceptance criteria used

FOG-518 is considered complete when this strategy exists and the issue comment records:

- Exact branch and SHA inspected.
- Risk tier policy for Door Games changes.
- Evidence matrix for native/demo, external executable, classic/dropfile, resize, timeout, crash, disconnect cleanup, terminal recovery, visual polish, and PR readiness.
- Required automated commands and SSH/TUI harness expectations.
- Clear pass/fail/blocker routing rules.

FOG-480 release signoff remains separate and requires runtime evidence on the final canonical PR/SHA:

- A native/demo door launches through the SSH/TUI and returns cleanly.
- An external executable door launches through the SSH/TUI and returns cleanly.
- Classic/dropfile adapter fixture is covered by automated tests.
- Resize, timeout, crash, and disconnect cleanup have automated or harness evidence.
- Process cleanup is demonstrated by observable command output or implementation-provided check.
- Terminal sizes include 80x24 and at least one cramped size.
- CI is green and the final PR file list has no unrelated artifacts.

## Risk tier policy

### Tier 0: static configuration, docs, and fixtures

Examples:
- Door manifest examples.
- Dropfile field documentation.
- Demo door fixture names and paths.
- User-facing copy changes that do not alter flow.

Required evidence:
- Static source review against FOG-480 requirements.
- Focused docs/fixture checks where available.
- Secret/privacy scan of examples and generated metadata.

Release gate:
- Can be accepted without SSH harness only when no TUI/user path changes.

### Tier 1: domain and data behavior

Examples:
- Manifest validation.
- Door visibility/launchability policy.
- Audit event shape.
- Metadata minimization/redaction.
- Classic dropfile generation.

Required evidence:
- Focused ExUnit tests for success, validation failure, authorization failure, redaction, and dropfile output.
- `rtk mix test test/foglet_bbs/doors*_test.exs` or narrower equivalent.
- Static review confirming no secrets or broad environment passthrough.

Release gate:
- Focused tests must pass before handing to runtime/TUI QA.

### Tier 2: OTP/process runtime behavior

Examples:
- Door supervisor and runner ownership.
- External PTY launch and I/O attachment.
- Normal exit, nonzero exit, crash, timeout, idle timeout, disconnect.
- Resize propagation to the running door or adapter boundary.
- Temporary context/dropfile cleanup.

Required evidence:
- Focused integration tests using supervised processes; avoid sleeps unless no synchronization point exists.
- Observable cleanup check proving no child process remains after normal exit, crash, timeout, and disconnect.
- Focused test command plus output.

Release gate:
- Blocking if orphaned process, leaked temp context, unredacted secret, or unowned process spawn is observed.

### Tier 3: SSH/TUI user path and visual polish

Examples:
- Main-menu Door Games entry.
- Door selector and confirmation modal.
- Launch handoff from Foglet to door and return to Foglet.
- Keyboard navigation, focus, redraw calmness, wrapping, borders, and terminal recovery.

Required evidence:
- `rtk npm run test:ssh-harness`.
- `rtk mix test` before final QA if implementation is runnable locally.
- TUI render evidence at 80x24 and cramped width, for example:
  - `rtk mix foglet.tui.render main_menu --width 80 --height 24`
  - `rtk mix foglet.tui.render door_list --width 80 --height 24`
  - `rtk mix foglet.tui.render door_list --width 64 --height 20`
- SSH harness run as an end user for native/demo and external executable launch/return.
- Visual report covering wrapping, alignment, cursor/focus stability, redraw calmness, layout anchoring, modal boundaries, keyboard usability, terminal fit, and overall composition.

Release gate:
- Static inspection alone is insufficient for TUI signoff.
- Blocking if terminal is garbled, focus is lost, borders overflow, key path is undiscoverable, or return from door is unreliable.

### Tier 4: final PR/release smoke

Examples:
- Canonical FOG-480 PR to `main`.
- Release closeout.

Required evidence:
- Exact PR URL and head SHA.
- CI green, including `mix format --check-formatted`.
- `rtk mix precommit` or documented implementation-owner precommit evidence plus final QA spot checks.
- Final branch file list reviewed for accidental artifacts: `.qa/`, scratch files, internal review docs, secrets, generated junk, and unrelated files.
- All active blocker children resolved or explicitly deduped.

Release gate:
- Blocking if there are duplicate helper PRs requiring board action, red CI, missing TUI runtime evidence, or unresolved active blocker defects.

## Evidence matrix

| Area | Setup | Commands / harness path | Expected behavior | Pass / fail rule | Blocker routing |
| --- | --- | --- | --- | --- | --- |
| Native demo door launch/return | Canonical branch with seeded user and native demo door visible | SSH harness: login, open Door Games, select native demo, confirm, send demo exit input | Door takes terminal, shows native demo content, exits, returns to Foglet selector or main menu with concise banner | Pass only with clean return, stable focus, no garbled terminal, no stuck raw/alt mode | File active child if launch, input, exit, return, or terminal recovery fails |
| External executable door launch/return | Canonical branch with non-Elixir demo executable visible and allowlisted | SSH harness: select external demo, confirm, interact, exit normally | PTY-attached executable receives input/output and returns cleanly | Pass only if external I/O works and exit status/audit is safe | File active child if executable is spawned outside owner boundary, cannot receive input, cannot return, or leaks metadata |
| Default demo-door gate | `FOGLET_ENABLE_DEMO_DOORS` absent or empty and no other browsable doors | Render or SSH harness: reach main menu, press `D`, optionally force/open selector fallback | Main menu omits `Door Games`; `D` does nothing visible; fallback selector says `No door games are available right now.` and has Back only | Pass only if users see no misleading launch path and no env/config jargon | File active child if demo doors appear by default, `D` opens a dead path, or empty state advertises launch |
| Enabled demo-door gate | `FOGLET_ENABLE_DEMO_DOORS=true`, `1`, or `yes` | Render or SSH harness: reach main menu, press `D`, inspect selector | Main menu includes `Door Games`; selector lists bundled demo/test doors according to actor visibility | Pass only if all documented truthy values enable demos and false-like values do not | File active child for inconsistent truthiness or Sysop SITE/runtime-config coupling |
| Classic/dropfile fixture | Synthetic or seeded session/user context | Focused ExUnit for generated dropfile; inspect temp cleanup if files are written | Documented fields generated with expected line endings and no secrets | Pass only if fields match contract and temp policy is explicit | File active child if secret leaks, fields are wrong, or cleanup is undefined |
| Resize while selector open | Door list rendered and active in harness | Render at 80x24 and cramped; harness resize from 80x24 to cramped and back | Borders, descriptions, keybars, and selection stay within viewport | Pass only if text wraps/clips intentionally and focus remains stable | File active child for overflow, jitter, lost focus, or hidden primary actions |
| Resize while door active | Running native and external demo doors | Harness launch, then `resize 80x24`, cramped size, optional wide size | Resize reaches door or degrades gracefully; return UI redraws cleanly | Pass only if no terminal corruption or unhandled crash | File active child if resize breaks I/O, hangs, or corrupts return screen |
| Timeout path | Door fixture with short timeout or controllable hang | Focused test plus harness if wired into catalog | Timeout message is understandable; runner kills process tree; audit reason is timeout | Pass only with cleanup evidence | File active child if orphan remains, timeout is silent, or user sees raw error |
| Crash path | Door fixture exits nonzero or crashes immediately | Focused test plus harness if wired into catalog | Foglet returns with concise failure message and safe audit status | Pass only if no stacktrace/secrets leak into TUI | File active child for leak, hang, garbled terminal, or missing audit reason |
| SSH disconnect cleanup | Long-running external door fixture | Harness/manual: launch door, disconnect session, then run observable cleanup check | Door process tree exits and next login starts in sane TUI | Pass only with cleanup command output or implementation-provided observable check | File active child for orphan process, stale session state, or broken next login |
| Process cleanup after normal exit | Native and external demos | Focused integration tests and observable process check | Runner stops, temp context/dropfiles removed, supervisor has no active child for completed door | Pass only with explicit observable evidence | File active child for temp leak or supervised child leak |
| Terminal recovery | Native/external normal exit, crash, timeout, disconnect | SSH harness screen snapshots after return and next login | Cursor/focus stable; no disruptive redraw; primary/cancel keys work | Pass only with user-visible sane terminal | File active child for stuck raw mode, hidden cursor in input contexts, or broken key path |
| Main menu / selector visual gate | Render fixtures with visible and empty catalog states | `rtk mix foglet.tui.render` at 80x24, 64x20, optional 120x30; screenshot/snapshot if useful | Door Games appears only when visible; selector/modal are readable and anchored | Pass only if wrapping, alignment, boundaries, and keybar are release-quality | File active child for obvious visual/usability defects even when tests pass |
| PR readiness | Final canonical PR opened by Platform Lead | `gh pr view`, CI status, git diff file list, focused/full tests | One canonical PR, green checks, no accidental artifacts, all evidence linked | Pass only if release shape is clean and active blockers are resolved | Route release-shape defects to Platform Lead; implementation defects to owner/CTO |

## Required harness evidence shape

Each SSH/TUI QA comment should include:

- Branch and exact SHA tested.
- PR URL or `none yet`.
- Server command class used, with secrets redacted.
- Harness script path or summarized manual key path.
- Terminal dimensions checked: 80x24 plus cramped size, and wide size if used.
- Expected result and observed result.
- Pass/fail/blocked call and whether it blocks merge.
- Visual/usability notes: wrapping, alignment, focus/cursor, redraw calmness, anchoring, modal boundaries, keyboard usability, terminal fit, overall composition.
- Follow-up backlog section.

## Suggested harness script skeletons

Do not commit scripts containing credentials. Keep scripts under a temporary or approved QA-artifacts path and summarize steps in issue comments.

Native demo launch/return skeleton:

```text
screen
key d
screen
key enter
screen
key enter
screen
type q
screen
```

External demo launch/return skeleton:

```text
screen
key d
key down
screen
key enter
screen
key enter
screen
type q
screen
```

Resize skeleton:

```text
resize 80x24
screen
resize 64x20
screen
resize 120x30
screen
```

Disconnect cleanup should be paired with an implementation-provided observable cleanup command, for example a safe test-only `mix` task, process-name check, or runner supervisor snapshot. Do not rely on arbitrary broad process greps as the only proof if the implementation can expose a better check.

## Blocker rules

QA must create or route an active child issue when a defect blocks current PR or FOG-480 acceptance. Blocking defects are not backlog polish.

Active blocker content must include:

- Parent: FOG-480.
- Tested branch and SHA.
- PR URL if one exists.
- Reproduction steps or harness script summary.
- Expected vs actual behavior.
- Commands/checks run.
- Terminal dimensions when relevant.
- Suggested owner role if clear; otherwise assign CTO for triage.
- Statement that it blocks merge/release signoff.

Use backlog only for non-blocking future polish or catalog-scale enhancements.

## Current residual risk

At the kickoff SHA, runtime QA cannot yet produce native/external launch evidence, resize evidence while a door is active, timeout/crash/disconnect cleanup evidence, or final PR readiness evidence. Those are required before FOG-480 release signoff.

## Follow-up backlog

None created by this strategy. Current gaps are active FOG-480 implementation and QA handoff requirements, not backlog polish.
