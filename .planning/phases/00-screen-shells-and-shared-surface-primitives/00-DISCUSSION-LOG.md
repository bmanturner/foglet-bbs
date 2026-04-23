# Phase 0: Screen Shells and Shared Surface Primitives - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the analysis.

**Date:** 2026-04-23T16:54:01Z
**Phase:** 00-Screen Shells and Shared Surface Primitives
**Mode:** assumptions
**Areas analyzed:** Navigation and Role Visibility, Shell Architecture Pattern, Tab Model and Shared Invite Primitive, Placeholder/Loading/Error Semantics, Shell Tab Sets

## Assumptions Presented

### Navigation and Role Visibility
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Account becomes a standard main-menu destination for authenticated users, while Moderation and Sysop appear only when the current session role warrants it, using simple UI visibility checks in Phase 0. | Likely | `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md`, `lib/foglet_bbs/tui/screens/main_menu.ex`, `lib/foglet_bbs/sessions/session.ex`, `lib/foglet_bbs/accounts/user.ex` |

### Shell Architecture Pattern
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Account, Moderation, and Sysop should be first-class TUI screens added to `Foglet.TUI.App`, rendered through `ScreenFrame`, with shell-local state in `state.screen_state`. | Confident | `lib/foglet_bbs/tui/app.ex`, `lib/foglet_bbs/tui/screen.ex`, `lib/foglet_bbs/tui/screens/new_thread/state.ex`, `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` |

### Tab Model and Shared Invite Primitive
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| The new shells should use `Foglet.TUI.Widgets.Input.Tabs`, and the reusable `INVITES` primitive should be scaffolded now as shared shell/tab state and rendering helpers but remain non-operational. | Likely | `.planning/ROADMAP.md`, `.planning/PROJECT.md`, `lib/foglet_bbs/tui/widgets/input/tabs.ex`, `lib/foglet_bbs/tui/widgets/README.md`, `lib/foglet_bbs/config/schema.ex` |

### Placeholder, Loading, and Error Semantics
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Shell tabs should follow existing TUI semantics: `nil` means loading, empty states render explicit copy, and unexpected failures use the shared modal/error flow. | Confident | `lib/foglet_bbs/tui/screens/board_list.ex`, `lib/foglet_bbs/tui/screens/thread_list.ex`, `lib/foglet_bbs/tui/screens/post_reader.ex`, `lib/foglet_bbs/tui/widgets/progress/spinner.ex`, `lib/foglet_bbs/tui/widgets/modal.ex` |

### Shell Tab Sets
| Assumption | Confidence | Evidence |
|------------|-----------|----------|
| Moderation should scaffold `QUEUE`, `LOG`, `USERS`, `SANCTIONS`, and `BOARDS`; Sysop should scaffold `SITE`, `BOARDS`, `LIMITS`, `SYSTEM`, and `USERS`; Account was initially assumed to be a shell entry point with a future-facing `INVITES` scaffold. | Likely | `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md` |

## Corrections Made

### Shell Tab Sets
- **Original assumption:** Account would be a simpler shell entry point with only the future-facing `INVITES` scaffold implied by the roadmap.
- **User correction:** Account should have `PROFILE` and `PREFS` tabs in addition to a future-facing, conditionally shown `INVITES` tab scaffold.
- **Reason:** The Account shell contract should be explicit from Phase 0 rather than leaving its tab structure underspecified.

## External Research

No external research was needed; local project docs and source code provided enough evidence for the assumptions pass.
