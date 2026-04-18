# Phase 2: Domain Core - Context

**Gathered:** 2026-04-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Build the BBS data model — `Foglet.Boards`, `Foglet.Threads`, `Foglet.Posts` contexts with their
schemas, migrations, and domain logic. This covers: categories, boards, threads, posts, post_edits,
board_subscriptions, board_read_pointers, thread_read_pointers, the `Foglet.Boards.Server` GenServer
for per-board message-number allocation, Markdown-to-terminal rendering, unread count queries, and
default seed data. No TUI, no SSH, no web routes.

Phase 2 also modifies `Foglet.Accounts.create_user/1` (Phase 1 code) to call
`Foglet.Boards.subscribe_to_defaults/1` — wiring default subscriptions at account creation time.

</domain>

<decisions>
## Implementation Decisions

### Markdown Rendering (BOARD-05)

- **D-01:** Use **MDEx** as the Markdown parsing library. Wraps `comrak` (CommonMark + GFM, Rust
  NIF). Fast, spec-compliant, actively maintained. Add as a dependency.
- **D-02:** "Terminal-friendly" means **ANSI-styled plain text** — no HTML output.
  Mapping: bold → `\e[1m`, italic → `\e[3m`, headings → uppercase + underline, code spans → dim
  color (`\e[2m`), code blocks → 2-space indent + dim, links → show URL in parens, images → alt
  text only. The `Foglet.Markdown` module wraps MDEx and owns this transformation.
- **D-03:** **Do not cache rendered output** in `body_rendered`. The column exists on the schema
  (per DATA_MODEL.md) but stays `NULL` in Phase 2. Always compute on the fly. Add a note in
  the schema that caching can be introduced later if profiling shows rendering is a hot path.

### Board Server Startup (BOARD-06)

- **D-04:** **Start all non-archived boards at application boot.** In `Foglet.Boards.Supervisor`
  (DynamicSupervisor), `init/1` queries all boards where `archived = false` and calls
  `DynamicSupervisor.start_child/2` for each. No on-demand logic needed in post-creation path.
  New boards created by a sysop start their Server immediately on board creation.
- **D-05:** **On Server crash/restart, reload from DB:** `init/1` queries
  `SELECT COALESCE(MAX(message_number), 0) FROM posts WHERE board_id = $board_id` and resumes from
  `MAX + 1`. This is self-healing — the persisted `boards.next_message_number` counter is updated
  on every successful post insert (inside the Multi transaction) but the Server always re-derives
  from the posts table on startup for safety.

### Default Subscription Wiring (BOARD-07)

- **D-06:** **Phase 2 adds `Foglet.Boards.subscribe_to_defaults/1`**, which queries all boards
  where `default_subscription = true` and inserts `board_subscriptions` rows for the given user.
  Phase 2 also modifies `Foglet.Accounts.create_user/1` to call this function after a successful
  user insert (wrapped in the same `Ecto.Multi` or called immediately after — either is fine; prefer
  the Multi for atomicity). Phase 3 SSH guest flow does not need to call it separately.

### Claude's Discretion

- Context split: `Foglet.Boards` owns categories, boards, subscriptions, and read pointers.
  `Foglet.Threads` owns threads and thread read pointers. `Foglet.Posts` owns posts, post_edits,
  and upvotes (upvote schema defined now even if toggling is Phase 9).
- Thread creation transaction: follow DATA_MODEL.md recommendation — `Ecto.Multi` that creates
  thread with `first_post_id = NULL`, creates the root post, then updates thread with `first_post_id`.
- Unread count queries: compute as `posts.message_number > board_read_pointers.last_read_message_number`
  with a query function in the Boards context. Implement per-board and per-thread variants.
- Property test tooling: use StreamData for message-number monotonicity tests.
- `Foglet.Markdown` module location: `lib/foglet_bbs/markdown.ex`. Single public function:
  `render/1` that accepts a markdown string and returns an ANSI-escaped string.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Schema + Data Model

- `docs/DATA_MODEL.md` §2 — Categories and Boards schemas, migration notes, `next_message_number`
  design rationale, Board Server insertion flow (`Ecto.Multi`)
- `docs/DATA_MODEL.md` §3 — Threads and Posts schemas, migration notes, `first_post_id` circular FK
  strategy, full-text search column (`body_tsv`)
- `docs/DATA_MODEL.md` §4 — Thread read pointers schema
- `docs/DATA_MODEL.md` §Conventions — `Foglet.Schema` macro; UUID v7; soft-delete pattern; citext

### Architecture

- `docs/ARCHITECTURE.md` §2 — Supervision tree (target shape; Boards.Supervisor placement)
- `docs/ARCHITECTURE.md` §5 — Data model topology (entity relationships)
- `docs/ARCHITECTURE.md` §6 — Ephemeral state (what lives in ETS vs DB)

### Requirements

- `.planning/REQUIREMENTS.md` BOARD-01 through BOARD-12 — acceptance criteria for this phase
- `.planning/ROADMAP.md` §Phase 2 — Success criteria (5 items) and dependencies

### Prior Phase

- `.planning/phases/01-accounts-and-identity/01-CONTEXT.md` — Phase 1 decisions, especially
  `Foglet.Schema` macro and `Foglet.Accounts.create_user/1` interface being modified in Phase 2

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `lib/foglet_bbs/schema.ex` — `Foglet.Schema` macro (created in Phase 1). All new schemas in
  this phase use `use Foglet.Schema`.
- `lib/foglet_bbs/repo.ex` — `Foglet.Repo`. Use for all DB operations.
- `lib/foglet_bbs/application.ex` — OTP supervision tree. `Foglet.Boards.Supervisor` added here
  alongside the existing entries from Phase 1.
- `lib/foglet_bbs/accounts.ex` — `Foglet.Accounts.create_user/1` modified here to call
  `Foglet.Boards.subscribe_to_defaults/1`.

### Established Patterns

- All schemas: `use Foglet.Schema` (UUID v7, utc_datetime_usec, foreign key UUID)
- Tests mirror lib: `test/foglet_bbs/boards/`, `test/foglet_bbs/threads/`, `test/foglet_bbs/posts/`
- `mix precommit` is the quality gate (format + Credo strict + test)
- DynamicSupervisor + named child spec pattern established in ARCHITECTURE.md §2

### Integration Points

- `Foglet.Accounts.create_user/1` — Phase 2 adds call to `Foglet.Boards.subscribe_to_defaults/1`
- `Foglet.Boards.Supervisor` — started in `application.ex` supervision tree; boots all board servers
- Phase 3 will consume: `Foglet.Boards.list_boards/0`, `Foglet.Threads.list_threads/1`,
  `Foglet.Posts.create_post/2`, `Foglet.Posts.create_reply/3`, `Foglet.Markdown.render/1`,
  `Foglet.Boards.unread_counts/1`

</code_context>

<specifics>
## Specific Ideas

- `Foglet.Markdown.render/1` — single clean public API; transformation logic internal. Downstream
  phases (TUI) call this everywhere they display post bodies.
- Board Server self-healing on restart via `MAX(message_number)` query — makes the process
  independently recoverable without relying on the `boards.next_message_number` counter being
  in sync after a mid-flight crash.

</specifics>

<deferred>
## Deferred Ideas

- Caching `body_rendered` in the database — deferred until profiling shows it's a hot path (Phase 9+)
- Full-text search index on `posts.body` — the generated tsvector column and GIN index are defined
  in DATA_MODEL.md §3; add the column in migrations now (it's in the schema), but search queries
  are Phase 9 scope.
- Upvote toggling logic — `upvotes` schema created now per DATA_MODEL.md; toggle/count functions
  are Phase 9 scope.

</deferred>

---

*Phase: 02-domain-core*
*Context gathered: 2026-04-18*
