---
status: complete
date: 2026-04-28
---

# Screen Text Assertion Catalogue

Scope: TUI screen-level render tests, layout smoke tests, ASCII renderer tests, and screen-adjacent shared surfaces. I did not include generic widget unit tests as primary candidates because those assert widget render contracts rather than full-screen text, though several use the same `flatten_text`/`String.contains?` pattern.

## Catalogue By File

| File | Main text assertion clusters | Load-bearing? |
|---|---|---|
| `test/foglet_bbs/tui/ascii_renderer_test.exs` | Chrome border glyphs; synthetic `@alice`; synthetic thread title. | Border/dimensions yes; synthetic content mostly low value. |
| `test/foglet_bbs/tui/layout_smoke_test.exs` | Positioned text sentinels for frame, board list rows, thread rows, composer, post reader, login/register/verify input echoes, modal content, tab rows, command bar jump hints, reset-token non-leak. | Many yes, because they anchor layout/position and security checks; many duplicate label checks are removable. |
| `test/support/foglet/tui/layout_smoke/account_helper.ex` | Account helper sentinels for form headings/footer suppression/table headers. | Mostly replaceable with structural checks; useful only as layout sentinels. |
| `test/support/foglet/tui/layout_smoke/moderation_helper.ex` | Moderation helper sentinels for KvGrid/ConsoleTable visible columns and empty states. | Medium; protects operator primitive presence at constrained sizes. |
| `test/support/foglet/tui/layout_smoke/sysop_helper.ex` | Sysop helper sentinels for Modal.Form footers, users table headers, system labels. | Medium; layout sentinel value, wording not important. |
| `test/foglet_bbs/tui/screens/account_test.exs` | Breadcrumb; tab labels; INVITES visibility; no fake invite/approval buttons; profile/prefs/SSH key labels; validation/status/errors; no discarded copy. | Policy visibility, fake-action absence, validation/error copy are load-bearing; breadcrumb/field-label smoke is mostly removable. |
| `test/foglet_bbs/tui/screens/board_list_test.exs` | Breadcrumb; category/board names; glyphs; unread/age; details strip; overlarge clipping; collapse/expand presence; required-subscription feedback. | Row metadata, glyphs, clipping, required feedback are load-bearing; breadcrumb is low value. |
| `test/foglet_bbs/tui/screens/login_test.exs` | Breadcrumb; forgot/reset copy; email/no-email reset flows; sysop email list; token non-leak from chrome/key/error text; modal copy. | Reset/no-email/token non-leak checks are strongly load-bearing; breadcrumb/generic labels can go. |
| `test/foglet_bbs/tui/screens/main_menu_test.exs` | Breadcrumb; oneliner empty/list/truncation/selection rows; Hide oneliner visibility; navigation/menu text; role-based shell entries; visible action keys. | Role visibility, Hide action, row truncation, command/action key separation are load-bearing; breadcrumb/generic menu labels are replaceable. |
| `test/foglet_bbs/tui/screens/moderation_test.exs` | Breadcrumb; tab labels; INVITES policy; absence of fake/placeholder/moderation actions; log/user/board/invite rows; primitive headers/empty states. | Fake-action absence, policy visibility, audit row content/order are load-bearing; primitive header smoke is mostly replaceable. |
| `test/foglet_bbs/tui/screens/new_thread_test.exs` | Board-step empty/no-subscription copy; breadcrumb; composer shell labels/counters; title/body visible; wrapping; modal errors. | Wrapping/value and submit-error checks are load-bearing; static composer labels/breadcrumb are low value. |
| `test/foglet_bbs/tui/screens/post_composer_test.exs` | Breadcrumb/thread context; editor mode labels/counter; body/preview text; wrapping; quote gutter; modal error copy. | Wrapping/value preservation and quote context are load-bearing; shell labels are low value. |
| `test/foglet_bbs/tui/screens/post_reader_test.exs` | Breadcrumb; loading canonical copy; selected post metadata/progress/body; markdown/raw syntax absence; viewport isolation; welcome thread body. | Markdown/raw syntax absence, viewport isolation, selected body/metadata are load-bearing; breadcrumb/loading wording is lower value. |
| `test/foglet_bbs/tui/screens/register_test.exs` | No-email-safe pending modal absence checks. | Load-bearing, because it prevents false email-notification promises. |
| `test/foglet_bbs/tui/screens/shared/invites_surface_test.exs` | Loading/empty state; invite lifecycle row values; generated-code banner; error; key hints; focused row preserves value; no legacy marker. | Lifecycle rows, generated-code, focused-row no-truncation are load-bearing; key-hint copy can be structural. |
| `test/foglet_bbs/tui/screens/sysop_test.exs` | Loading/error/retry panels; INVITES policy; config descriptions; field labels; users list/actions; status transition copy; boards/system labels; command/action gating. | Policy, retry gating, status action availability, config conditional field, users list, and modal errors are load-bearing; repeated primitive labels/descriptions are brittle. |
| `test/foglet_bbs/tui/screens/sysop/site_form_test.exs` | Config field labels/descriptions/values; conditional `invite_generation_per_user_limit`; no legacy marker; saved/error/discarded status rows. | Conditional field visibility and saved/error/discarded status are load-bearing; repeated label/description checks can move to field specs. |
| `test/foglet_bbs/tui/screens/thread_list_test.exs` | Breadcrumb; loading; creator handles; post counts; age/new; unread/sticky/locked glyphs; no legacy `[S]`; metadata format. | Row metadata/glyph/legacy marker assertions are load-bearing; breadcrumb is low value. |
| `test/foglet_bbs/tui/screens/verify_test.exs` | Honest prompt copy; cooldown modal wording. | Honest no-email promise is load-bearing; cooldown wording is lower value if state is asserted elsewhere. |

## Load-Bearing Categories

Keep or replace with equivalent structural assertions:

- Security/privacy non-leaks: reset token absent from chrome/key/error text, no password/reset URLs in no-email flows, no false email notification promises.
- Authorization and capability visibility: role/policy-driven INVITES visibility, Hide oneliner, sysop/moderation/account command availability, forbidden Retry/action suppression.
- Domain data reaches the terminal: board/thread/user/invite/SSH-key rows, generated invite codes, validation errors, required-subscription feedback.
- Layout sentinels at constrained terminal sizes: text used to locate positioned rows/panels/gutters, clipping/truncation, cursor/input echo, no overlap.
- Formatting transformations: markdown renders without raw syntax, compact timestamps/time-ago/glyph clusters, old placeholder/action copy absent.

## Low-Value Removal Candidates

Safe to remove outright or replace with state/structure checks:

- Chrome breadcrumb smoke checks such as `Foglet`, `Home`, `Boards`, `Login`, `Account` when the same screen already has non-text render smoke.
- Generic primitive presence checks like headings, field labels, and table headers when the form/table spec already exposes the same field/column list.
- Exact configuration description copy checks, especially repeated `spec.description` presence.
- ASCII renderer synthetic fixture content (`@alice`, `Welcome - read me first`) except where used to prove the renderer paints arbitrary text at all.
- Duplicate command-bar key text checks when `visible_actions/1`, `key_bar/1`, `tab_labels/1`, or action-command data already asserts the underlying contract.

## Recommendation

Do not remove all rendered-text assertions in one sweep. Split them into:

1. Keep security/privacy and authorization/capability text assertions.
2. Convert repeated label/header/copy assertions to structural checks against form specs, tab labels, visible actions, or table columns.
3. Keep a small number of layout smoke sentinels per surface, because without text anchors the layout tests stop proving that actual content is visible.
4. Remove duplicate breadcrumb and primitive-heading assertions after the structural replacements land.

