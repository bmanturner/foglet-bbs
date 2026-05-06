# FOG-1030 / FOG-1040: Post Reader reply-context modal interaction contract

Status: TUI UX design contract for implementation and QA.

Source issue: FOG-1040, child of FOG-1030.

## Acceptance criteria used

- A selected reply post exposes a visible inspect-context affordance; non-reply posts do not advertise a dead key.
- Opening reply context preserves the current Post Reader route, visible screenful, selected action post, partial-scroll state, and pending read-pointer state.
- Reply context renders the replied-to post's author, message number, age, upvote count, and body with Post Reader-compatible wrapping.
- Long replied-to posts scroll inside a bounded terminal-native surface at 64x22 and 80x24.
- Authenticated users can upvote the context post; guests can inspect readable context but do not see unavailable upvote/profile actions.
- Inaccessible/stale reply targets show safe feedback without leaking private board/thread details.
- Modal stacking/replacement behavior is explicit enough for implementation and QA replay.

## Recommendation

Use a scrollable reply-context modal as the primary interaction.

Key: `C` = Context. The key is shown only when the selected/action-target post has a `reply_to_id` or loaded `reply_to` target. The command label should be short: `C Context`.

Why `C`: `R` already means reply, `V` already means author profile, and `U` already means upvote. `C` is mnemonic, does not collide with existing Post Reader navigation, and can remain visible in the keybar at narrow widths without stealing priority from `Q Back` or `R Reply`.

Non-reply posts: no `C Context` command in the keybar and pressing `C` should be absorbed as a no-op with no modal. Do not show helper text saying there is no context; absence of the command is enough and avoids keybar noise.

## Interaction pattern alternatives considered

1. Scrollable modal preserving reader position — chosen.
   - Pros: matches Brendan's preference, avoids disorientation in long threads, keeps read-pointer behavior local to the real reader, and makes the action feel like inspecting context rather than navigating history.
   - Cons: current modal runtime is single-slot and not scroll-aware; implementation must add a screen-owned modal message/state or modal type for bounded viewport behavior.
   - Good enough because the user goal is quick context inspection, not permanent relocation.

2. Direct jump to replied-to post with return anchor — rejected as primary.
   - Pros: reuses the reader surface and avoids a new modal body primitive.
   - Cons: changes selection, viewport, read-pointer semantics, and mental location. A return anchor would have to preserve original window, partial scroll, and selected action post anyway. In long threads, this feels like being teleported to old mail.
   - Optional later shortcut only if the modal path already exists and return is explicit.

3. Routed detail surface / separate screen — rejected for this slice.
   - Pros: cleaner state model than modal stacking and could grow into a full post permalink reader.
   - Cons: heavier IA, extra route/back semantics, more risk of losing the current reader's ephemeral scroll and pending read state. It feels too much like leaving the thread for a quick question: "what is this replying to?"

## Primitive fit

Primitives considered: `viewport`, composed `box`/`column` modal body, `PostCard.reader_parts`, `markdown_renderer`/existing markdown body, `split_pane`, `table`, and modal stacking.

Primitives chosen:
- Bounded app modal overlay using existing modal chrome plus a new reply-context body/message shape.
- Internal `viewport` for body rows when the context post exceeds the modal body budget.
- Reuse `PostCard.reader_parts` or a thin compact wrapper around it so header/body wrapping matches Post Reader.

Richer primitives rejected:
- `split_pane`: useful at 120x36+ but wrong as the primary model because context inspection should not permanently consume reader width or create a second focus region. A wide-terminal side inspector could be a future enhancement, not this contract.
- `table`: metadata is narrative and compact; columns would waste space and make long handles/body context harder to scan.
- `tree`: no hierarchy beyond possibly nested reply chains; showing a reply chain is out of scope.
- Full `markdown_renderer`: use existing Post Reader markdown pipeline instead so body wrapping and clipping stay consistent.

Implementation risks requiring Elixir OTP review:
- `Foglet.TUI.App.Modal` currently stores one `state.modal` and handles only info/success/error/warning/confirm/form keys. Reply context needs either a new modal type or a structured message with its own key handler.
- Existing modal overlay width is max 76 body columns; long-content height must also be bounded, not just centered.
- Upvoting inside the context modal needs an effect result routed back to the modal/context state without mutating the main reader selection.

## Layout and composition contract

Modal title: `Reply Context`.

Header region, fixed height:
- Line 1: `Replying to #<message_number> • ▲<upvote_count> • @<handle> • <age>`.
- If width is tight, keep in priority order: message number, handle, upvote count, age. Truncate handle with ellipsis before dropping age.
- Line 2: divider.

Body region, scrollable:
- Render body rows with the same wrapping/gutter policy as Post Reader.
- Scroll state belongs to reply-context modal state, not `PostReader.State.viewport`.
- The modal must not advance thread read pointers or alter `selected_post_index`, `selected_action_post_index`, `partial_scroll_tops`, or `pending_read_positions`.

Footer/keybar region, fixed height:
- Authenticated user: `[↑/↓] Scroll  [U] Upvote  [V] Profile  [Esc] Close`.
- Guest: `[↑/↓] Scroll  [Esc] Close`.
- If body fits without scrolling, omit `Scroll` from the footer but keep `Esc Close`.
- Do not list duplicate fallback keys in the visible footer. `J/K` may be supported as hidden familiar fallback if engineering wants parity with Post Reader.

Modal dimensions:
- Width: min(terminal_width - 4, 76), with the current lower bound of 28 acceptable at the hard minimum.
- Height: min(terminal_height - 4, 18) at 80x24 and above; at 64x22 use max available height inside the overlay after one-row title/header/footer. Body viewport should have at least 5 visible rows.
- Borders must not overflow. Long lines and long handles must clip/truncate within the calculated body width.

Visual flavor:
- This should feel like pulling an old message card out of the thread, not a generic error dialog. Use the existing double-border modal shell, a compact BBS-style header, and the same post body gutter so the context reads as a real post.

## Key map

Main Post Reader:
- `Tab` / `Shift+Tab`: move selected action target among visible packed posts, unchanged.
- `N` / `P` / `Space` / PageDown / PageUp: navigate posts, unchanged.
- `Up` / `Down`: select/scroll behavior, unchanged.
- `J` / `K`: long-post scroll fallback, unchanged.
- `R`: reply to selected action post, unchanged.
- `U`: upvote selected action post for authenticated users, unchanged.
- `V`: open selected action post author's profile for authenticated users, unchanged.
- `C`: when selected action post has reply context, fetch/read-check the replied-to post and open reply-context modal. When no reply context exists, no visible command and no-op if pressed.
- `Q`: back to thread list and flush read pointers, unchanged.

Reply-context modal:
- `Esc`: close reply-context modal and return to exact reader state.
- `Enter` / `Space`: close only if implementation keeps generic info-modal defaults; preferred for reply-context modal is no close-on-space because space commonly pages readers. If generic modal key behavior is reused, QA must verify it does not conflict with scrolling.
- `Up` / `Down`: scroll body by one row when scrollable.
- `PageUp` / `PageDown`: scroll body by one viewport page when scrollable.
- `Home` / `End`: jump to top/bottom when scrollable.
- `U`: authenticated only, toggle upvote for context post and refresh the modal header/count. Own-post no-op should look stable.
- `V`: authenticated only, open author profile via replacement contract below.
- Unknown keys: absorb with no state change.

## Modal replacement / profile behavior

Choose safe replacement, not nested modal stack, for this slice.

Contract:
1. Reply-context modal opens from Post Reader.
2. `V` inside reply context replaces the visible modal with the existing Public Profile modal/card for the context post author.
3. Dismissing the profile returns directly to Post Reader, not back to reply context.
4. The reader state remains untouched throughout.

Why not stack now: `state.modal` is a single slot today. A true stack would be a broader App.Modal architecture change and should not be introduced as an incidental dependency of this feature. Replacement is predictable, uses the current app model, and avoids stranding the user in nested dialog state.

Follow-up if desired: add a backlog item for a modal stack / modal history primitive only if future flows need return-to-previous-modal behavior. It does not block FOG-1030.

## Loading, empty, and error states

Opening context should not immediately display stale preloaded content unless readability has been checked. Fetch through `Posts.fetch_readable_post/2` or an equivalent readable boundary.

- Loading: small modal or inline modal body: `Looking up replied-to post…` with a spinner if available. Keep the reader behind it unchanged.
- Success: replace loading body with reply-context post.
- `:not_found` / deleted / stale target: show safe warning modal: `That earlier post is no longer available.` Do not include board/thread names.
- `:board_archived` or unreadable/private board: show safe warning modal: `That earlier post is not readable from here.` Do not leak where it lives.
- Upvote failure: keep the context modal open and show one-line status in the footer area: `Could not update vote.` Do not close the modal or change reader selection.

## Guest rules

Guests may inspect readable reply context.

Guests must not see `U Upvote` or `V Profile` inside the reply-context modal. Pressing `U` or `V` while the modal is open should be absorbed as no-op; do not show the generic guest denial modal from inside context because the command was not advertised.

Main Post Reader existing guest action behavior remains out of scope except that the new `C Context` command may be visible to guests for reply posts.

## Breakpoint behavior

64x22 hard minimum:
- Single centered modal overlay; no side panel.
- Width budget: terminal minus four columns, lower-bounded by existing modal width logic.
- Body viewport gets remaining rows after border, title, header, footer; target at least 5 rows.
- Footer keeps only visible commands that apply now: `Scroll` if needed and `Esc Close`; authenticated `U`/`V` may drop from visible footer before causing wrap, but keys may still work if implemented.
- Selected reader item remains visually preserved behind state, but overlay owns focus.

80x24 baseline:
- Modal feels deliberate: title, compact metadata header, divider, body viewport, restrained footer.
- Body viewport target: 10-12 rows depending on chrome.
- Footer can show `Scroll`, `U`, `V`, `Esc` for authenticated users without wrapping.

100x30 comfortable:
- Same modal pattern with more body rows up to max height.
- Do not stretch past 76 body columns; keep body readable and centered.
- Extra height goes to viewport, not empty padding.

120x36+ wide operator view:
- Still use modal as primary to preserve thread focus.
- Do not introduce split pane in this issue. A future optional inspector could appear at wide widths, but that would be a separate interaction contract because it creates persistent dual focus.

## Acceptance scenarios for implementation and QA

1. Reply affordance visible only for replies.
   - Given a Post Reader screen with one plain post and one reply post visible.
   - When the action target is the plain post.
   - Then the command bar does not show `C Context`.
   - When the action target moves to the reply post.
   - Then the command bar shows `C Context`.

2. Open and dismiss preserves reader state.
   - Given selected post index N, selected action post M, partial scroll top S, and pending read pointer P.
   - When `C` opens the reply-context modal and `Esc` closes it.
   - Then the reader returns with N, M, S, and P unchanged.

3. Long replied-to post scrolls inside modal.
   - Given a reply target whose body exceeds the modal viewport at 64x22.
   - When `C` opens context.
   - Then the modal body shows a bounded viewport and footer scroll affordance.
   - When `Down` or `PageDown` is pressed.
   - Then only the modal body scrolls; reader selection and thread read pointer do not change.

4. Authenticated upvote from context.
   - Given a signed-in user opens reply context for another user's post.
   - When `U` is pressed in the context modal.
   - Then the modal header upvote count refreshes and the modal remains open.
   - And the main reader selected post stays unchanged.

5. Own-post upvote from context.
   - Given a signed-in user opens reply context for their own post.
   - When `U` is pressed.
   - Then the domain own-post no-op is preserved: no error modal, no count jump, context remains open.

6. Guest context inspection.
   - Given a guest can read the current thread and the replied-to post.
   - When the reply post is selected.
   - Then `C Context` is available.
   - When the modal opens.
   - Then it does not show `U Upvote` or `V Profile`.

7. Inaccessible target.
   - Given a reply points to a post the current user cannot read.
   - When `C` is pressed.
   - Then a safe warning appears without private board/thread details.
   - And dismissing it returns to the exact reader state.

8. Profile replacement.
   - Given an authenticated user opens reply context.
   - When `V` is pressed.
   - Then the Public Profile card replaces reply context.
   - When the profile is dismissed.
   - Then the user returns to Post Reader, not to the reply-context modal.

9. Narrow footer restraint.
   - Given terminal size 64x22.
   - When the reply-context modal is open.
   - Then footer/key hints do not wrap through the border, and any hidden but supported fallback keys are not required for task completion.

## Evidence and current repository reconciliation

Static repo evidence used:
- `lib/foglet_bbs/tui/screens/post_reader.ex` already owns selected action post, existing `R`, `U`, `V`, read-pointer state, and a viewport for main post body.
- `lib/foglet_bbs/tui/screens/post_reader/render.ex` already builds command groups and uses keybar priority, so `C Context` can be conditional and low-noise.
- `lib/foglet_bbs/tui/widgets/post/post_card.ex` exposes `reader_parts/5`, giving implementation a reuse path for consistent post headers/body wrapping.
- `lib/foglet_bbs/posts.ex` exposes `fetch_readable_post/2` and `toggle_upvote/2`, matching the authorization/upvote requirements.
- `lib/foglet_bbs/tui/app/modal.ex` and `lib/foglet_bbs/tui/modal.ex` show the current single-modal model, so replacement is safer than true modal stacking for this slice.

Render evidence: not produced in this design-only child because the reply-context UI is not implemented yet. QA should require render or SSH/TUI harness evidence for 64x22 and 80x24 before FOG-1030 is accepted.

## Follow-up backlog

Proposed but not created: `Modal stack / modal history primitive for nested TUI dialogs`.
- Source: FOG-1040 reply context profile decision.
- Gap: current App modal model is a single slot, so reply context chooses profile replacement instead of return-to-context stacking.
- Why out of scope: FOG-1030 can be completed predictably with replacement and does not require an app-wide modal architecture change.
- Suggested owner: Elixir OTP Engineer with TUI UX review.
- Acceptance criteria: app modal state supports push/pop, nested modal dismiss semantics are deterministic, and at least one nested flow has 64x22/80x24 harness evidence.
- Blocking current PR: no.

Intentionally untracked: wide-terminal split-pane context inspector. It is a plausible future enhancement, but the modal better serves the current inspect-without-losing-place goal and adding an issue now would be premature product surface expansion.
