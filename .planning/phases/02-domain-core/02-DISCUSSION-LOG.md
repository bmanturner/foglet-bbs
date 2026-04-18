# Phase 2: Domain Core - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-18
**Phase:** 02-domain-core
**Areas discussed:** Markdown rendering, Board Server startup, Default subscription wiring

---

## Markdown Rendering

| Option | Description | Selected |
|--------|-------------|----------|
| MDEx | Wraps comrak (CommonMark + GFM, Rust NIF). Fast, spec-compliant, actively maintained. | ✓ |
| Earmark | Pure Elixir Markdown parser. HTML-centric output requires extra stripping for terminal. | |
| You decide | Claude chooses based on what fits best. | |

**User's choice:** MDEx

---

| Option | Description | Selected |
|--------|-------------|----------|
| ANSI-styled plain text | Bold → \e[1m, italic → \e[3m, code blocks indented + dim color, headings uppercase + underline. No HTML. | ✓ |
| Plain stripped text | Strip all formatting. Pure readable prose, no ANSI codes. | |
| Hybrid — ANSI for inline, plain for blocks | Inline bold/italic get ANSI; headers and code blocks become plain text. | |

**User's choice:** ANSI-styled plain text

---

| Option | Description | Selected |
|--------|-------------|----------|
| Always compute on the fly | Simpler. No cache invalidation problem. body_rendered stays NULL. | ✓ |
| Cache in body_rendered on insert/edit | Store ANSI string in DB. Faster reads but adds complexity. | |

**User's choice:** Always compute on the fly

---

## Board Server Startup

| Option | Description | Selected |
|--------|-------------|----------|
| At app boot — start all boards | Query all non-archived boards at startup; start a Server for each. Simple, predictable. | ✓ |
| On demand — lazy per board | Start on first post in a board. Lighter startup, more complex post-creation path. | |
| You decide | Claude chooses. | |

**User's choice:** At app boot — start all boards

---

| Option | Description | Selected |
|--------|-------------|----------|
| Reload from DB on restart — MAX(message_number) | Query MAX from posts on init. Self-healing, no collision risk. | ✓ |
| Re-read boards.next_message_number on restart | Use persisted counter. Simpler but relies on last write being accurate. | |

**User's choice:** Reload from DB on restart (MAX query)

---

## Default Subscription Wiring

| Option | Description | Selected |
|--------|-------------|----------|
| Phase 2 adds subscribe_to_defaults/1, called from create_user/1 | Clean cross-context call. Accounts stays the entry point. | ✓ |
| Defer — Phase 3 SSH flow calls subscribe_to_defaults/1 | Don't touch Phase 1 code now. Phase 3 handles it. | |

**User's choice:** Phase 2 adds Boards.subscribe_to_defaults/1, called from Accounts.create_user/1

---

## Claude's Discretion

- Context split strategy (Foglet.Boards / Foglet.Threads / Foglet.Posts)
- Thread creation Multi transaction approach (follows DATA_MODEL.md recommendation)
- Unread count query implementation
- Foglet.Markdown module location and API surface
- StreamData for property tests

## Deferred Ideas

- body_rendered caching — deferred to Phase 9+ (profile first)
- Full-text search queries — schema column created now, query logic is Phase 9
- Upvote toggle functions — schema created now, logic is Phase 9
