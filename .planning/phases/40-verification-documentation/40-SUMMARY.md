---
phase: 40-verification-documentation
status: in-progress
started: 2026-04-29T14:51:06Z
requirements: [VERIFY-01, VERIFY-05]
---

# Phase 40: Verification & Documentation Evidence

Phase 40 closes the v2.0 TUI runtime migration by turning Phase 39 carry-forward
items into explicit dispositions, fixing known close-gate blockers, and
recording final verification evidence.

## Carry-Forward Disposition Register

| Source | Item | Disposition | Evidence | Plan |
|--------|------|-------------|----------|------|
| `deferred-items.md` | BL-01 doomed oneliner submit leaves form in `{:error, _}` | In scope - fix modal submit failure recovery. | Pending `rtk mix test test/foglet_bbs/tui/screens/account_test.exs`. | 40-01 |
| `deferred-items.md` | BL-01 doomed hide-oneliner submit leaves form in `{:error, _}` | In scope - fix modal submit failure recovery. | Pending `rtk mix test test/foglet_bbs/tui/screens/account_test.exs`. | 40-01 |
| `deferred-items.md` | `board_list.ex:161` Dialyzer `pattern_match_cov` | Fixed - removed the unreachable `_other` branch from the unsubscribe case after the typed `BoardTree.focused_board_entry/1` patterns cover the possible subscription states. | `rtk mix dialyzer` passed with no emitted warnings for this path. | 40-01 |
| `deferred-items.md` | `sysop.ex:823` Dialyzer `pattern_match` | Fixed - removed the impossible tuple-shaped `maybe_request_invites_load/2` overload; the actual reducer flow passes `%Sysop.State{}` first, then appends active-load effects through `maybe_request_active_load/2`. | `rtk mix dialyzer` passed with no emitted warnings for this path. | 40-01 |
| `39-SUMMARY.md` | Transitional callbacks `render/1`, `handle_key/2`, `init_screen_state/1` | In scope for production runtime cleanup after blockers are closed. | Pending static inspection and focused tests. | 40-02 |
| `39-SUMMARY.md` | Remaining breadcrumb migration for Login, MainMenu, BoardList, Account, Moderation, and Sysop | In scope for explicit breadcrumb behavior or documented exact fallback intent. | Pending active breadcrumb/layout evidence. | 40-03 |
| `39-REVIEW-FIX.md` | WR-02 duplicate legacy `handle_key/2` and `render/1` implementations | In scope with transitional callback cleanup where production/test seams permit. | Pending callback cleanup evidence. | 40-02 |
| `39-REVIEW-FIX.md` | WR-04 `App.take_screen_modal_submit/0` Process dictionary submit handoff | Bounded in Phase 40 unless it blocks BL-01 recovery; full protocol redesign remains out of scope. | Pending BL-01 behavior tests; retained seam to be documented if unchanged. | 40-01 / 40-02 |
| `39-REVIEW-FIX.md` | IN-02 PostReader legacy render helper chain | In scope with WR-02 legacy renderer cleanup. | Pending callback cleanup evidence. | 40-02 |
| `39-REVIEW-FIX.md` | IN-03 migrated TUI text-presence assertions | In scope only for known migrated-surface weak tests and new Phase 40 tests. | Pending targeted test hygiene evidence. | 40-03 / 40-04 |
| `39-REVIEW-FIX.md` | IN-04 App-shaped `frame_state/2` maps across screens | Intentionally excluded unless callback cleanup naturally removes a local case; broad `Theme.from_context/1` refactor is out of scope. | Research marks this as optional cleanup, not a close-gate blocker. | Excluded |

## Verification Evidence

Evidence will be appended by the individual Phase 40 plans as each close-gate
item is fixed or explicitly bounded.

## Plan 40-03 IN-03 Targeted Test Hygiene

- Replaced one weak assertion in
  `test/foglet_bbs/tui/screens/post_composer_test.exs`: the reply preview-mode
  test now asserts reducer-owned local state (`mode`, draft value, and
  `reply_to`) instead of proving the mode switch by arbitrary rendered text.
- Kept breadcrumb/chrome assertions in
  `test/foglet_bbs/tui/widgets/chrome/screen_frame_test.exs` and
  `test/foglet_bbs/tui/widgets/chrome/breadcrumb_migration_test.exs` as visual
  contract coverage because the rendered chrome string is the behavior under
  test.
- Kept PostReader compact metadata/gutter and Sysop command/tab text checks as
  visual contract coverage where they prove terminal layout and command-surface
  behavior, not domain reducer state.
- Deferred broad IN-03 cleanup beyond the named files; Phase 40-03 intentionally
  avoids a whole-suite weak assertion rewrite.
