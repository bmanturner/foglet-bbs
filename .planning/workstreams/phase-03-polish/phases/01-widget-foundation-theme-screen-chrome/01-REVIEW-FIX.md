---
phase: 01-widget-foundation-theme-screen-chrome
fixed_at: 2026-04-20T15:00:00Z
review_path: .planning/workstreams/phase-03-polish/phases/01-widget-foundation-theme-screen-chrome/01-REVIEW.md
iteration: 1
findings_in_scope: 7
fixed: 7
skipped: 0
status: all_fixed
---

# Phase 01: Code Review Fix Report

**Fixed at:** 2026-04-20
**Source review:** .planning/workstreams/phase-03-polish/phases/01-widget-foundation-theme-screen-chrome/01-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 7
- Fixed: 7
- Skipped: 0

## Fixed Issues

### WR-01: Connection counter double-decrement when over-limit client disconnects

**Files modified:** `lib/foglet_bbs/ssh/cli_handler.ex`
**Commit:** 7f58606
**Applied fix:** Added `over_limit: false` boolean field to `defstruct`. In the `:over_limit` branch of `handle_msg/2`, replaced `{:ok, state}` with a fresh `%__MODULE__{over_limit: true, channel_id: channel_id, connection_ref: connection_ref}` so the flag is set. In the `:closed` handler, wrapped `decrement_connection_count()` in `unless state.over_limit do ... end` to skip the decrement for rejected connections.

---

### WR-02: `build_context/3` crashes when a pubkey-authenticated user has been deleted

**Files modified:** `lib/foglet_bbs/ssh/cli_handler.ex`
**Commit:** 70c513f
**Applied fix:** Replaced `Foglet.Accounts.get_user!(uid)` with `Foglet.Accounts.get_user(uid)` in `build_context/3`. `Repo.get/2` (the non-bang variant) returns `nil` instead of raising `Ecto.NoResultsError` when the user row no longer exists.

---

### WR-03: Unguarded `state.current_user.id` access in `PostComposer.do_submit/3`

**Files modified:** `lib/foglet_bbs/tui/screens/post_composer.ex`
**Commit:** 6b61b1b
**Applied fix:** Applied the same nil-guard pattern used in `new_thread.ex`: extracted `user_id = state.current_user && state.current_user.id`, then wrapped the entire submit body in `if is_nil(user_id) do ... else ... end`, returning an error modal for unauthenticated users rather than raising a KeyError.

---

### WR-04: `DateTime.add/3` crash when config value is a string in `verify.ex`

**Files modified:** `lib/foglet_bbs/tui/screens/verify.ex`
**Commit:** 0705376
**Applied fix:** Replaced the bare `Foglet.Config.get("email_verify_resend_cooldown_seconds", 60)` call with a `case` expression that guards `n when is_integer(n) and n > 0 -> n` and falls back to `60` for any non-integer value (string, nil, float, etc.). This matches the pattern used elsewhere in the codebase for other `Config.get!` usages.

---

### IN-01: `KeyBar` implementation does not match its documented UI-SPEC contract

**Files modified:** `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex`
**Commit:** 4f8b607
**Applied fix:** Changed `Enum.map` to `Enum.flat_map` and split each hint into two `text/2` nodes: `text("[#{k}] ", fg: theme.accent.fg, style: accent_style)` for the key label and `text("#{d}  ", fg: theme.dim.fg)` for the description (with two trailing spaces to provide inter-hint gap). Changed `row` gap from `2` to `0` since the spacing is now embedded in the description text node.

---

### IN-02: Dead branch in `ListRow.truncate_title/2` — clauses 2 and 3 are identical

**Files modified:** `lib/foglet_bbs/tui/widgets/list/list_row.ex`
**Commit:** aa8d54a
**Applied fix:** Collapsed the four-branch `cond` to three branches: `title_len <= max_len` (return as-is), `max_len >= 1` using `String.slice(title, 0, max(max_len - 1, 0)) <> @ellipsis` (handles both the `>= @min_title_length` and `>= 2` cases uniformly), and `true -> @ellipsis` (zero-width terminal). The `max/2` guard prevents a negative slice length.

---

### IN-03: Initial render in `PostReader` bypasses the render cache

**Files modified:** `lib/foglet_bbs/tui/screens/post_reader.ex`
**Commit:** 9941d94 *(applied in prior session as fix(02): WR-01)*
**Applied fix:** Added `warm_cache_for_index/5` private helper that calls `warm_cache/4` for the post at a given index. Called from `load_posts/2` immediately after fetching posts, pre-populating the render cache for the first post before the first render frame. The cache is keyed on `{post_id, width}` and persisted into `screen_state`. This commit was already present in the branch from a prior fix session.

---

_Fixed: 2026-04-20_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
