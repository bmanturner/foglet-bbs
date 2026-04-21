---
phase: 4
plan: "03"
subsystem: tui
tags: [composer, navigation, origin, cancel, title-cap, reply-jump]

requires:
  - phase: 4
    provides: "Plan 04-01 shared Compose widget, Plan 04-02 config seeds (max_thread_title_length)"
provides:
  - "Origin-aware cancel navigation from PostComposer and NewThread"
  - "Reply-jump: PostComposer submit lands user on their new reply"
  - "ThreadList [C] routes to :new_thread (crash fix COMPOSE-03)"
  - "NewThread submit navigates to :thread_list with {:load_threads}"
  - "Title length cap enforced via config (default 60) with live counter"
affects: [composer-navigation, thread-creation, post-reply]

tech-stack:
  added: []
  patterns:
    - "Origin stashing: entry-point screens set :origin on composer screen_state; cancel reads it"
    - "3-arity command extension: {:load_posts, id, opts} with backward-compat 2-arity shim"

key-files:
  created: []
  modified:
    - lib/foglet_bbs/tui/app.ex
    - lib/foglet_bbs/tui/screens/main_menu.ex
    - lib/foglet_bbs/tui/screens/thread_list.ex
    - lib/foglet_bbs/tui/screens/post_reader.ex
    - lib/foglet_bbs/tui/screens/post_composer.ex
    - lib/foglet_bbs/tui/screens/new_thread.ex
    - test/foglet_bbs/tui/screens/thread_list_test.exs
    - test/foglet_bbs/tui/screens/main_menu_test.exs
    - test/foglet_bbs/tui/screens/post_reader_test.exs
    - test/foglet_bbs/tui/screens/post_composer_test.exs
    - test/foglet_bbs/tui/screens/new_thread_test.exs

key-decisions:
  - "Origin stashed at call site (Map.put) rather than extending init_screen_state/1 opts — keeps init scope-clean"
  - "PostComposer cancel defaults to :main_menu (not :thread_list) as safety net — :main_menu is always renderable"
  - "2-arity backward-compat shims in app.ex avoid touching existing callers of {:load_posts, id}"
  - "Title cap enforced at keystroke level (not on submit) for immediate feedback"

patterns-established:
  - "Origin-aware navigation: screens set origin in screen_state, composers read it on cancel"
  - "Config-driven soft caps with safe fallbacks (max_thread_title_length)"
  - "3-arity command extension pattern: add opts param with backward-compat shim"

requirements-completed:
  - COMPOSE-01
  - COMPOSE-02
  - COMPOSE-03

duration: 38min
completed: "2026-04-20T18:27:44Z"
---

# Phase 4 Plan 03: Composer Wiring Summary

**Origin-aware composer routing, crash fix, reply-jump, title cap, and thread-list navigation — end-to-end composer wiring across 6 source files and 5 test files**

## Performance

- **Duration:** 38 min
- **Started:** 2026-04-20T17:50:00Z
- **Completed:** 2026-04-20T18:27:44Z
- **Tasks:** 8
- **Files modified:** 11

## Accomplishments
- Fixed COMPOSE-03 crash: ThreadList [C] no longer routes to :post_composer with nil thread
- Three composer entry points now stash origin for cancel navigation
- PostComposer cancel is origin-aware (routes back to originating screen)
- PostComposer submit dispatches reply-jump so user lands on their new reply
- NewThread cancel is origin-aware (Ctrl+C/Esc returns to originating screen)
- NewThread submit navigates to :thread_list with {:load_threads} dispatch
- Title field enforces configurable soft cap (default 60) with live char counter
- Removed dead code: "coming soon" fallback, function_exported? guard

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend {:load_posts} handler** - `2bca66d` (feat)
2. **Task 2: MainMenu origin stash** - `70f36df` (feat)
3. **Task 3: ThreadList crash fix** - `8082d32` (fix)
4. **Task 4: PostReader origin stash** - `525470d` (feat)
5. **Task 5: PostComposer origin-aware cancel + reply-jump** - `5cc6cee` (feat)
6. **Task 6: NewThread cancel, title cap, thread-list nav** - `2f8e42c` (feat)
7. **Task 7: Tests for entry-point screens** - `fcdfdfe` (test)
8. **Task 8: Tests for composer screens** - `5869c1b` (test)

## Files Created/Modified
- `lib/foglet_bbs/tui/app.ex` - 3-arity {:load_posts}/{:posts_loaded} with jump_last support
- `lib/foglet_bbs/tui/screens/main_menu.ex` - origin: :main_menu stash on [C]
- `lib/foglet_bbs/tui/screens/thread_list.ex` - [C] routes to :new_thread (crash fix)
- `lib/foglet_bbs/tui/screens/post_reader.ex` - origin: :post_reader stash on [R]
- `lib/foglet_bbs/tui/screens/post_composer.ex` - origin-aware cancel, reply-jump submit
- `lib/foglet_bbs/tui/screens/new_thread.ex` - origin-aware cancel, title cap, thread-list nav
- `test/foglet_bbs/tui/screens/thread_list_test.exs` - [C] routing + origin + regression tests
- `test/foglet_bbs/tui/screens/main_menu_test.exs` - origin stash test
- `test/foglet_bbs/tui/screens/post_reader_test.exs` - origin stash test
- `test/foglet_bbs/tui/screens/post_composer_test.exs` - origin-aware cancel + reply-jump tests
- `test/foglet_bbs/tui/screens/new_thread_test.exs` - cancel, title cap, submit nav tests

## Decisions Made
- Origin stashed via Map.put at call site rather than extending init_screen_state/1 — reduces blast radius
- PostComposer cancel defaults to :main_menu (always renderable) rather than :thread_list (needs board context)
- 2-arity backward-compat shims in app.ex preserve existing callers unchanged
- Title cap enforced at keystroke level with :no_match return for immediate UX feedback

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- Existing ThreadList test asserted old broken behavior (current_screen: :post_composer) — updated to assert new routing
- Existing PostComposer cancel test asserted :thread_list — updated since cancel now defaults to :main_menu (no origin set in test fixture)
- NewThread "coming soon" test used FakeBoardsEmpty as threads module which lacks create_thread/3 — replaced with test for unauthenticated-user path (the remaining guard in do_create_thread)

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All three composer entry points route correctly with origin stashing
- Cancel navigation is origin-aware from both composers
- Reply-jump works end-to-end (app.ex handles jump_last option)
- Title cap enforced with live counter
- Ready for Plan 04-04 (cosmetic cleanup: shared widget delegation, preview integration)

---
*Phase: 04-composer-thread-creation-end-to-end*
*Completed: 2026-04-20*
