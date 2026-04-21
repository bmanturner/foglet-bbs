# Phase 5: Terminal size gate — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in 05-CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-20
**Phase:** 05-terminal-size-gate
**Workstream:** phase-03-polish (v1.0.1)
**Areas discussed:** Threshold value, Gate location, Message content, Resize debounce, Keys during too-small, Boundary semantics

---

## A — Threshold value

### A1. Minimum terminal dimension

| Option | Description | Selected |
|--------|-------------|----------|
| 80×24 (research pick) | Near-universal floor; thread-list + post-reader both fit; chrome + content in 24 rows. | |
| 60×20 (generous) | Floor before garbling. Accepts cramped look for phone SSH and small panes. | ✓ |
| Config-tunable (default 80×24) | Foglet.Config keys for min dims; sysop-adjustable. | |

**User's choice:** 60×20 (generous)
**Notes:** Research recommended 80×24 but user prioritizes user accessibility over comfort. Phase 3's title truncation handles the density trade-off.

---

## B — Gate implementation location

### B1. Where does the too-small check live?

| Option | Description | Selected |
|--------|-------------|----------|
| Inside ScreenFrame.render/4 | Every screen already calls ScreenFrame; gate inherits through it. | |
| At App.view/1 top level | Check terminal_size before screen dispatch; bypass ScreenFrame entirely when gated. | ✓ |
| Per-screen render/1 | Distributed if-guard in each of 9 screens. | |

**User's choice:** At App.view/1 top level
**Notes:** Cleanest separation; no chrome on the too-small screen; one code site to change.

---

## C — Gate message content

### C1. What appears on the too-small screen?

| Option | Description | Selected |
|--------|-------------|----------|
| Current + required dims | Multi-line: required 60×20, current {cols}×{rows}, please resize. | ✓ |
| Minimal | Single line. | |
| Required + exit hint | Required dims + 'Press Ctrl+C to disconnect.' | |
| Full: dims + exit + ASCII frame | Everything. | |

**User's choice:** Current + required dims
**Notes:** Helpful diagnostic; matches research-recommended tone.

---

## D — Resize event dedup

### D1. Handling bursty window_change events

| Option | Description | Selected |
|--------|-------------|----------|
| Same-size guard in do_update | Short-circuit when {cols, rows} == state.terminal_size. | ✓ |
| Time-based debounce | Buffer events with a timer. | |
| No debounce | Rely on Raxol's internal render coalescing. | |

**User's choice:** Same-size guard in do_update
**Notes:** Simple, correct, matches research recommendation in Pitfall 4.

---

## E — Keys during too-small state (follow-up)

### E1. Key event routing while gated

| Option | Description | Selected |
|--------|-------------|----------|
| Swallow all keys | App.update/2 returns {state, []} without dispatching to screen. | ✓ |
| Route normally | Keys reach hidden screen's handle_key. | |
| Show a flash message | Swallow + display 'resize first' message. | |

**User's choice:** Swallow all keys
**Notes:** Prevents hidden state mutation. Ctrl+C / EOF reach CLIHandler at the SSH channel layer independently.

---

## F — Boundary semantics (follow-up)

### F1. Threshold inclusivity at exactly 60×20

| Option | Description | Selected |
|--------|-------------|----------|
| 60×20 allowed (>=) | Gate fires at cols < 60 OR rows < 20. | |
| 60×20 gated (>) | Gate fires at cols <= 60 OR rows <= 20. | |
| Round up for safety | Gate fires at < 64×22 (4-col / 2-row margin for chrome). | ✓ |

**User's choice:** Round up for safety
**Notes:** 60×20 is the user-facing mental minimum; the actual code-level threshold is 64×22 to account for border+padding+StatusBar+divider+KeyBar overhead. Effective content area at 64×22 ≈ 60×15.

---

## Claude's Discretion

- Module placement for constants (App vs new SizeGate module)
- Exact Raxol element shape for the centered message
- `too_small?` predicate signature (state vs terminal_size)
- Regression test coverage for MultiLineInput preservation across resize

## Deferred Ideas

- Sysop-tunable min dims via Foglet.Config
- Hysteresis / anti-flicker band at the boundary
- Graceful compact layouts for narrow terminals
- Per-screen thresholds
- Time-based debouncing
- Exit / disconnect hint in the gate message
