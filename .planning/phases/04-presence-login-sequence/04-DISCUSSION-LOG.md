# Phase 4: Presence & Login Sequence - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-18
**Phase:** 04-presence-login-sequence
**Areas discussed:** Login Sequence Pacing, Online List Display, Theme Stubs Scope, Sysop Banner/News Editor

---

## Login Sequence Pacing

| Option | Description | Selected |
|--------|-------------|----------|
| Keypress to advance | Banner displays until user presses any key. Classic BBS feel. | ✓ |
| Auto-advance after timeout | Banner displays for N seconds then automatically proceeds. | |
| Both — timeout with keypress shortcut | Auto-advance after N seconds, but any key skips immediately. | |

**User's choice:** Keypress to advance

---

| Option | Description | Selected |
|--------|-------------|----------|
| Keypress on banner only; news+last callers auto-flow | Banner pauses; news and last callers auto-advance. | |
| Keypress on each step | Every step waits for a keypress before advancing. | ✓ |
| All auto-flow with configurable delays | All three steps auto-advance with no keypresses. | |

**User's choice:** Keypress on each step

---

| Option | Description | Selected |
|--------|-------------|----------|
| Full sequence every time | No skipping — every login sees the full sequence. | |
| Skip banner if seen recently (e.g. same day) | Auto-skip banner for same-day repeat logins. | |
| User-configurable skip | User can toggle 'show login sequence' in their preferences. | ✓ |

**User's choice:** User-configurable skip

---

## Online List Display

| Option | Description | Selected |
|--------|-------------|----------|
| Handle only | Clean, compact list of handles. | ✓ (with note) |
| Handle + role badge | Handle with text role indicator e.g. [sysop]. | |
| Handle + location | Handle plus current BBS location. | |

**User's choice:** Handle only — with color coding for role (sysop = one color, mod = another, user = default)
**Notes:** User added note "Handle only, use color for role" — role communicated via ANSI color rather than a text badge.

---

| Option | Description | Selected |
|--------|-------------|----------|
| Fill available space | Show as many users as fit terminal height. | |
| Fixed cap (e.g. 10-15) | Max N users shown regardless of terminal size. | |
| Pageable list | Show first N on main menu with key to expand full scrollable screen. | ✓ |

**User's choice:** Pageable list

---

| Option | Description | Selected |
|--------|-------------|----------|
| In-place update via PubSub | Presence diff events update only the online list section. | ✓ |
| Periodic poll (e.g. every 10s) | Main menu polls Presence on a timer. | |
| Full menu refresh on any Presence event | Any join/leave triggers full main menu re-render. | |

**User's choice:** In-place update via PubSub

---

## Theme Stubs Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Infrastructure only — no UI yet | Wire config key, user preference field, Session slot. No picker. | ✓ |
| Preference field + basic picker in user profile | User can select from list in profile settings screen. | |
| Preference field + stub themes (not usable yet) | 2-3 named themes selectable but all render identical to default. | |

**User's choice:** Infrastructure only — no UI yet

---

## Sysop Banner/News Editor

| Option | Description | Selected |
|--------|-------------|----------|
| Upload from filesystem path | Sysop provides path to .ANS/.txt file; system reads and stores it. | ✓ |
| Inline text editor (Raxol multiline input) | Sysop edits banner directly in TUI. | |
| Both — paste/type or specify a file path | Sysop can paste or provide a path. | |

**User's choice:** Upload from filesystem path

---

| Option | Description | Selected |
|--------|-------------|----------|
| Add/remove titled bulletins | Each bulletin has title + body; sysop can add/delete. | ✓ |
| Single news body (replace-all) | One news text block edited in full each time. | |
| Dated bulletin board (append-only) | Sysop adds; old bulletins archived but never deleted. | |

**User's choice:** Add/remove titled bulletins (matches DATA_MODEL.md news.bulletins structure)

---

| Option | Description | Selected |
|--------|-------------|----------|
| Temporary standalone sysop screen | Minimal sysop screen from main menu, role-gated; Phase 8 replaces it. | ✓ |
| Profile/settings screen extension | Banner/news editing added to existing profile screen, role-gated. | |
| Mix task fallback (no TUI in Phase 4) | Banner/news edited via Mix tasks; TUI editing deferred to Phase 8. | |

**User's choice:** Temporary standalone sysop screen

---

## Claude's Discretion

- Count of last callers shown in login sequence
- Exact role colors within the green-on-black theme palette
- Number of users shown on main menu before expand key
- Retention cleanup job schedule for last_callers
- Bulletin body format (plain text vs. Markdown)
- Edit-in-place vs. delete + re-add for existing bulletins

## Deferred Ideas

- Theme picker UI and actual alternative themes — Phase 9+
- Full sysop admin menu — Phase 8
- In-TUI banner text editor — not planned
- Idle time in online list — not in Phase 4
