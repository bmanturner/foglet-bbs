# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v2.0 — TUI Runtime Shell & Screen Update Loops

**Shipped:** 2026-04-29
**Phases:** 7 | **Plans:** 28 | **Tasks:** 78

### What Was Built

- A screen runtime contract based on `Foglet.TUI.Context`, `Foglet.TUI.Effect`, and screen-owned `init/1`, `update/3`, and `render/2`.
- Screen-owned reducers for auth/home, board and thread browsing, post reading/composition, account, moderation, and sysop flows.
- A smaller `Foglet.TUI.App` runtime shell that owns route/session/modal coordination, task dispatch, PubSub forwarding, and render delegation.
- A TUI screen contract guide plus close-gate evidence for render smoke, full tests, and `rtk mix precommit`.

### What Worked

- Migrating representative screen families first made later workbench and App-shell cleanup much safer.
- Keeping domain work behind context calls and task effects preserved the SSH-first product surface while the runtime changed underneath.
- Phase 40's carry-forward register made deferred Phase 39 risks explicit and turned the close gate into a clean verification pass.

### What Was Inefficient

- Some planning metadata lagged behind implementation, especially Phase 38 plan counts and Phase 39 completion status in ROADMAP.
- The automatic milestone accomplishment extraction was too verbose and needed human cleanup before it was useful as historical record.
- Existing open debug/quick/seed artifacts had to be acknowledged separately at close because they were outside the v2.0 milestone audit.

### Patterns Established

- Screens own local state and async result handling; App interprets generic effects.
- Screen PubSub interest should be declared through `subscriptions/2` when route-derived topics are not enough.
- Close-gate phases should convert carry-forward risk into explicit Fixed, Excluded, or Blocking dispositions.

### Key Lessons

1. Keep milestone ROADMAP metadata aligned as phases complete; stale phase tables create unnecessary friction during archive.
2. Use concise milestone entries for history and leave detailed plan-by-plan evidence in phase archives.
3. Preserve render smoke as a lightweight confidence signal, but keep behavior assertions focused on state and effects.

### Cost Observations

- Model mix: not tracked.
- Sessions: not tracked.
- Notable: the screen-contract migration paid down central App complexity and gives future TUI work a smaller, clearer boundary.

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Sessions | Phases | Key Change |
|-----------|----------|--------|------------|
| v2.0 | not tracked | 7 | Architecture milestone closed with audit, Nyquist validation, archived phase history, and deferred artifact acknowledgement. |

### Cumulative Quality

| Milestone | Tests | Coverage | Zero-Dep Additions |
|-----------|-------|----------|-------------------|
| v2.0 | 2160 tests plus 1 property in final evidence | not tracked | Context/Effect/screen-contract primitives added without replacing Raxol. |

### Top Lessons (Verified Across Milestones)

1. The project benefits from small, auditable TUI slices with explicit render and reducer evidence.
2. Planning archives should stay concise at the top level and preserve deep execution history in milestone folders.
