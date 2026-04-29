# Phase 43: Large Screen Decomposition - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md - this log preserves the analysis.

**Date:** 2026-04-29
**Phase:** 43-large-screen-decomposition
**Mode:** assumptions
**Areas analyzed:** Decomposition Boundary, Render Module Ownership, Screen-Specific Treatment, Extraction Order, Coverage And Evidence

## Assumptions Presented

### Decomposition Boundary
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Add `Foglet.TUI.Screens.<Screen>.Render` sibling modules for all six named screens, while top-level modules remain reducer-facing `Foglet.TUI.Screen` implementations. | Confident | `.planning/phases/43-large-screen-decomposition/43-SPEC.md`; `lib/foglet_bbs/tui/SCREEN_CONTRACT.md`; `lib/foglet_bbs/tui/screens/*/state.ex` |
| Top-level `render/2` callbacks should delegate to render entry points and stop owning detailed screen-body helper families. | Confident | `.planning/phases/43-large-screen-decomposition/43-SPEC.md`; render helper families in `post_reader.ex`, `sysop.ex`, `login.ex`, `main_menu.ex`, `new_thread.ex`, `account.ex` |

### Render Module Ownership
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Render modules own frame/content/keybar assembly and consume state/context-derived data, but do not mutate state or perform durable/runtime side effects. | Confident | `lib/foglet_bbs/tui/SCREEN_CONTRACT.md`; `.planning/phases/43-large-screen-decomposition/43-SPEC.md`; PostReader render-path purity moduledoc in `post_reader.ex` |
| Existing widgets and screen-owned surface modules should be reused rather than replaced during extraction. | Likely | `lib/foglet_bbs/tui/widgets/README.md`; `lib/foglet_bbs/tui/screens/sysop/*.ex`; `lib/foglet_bbs/tui/screens/account/*.ex` |

### Screen-Specific Treatment
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| PostReader extraction should not change loading, read-pointer flushing, cache warming, pagination, or resize cache behavior. | Confident | `.planning/phases/43-large-screen-decomposition/43-SPEC.md` out-of-scope list; `.planning/ROADMAP.md` Phase 44; `lib/foglet_bbs/tui/screens/post_reader.ex` |
| Sysop and Account render modules should orchestrate existing tab/surface modules instead of flattening or redesigning them. | Likely | `lib/foglet_bbs/tui/screens/sysop/boards_view.ex`; `lib/foglet_bbs/tui/screens/sysop/users_view.ex`; `lib/foglet_bbs/tui/screens/account/profile_form.ex`; `lib/foglet_bbs/tui/screens/account/ssh_keys_surface.ex` |
| Login, MainMenu, and NewThread should move menu/form/panel/composer rendering out while keeping input, validation, task, and domain-module logic in reducer/state code. | Likely | `lib/foglet_bbs/tui/screens/login.ex`; `lib/foglet_bbs/tui/screens/main_menu.ex`; `lib/foglet_bbs/tui/screens/new_thread.ex` |

### Extraction Order
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Plan the work incrementally by screen or screen groups, starting with lower-risk extractions before the most entangled render helpers. | Likely | Six screen file sizes from 522 to 901 lines; existing tests for all six screens; Phase 42 precedent of bounded helper extraction plans |
| Do not introduce separate reducer modules unless render extraction reveals a clear need. | Likely | `43-SPEC.md` requires reducer-facing top-level modules plus state/render boundaries, not a new reducer namespace; Phase 41/42 contexts prefer minimal compatibility surface and narrow helpers |

### Coverage And Evidence
| Assumption | Confidence | Evidence |
|------------|------------|----------|
| Preserve behavior through reducer/effect tests driven through `update/3`, task results, modal submits, route entry, and public non-render seams. | Confident | `lib/foglet_bbs/tui/SCREEN_CONTRACT.md`; `.planning/codebase/TESTING.md`; existing `test/foglet_bbs/tui/screens/*_test.exs` files |
| Render verification should use layout smoke or `rtk mix foglet.tui.render` evidence for all six screens, with no pure text-presence tests. | Confident | AGENTS.md testing rule; `.planning/phases/43-large-screen-decomposition/43-SPEC.md`; `.planning/codebase/TESTING.md`; `test/foglet_bbs/tui/layout_smoke_test.exs` |
| Documentation should capture the state/render/reducer ownership pattern for future TUI work. | Confident | `.planning/phases/43-large-screen-decomposition/43-SPEC.md`; `lib/foglet_bbs/tui/SCREEN_CONTRACT.md` |

## Corrections Made

No corrections - all assumptions confirmed.
