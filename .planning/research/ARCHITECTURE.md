# v1.4 Architecture Analysis — Polish/Bugfix Integration with Existing Foglet TUI

**Project:** Foglet BBS v1.4 Post-Facelift Polish & Bug Fixes
**Domain:** SSH-first terminal UI bugfix milestone (Elixir/Phoenix + vendored Raxol)
**Researched:** 2026-04-26
**Confidence:** HIGH on directly-verified locations; MEDIUM on a few sysop submodule init failure modes that were not deeply read.

This is a brownfield bug-fix milestone. Almost every fix is **modify** (touching one or two existing files), with only a handful of small **new components** required. Below is the integration map per ISSUES.md category, then the suggested phase build order with cross-fix dependencies called out.

---

## Existing Architecture Recap (verified by reading)

The TUI runs as a Raxol `Application` (`Foglet.TUI.App`) inside a per-connection Lifecycle started by `Foglet.SSH.CLIHandler.handle_ssh_msg/2` on PTY allocation. Bytes arrive from the SSH channel, are parsed by `Raxol.SSH.IOAdapter.parse_input/1` → `InputParser.parse/1` (vendor dependency, not in `vendor/raxol/lib`), and dispatched to the Lifecycle dispatcher as `Raxol.Core.Events.Event` structs. `App.normalize_message/1` collapses key events into `{:key, %{key: …, char: …, shift: …, ctrl: …}}` and resize events into `{:window_change, w, h}`.

Key routing chain (verified at `lib/foglet_bbs/tui/app.ex:359-392`):

1. SizeGate gate — swallow keys when terminal is too small.
2. `state.modal != nil` — route to `global_key_handler/2` (modal dismissal/forms).
3. Otherwise, dispatch to `screen_module_for(state.current_screen).handle_key/2`. The screen returns `{:update, new_state, commands}` or `:no_match`.
4. On `:no_match`, fall back to `global_key_handler/2` (login `q` → quit; everything else is no-op).

Screen-local state lives at `state.screen_state[<screen_atom>]`, typed as a per-screen `State` struct. Tabs widget (`Foglet.TUI.Widgets.Input.Tabs`) consumes Left/Right/Home/End/1-9 — every other key is forwarded to `delegate_to_active_tab/3` in the screen.

Modal forms (Account `Profile`/`Prefs`, oneliners) all go through `Foglet.TUI.Widgets.Modal.Form`, which owns the focus index and handles Tab / Shift-Tab / Esc / Enter (`form.ex:101-153`).

Domain mutations are off-process: `do_update/2` builds a `Foglet.TUI.Command.task` closure that calls `Foglet.{Accounts,Boards,Threads,Posts,Moderation,Oneliners}` and returns a typed result tuple wrapped in `{:command_result, inner}` for re-dispatch.

---

## Integration Points by ISSUES.md Category

### A. Layout regressions (Globally #1; Moderation #1; Boards #1)

| Issue | Location | Modify or New |
|---|---|---|
| Global "border glyphs to the right of right-most tab" | `lib/foglet_bbs/tui/widgets/input/tabs.ex:90-105` — the tab-bar `box do row do … end end` has padding 0 and renders only tab labels with `text("   ", fg: theme.border.fg)` interspersed. The `box style: %{border_fg: …}` the row sits inside is rendered by Raxol's `box` border-fill, which fills remaining width with the border glyph. The "trailing border glyphs" are actually the box's right-edge padding being rendered by Raxol's border layout because the row doesn't consume the full width. | MODIFY `tabs.ex` only — add a trailing spacer text node (or a `flex_grow` filler) sized to `max(width - sum_of_tab_widths, 0)` so the row consumes full width, OR drop the wrapping `box` (it has padding 0; it's only there for the `border_fg` color slot). |
| Moderation LOG/USERS/BOARDS extends above terminal | `lib/foglet_bbs/tui/screens/moderation.ex` + the table widgets in `lib/foglet_bbs/tui/widgets/display/table.ex` and `console_table.ex` | MODIFY: Likely the table widgets render rows unconditionally (no viewport / `max_lines` clamp). The fix mirrors what `MarkdownBody.render_tuples` does: take `terminal_size` from state, compute available height (after ScreenFrame top + tab bar + divider + key bar = ~5 rows), and have the table either truncate or page rows. |
| Boards screen entire interface broken (extends above terminal) | `lib/foglet_bbs/tui/screens/board_list.ex:65-78` — `render_board_content/3` calls `BoardTree.render` which renders every visible node; `details_strip/4` and `wide_inspector/4` add 1-2 rows. With many boards the column overruns. | MODIFY `board_list.ex` and/or `widgets/list/board_tree.ex` to clamp `visible` rows to available height (`terminal_size` minus chrome). |
| Invites table cramping (Sysop #12) | `lib/foglet_bbs/tui/screens/shared/invites_surface.ex` rendering `ConsoleTable` | MODIFY `console_table.ex` / `display/table.ex`: column widths don't have minimum padding between columns (note `│CodeStatusCreatedUsed by` collision in ISSUES.md). Add gap/min-width per column in the table widget. |

**Ordering constraint:** Layout fixes are foundational for visual verification of every other fix. They are also independent of focus-routing logic, so they can land first and in parallel. The tab-row trailing glyph (`Tabs.render`) is the smallest, lowest-risk change and unblocks visual review of every tabbed screen.

---

### B. Form interaction (Account #1, #4, #5, #7, #8; Sysop #3, #5)

| Issue | Root cause / location | Modify or New |
|---|---|---|
| Account Esc inert | `widgets/modal/form.ex:102-105` Esc IS handled and returns `:cancelled`. But `Foglet.TUI.Screens.Account.PrefsForm.do_handle_key/3` only treats `:cancelled` as "reseed from user, set status_message" — there's no upward navigation (the screen never exits). Same for ProfileForm. So Esc visibly does nothing because the screen doesn't navigate or close anything; it just resets the draft to the saved values. The user sees "no change." | MODIFY `account/profile_form.ex` and `account/prefs_form.ex`: on `:cancelled`, either pop a "changes discarded" toast for ≥1 frame, or accept that the existing Ctrl+Q is the only way out and update the key-bar to drop the misleading `[Esc] Cancel` hint at `account.ex:42-48`. Decision belongs to product. |
| Account Preferences typing into wrong field (#8) | The bug: in `account/state.ex` PrefsForm builds a Modal.Form with three fields `[timezone, time_format, theme]`. Tab/Shift-Tab is the only way to change `focus_index` (verified at `widgets/modal/form.ex:108-130`). Up/Down only cycle within `:enum` field state. There's also a parallel `prefs_focus` atom in `Account.State` synced into `form.focus_index` by `Account.sync_prefs_focus/1` (`account.ex:241-254`). If anything sets `prefs_focus` to e.g. `:time_format` without going through the form, the form still receives `:char` events at the OLD focus_index until next sync. The user perception that "selecting another field types into timezone" probably means the user pressed `↓` on the timezone text field; `:down` is forwarded by Modal.Form clause 5 to `dispatch_to_field`, which for a `:text` field calls `TextInput.handle_event` — which doesn't move focus. The user assumed `↓` moves to the next field. | MODIFY `widgets/modal/form.ex`: add Up/Down key clauses that move focus (`focus_index ± 1`) when the focused field is NOT `:enum` (preserves enum-cycling behavior). OR: clarify UX: only Tab/Shift-Tab moves focus and add this to the form's footer. The first option matches user expectation. |
| Account Preferences "no way to select options" (#4) | Same root cause as #8 — `time_format`/`theme` ARE `:enum` types and cycle with Up/Down per `form.ex:280-293`, but the user can't reach them because timezone is field 0 and they don't know to press Tab. | Same fix: enable Up/Down for inter-field movement on text fields. |
| Account Shift-Tab inert (#5) | `widgets/modal/form.ex:110-123` handles BOTH `%{key: :tab, shift: true}` AND `%{key: :shift_tab}`. So at the form layer this works. The bug must be in event normalization: `App.normalize_message/1` flattens `Raxol.Core.Events.Event{type: :key, data: data}` and forwards `data`. Whether `data` contains `shift: true` for Shift-Tab depends on `InputParser`. Most terminals send Shift-Tab as `ESC[Z` (back-tab) and InputParser should emit `%{key: :shift_tab}` or `%{key: :backtab}`. SiteForm in `screens/sysop/site_form.ex:81-82` accepts BOTH `:shift_tab` and `:backtab`. The Modal.Form clause 2b only accepts `:shift_tab`. | MODIFY `widgets/modal/form.ex` to also handle `%{key: :backtab}` (one-line addition, matching SiteForm). Also worth adding a unit test fixture that asserts each of `{:tab, shift: true}`, `:shift_tab`, `:backtab` produces the same focus retreat. |
| Account Profile "Enter submits but nothing happens, values vanish on re-enter" (#3) | `account/profile_form.ex:39-49` returns `[{:account_save_profile, attrs}]` to the App layer. App's `do_update({:account_save_profile, attrs}, state)` (`app.ex:892-894`) calls `Accounts.update_profile/2`. On `{:ok, updated_user}` it calls `clear_account_save_state/2` which sets `status_message: "Account changes saved."`. But on re-enter, `synced_screen_state/1` calls `State.ensure_visibility` which doesn't reseed; the issue is that submit goes through `SubmitStash.pop` and then ProfileForm sets `status_message: "Profile ready to save."` BEFORE the App.do_update fires. Profile_dirty is reset to `false` but **the `state.current_user` IS updated** by `clear_account_save_state`. So the values should persist… unless `current_user` reload is missing. Need to verify `Accounts.update_profile/2` returns the new user with the saved fields. The "re-enter" bug suggests `seed_from_user` is not being called after save, so `profile_form` retains stale values that get overwritten next render. | MODIFY `account/state.ex` `seed_from_user/2` integration with `app.ex:1218-1226 clear_account_save_state/2` — the function calls `seed_from_user(updated_user)` then sets `status_message`. Verify this rebuilds `profile_form` with the new values. The user-visible "values are gone on re-enter" could be that `prefs_form` defaults to `"Etc/UTC"` when timezone is nil (`state.ex:170-176`), masking the saved value. Add an integration test: save → leave → re-enter → assert form fields show saved values. |
| Account "Enter Submit / Esc Cancel redundant under menu" (#7) | `widgets/modal/form.ex:193` renders a `text("[Enter] Submit   [Esc] Cancel", …)` footer. It's a body-only render; the screen also shows it in the key bar. | MODIFY `widgets/modal/form.ex` — make the footer optional (`opts[:footer]` default `false` for screens that show the key bar; `true` for actual modal overlays). Account/Sysop pass `false`; oneliner composer (real overlay) passes `true`. |
| Sysop Site tab "Unable to edit any of the values" (#3) | `screens/sysop/site_form.ex:89-96` accepts `:char`. Tab cycles focus via `:tab`. Submit via `:enter` or Ctrl+S. Submit calls `Config.put/3`. The "unable to edit" probably means: typing `o` to set `registration_mode` to `"open"` calls `apply_char_to_field` which is enum-prefix-match (verified). For text/integer fields though, there may not be a path. The bug is that values mutate `drafts` in-memory but the user sees no change because SiteForm doesn't echo the draft inline (uses the D-19 fallback render, which renders saved values). | MODIFY `screens/sysop/site_form.ex` to render the **draft** value (with focus marker) per row, not the saved Config value. |
| Sysop Site "Enter does nothing, Escape does nothing" (#5) | `site_form.ex:84` does handle `:enter` (calls `submit/1`). So Enter should call `Config.put/3`. The user must not see any feedback on success. There's no `:escape` clause at all → escape is a no-op. | MODIFY `site_form.ex`: (a) emit a status row on submit success (the submodule contract supports `events`; surface via `apply_submodule_result` in `screens/sysop.ex:238-262`); (b) add `:escape` clause that resets drafts to saved values. |
| Sysop Site subtitles expose internal planning notes (#4) | Likely in `Foglet.Config.Schema` field descriptions — the SiteForm renders `Schema.fetch_spec/1` → `:description` text. | MODIFY `lib/foglet_bbs/config/schema.ex` descriptions to be user-facing copy, not planning notes. |

**Ordering constraint:** "Account #4 (no way to select options)" depends on the Up/Down focus fix (Modal.Form). Once Modal.Form supports inter-field Up/Down, the prefs UX works. The Esc UX fix is product-decision. **Form fixes should land after layout fixes**, otherwise verification is hampered by layouts shifting under the form.

---

### C. Sysop tabs that "never load" (Sysop #1, #6, #7, #8, #9)

This is the most architecturally important category. Verified flow:

`screens/sysop.ex:113-146` — Each tab body renders `placeholder("Press any key to load …", theme)` when its sub-state field is `nil`. Loading happens in `delegate_to_submodule/4` at `sysop.ex:227-231`, which calls `module.init(current_user: …)` ONLY IF the Tabs widget did NOT consume the key. That is:

1. User switches to BOARDS tab (digit `2` or arrow). `Tabs.handle_event/2` returns `{new_tabs, {:tab_changed, idx}}` → `action != nil` → goes to `maybe_load_invites_on_entry`, which only loads INVITES. **Other tabs are NOT auto-loaded on tab switch.** Their submodules' `:nil` placeholder remains.
2. User then presses any other key. `Tabs.handle_event/2` ignores it (e.g. `c`). `action == nil and new_tabs == ss.tabs` → `delegate_to_active_tab` → `delegate_to_submodule` → calls `module.init(current_user: …)`, loading the data.

So "press any key to load" is literally the design — but the user sees that pressing keys does NOT load BOARDS/LIMITS/SYSTEM because:

- **BOARDS:** `BoardsView.init/1` opens the boards/categories list. The first key press triggers init. Then `BoardsView.handle_key/2` handles the key. If BoardsView raises during init (e.g. on a permission check), the screen swallows the error silently and re-renders the placeholder. Most likely the bug.
- **LIMITS:** Same pattern. If `LimitsForm.init/1` reads from `Config` and one of the keys is missing, init may fail.
- **SYSTEM:** `SystemSnapshot.init/1` likely calls Erlang/OTP introspection that may fail in some environments.
- **USERS (#9 "only loads sometimes"):** `UsersView.init/1` queries pending users. Race or env-dependent failure.
- **USERS "Invalid status transition" (#10):** A `Foglet.Accounts.update_user_status/3` call returning `{:error, :invalid_status_transition}` is being surfaced via `:error_modal` in `apply_submodule_result/6`. The key handler is wired (see `sysop.ex:243-252`) but the user is hitting the transition for an `:active` user → `:pending` (or similar disallowed move).

| Issue | Modify or New |
|---|---|
| "Press any key to load" UX (#1) and tabs that never load (#6, #7, #8, #9) | MODIFY `screens/sysop.ex`: load tab data **on tab switch** rather than on next key. In `handle_key/2`, when `action == {:tab_changed, idx}`, look up the new tab's label and call its submodule's `init/1` if not already loaded. Mirror `maybe_load_invites_on_entry/2`. This also fixes "only Tab loads it (not 'any key')" (#1). |
| Submodule init that crashes silently | MODIFY each Sysop submodule (`boards_view.ex`, `limits_form.ex`, `system_snapshot.ex`, `users_view.ex`) to have a defensive `init/1` that returns a struct with an `:error` field on failure rather than raising. Render the error in place of the placeholder. |
| USERS "Invalid status transition" (#10) | MODIFY `lib/foglet_bbs/accounts.ex` (`update_user_status/3` or equivalent) to enumerate valid transitions clearly; map `{:error, :invalid_status_transition}` to a user-friendly message in `screens/sysop/users_view.ex` rather than the raw atom. |
| USERS "advertised keys do nothing" (#11) | MODIFY `screens/sysop/users_view.ex` `handle_key/2` — likely missing handlers for the keys advertised in the screen's key bar. Audit advertised vs. handled and reconcile. |
| Sysop command-bar "1-6 Jump" inconsistency (#2) | MODIFY the per-screen key-bar at the call sites (e.g. `screens/account.ex:42-48` for Account, `screens/moderation.ex:44`). Add the same `1-N Jump` group to Account and Moderation if Tabs widget supports digit jump (it does — verified `widgets/input/tabs.ex:12-17`). |

**Ordering constraint:** Sysop tab loading fix (load-on-switch) blocks fixes for USERS/BOARDS/LIMITS/SYSTEM since you can't verify a tab works until it loads. The `:invalid_status_transition` reconciliation depends on the load fix landing first.

---

### D. Auth flow gaps (Login #1-4)

| Issue | Location | Modify or New |
|---|---|---|
| Cursor doesn't follow text input (#1) | `widgets/input/text_input.ex:117-124` — `render_with_cursor_marker/3` ALWAYS renders a static `▌` prefix and then the Raxol-rendered value. The "cursor" is decorative (a focus indicator), not a real cursor that moves with insertion point. To make it follow text, render the value with the cursor block injected at `cursor_pos` — exactly the technique already used in `widgets/compose.ex:130-148` (`Compose.render_input/3` injects `█` at `cursor_pos`). | MODIFY `widgets/input/text_input.ex` to compute `cursor_pos` from `raxol_state.cursor_pos` (or recompute as length-of-value for a single-line input) and inject the cursor block at that position when `focused?`. Alternative: drop the `▌ ` prefix entirely and let the underlying Raxol TextInput render its own cursor (verify it does at the byte level). |
| Email validation on forgot password (#2) | `screens/login.ex:144-154` `handle_reset_key/2` — Enter calls `submit_reset_request/1` immediately with no validation. `Foglet.Accounts.request_password_reset_delivery/1` returns `:generic_response` regardless of whether the input was an email. | MODIFY `screens/login.ex submit_reset_request/1`: validate the identifier locally (handle pattern OR `EmailFormat`) before dispatching. Surface inline error in `login_ss.message`. |
| Breadcrumbs don't change for Register / Forgot Password (#3) | `widgets/chrome/breadcrumb_bar.ex:66-82` only handles `:login`, `:register`, `:verify` mapped to `[@root, "Login"]` etc. Wait — checking again: only `:login`, `:main_menu`, `:board_list`, `:thread_list`, `:post_reader`, `:new_thread`, `:post_composer`, `:account`, `:moderation`, `:sysop` have `parts_for_screen/2` clauses. `:register` and `:verify` fall through to default `[@root]`. Also Login has SUB-states (`:menu`, `:login_form`, `:reset_request`) which BreadcrumbBar doesn't see. | MODIFY `widgets/chrome/breadcrumb_bar.ex`: (a) add `:register` and `:verify` clauses; (b) add a clause for `:login` that reads `state.screen_state[:login][:sub]` and emits `[@root, "Login", "Register"]` etc. This is the cleanest fix because login forks happen via screen_state, not a separate screen atom. |
| Reset email cropping at small terminals (#4) | `screens/login.ex:281-306 render_reset_request/2` outputs `login_ss.message` as a single `text(login_ss.message, fg: theme.accent.fg)` — Raxol may truncate at terminal width. The 1-line constants `@reset_success_message` and `@reset_unavailable_message` are long. | MODIFY `screens/login.ex render_reset_request/2`: word-wrap the message at `terminal_size` width using `TextWidth` helpers, render as multiple text rows. |
| No-email reset path / token-consume entry point (#4) | Currently `delivery_mode == "no_email"` → `:no_match` (i.e. F is hidden). There's no flow at all for entering a token. | **NEW** small UI flow: a sub-state `:reset_consume` in `login.ex` with a TextInput for the raw token + new password, calling a NEW `Foglet.Accounts.consume_password_reset_token/2`. NEW work split across: (a) `lib/foglet_bbs/accounts.ex` — `consume_password_reset_token/2` (verify whether one exists; if so, modify to add the SSH path); (b) `screens/login.ex` — new sub-state `:reset_consume` with a 2-field flow; (c) `widgets/chrome/breadcrumb_bar.ex` add the breadcrumb part for it. The Account boundary is correct: token storage already exists in `Foglet.Accounts.UserToken` (per existing reset email flow). |

**Ordering constraint:** The cursor fix (TextInput) is foundational because it changes how every TextInput renders — Account, Login, Register, Sysop SiteForm — every form is downstream. Land cursor fix first to verify visually. The breadcrumb fix is independent and tiny. The no-email reset path is the only feature-shaped work in v1.4 and should be sequenced after the email reset flow has been verified.

---

### E. Main Menu chrome polish (Main Menu #1-7)

| Issue | Location | Modify |
|---|---|---|
| Navigation/Oneliners titles inside the box, not on border (#1) | `screens/main_menu.ex:293-302 nav_panel/3` and `:313-319 oneliners_panel/3` — both wrap `text("Navigation", …)` or `text("Oneliners", …)` INSIDE a `box do column do …` instead of using a border-title. Raxol's `box` does support a `:title` style attr (verify in vendor) — alternatively, render a custom 1-line top border with the title embedded, matching `widgets/chrome/screen_frame.ex:107-113` pattern. | MODIFY `main_menu.ex` to render box border with embedded title. Either via Raxol box `:title` option (preferred if supported) or via a custom wrapper similar to ScreenFrame's segment_row. |
| Oneliners glyph artifact `\|\|\|\|\|` on top border (#2) | Almost certainly a bidi/zero-width issue or a stray padding character introduced by the box border renderer when `Oneliners` appears inside an outer split-pane that conflicts with the box's character. Investigate the box border renderer interaction with split_pane. | MODIFY likely the same fix as #1 — by moving the title to the border line, the artifact goes away. |
| `↑/↓ Select` inert (#3) — RESOLVED | This Main Menu item is **already resolved** between ISSUES.md filing and milestone start, per PROJECT.md. Listed for completeness only. | n/a |
| Navigation keys should be accent color (#4) | `screens/main_menu.ex:304-311 nav_row/3` renders `text(prefix <> padding <> key, fg: theme.primary.fg)` as a single text node. To color the key differently, split into two `text` calls inside a `row`. The header comment at lines 56-62 acknowledges this is deferred. | MODIFY `main_menu.ex nav_row/3` to render `[text(prefix <> padding, fg: theme.primary.fg), text(key, fg: theme.accent.fg)]` inside a `row`. Update positioned-render tests that assert single-text-node layout. |
| Indent navigation items 1, move keys left 1 (#5) | Same `nav_row/3`. Add 1-space leading pad to `prefix` and decrement `padding_width` by 1. | MODIFY `main_menu.ex` only. |
| Apply theme properly (#6, #7) | Audit current theme routing — both panels currently use `theme.title.fg` for their headers and `theme.primary.fg` for body. The "apply theme properly" is likely about inactive states / hover highlight / contrast. | Product-decision; ask which theme slots should be used. MODIFY only after spec is clear. |

**Ordering constraint:** Main Menu fixes can land in parallel with the rest. They don't affect other screens. The nav-row coloring split (#4) is the only one that risks breaking existing positioned-render tests (`test/foglet_bbs/tui/screens/main_menu_test.exs`) — schedule together with test updates.

---

### F. Account SSH Keys paste (Account #9)

The flow: pressing `A` to add invokes `SSHKeysState.start_add` → form mode `:add` with two fields, focused on `:label` first. Tab → `:public_key`. The user pastes a multi-line OpenSSH key.

The paste delivery path:
1. The terminal sends bytes to SSH channel.
2. `IOAdapter.parse_input/1` → `InputParser.parse/1` produces a sequence of events. **Bracketed-paste mode is NOT enabled** (`CLIHandler.send_alt_screen_enter/1` emits only `\e[H\e[2J\e[3J\e[?1049h\e[H\e[2J\e[3J` — no `\e[?2004h`). So a paste of `ssh-ed25519 AAAA…\n` arrives as ~hundreds of `:char` events plus potentially an `:enter` for the trailing newline.
3. Each `:char` is dispatched to `Foglet.TUI.Screens.Account.handle_key/2` → `delegate_ssh_keys_key` → `SSHKeysActions.handle_key(char, …)` → `SSHKeysState.append_focused/2`.
4. Trailing `\n` becomes `:enter`, which `SSHKeysActions` clause `def handle_key(:enter, %User{} = actor, %SSHKeysState{mode: :add, form: form} = state), do: add(actor, state, form)` — **submits the form prematurely** before the next key fragment arrives.

| Fix | Modify or New |
|---|---|
| Multi-line paste support for SSH keys | Two complementary fixes. (1) MODIFY `Foglet.SSH.CLIHandler.send_alt_screen_enter/1` to also enable bracketed paste (`\e[?2004h`) and disable on leave (`\e[?2004l`). (2) MODIFY `Raxol.SSH.IOAdapter.parse_input` consumer **OR** wrap it in CLIHandler to detect `\e[200~ … \e[201~` and emit a single `{:paste, binary}` event. (3) MODIFY `widgets/modal/form.ex` and `Account.SSHKeysActions` to handle a `:paste` event by appending the entire pasted blob to the focused field. The fallback (no bracketed paste) is to make SSH key field a `:textarea` type: convert the public_key field to `:textarea` so `:enter` becomes a literal newline rather than submit. The textarea path already works (`form.ex:295-325 dispatch_to_field` for `:textarea`). |

**This is the largest "new component" risk in v1.4.** It crosses three layers (CLIHandler → Raxol parser → Form widget). Recommend the simpler textarea fallback as a v1.4 fix and defer real bracketed-paste to a follow-up. Also, recall AGENTS.md: `Foglet.SSH.CLIHandler` "owns the SSH channel lifecycle" — the bracketed-paste negotiation belongs there, not in Raxol vendor code.

---

### G. Boards screen Enter on category (Boards #2)

`screens/board_list.ex:91-118 handle_key(%{key: :enter}, state)` — calls `BoardTree.handle_event` and pattern-matches only on `{… :node_activated}` with `BoardTree.focused_board_entry(new_tree)` returning a board. For categories, this returns `nil` → `:no_match`.

| Fix | Modify |
|---|---|
| Enter on category expand/collapse | MODIFY `screens/board_list.ex` Enter handler to: (a) call `BoardTree.focused_entry/1` to inspect the focused node's `:kind`; (b) for `:category`, dispatch a toggle event (Tree widget supports `:left`/`:right` for collapse/expand; mirror that semantic). The simplest path: when focused entry is `:category`, send `%{key: :right}` if collapsed, else `%{key: :left}`, to BoardTree.handle_event, and update the screen state. |

**Ordering constraint:** Independent. Can land in parallel with anything else.

---

### H. Composer word-wrap + Markdown line breaks (Globally #2, #3)

`widgets/compose.ex:118-148 render_input/4` explicitly comments `Width is not taken as an argument — hard wrapping is the caller's responsibility (the callers pre-size MultiLineInput via its own width: option at init time)`. So MultiLineInput should already wrap at its `width:`. The bug is likely:
- `width:` at init is computed once from `terminal_size` and never updated on resize, OR
- MultiLineInput's wrap logic doesn't insert visual line breaks on `String.split(value, "\n")` rendering.

Verification: `widgets/compose.ex` splits ONLY on `\n` — so an over-long single line stays as a single line and overflows the column.

| Fix | Modify |
|---|---|
| Composer long-line wrap | MODIFY `widgets/compose.ex render_input/4`: after `String.split(value, "\n")`, run each line through a `TextWidth.wrap/2` helper (currently `Foglet.TUI.TextWidth` provides `display_width/1`, `truncate/2`, `pad_trailing/2`, `split_at/2` — verify if `wrap/2` exists; if not, NEW small helper in `text_width.ex`). Then re-flatten the wrapped lines preserving cursor row mapping. |
| Markdown line breaks "all lines cramped" (Globally #2) | MODIFY `widgets/post/markdown_body.ex group_by_newline/1`: currently uses `Enum.chunk_by(&newline?/1)` then `Enum.reject(&newline_group?/1)` — this DROPS all consecutive newline tuples, collapsing paragraph breaks. Change to drop only **single** newline groups but keep groups of length ≥ 2 (rendered as a blank `text("")` row). Alternatively, `Foglet.Markdown.render/1` could emit a `:blank_line` style, but that's a wider change. |

**Ordering constraint:** TextWidth.wrap (if added) is a building block; markdown line-break fix is independent. The composer wrap fix is needed before users can verify the composer feels right.

---

## New Components vs Modified Components — Summary

### NEW (small)

| Component | Purpose | Est size |
|---|---|---|
| `TextWidth.wrap/2` (or similar) in `lib/foglet_bbs/tui/text_width.ex` | Width-aware word-wrap for composer | 30 LOC + tests |
| `:reset_consume` sub-state in `screens/login.ex` | No-email reset path | ~80 LOC + tests |
| `Foglet.Accounts.consume_password_reset_token/2` | If not already in Accounts; verify before adding | ~30 LOC if needed |
| Bracketed-paste negotiation in `Foglet.SSH.CLIHandler` | OPTIONAL; textarea fallback removes need | ~10 LOC |
| `:paste` event handling in `widgets/modal/form.ex` and TextInput | OPTIONAL with bracketed paste | ~20 LOC |

### MODIFIED (the majority)

| File | Issues touched |
|---|---|
| `widgets/input/tabs.ex` | Trailing border glyph |
| `widgets/input/text_input.ex` | Cursor follows text |
| `widgets/modal/form.ex` | Up/Down inter-field movement; backtab; optional footer |
| `widgets/chrome/breadcrumb_bar.ex` | Register/Verify/Reset breadcrumbs |
| `widgets/post/markdown_body.ex` | Preserve consecutive newlines |
| `widgets/compose.ex` | Word-wrap long lines |
| `widgets/display/table.ex`, `console_table.ex` | Invites cramping; Moderation overflow |
| `widgets/list/board_tree.ex` (or its consumer) | Boards overflow |
| `screens/account.ex`, `screens/account/profile_form.ex`, `screens/account/prefs_form.ex`, `screens/account/state.ex` | Esc behavior; profile persistence; redundant footer; preference selection |
| `screens/account/ssh_keys_actions.ex` (textarea path) | SSH key paste fallback |
| `screens/sysop.ex` | Auto-load on tab switch |
| `screens/sysop/site_form.ex` | Edit drafts; Esc; submit feedback |
| `screens/sysop/boards_view.ex`, `limits_form.ex`, `system_snapshot.ex`, `users_view.ex` | Defensive init; render errors in place |
| `screens/login.ex` | Reset validation; reset message wrap; sub-state breadcrumbs |
| `screens/main_menu.ex` | Title on border; nav_row coloring; up/down oneliners; indent |
| `screens/board_list.ex` | Enter on category |
| `screens/moderation.ex` | Auto-load consistency with Sysop fix |
| `lib/foglet_bbs/config/schema.ex` | Site form descriptions |
| `lib/foglet_bbs/accounts.ex` | `:invalid_status_transition` reconciliation; `consume_password_reset_token/2` |
| `lib/foglet_bbs/markdown.ex` | Possibly: preserve blank-line tuples |

---

## Suggested Phase Build Order

The build order is driven by three structural dependencies:

1. **Layout fixes block visual verification of every form/interaction fix.** Tab-row trailing glyph, table cramping, and overflow all change pixel positions of subsequent fixes.
2. **Focus-routing fixes (Modal.Form Up/Down + backtab) block Account/Sysop edit verification.** Account #4, #5, #8, #11 all stem from inter-field navigation.
3. **Sysop tab auto-load fix blocks Sysop tab body fixes.** You can't verify USERS handler keys until USERS loads.

**Recommended phase grouping:**

| Phase | Scope | Why this position | Parallel-safe with |
|---|---|---|---|
| P1 — Foundation (layout) | Tab-row trailing glyph (`tabs.ex`); table cramping (`display/table.ex`, `console_table.ex`); Moderation overflow; Boards overflow; Markdown blank-line preservation; TextWidth.wrap helper | Every screen renders through these widgets. Land first to make manual verification reliable. Smallest blast radius first (tabs.ex is ~10 LOC), tables second. | All four sub-items can ship in parallel within the phase. |
| P2 — Cursor + breadcrumbs | TextInput cursor follow (`text_input.ex`); BreadcrumbBar Register/Verify/Login sub-state clauses | Both are widget-layer fixes touched by every form-having screen. Independent of P1. | Yes, can run alongside P1. |
| P3 — Modal.Form interaction | Up/Down focus movement; backtab; optional footer | Fixes Account #4, #5, #7, #8 plus Sysop #11. Depends on P1 only insofar as visual verification needs the table fixes. | Yes with P2. |
| P4 — Sysop tab loading + tab bodies | Auto-load on tab switch (`sysop.ex`); defensive init in BoardsView/LimitsForm/SystemSnapshot/UsersView; SiteForm draft echo + escape; Schema descriptions; UsersView keys | Depends on P3 (because submodule forms use Modal.Form patterns) and P1 (because table widgets are involved). | Internally serial: load fix first, then per-tab-body fixes. |
| P5 — Account workflow | Profile save persistence (verify and fix); SSH KEYS textarea fallback for paste; Esc UX disposition | Depends on P3 (Modal.Form changes). Independent of P4. | Yes with P4 (different files). |
| P6 — Auth flow | Reset email validation; reset message word-wrap; no-email reset consume sub-state + Accounts.consume_password_reset_token | Depends on P2 (BreadcrumbBar). Largest "new component" pocket — sequence after established foundations. | Independent of P4/P5. |
| P7 — Main Menu polish | Border titles; nav-row coloring; up/down oneliners; indent | Independent surface. Schedule near the end so test churn around `main_menu_test.exs` happens once. | Yes, parallel with P6. |
| P8 — Boards screen Enter | Category expand/collapse | Single-screen, low-risk. Anywhere after P1. | Yes, anywhere. |
| P9 — Composer wrap | Long-line wrap in compose render_input | Uses TextWidth.wrap from P1. | Yes, after P1. |
| P10 — Optional bracketed paste | CLIHandler `\e[?2004h`; paste event plumbing | Only if textarea fallback in P5 isn't sufficient. Highest-risk; defer. | Last. |

---

## Existing tests that need updates / new regression tests

| Existing test | Likely change |
|---|---|
| `test/foglet_bbs/tui/widgets/input/tabs_test.exs` | Add: trailing-glyph absence assertion at multiple widths. |
| `test/foglet_bbs/tui/widgets/input/text_input_test.exs` | Add: cursor-position-follows-value assertion at insertion point. |
| `test/foglet_bbs/tui/widgets/modal/form_test.exs` | Add: Up/Down moves focus on text fields, cycles enums; `:backtab` retreats focus. |
| `test/foglet_bbs/tui/widgets/chrome/breadcrumb_test.exs` | Add: `:register`/`:verify` cases; login sub-state cases. |
| `test/foglet_bbs/tui/widgets/post/markdown_body_test.exs` (if present, else add) | Add: consecutive newlines preserve blank line. |
| `test/foglet_bbs/tui/screens/sysop_test.exs` | Add: tab switch auto-loads BOARDS/LIMITS/SYSTEM/USERS; defensive init renders error in place. |
| `test/foglet_bbs/tui/screens/account_test.exs` | Add: profile save persists across re-enter; PREFS up/down moves focus; SSH KEYS textarea accepts newline-bearing paste. |
| `test/foglet_bbs/tui/screens/login_test.exs` | Add: forgot-password validation; reset-message wraps at small width; no-email reset consume flow. |
| `test/foglet_bbs/tui/screens/main_menu_test.exs` | Update: nav-row coloring split into accent key segment; up/down adjusts selected_oneliner_index; titles on border. |
| `test/foglet_bbs/tui/screens/board_list_test.exs` | Add: Enter on focused category toggles expanded set. |
| `test/foglet_bbs/tui/layout_smoke_test.exs` | Add: 64×22 / 80×24 / 132×50 no-overflow assertions for Moderation LOG/USERS/BOARDS, Boards, Sysop INVITES. |

---

## Cross-fix Ordering Constraints (the quality-gate items)

- **Layout fixes (P1) block form fixes (P3, P4, P5).** The form bugs are partly perception-bugs caused by misaligned tables and missing cursors; verifying them requires a stable canvas.
- **Chrome tab-row fix (`tabs.ex`) blocks the global trailing-glyph fix.** They're the same fix, in one file.
- **Modal.Form Up/Down fix (P3) blocks Account Preferences edit fixes (P5).** Without inter-field arrows, the user still can't reach `time_format`/`theme`.
- **TextInput cursor fix (P2) blocks visual verification of every form fix.** Without a real cursor, "is my keystroke landing in the right field?" is hard to verify manually.
- **Sysop auto-load (P4 first task) blocks Sysop tab body fixes (rest of P4).** You can't manually verify USERS keys until USERS loads.
- **BreadcrumbBar fix (P2) blocks the no-email reset consume path (P6).** The new sub-state needs a breadcrumb to be testable.
- **TextWidth.wrap helper (P1) blocks composer wrap (P9) and reset-email wrap (P6).** Land it once.

---

## Files referenced (absolute paths)

- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/app.ex` — top-level routing, modal handling, do_update dispatch
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/account.ex` — Account screen entry, tab delegation
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/account/state.ex` — Account State, form builders
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/account/profile_form.ex` — Profile submit/cancel handler
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/account/prefs_form.ex` — Prefs submit/cancel + theme preview
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/account/ssh_keys_actions.ex` — SSH keys add/revoke
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/sysop.ex` — Sysop tab routing, submodule delegation
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/sysop/site_form.ex` — Site config inline form
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/login.ex` — Login menu/form/reset sub-states
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/main_menu.ex` — Main menu nav/oneliners panels
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/board_list.ex` — BoardList screen with Enter handler
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/screens/moderation.ex` — Moderation screen, tab routing
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/widgets/input/tabs.ex` — Tab bar (trailing glyph source)
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/widgets/input/text_input.ex` — Text input cursor decoration
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/widgets/modal/form.ex` — Modal form focus + dispatch
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex` — Breadcrumb derivation
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` — Outer chrome render (for layout context)
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/widgets/compose.ex` — Composer render_input (no wrap)
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/widgets/post/markdown_body.ex` — Markdown rendering (newline collapse)
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/tui/widgets/list/board_tree.ex` — BoardTree (category expand)
- `/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/ssh/cli_handler.ex` — SSH lifecycle (paste negotiation point)
- `/Users/brendan.turner/Dev/personal/foglet_bbs/vendor/raxol/lib/raxol/ssh/io_adapter.ex` — Vendor input/output adapter

---

## Confidence

HIGH on locations and behaviors verified directly in source (focus routing, breadcrumb derivation, sysop tab loading flow, Markdown newline collapse, BoardList Enter handler, TextInput cursor decoration, CLIHandler paste negotiation absence). MEDIUM on Sysop submodule init failure modes (#6/#7/#8) — symptoms in ISSUES.md strongly suggest silent init crashes but I did not load `boards_view.ex`/`limits_form.ex`/`system_snapshot.ex`/`users_view.ex`; phase work should start by reading those four files and confirming the failure mode. MEDIUM on the exact Account "values are gone on re-enter" bug — `clear_account_save_state/2` does call `seed_from_user/2` which should rebuild the form, so the bug may be elsewhere (perhaps the form is rebuilt but `state.current_user` isn't updated by `Accounts.update_profile/2`); needs an integration test before attempting a fix. LOW on whether bracketed paste detection lives in the (vendor-shipped, not in repo tree) `Raxol.Terminal.ANSI.InputParser` — I could not locate the module file under `vendor/raxol/lib/raxol/terminal/ansi/`. The textarea fallback for SSH key paste works regardless and is the recommended v1.4 path.
