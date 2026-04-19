---
phase: 03-ssh-server-tui
reviewed: 2026-04-19T18:02:04Z
depth: standard
files_reviewed: 19
files_reviewed_list:
  - lib/foglet_bbs/markdown.ex
  - lib/foglet_bbs/tui/screens/board_list.ex
  - lib/foglet_bbs/tui/screens/login.ex
  - lib/foglet_bbs/tui/screens/main_menu.ex
  - lib/foglet_bbs/tui/screens/new_thread.ex
  - lib/foglet_bbs/tui/screens/post_composer.ex
  - lib/foglet_bbs/tui/screens/post_reader.ex
  - lib/foglet_bbs/tui/screens/register.ex
  - lib/foglet_bbs/tui/screens/thread_list.ex
  - lib/foglet_bbs/tui/screens/verify.ex
  - lib/foglet_bbs/tui/widgets/modal.ex
  - test/foglet_bbs/markdown_test.exs
  - test/foglet_bbs/tui/layout_smoke_test.exs
  - test/foglet_bbs/tui/screens/login_test.exs
  - test/foglet_bbs/tui/screens/main_menu_test.exs
  - test/foglet_bbs/tui/screens/new_thread_test.exs
  - test/foglet_bbs/tui/screens/post_composer_test.exs
  - test/foglet_bbs/tui/screens/post_reader_test.exs
  - test/foglet_bbs/tui/widgets/modal_test.exs
findings:
  critical: 1
  warning: 5
  info: 4
  total: 10
status: issues_found
---

# Phase 03: Code Review Report (Markdown + TUI Screens)

**Reviewed:** 2026-04-19T18:02:04Z
**Depth:** standard
**Files Reviewed:** 19
**Status:** issues_found

## Summary

This review covers the Markdown renderer, ten TUI screen/widget modules, and eight test files added or modified as part of the gap-closure work (markdown preview, NewThread composer, modal, KeyBar/StatusBar integration).

The architecture is sound. The domain-adapter injection pattern for testability, the Raxol block-macro DSL usage throughout (matching project memory guidelines), and the screen-state isolation per module are all well-designed. The test suite is comprehensive for the happy paths and covers the known bugs (Bug A plain-text rendering, Bug B MultiLineInput layout crash) effectively.

Three categories of issues were found:

1. **Security (Critical):** Verification codes are logged at INFO in production paths, leaking live OTP tokens to log aggregators.
2. **Logic bugs (Warnings):** Map access syntax used on a struct-like map; backspace truncates mid-grapheme for multi-byte Unicode; guard clauses in BoardList and ThreadList are not reachable for nil state; PostComposer accesses post fields without nil-safety; translate_key truncates multi-codepoint graphemes.
3. **Info:** Duplicated private functions across three modules; silent catch-all for unknown wizard steps; word_wrap strips newlines in multi-paragraph messages; invite code stub acceptance is not tracked.

---

## Critical Issues

### CR-01: Verification codes logged at INFO in production code paths

**File:** `lib/foglet_bbs/tui/screens/login.ex:278-279`
**Also:** `lib/foglet_bbs/tui/screens/register.ex:249-250`

**Issue:** After building a verification code for email confirmation, both `login.ex` (unconfirmed active user branch) and `register.ex` (open/invite_only registration success branch) log the raw 6-character token via `Logger.info("[verify] code for @#{user.handle}: #{code}")`. In any deployment with centralized log aggregation (CloudWatch, Papertrail, Datadog, on-disk log rotation), this exposes a live OTP token that grants account access. The verify screen exists precisely to guard this boundary; logging the code at INFO bypasses it (T-2-03 adjacent).

**Fix:** Remove the token from the log message entirely, or gate it behind `Mix.env() == :dev`:

```elixir
# Replace in both login.ex and register.ex:

# REMOVE:
Logger.info("[verify] code for @#{user.handle}: #{code}")

# USE INSTEAD (token not in message):
Logger.debug("[verify] code generated for @#{user.handle}")

# OR, for a dev-only escape hatch:
if Mix.env() == :dev do
  Logger.debug("[verify][DEV ONLY] code for @#{user.handle}: #{code}")
end
```

---

## Warnings

### WR-01: Map access syntax used on a plain map (CLAUDE.md violation)

**File:** `lib/foglet_bbs/tui/screens/post_composer.ex:374`

**Issue:** `ss[:reply_to] && ss[:reply_to].id` uses bracket/Access syntax on `ss`, which is the `post_composer` screen-state plain map. While this does not crash today (plain maps implement Access), the surrounding code uses direct dot-access (`ss.input_state`, `ss.mode`, `ss.error`). CLAUDE.md prohibits bracket syntax on struct-like values because it silently returns `nil` instead of raising when a key is absent — if `ss` is ever migrated to a typed struct, this becomes a silent bug. The `reply_to` key is always present in the map (initialized in `init_screen_state/1`), so dot-access is both correct and consistent.

**Fix:**
```elixir
# Replace:
reply_to_id = ss[:reply_to] && ss[:reply_to].id

# With:
reply_to_id = ss.reply_to && ss.reply_to.id
```

### WR-02: Backspace corrupts multi-byte graphemes in Login and Register

**File:** `lib/foglet_bbs/tui/screens/login.ex:140`
**Also:** `lib/foglet_bbs/tui/screens/register.ex:77`

**Issue:** Both backspace handlers use `String.length/1` to count characters and `String.slice/3` to drop the last one. `String.length/1` counts Unicode codepoints, not grapheme clusters. For composed graphemes — accented characters built from a base + combining mark (e.g., `e` + U+0301 = `é`, 2 codepoints), or ZWJ sequences — this slices mid-grapheme and produces an invalid or wrong string. `drop_last_grapheme/1` in `login.ex` is named to suggest grapheme-awareness but implements codepoint counting.

**Fix:**
```elixir
# login.ex — replace drop_last_grapheme/1:
defp drop_last_grapheme(""), do: ""
defp drop_last_grapheme(str) do
  graphemes = String.graphemes(str)
  graphemes |> Enum.take(length(graphemes) - 1) |> Enum.join()
end

# register.ex — replace the backspace new_input calculation:
new_input =
  case String.graphemes(current) do
    [] -> ""
    gs -> gs |> Enum.take(length(gs) - 1) |> Enum.join()
  end
```

### WR-03: Guard clause for empty list is unreachable when state field is nil

**File:** `lib/foglet_bbs/tui/screens/board_list.ex:40-55`
**Also:** `lib/foglet_bbs/tui/screens/thread_list.ex:41-53`

**Issue:** In `BoardList.render_board_rows/2`:

```elixir
defp render_board_rows(state, _ss) when state.board_list == [] do
  [text("No boards subscribed...")]   # "empty" message
end

defp render_board_rows(state, ss) do
  boards = state.board_list || []
  if boards == [] do
    [text("Loading...", style: [:dim])]  # also shows for empty
  ...
end
```

The guard `when state.board_list == []` only matches when the field is exactly `[]`. The initial state before boards are loaded has `board_list: nil`. `nil == []` is `false`, so the "No boards subscribed" message is never shown for the nil case — instead, the fallback clause renders "Loading…" (because `nil || [] == []`). After `load_boards/1` runs and the domain module returns `[]`, the guard does match and the "No boards subscribed" message appears. The same structural issue exists in `ThreadList` with `current_thread_list`. Functionally this is close to correct, but the "Loading…" vs "No boards" distinction is inverted from what the guard-based arrangement suggests.

**Fix:** Replace the two-clause pattern with a single explicit `case`:

```elixir
defp render_board_rows(state, ss) do
  case state.board_list do
    nil ->
      [text("Loading...", style: [:dim])]
    [] ->
      [text("No boards subscribed. Ask your sysop to subscribe you.", fg: :yellow)]
    boards ->
      Enum.with_index(boards)
      |> Enum.map(fn {board, idx} -> render_board_row(board, idx, ss.selected_index) end)
  end
end
```

### WR-04: `render_post_items/4` accesses post fields without nil guards

**File:** `lib/foglet_bbs/tui/screens/post_reader.ex:180-199`

**Issue:** `render_post_items/4` accesses `post.body`, `post.inserted_at`, and `post.user` via direct struct field access. If a post arrives with any of these keys absent (e.g., a partially-hydrated map from a query missing a preload), accessing a missing key on a plain map raises `KeyError`. The function also assumes `post.body` is always binary — `post.body || ""` handles `nil` but not a missing key. `post.inserted_at` at line 197 is interpolated directly without any nil guard. Compare this with `quote_preview/1` at line 319 which correctly uses `Map.get(post, :body, "")`.

**Fix:**
```elixir
defp render_post_items(state, post, idx, total) do
  sc = Map.get(state, :session_context) || %{}
  markdown_mod = get_in(sc, [:domain, :markdown]) || Foglet.Markdown
  body = Map.get(post, :body, "")
  inserted_at = Map.get(post, :inserted_at, "unknown")
  author = get_post_author(post)

  rendered =
    if function_exported?(markdown_mod, :render, 1) do
      render_markdown_tuples(markdown_mod.render(body))
    else
      text(body, fg: :green)
    end

  [
    text("Post #{idx + 1} of #{total}", style: [:dim]),
    text("By @#{author} at #{inserted_at}", style: [:dim]),
    text(""),
    rendered
  ]
end
```

### WR-05: `translate_key/1` truncates multi-codepoint graphemes to first codepoint

**File:** `lib/foglet_bbs/tui/screens/post_composer.ex:208-213`
**Also:** `lib/foglet_bbs/tui/screens/new_thread.ex:461-466`

**Issue:** The typed-character translation converts the grapheme string `c` to a charlist and extracts only `[cp | _]` — the first codepoint — discarding the rest. For multi-codepoint graphemes (combining characters, ZWJ sequences such as the rainbow flag `🏳️‍🌈` = 4 codepoints), everything after the first codepoint is silently dropped. The comment "emoji/unicode graphemes work too" is only accurate for single-codepoint emoji (e.g., 🐸 U+1F438). The test at `post_composer_test.exs:157` verifies only 🐸, which is a single codepoint and passes through correctly.

**Fix:** Verify what `MultiLineInput.update/2` accepts for `{:input, ...}`. If it accepts a binary string, pass the full grapheme:

```elixir
defp translate_key(%{key: :char, char: c}) do
  # Filter control characters; pass full grapheme binary to MultiLineInput.
  case String.to_charlist(c) do
    [cp | _] when cp >= 32 -> {:input, c}   # binary grapheme, not integer codepoint
    _ -> nil
  end
end
```

If `MultiLineInput` strictly requires an integer codepoint, remove the misleading comment and document the multi-codepoint grapheme limitation explicitly.

---

## Info

### IN-01: `translate_key/1` and `render_markdown_tuples/1` are duplicated across three modules

**File:** `lib/foglet_bbs/tui/screens/post_composer.ex:194-215`
**Also:** `lib/foglet_bbs/tui/screens/new_thread.ex:447-468`
**Also:** `lib/foglet_bbs/tui/screens/post_reader.ex:204-215`

**Issue:** The `translate_key/1` function (14 clauses) is copy-pasted identically in both `PostComposer` and `NewThread`. The `render_markdown_tuples/1` function (7 match clauses) is duplicated in `PostComposer`, `NewThread`, and `PostReader`. Any future change — a new style atom from `Foglet.Markdown`, a new key type from Raxol — must be applied in all copies.

**Fix:** Extract into shared modules:

```elixir
defmodule Foglet.TUI.InputBridge do
  @doc "Translate a Raxol key event to a MultiLineInput.update/2 message."
  def translate_key(event), do: ...
end

defmodule Foglet.TUI.MarkdownView do
  import Raxol.Core.Renderer.View
  @doc "Render a [{text, style_atom}] list as a column of styled text/2 elements."
  def render_markdown_tuples(tuples), do: ...
end
```

### IN-02: `Register.advance/5` catch-all silently no-ops on unknown steps

**File:** `lib/foglet_bbs/tui/screens/register.ex:205`

**Issue:** The catch-all clause `defp advance(_w, _unknown_step, _value, state), do: {state, []}` silently returns unmodified state when called with an unexpected step atom. A typo in a step atom or a future refactor that renames a step atom will stall the wizard with no error. This is a low-priority issue in the current stable wizard, but it makes future debugging harder.

**Fix:**
```elixir
defp advance(_w, unknown_step, _value, state) do
  require Logger
  Logger.warning("[Register.advance] unexpected wizard step: #{inspect(unknown_step)}")
  {state, []}
end
```

### IN-03: `Modal.word_wrap/2` strips embedded newlines, merging multi-paragraph messages

**File:** `lib/foglet_bbs/tui/widgets/modal.ex:72-88`

**Issue:** `word_wrap/2` splits the full message string on `~r/\s+/` (all whitespace including `\n`), then re-joins as a single paragraph flow. A message like `"Registration complete.\n\nCheck your email."` is rendered as one wrapped paragraph with no blank line. This collapses intentional paragraph breaks in modal messages. The sysop-approval modal in `register.ex` does not currently use multi-paragraph messages, but as messages grow more complex this will surface.

**Fix:** Split on newlines first, then wrap each paragraph independently:

```elixir
defp word_wrap(text, max_width) when is_binary(text) and is_integer(max_width) do
  text
  |> String.split("\n")
  |> Enum.flat_map(fn paragraph ->
    if paragraph == "" do
      [""]  # preserve blank lines as empty line separators
    else
      wrap_paragraph(paragraph, max_width)
    end
  end)
end

defp wrap_paragraph(text, max_width) do
  text
  |> String.split(~r/\s+/, trim: true)
  |> Enum.reduce([""], fn word, [current | rest] ->
    cond do
      current == "" -> [word | rest]
      String.length(current) + 1 + String.length(word) <= max_width ->
        ["#{current} #{word}" | rest]
      true -> [word, current | rest]
    end
  end)
  |> Enum.reverse()
end
```

### IN-04: Invite code stub acceptance is not marked as a tracked TODO

**File:** `lib/foglet_bbs/tui/screens/register.ex:218-220`

**Issue:** The fallback path when `Foglet.Accounts.consume_invite_code/1` is not yet exported accepts any 4-32 character alphanumeric string as a valid invite code: `Regex.match?(~r/\A[A-Za-z0-9]{4,32}\z/, code)`. This is the currently active path. The code comment says "Phase 8 wires real invite code generation (D-04)" but there is no machine-trackable marker (e.g., a `TODO(phase-8)` tag) that would surface in a `mix todo` scan or roadmap check.

**Fix:** Add a structured TODO tag so it appears in any future audit:

```elixir
# TODO(phase-8, D-04): Replace stub with Accounts.consume_invite_code/1.
# Until then, any 4-32 char alphanumeric string is accepted as a valid invite code.
Regex.match?(~r/\A[A-Za-z0-9]{4,32}\z/, code)
```

---

_Reviewed: 2026-04-19T18:02:04Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
