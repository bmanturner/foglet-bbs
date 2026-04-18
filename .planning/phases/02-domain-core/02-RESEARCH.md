# Phase 2: Domain Core - Research

**Researched:** 2026-04-18
**Domain:** Elixir/Phoenix domain contexts, Ecto schemas/migrations, DynamicSupervisor + GenServer (Board Server), MDEx Markdown rendering, StreamData property tests
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01:** Use **MDEx** as the Markdown parsing library. Wraps `comrak` (CommonMark + GFM, Rust NIF). Must be added as a dependency to `mix.exs`.

**D-02:** "Terminal-friendly" means **ANSI-styled plain text** — no HTML output.
Mapping: bold → `\e[1m`, italic → `\e[3m`, headings → uppercase + underline, code spans → dim color (`\e[2m`), code blocks → 2-space indent + dim, links → show URL in parens, images → alt text only. The `Foglet.Markdown` module wraps MDEx and owns this transformation.

**D-03:** **Do not cache rendered output** in `body_rendered`. Column exists on the schema but stays `NULL` in Phase 2. Always compute on the fly. Add a note in the schema that caching can be introduced later if profiling shows rendering is a hot path.

**D-04:** **Start all non-archived boards at application boot.** In `Foglet.Boards.Supervisor` (DynamicSupervisor), `init/1` queries all boards where `archived = false` and calls `DynamicSupervisor.start_child/2` for each. No on-demand logic needed in post-creation path. New boards created by a sysop start their Server immediately on board creation.

**D-05:** **On Server crash/restart, reload from DB:** `init/1` queries `SELECT COALESCE(MAX(message_number), 0) FROM posts WHERE board_id = $board_id` and resumes from `MAX + 1`. The persisted `boards.next_message_number` counter is updated on every successful post insert (inside the Multi transaction) but the Server always re-derives from the posts table on startup for safety.

**D-06:** **Phase 2 adds `Foglet.Boards.subscribe_to_defaults/1`**, which queries all boards where `default_subscription = true` and inserts `board_subscriptions` rows for the given user. Phase 2 also modifies `Foglet.Accounts.create_user/1` to call this function after a successful user insert.

### Claude's Discretion

- Context split: `Foglet.Boards` owns categories, boards, subscriptions, and read pointers. `Foglet.Threads` owns threads and thread read pointers. `Foglet.Posts` owns posts, post_edits, and upvotes.
- Thread creation transaction: `Ecto.Multi` that creates thread with `first_post_id = NULL`, creates the root post, then updates thread with `first_post_id`.
- Unread count queries: compute as `posts.message_number > board_read_pointers.last_read_message_number`.
- Property test tooling: use StreamData (already in deps) for message-number monotonicity tests.
- `Foglet.Markdown` module location: `lib/foglet_bbs/markdown.ex`. Single public function: `render/1`.

### Deferred Ideas (OUT OF SCOPE)

- Caching `body_rendered` in the database — Phase 9+
- Full-text search queries — Phase 9 (the `body_tsv` column is created in migration now, but querying it is Phase 9)
- Upvote toggling logic — Phase 9 (schema created now, toggle/count functions are Phase 9)
- Thread move implementation (cross-board reassignment) — see note in Pitfalls
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BOARD-01 | Sysop can create Categories → Boards | `Foglet.Boards` context with `create_category/1`, `create_board/1`; migrations for `categories` and `boards` tables |
| BOARD-02 | User can create a Thread (title + root post) in a board | `Foglet.Threads.create_thread/2` — `Ecto.Multi` with three steps: thread insert, post insert, thread update (`first_post_id`) |
| BOARD-03 | User can reply to a thread | `Foglet.Posts.create_reply/3` — routes through Board Server for message-number allocation |
| BOARD-04 | User can edit their own posts; edit history preserved | `Foglet.Posts.edit_post/3` — inserts into `post_edits` before updating `posts`; increments `edit_count` |
| BOARD-05 | Posts support Markdown; renders to terminal representation | `Foglet.Markdown.render/1` using MDEx; ANSI escape output; no HTML |
| BOARD-06 | Per-board message numbers sequential via `Foglet.Boards.Server` GenServer | `Foglet.Boards.Server` — DynamicSupervisor child; allocates numbers in-memory, persists via `Ecto.Multi` |
| BOARD-07 | User can subscribe to boards; default subscriptions on signup | `Foglet.Boards.subscribe_to_defaults/1`; called from `Foglet.Accounts.create_user/1` |
| BOARD-08 | Per-user per-board read pointer tracks last-read message number | `Foglet.Boards.advance_read_pointer/3` — upsert on `board_read_pointers`; `Foglet.Boards.unread_count/2` query |
| BOARD-09 | Per-user per-thread read pointer tracks last-read post | `Foglet.Threads.advance_read_pointer/3` — upsert on `thread_read_pointers` |
| BOARD-10 | Unread counts queryable per user per board and per thread | `Foglet.Boards.unread_counts/1` (all boards for user); `Foglet.Threads.unread_count/2` (single thread) |
| BOARD-11 | Posts support soft-delete; thread coherence and message numbers preserved | `Foglet.Posts.delete_post/2` — sets `deleted_at`; message number gap is permanent (by design); coherence preserved |
| BOARD-12 | Threads can be locked, stickied, or moved between boards | `Foglet.Threads.lock_thread/1`, `sticky_thread/1`, `move_thread/3` — mod/sysop pathways |
</phase_requirements>

---

## Summary

Phase 2 builds the complete BBS data model in three bounded contexts: `Foglet.Boards` (categories, boards, subscriptions, read pointers, Board Server), `Foglet.Threads` (threads, thread read pointers), and `Foglet.Posts` (posts, post_edits, upvotes). It also adds `Foglet.Markdown` for ANSI rendering and `Foglet.Boards.Supervisor` (DynamicSupervisor) to the application supervision tree.

The most architecturally complex piece is `Foglet.Boards.Server` — a GenServer per active board that serializes message-number allocation. This avoids Postgres sequence gymnastics and makes the sequence independently testable. The Board Server integrates with `Ecto.Multi` transactions: the Server calls into the Multi, the Multi writes the post to Postgres and bumps `boards.next_message_number` atomically, and the Server's in-memory state reflects the committed number.

MDEx must be added to `mix.exs` as a dependency. It is a Rust NIF library (via `comrak`) so it compiles on first `mix deps.get`. No other new dependencies are required — StreamData (property tests) is already in the dev/test deps.

The key engineering challenge is the `first_post_id` circular FK between `threads` and `posts`. DATA_MODEL.md's recommended approach: create the thread with `first_post_id = NULL`, create the post, then update the thread — all in one `Ecto.Multi`. This requires the `first_post_id` FK to allow NULL, which the DATA_MODEL.md confirms with `references(..., on_delete: :nilify_all)`.

**Primary recommendation:** Follow DATA_MODEL.md schemas exactly. The schemas are the contract; departures happen via deliberate decision. The Board Server pattern is well-established in the Elixir ecosystem (DynamicSupervisor + named Registry children). Migrations must use `mix ecto.gen.migration migration_name_using_underscores` per CLAUDE.md.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Schema definitions | Database / Storage | — | DATA_MODEL.md is the contract |
| Board/Category/Subscription context | API / Backend | Database / Storage | CRUD + subscription logic in `Foglet.Boards` |
| Thread context (create, lock, sticky, move) | API / Backend | Database / Storage | `Foglet.Threads` — reads through Board Server for post operations |
| Post context (create, reply, edit, delete) | API / Backend | Database / Storage | `Foglet.Posts` — all writes go through Board Server |
| Board Server (message-number allocator) | API / Backend (GenServer) | Database / Storage | Stateful process; serializes allocations per board |
| Boards Supervisor | OTP / Process Management | — | DynamicSupervisor that boots all Board Servers |
| Markdown rendering | API / Backend | — | `Foglet.Markdown` — stateless transform; MDEx NIF |
| Unread count queries | Database / Storage | API / Backend | SQL `WHERE message_number > last_read` via Ecto queries |
| Default subscription wiring | API / Backend | — | Called from `Foglet.Accounts.create_user/1` after user insert |
| Property tests (message-number monotonicity) | Testing | — | StreamData concurrency simulation |

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `ecto_sql` | ~> 3.13 (locked) | Migrations, queries | Already in project |
| `postgrex` | >= 0.0.0 (locked) | Postgres adapter | Already in project |
| `stream_data` | ~> 1.0 (locked, dev/test only) | Property-based tests for message-number monotonicity | Already in project; CONTEXT.md specifies StreamData |

### New Dependency
| Library | Version | Purpose | Why Needed |
|---------|---------|---------|------------|
| `mdex` | `~> 0.2` | Markdown → ANSI rendering | D-01 locked; wraps `comrak` Rust NIF; CommonMark + GFM spec compliant |

**Installation:**
```elixir
# Add to mix.exs deps:
{:mdex, "~> 0.2"}
```

Then `mix deps.get`. MDEx compiles a Rust NIF (requires Rust toolchain on dev machine; pre-compiled binaries available via `:rustler_precompiled`).

**Note on MDEx API:** MDEx accepts Markdown string and returns HTML by default. For ANSI output, use the AST traversal API or post-process the HTML. The cleanest approach for Phase 2 is to use `MDEx.to_html!/2` with options `%{parse: %{..., smart: true}}` to get structured HTML output, then transform it via a simple regex-based converter, OR use `MDEx.parse_document!/1` to get the AST and traverse it directly. The AST approach is more robust. See Code Examples below.

**Alternative:** Since MDEx outputs HTML and we need ANSI text, the implementation in `Foglet.Markdown.render/1` will: (1) call `MDEx.to_html!(markdown, [])`, (2) strip/convert HTML tags to ANSI escapes. A simple regex pass over the HTML output handles this well for the BBS's modest markdown subset (bold, italic, headings, code). This approach is simpler than full AST traversal.

### Supporting (already in project)
| Library | Version | Purpose |
|---------|---------|---------|
| `Ecto.Multi` | ecto_sql | Multi-step atomic transactions — thread creation, post insertion |
| `:ets` (OTP) | OTP 28.3.1 | Board Server uses `GenServer` state (not ETS) for counter; ETS could be used for a cross-process cache but is NOT needed for Phase 2 |
| `Phoenix.PubSub` | phoenix | PubSub topics for board activity — wired now even if Phase 3 consumes it |

---

## Architecture Patterns

### System Architecture Diagram

```
Foglet.Accounts.create_user/1
  |
  | (after user insert)
  v
Foglet.Boards.subscribe_to_defaults/1
  |
  v
board_subscriptions (insert default subs)

===

FogletBbs.Application (start/2)
  |
  +---> Foglet.Boards.Supervisor (DynamicSupervisor)
          |
          | (on start — queries all boards where archived = false)
          +---> Foglet.Boards.Server (board_id: "uuid-1") [GenServer]
          +---> Foglet.Boards.Server (board_id: "uuid-2") [GenServer]
          +---> ...

===

Post creation flow:
Foglet.Posts.create_post/2 (or create_reply/3)
  |
  | GenServer.call(:boards_server_uuid, :allocate_and_insert, %{...})
  v
Foglet.Boards.Server (handle_call :allocate_and_insert)
  |
  | runs Ecto.Multi:
  |   1. UPDATE boards SET next_message_number = next_message_number + 1 WHERE id = board_id
  |   2. INSERT INTO posts (message_number, ...) VALUES (current_number, ...)
  |   3. UPDATE threads SET post_count = post_count + 1, last_post_at = now() WHERE id = thread_id
  |   4. UPDATE users SET post_count = post_count + 1 WHERE id = user_id
  v
Foglet.Repo.transaction()
  |
  | {:ok, %{post: post}} -> update GenServer state (counter++)
  v
Return {:ok, post} to caller
```

### Recommended Project Structure

```
lib/foglet_bbs/
├── markdown.ex                          # Foglet.Markdown — render/1 public API
│
├── boards.ex                            # Foglet.Boards context — public API
├── boards/
│   ├── category.ex                      # Foglet.Boards.Category schema
│   ├── board.ex                         # Foglet.Boards.Board schema
│   ├── subscription.ex                  # Foglet.Boards.Subscription schema
│   ├── read_pointer.ex                  # Foglet.Boards.ReadPointer schema (board_read_pointers)
│   ├── server.ex                        # Foglet.Boards.Server GenServer
│   └── supervisor.ex                    # Foglet.Boards.Supervisor DynamicSupervisor
│
├── threads.ex                           # Foglet.Threads context — public API
├── threads/
│   ├── thread.ex                        # Foglet.Threads.Thread schema
│   └── read_pointer.ex                  # Foglet.Threads.ReadPointer schema (thread_read_pointers)
│
├── posts.ex                             # Foglet.Posts context — public API
├── posts/
│   ├── post.ex                          # Foglet.Posts.Post schema
│   ├── edit.ex                          # Foglet.Posts.Edit schema (post_edits)
│   └── upvote.ex                        # Foglet.Posts.Upvote schema (upvotes — schema only)
│
priv/repo/migrations/
├── 20260418XXXXXX_create_categories.exs
├── 20260418XXXXXX_create_boards.exs
├── 20260418XXXXXX_create_board_subscriptions.exs
├── 20260418XXXXXX_create_board_read_pointers.exs
├── 20260418XXXXXX_create_threads.exs
├── 20260418XXXXXX_create_posts.exs
├── 20260418XXXXXX_create_post_edits.exs
├── 20260418XXXXXX_create_upvotes.exs
└── 20260418XXXXXX_create_thread_read_pointers.exs
│
priv/repo/seeds.exs                      # Add default categories, boards (after tombstone user)
│
test/foglet_bbs/
├── boards/
│   ├── boards_test.exs                  # Context function tests (BOARD-01, BOARD-07, BOARD-08, BOARD-10)
│   ├── category_test.exs                # Schema changeset tests
│   ├── board_test.exs                   # Schema changeset tests
│   └── board_server_test.exs            # GenServer unit tests + property test (BOARD-06)
├── threads/
│   └── threads_test.exs                 # Context function tests (BOARD-02, BOARD-09, BOARD-12)
├── posts/
│   ├── posts_test.exs                   # Context function tests (BOARD-03, BOARD-04, BOARD-11)
│   └── post_test.exs                    # Schema changeset tests
└── markdown_test.exs                    # Render output tests (BOARD-05)
```

### Pattern 1: DynamicSupervisor for Board Servers (D-04)

**What:** A DynamicSupervisor that starts one GenServer per active board at boot and on board creation.
**When to use:** `Foglet.Boards.Supervisor` + `Foglet.Boards.Server`

```elixir
# lib/foglet_bbs/boards/supervisor.ex
defmodule Foglet.Boards.Supervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    # Boot all non-archived boards
    active_boards = Foglet.Repo.all(
      from b in Foglet.Boards.Board, where: b.archived == false, select: b.id
    )
    DynamicSupervisor.init(strategy: :one_for_one)
    # Note: cannot start children in init/1 directly — use a Task or handle in start_link
    # Pattern: start children AFTER supervisor is registered, in a separate call
  end
end
```

**Better pattern** — start board servers after supervisor is up, using `Application.start/2`:

```elixir
# In FogletBbs.Application.start/2, AFTER starting the supervisor:
def start(_type, _args) do
  children = [
    ...,
    Foglet.Boards.Supervisor,
    ...
  ]
  {:ok, pid} = Supervisor.start_link(children, opts)

  # Boot board servers after supervision tree is up
  Foglet.Boards.boot_board_servers()

  {:ok, pid}
end

# In Foglet.Boards context:
def boot_board_servers do
  active_boards = Repo.all(from b in Board, where: b.archived == false, select: b.id)
  Enum.each(active_boards, &start_board_server/1)
end

def start_board_server(board_id) do
  spec = {Foglet.Boards.Server, board_id: board_id}
  DynamicSupervisor.start_child(Foglet.Boards.Supervisor, spec)
end
```

**Board Server naming:** Use `Registry` for named Board Servers so the context can call them by board_id without knowing the PID:

```elixir
# In FogletBbs.Application:
children = [
  ...,
  {Registry, keys: :unique, name: Foglet.BoardRegistry},
  Foglet.Boards.Supervisor,
  ...
]

# In Foglet.Boards.Server:
def start_link(opts) do
  board_id = Keyword.fetch!(opts, :board_id)
  GenServer.start_link(__MODULE__, board_id, name: via_tuple(board_id))
end

defp via_tuple(board_id) do
  {:via, Registry, {Foglet.BoardRegistry, board_id}}
end

# Calling the server from context:
defp board_server(board_id) do
  {:via, Registry, {Foglet.BoardRegistry, board_id}}
end
```

[VERIFIED: CLAUDE.md — "OTP primitives like DynamicSupervisor and Registry require names in the child spec"; docs/ARCHITECTURE.md §2 — confirms DynamicSupervisor pattern]

### Pattern 2: Board Server Message-Number Allocation (D-05)

**What:** GenServer holds the current `next_message_number` in state. On each post insert, runs an `Ecto.Multi` that atomically updates `boards.next_message_number` in Postgres AND inserts the post with that number. The GenServer serializes all writes to a board.

```elixir
defmodule Foglet.Boards.Server do
  use GenServer

  def init(board_id) do
    # D-05: reload from DB on (re)start for safety
    current_max = Foglet.Repo.one(
      from p in Foglet.Posts.Post,
        where: p.board_id == ^board_id,
        select: coalesce(max(p.message_number), 0)
    )
    {:ok, %{board_id: board_id, next_number: current_max + 1}}
  end

  def handle_call({:allocate_and_insert, post_attrs, thread_id, user_id}, _from, state) do
    %{board_id: board_id, next_number: n} = state

    result =
      Ecto.Multi.new()
      |> Ecto.Multi.run(:update_board_counter, fn repo, _ ->
        {1, _} = repo.update_all(
          from(b in Foglet.Boards.Board, where: b.id == ^board_id),
          inc: [next_message_number: 1]
        )
        {:ok, n}
      end)
      |> Ecto.Multi.insert(:post, fn _ ->
        Foglet.Posts.Post.creation_changeset(%Foglet.Posts.Post{}, Map.merge(post_attrs, %{
          message_number: n,
          board_id: board_id,
          thread_id: thread_id,
          user_id: user_id
        }))
      end)
      |> Ecto.Multi.update(:thread, fn %{post: _post} ->
        Foglet.Threads.Thread.bump_counters_changeset(thread_id)
      end)
      |> Ecto.Multi.update(:user, fn _ ->
        Foglet.Accounts.User.increment_post_count_changeset(user_id)
      end)
      |> Foglet.Repo.transaction()

    case result do
      {:ok, %{post: post}} ->
        {:reply, {:ok, post}, %{state | next_number: n + 1}}
      {:error, _op, reason, _changes} ->
        {:reply, {:error, reason}, state}  # counter NOT incremented on failure
    end
  end
end
```

**Key insight:** The GenServer's in-memory counter only advances on successful commit. If the transaction fails, the counter stays at `n` and the next attempt reuses the same number. This is correct — the DB-level uniqueness constraint on `(board_id, message_number)` is the backstop.

[VERIFIED: docs/DATA_MODEL.md §3 — Insertion flow description confirms this Multi pattern]

### Pattern 3: Thread Creation with Circular FK (BOARD-02)

**What:** `threads.first_post_id` → `posts.id` is a circular FK. Solution: three-step `Ecto.Multi`.

```elixir
def create_thread(board_id, user_id, %{title: title, body: body}) do
  # Route through Board Server to get message number
  board_server_name = {:via, Registry, {Foglet.BoardRegistry, board_id}}

  # Pre-create the thread struct (no first_post_id yet)
  # Then call the Board Server which runs the full Multi
  GenServer.call(board_server_name, {:create_thread, %{
    title: title,
    body: body,
    user_id: user_id,
    board_id: board_id
  }})
end

# In Board Server handle_call {:create_thread, ...}:
# Ecto.Multi steps:
# 1. Multi.insert(:thread) — Thread with first_post_id: nil
# 2. Multi.insert(:post, fn %{thread: thread} ->) — Post with thread_id: thread.id
# 3. Multi.update(:thread_update, fn %{thread: thread, post: post} ->) — Set first_post_id: post.id
# 4. Multi.update(:board_counter, ...) — Bump next_message_number
# 5. Multi.update(:user_counter, ...) — Bump post_count
```

[VERIFIED: docs/DATA_MODEL.md §3 — "Recommendation: create thread with `first_post_id = NULL`, create post, update thread, all in one `Ecto.Multi`"]

### Pattern 4: Read Pointer Upsert (BOARD-08, BOARD-09)

**What:** `board_read_pointers` and `thread_read_pointers` use upsert semantics — insert on first read, update on subsequent reads.

```elixir
# Upsert pattern with Ecto
def advance_board_read_pointer(user_id, board_id, message_number) do
  %Foglet.Boards.ReadPointer{}
  |> Foglet.Boards.ReadPointer.changeset(%{
    user_id: user_id,
    board_id: board_id,
    last_read_message_number: message_number,
    last_read_at: DateTime.utc_now()
  })
  |> Foglet.Repo.insert(
    on_conflict: [set: [last_read_message_number: message_number, last_read_at: DateTime.utc_now()]],
    conflict_target: [:user_id, :board_id]
  )
end
```

[VERIFIED: docs/DATA_MODEL.md §2 — ReadPointer — "Updated with upserts — `INSERT ... ON CONFLICT (user_id, board_id) DO UPDATE`"]

### Pattern 5: Unread Count Query (BOARD-10)

**What:** Count posts in a board (or thread) with `message_number > last_read_message_number`.

```elixir
# Per-board unread count for a user
def unread_count(user_id, board_id) do
  pointer_query =
    from(p in Foglet.Boards.ReadPointer,
      where: p.user_id == ^user_id and p.board_id == ^board_id,
      select: p.last_read_message_number
    )

  last_read = Foglet.Repo.one(pointer_query) || 0

  Foglet.Repo.aggregate(
    from(p in Foglet.Posts.Post,
      where: p.board_id == ^board_id and
             p.message_number > ^last_read and
             is_nil(p.deleted_at)
    ),
    :count,
    :id
  )
end

# Batch unread counts for all subscribed boards — one query
def unread_counts(user_id) do
  from(s in Foglet.Boards.Subscription,
    where: s.user_id == ^user_id,
    left_join: rp in Foglet.Boards.ReadPointer,
      on: rp.user_id == s.user_id and rp.board_id == s.board_id,
    left_join: p in Foglet.Posts.Post,
      on: p.board_id == s.board_id and
          p.message_number > coalesce(rp.last_read_message_number, 0) and
          is_nil(p.deleted_at),
    group_by: s.board_id,
    select: {s.board_id, count(p.id)}
  )
  |> Foglet.Repo.all()
  |> Map.new()
end
```

### Pattern 6: MDEx Markdown Rendering (D-01, D-02, BOARD-05)

**What:** `Foglet.Markdown.render/1` accepts Markdown, returns ANSI-escaped plain text.

```elixir
defmodule Foglet.Markdown do
  @moduledoc """
  Converts Markdown to ANSI-escaped terminal-friendly text.

  D-02 ANSI mapping:
  - bold → \e[1m...\e[0m
  - italic → \e[3m...\e[0m
  - headings → UPPERCASE + underline (\e[4m)
  - code spans → dim (\e[2m...\e[0m)
  - code blocks → 2-space indent + dim
  - links → display text (url in parens)
  - images → alt text only
  """

  @doc "Render Markdown string to ANSI-escaped plain text."
  @spec render(String.t()) :: String.t()
  def render(markdown) when is_binary(markdown) do
    # Convert Markdown → HTML via MDEx
    html = MDEx.to_html!(markdown, extension: [table: true, autolink: true])
    # Strip/transform HTML tags to ANSI
    html_to_ansi(html)
  end

  defp html_to_ansi(html) do
    html
    |> String.replace(~r/<strong>(.*?)<\/strong>/s, "\e[1m\\1\e[0m")
    |> String.replace(~r/<em>(.*?)<\/em>/s, "\e[3m\\1\e[0m")
    |> String.replace(~r/<h[1-6]>(.*?)<\/h[1-6]>/si, fn _, text ->
      "\e[4m\e[1m#{String.upcase(text)}\e[0m\n"
    end)
    |> String.replace(~r/<code>(.*?)<\/code>/s, "\e[2m\\1\e[0m")
    |> String.replace(~r/<pre><code[^>]*>(.*?)<\/code><\/pre>/s, fn _, code ->
      indented = code |> String.split("\n") |> Enum.map_join("\n", &("  \e[2m" <> &1 <> "\e[0m"))
      "\n" <> indented <> "\n"
    end)
    |> String.replace(~r/<a href="([^"]+)"[^>]*>(.*?)<\/a>/s, "\\2 (\\1)")
    |> String.replace(~r/<img[^>]+alt="([^"]*)"[^>]*>/s, "\\1")
    |> String.replace(~r/<[^>]+>/, "")  # strip remaining tags
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.trim()
  end
end
```

**Note:** The regex approach is simple and sufficient for BBS post rendering. Headings use `String.replace/4` with a function capture. The MDEx call uses `to_html!/2` which raises on invalid input — use `to_html/2` if you want error handling.

[VERIFIED: MDEx hex package readme — `MDEx.to_html!/2` API confirmed; extension options available]

### Pattern 7: Property Test for Message-Number Monotonicity (BOARD-06)

**What:** Use StreamData to verify that concurrent Board Server calls produce monotonically sequential, non-duplicate message numbers.

```elixir
defmodule Foglet.Boards.BoardServerTest do
  use Foglet.DataCase, async: false  # async: false for GenServer tests
  use ExUnitProperties

  property "message numbers are monotonically sequential under concurrent inserts" do
    check all(
      board_id <- StreamData.constant(create_board!()),
      post_count <- StreamData.integer(2..20),
      max_runs: 10
    ) do
      # Start board server
      {:ok, _} = start_supervised!({Foglet.Boards.Server, board_id: board_id})

      user_id = create_user!()
      thread_id = create_thread_stub!(board_id, user_id)

      # Concurrent inserts via Task.async_stream
      tasks =
        1..post_count
        |> Task.async_stream(fn _ ->
          Foglet.Posts.create_reply(thread_id, user_id, %{body: "test"})
        end, timeout: :infinity)
        |> Enum.to_list()

      {:ok, posts} =
        Enum.reduce_while(tasks, {:ok, []}, fn
          {:ok, {:ok, post}}, {:ok, acc} -> {:cont, {:ok, [post | acc]}}
          {:ok, {:error, _}}, _ -> {:halt, {:error, :insert_failed}}
          {:exit, reason}, _ -> {:halt, {:error, reason}}
        end)

      message_numbers = posts |> Enum.map(& &1.message_number) |> Enum.sort()

      # All numbers must be unique
      assert length(message_numbers) == length(Enum.uniq(message_numbers))
      # Numbers form a contiguous sequence
      [first | _] = message_numbers
      expected = Enum.to_list(first..(first + post_count - 1))
      assert message_numbers == expected
    end
  end
end
```

[VERIFIED: StreamData already in project deps (`stream_data ~> 1.0`); CONTEXT.md specifies StreamData; CLAUDE.md specifies `Task.async_stream/3` with `timeout: :infinity` for concurrent enumeration]

### Pattern 8: Default Subscription Wiring (D-06, BOARD-07)

**What:** `Foglet.Boards.subscribe_to_defaults/1` is called from `Foglet.Accounts.create_user/1`.

```elixir
# In Foglet.Boards:
def subscribe_to_defaults(user_id) do
  default_boards = Repo.all(from b in Board, where: b.default_subscription == true, select: b.id)

  Enum.each(default_boards, fn board_id ->
    %Subscription{}
    |> Subscription.changeset(%{
      user_id: user_id,
      board_id: board_id,
      subscribed_at: DateTime.utc_now()
    })
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:user_id, :board_id])
  end)
end

# Modification to Foglet.Accounts (lib/foglet_bbs/accounts.ex):
# After successful user insert in create_user/1, add:
# Foglet.Boards.subscribe_to_defaults(user.id)
```

**Important:** The call to `Foglet.Boards.subscribe_to_defaults/1` should happen AFTER `Repo.insert/1` for the user, not inside the same `Ecto.Multi`. If it runs inside the Multi and fails for a transient reason, it rolls back the user creation. Since missing default subscriptions are recoverable but lost users are not, prefer calling it after the committed insert.

However, CONTEXT.md says "either is fine; prefer the Multi for atomicity". Follow CONTEXT.md: wrap in Multi if simple, otherwise post-commit call.

### Anti-Patterns to Avoid

- **Starting children in `DynamicSupervisor.init/1`:** Cannot call `DynamicSupervisor.start_child/2` inside `init/1`. Start children AFTER the supervisor is registered (see Pattern 1).
- **Using `def change` with `execute/1` in migrations:** Use `def up/def down` for any migration with raw SQL (`CREATE EXTENSION`, `CREATE INDEX CONCURRENTLY`, generated columns). Generated column for `body_tsv` requires raw SQL — use `def up/def down`.
- **`changeset[:field]` on structs:** Use `Ecto.Changeset.get_field/2`. (CLAUDE.md)
- **Listing `user_id`, `board_id`, `thread_id` in `cast` calls:** These are FK fields set programmatically. Set on struct directly or via explicit `put_change`. (CLAUDE.md)
- **`Process.sleep/1` in Board Server tests:** Use `:sys.get_state/1` after calls to ensure the server has processed messages before asserting.
- **`String.to_atom/1` on user input:** Not applicable to this phase (no CLI input), but avoid in any context-facing helper.
- **`Ecto.Schema` field type `:text`:** Use `:string` for text columns (CLAUDE.md). Even for `body` (markdown source), `field :body, :string`.
- **Nested modules in the same file:** Each schema (Category, Board, Subscription, ReadPointer, Server, Supervisor, Thread, Post, Edit, Upvote) must be its own file.
- **Accessing GenServer state with `Process.info` in tests:** Use `:sys.get_state(server_name)` instead.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Markdown parsing | Custom parser | MDEx (`to_html!/2`) | D-01 locked; Rust NIF; CommonMark compliant |
| ANSI color codes | Custom escape builder | Hard-coded `"\e[1m"` etc. in `html_to_ansi/1` | No ANSI library needed for the simple BBS mapping |
| Message-number sequence | Postgres sequence | `Foglet.Boards.Server` GenServer | ARCHITECTURE.md §2 — "Board servers own their message-number sequence"; testable in isolation |
| Concurrent test synchronization | `Process.sleep/1` | `:sys.get_state/1` + `start_supervised!/1` | CLAUDE.md constraint; eliminates flakiness |
| Board lookup by ID | Manual Registry lookup | `{:via, Registry, {Foglet.BoardRegistry, board_id}}` | Standard OTP pattern; Registry handles process discovery |

---

## Common Pitfalls

### Pitfall 1: Generated Column Syntax for `body_tsv`

**What goes wrong:** Migration fails with `ERROR: syntax error at or near "GENERATED"`.
**Why it happens:** Ecto's `add :column` DSL doesn't support `GENERATED ALWAYS AS ... STORED` columns. Must use raw SQL.
**How to avoid:** Use `execute/1` in migration:
```elixir
def up do
  create table(:posts, primary_key: false) do
    # ... other columns ...
  end
  execute """
    ALTER TABLE posts ADD COLUMN body_tsv tsvector
    GENERATED ALWAYS AS (to_tsvector('english', coalesce(body, ''))) STORED;
  """
  execute "CREATE INDEX posts_body_tsv_gin_idx ON posts USING GIN (body_tsv);"
end
def down do
  drop table(:posts)
end
```
Use `def up/def down` not `def change` because of `execute/1`.

[VERIFIED: DATA_MODEL.md §3 — "Generated columns (Postgres `GENERATED ALWAYS AS ... STORED`) are used for the full-text search `tsvector`"]

### Pitfall 2: Circular FK — `threads.first_post_id`

**What goes wrong:** Migration fails because `threads` table references `posts` but `posts` references `threads` — circular FK at migration time.
**Why it happens:** Both FKs try to point at tables that don't exist yet when the migration runs.
**How to avoid:**
1. Create `threads` table WITHOUT `first_post_id` column.
2. Create `posts` table with `thread_id` FK → `threads`.
3. Use `alter table(:threads)` to ADD `first_post_id` as nullable FK → `posts` with `on_delete: :nilify_all`.
This three-step approach in one migration (or across two) resolves the circular dependency.

```elixir
def up do
  create table(:threads, primary_key: false) do
    add :id, :binary_id, primary_key: true
    add :title, :string, null: false
    # ... other columns ...
    # Note: first_post_id added AFTER posts table is created
    timestamps(type: :utc_datetime_usec)
  end

  create table(:posts, primary_key: false) do
    add :id, :binary_id, primary_key: true
    add :thread_id, references(:threads, type: :binary_id, on_delete: :delete_all), null: false
    # ...
  end

  alter table(:threads) do
    add :first_post_id, references(:posts, type: :binary_id, on_delete: :nilify_all)
  end
end
```

[VERIFIED: DATA_MODEL.md §3 — "`first_post_id` is a circular FK with `posts`; use `references(..., on_delete: :nilify_all)`"]

### Pitfall 3: Board Server Not Started in Tests

**What goes wrong:** Tests that call `Foglet.Posts.create_post/2` crash because `GenServer.call` on the Registry name finds no process.
**Why it happens:** Board Servers are started by `Foglet.Boards.Supervisor` in production, but tests use the Ecto sandbox, not the full application boot.
**How to avoid:** In Board Server tests, use `start_supervised!`:
```elixir
board = create_board!()
start_supervised!({Foglet.Boards.Server, board_id: board.id})
```
Also start the Registry as part of test setup if not already in the test application:
```elixir
# In test_helper.exs or DataCase setup:
start_supervised!({Registry, keys: :unique, name: Foglet.BoardRegistry})
```

[VERIFIED: CLAUDE.md — "Always use `start_supervised!/1` to start processes in tests"]

### Pitfall 4: `body_tsv` Column Break in Schema

**What goes wrong:** Ecto schema includes `field :body_tsv, :string` and migrations set it as a generated column, but Ecto tries to SELECT it normally and can also attempt to INSERT it (which Postgres rejects for generated columns).
**Why it happens:** Generated columns are read-only; Ecto doesn't know this.
**How to avoid:** Mark `body_tsv` in the schema but exclude it from changesets:
```elixir
# In Post schema:
field :body_tsv, :string, load_in_query: false  # Ecto 3.9+ option
# OR simply don't include body_tsv in the schema at all for Phase 2
# since it's only needed for Phase 9 full-text search queries.
```
Recommendation: **omit `body_tsv` from the Ecto schema entirely in Phase 2**. The column exists in the DB (via `execute/1` in migration), but `Foglet.Posts.Post` doesn't declare `field :body_tsv`. Phase 9 can add it when search queries need it. This avoids the generated column INSERT issue.

### Pitfall 5: `Task.async_stream` and Ecto Sandbox in Tests

**What goes wrong:** Concurrent insert tests fail with `DBConnection.OwnershipError` — the sandbox connection isn't shared with spawned tasks.
**Why it happens:** Ecto sandbox ownership is per-process. Tasks spawned by `Task.async_stream` are separate processes.
**How to avoid:** Use `Ecto.Adapters.SQL.Sandbox.allow/3` to grant the task processes access to the test's sandbox connection:
```elixir
# In test setup or property test:
parent = self()
Task.async_stream(1..10, fn _ ->
  Ecto.Adapters.SQL.Sandbox.allow(Foglet.Repo, parent, self())
  Foglet.Posts.create_reply(...)
end, timeout: :infinity)
```

[VERIFIED: Ecto docs — sandbox ownership and `allow/3` for concurrent tests]

### Pitfall 6: Boot Order — Board Servers Before DB is Ready

**What goes wrong:** `Foglet.Boards.boot_board_servers/0` is called in `Application.start/2` before `FogletBbs.Repo` is started, crashing the application.
**Why it happens:** The supervision tree starts children in order. If `Foglet.Boards.Supervisor` is listed before `FogletBbs.Repo`, the Repo isn't available when the supervisor tries to query for active boards.
**How to avoid:** Always list `FogletBbs.Repo` before `Foglet.Boards.Supervisor` in the `children` list in `FogletBbs.Application.start/2`. Also, call `Foglet.Boards.boot_board_servers/0` AFTER `Supervisor.start_link` completes (not in the supervisor's init callback).

### Pitfall 7: Thread Move Breaks `posts.board_id` Invariant

**What goes wrong:** Moving a thread to another board (`Foglet.Threads.move_thread/3`) updates `threads.board_id` but leaves `posts.board_id` pointing to the old board. This breaks `posts.board_id == posts.thread.board_id` invariant.
**Why it happens:** The denormalized `posts.board_id` must be updated for all posts in the thread.
**How to avoid:** Thread move is a Multi operation:
1. Update `threads.board_id`
2. `update_all` on `posts` where `thread_id = ^thread_id`, set `board_id = ^new_board_id`
3. Optionally: don't reassign `posts.message_number` (BOARD-12 says "without breaking message-number continuity")
Note: message numbers are per-board. After a move, posts in the new board may have message numbers that already exist in that board. DATA_MODEL.md doesn't explicitly handle this. **For Phase 2: do NOT renumber posts on move** — the `(board_id, message_number)` unique constraint may need to be violated temporarily or handled by the Board Server. Flag this as a known complexity; document in code that moved posts retain their original message numbers (which become "out of sequence" in the new board).

[VERIFIED: DATA_MODEL.md — unique index `(board_id, message_number)` — the core invariant; BOARD-12 requirement]

### Pitfall 8: MDEx NIF Compilation

**What goes wrong:** `mix deps.get` succeeds but the app fails to start with NIF loading errors.
**Why it happens:** MDEx uses Rustler for its NIF. If Rust is not installed on the machine, compilation fails.
**How to avoid:** MDEx ships pre-compiled NIF binaries via `:rustler_precompiled`. The default behavior downloads the correct binary for your platform. Ensure the machine has internet access during `mix deps.get`. If offline or in CI without Rust, check MDEx docs for pre-compiled binary fallback configuration:
```elixir
# In config/config.exs (if needed for pre-compiled fallback):
config :mdex, skip_compilation?: true
```
This is likely not needed for normal dev/CI environments.

---

## Code Examples

### Migration: Categories and Boards

```elixir
# priv/repo/migrations/TIMESTAMP_create_categories.exs
defmodule FogletBbs.Repo.Migrations.CreateCategories do
  use Ecto.Migration

  def change do
    create table(:categories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :string
      add :display_order, :integer, null: false, default: 0
      add :archived, :boolean, null: false, default: false
      timestamps(type: :utc_datetime_usec)
    end
  end
end

# priv/repo/migrations/TIMESTAMP_create_boards.exs
defmodule FogletBbs.Repo.Migrations.CreateBoards do
  use Ecto.Migration

  def change do
    create table(:boards, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :name, :string, null: false
      add :description, :string
      add :display_order, :integer, null: false, default: 0
      add :next_message_number, :integer, null: false, default: 1
      add :readable_by, :string, null: false, default: "public"
      add :postable_by, :string, null: false, default: "members"
      add :archived, :boolean, null: false, default: false
      add :default_subscription, :boolean, null: false, default: false
      add :category_id, references(:categories, type: :binary_id, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:boards, [:slug])
    create index(:boards, [:category_id, :display_order])
  end
end
```

### Seed: Default Category and Board

```elixir
# In priv/repo/seeds.exs (additions for Phase 2):
alias Foglet.Boards.{Category, Board}

# Default category
general_cat =
  case Repo.get_by(Category, name: "General") do
    nil ->
      Repo.insert!(%Category{
        name: "General",
        description: "General discussion",
        display_order: 1
      })
    existing -> existing
  end

# Default board with default_subscription: true
unless Repo.get_by(Board, slug: "general") do
  Repo.insert!(%Board{
    slug: "general",
    name: "General",
    description: "General discussion board",
    display_order: 1,
    readable_by: :public,
    postable_by: :members,
    default_subscription: true,
    category_id: general_cat.id
  })
end
```

### Schema: Post with Generated Column Omitted

```elixir
defmodule Foglet.Posts.Post do
  use Foglet.Schema

  schema "posts" do
    field :message_number, :integer
    field :body, :string
    field :body_rendered, :string   # stays NULL in Phase 2; computed on demand via Foglet.Markdown.render/1
    field :deleted_at, :utc_datetime_usec
    field :deletion_reason, :string
    field :upvote_count, :integer, default: 0
    field :edit_count, :integer, default: 0
    field :last_edited_at, :utc_datetime_usec
    # body_tsv INTENTIONALLY OMITTED — generated column, Phase 9 adds it to queries

    belongs_to :thread, Foglet.Threads.Thread
    belongs_to :board, Foglet.Boards.Board
    belongs_to :user, Foglet.Accounts.User
    belongs_to :reply_to, Foglet.Posts.Post

    has_many :edits, Foglet.Posts.Edit
    has_many :upvotes, Foglet.Posts.Upvote

    timestamps()
  end
end
```

---

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| DB sequences for per-board message numbers | GenServer per board (D-04 locked) | Testable in isolation; no Postgres sequence gymnastics |
| Caching rendered Markdown in DB | Compute on-demand via `Foglet.Markdown.render/1` (D-03) | No cache invalidation complexity; deferred until profiling needed |
| Polling DB for unread counts | Query-on-demand via `unread_count/2` | Correct for Phase 2; Phase 3+ may push via PubSub |
| Storing ANSI-escaped text in DB | Store raw Markdown, render at read time | Markdown is theme-agnostic; ANSI output depends on terminal capabilities |

---

## Runtime State Inventory

**Existing state (from Phase 1):**
- `users` table — 1 tombstone user row seeded
- `configuration` table — `registration.mode` + `registration.require_email_verification` seeded
- ETS table `:foglet_config` — started in `FogletBbs.Application`
- 5 migrations already run: citext+enum, users, ssh_keys, user_tokens, configuration

**What Phase 2 adds:**
- 9 new migrations (categories, boards, board_subscriptions, board_read_pointers, threads, posts, post_edits, upvotes, thread_read_pointers)
- New seed data: default category + default board
- `Foglet.Boards.Supervisor` + `Registry` added to application supervision tree
- Board Servers started for each non-archived board at boot

**No existing runtime state to migrate or rename.**

---

## Environment Availability

| Dependency | Required By | Available | Notes |
|------------|------------|-----------|-------|
| PostgreSQL | Ecto Repo | Assumed running | Phase 1 already required it |
| Rust toolchain | MDEx NIF compilation | Unknown | MDEx ships pre-compiled binaries; likely not needed |
| StreamData | Property tests | Yes (locked in mix.lock) | Already in project |
| OTP Registry | Board Server naming | Yes (OTP 28.3.1) | Built-in; no extra deps |

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit (built-in Elixir) |
| Config file | `test/test_helper.exs` |
| Quick run command | `mix test test/foglet_bbs/boards/ test/foglet_bbs/threads/ test/foglet_bbs/posts/` |
| Full suite command | `mix test` |
| Precommit gate | `mix precommit` (compile + credo + format — does NOT run tests) |
| Property tests | `mix test test/foglet_bbs/boards/board_server_test.exs` |

**Important:** `mix precommit` does not run tests. Run `mix precommit && mix test` for full validation.

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| BOARD-01 | `create_category/1` and `create_board/1` create DB rows | unit | `mix test test/foglet_bbs/boards/boards_test.exs` | No — Wave 0 |
| BOARD-02 | `create_thread/3` creates thread + root post atomically | unit | `mix test test/foglet_bbs/threads/threads_test.exs` | No — Wave 0 |
| BOARD-02 | Thread `first_post_id` is set after creation | unit | `mix test test/foglet_bbs/threads/threads_test.exs` | No — Wave 0 |
| BOARD-03 | `create_reply/3` increments `post_count`, sets `message_number` | unit | `mix test test/foglet_bbs/posts/posts_test.exs` | No — Wave 0 |
| BOARD-04 | `edit_post/3` creates `post_edits` row, increments `edit_count` | unit | `mix test test/foglet_bbs/posts/posts_test.exs` | No — Wave 0 |
| BOARD-05 | `Foglet.Markdown.render/1` returns ANSI-escaped string | unit | `mix test test/foglet_bbs/markdown_test.exs` | No — Wave 0 |
| BOARD-05 | Bold, italic, headings, code, links render correctly | unit | `mix test test/foglet_bbs/markdown_test.exs` | No — Wave 0 |
| BOARD-06 | Board Server allocates sequential message numbers | unit | `mix test test/foglet_bbs/boards/board_server_test.exs` | No — Wave 0 |
| BOARD-06 | Message numbers monotonically sequential under concurrent inserts (property test) | property | `mix test test/foglet_bbs/boards/board_server_test.exs` | No — Wave 0 |
| BOARD-07 | `subscribe_to_defaults/1` inserts subscription rows for default boards | unit | `mix test test/foglet_bbs/boards/boards_test.exs` | No — Wave 0 |
| BOARD-07 | `create_user/1` triggers default board subscriptions | integration | `mix test test/foglet_bbs/boards/boards_test.exs` | No — Wave 0 |
| BOARD-08 | `advance_board_read_pointer/3` upserts correctly | unit | `mix test test/foglet_bbs/boards/boards_test.exs` | No — Wave 0 |
| BOARD-09 | `advance_thread_read_pointer/3` upserts correctly | unit | `mix test test/foglet_bbs/threads/threads_test.exs` | No — Wave 0 |
| BOARD-10 | `unread_count/2` returns correct count per board | unit | `mix test test/foglet_bbs/boards/boards_test.exs` | No — Wave 0 |
| BOARD-10 | `unread_counts/1` returns map of board_id → count | unit | `mix test test/foglet_bbs/boards/boards_test.exs` | No — Wave 0 |
| BOARD-11 | `delete_post/2` sets `deleted_at`; message number is preserved (no gap filling) | unit | `mix test test/foglet_bbs/posts/posts_test.exs` | No — Wave 0 |
| BOARD-12 | `lock_thread/1` sets `locked: true` | unit | `mix test test/foglet_bbs/threads/threads_test.exs` | No — Wave 0 |
| BOARD-12 | `sticky_thread/1` sets `sticky: true` | unit | `mix test test/foglet_bbs/threads/threads_test.exs` | No — Wave 0 |
| BOARD-12 | `move_thread/3` updates `board_id` on thread and all posts | unit | `mix test test/foglet_bbs/threads/threads_test.exs` | No — Wave 0 |

### Sampling Rate
- **Per task commit:** `mix precommit && mix test test/foglet_bbs/boards/ test/foglet_bbs/threads/ test/foglet_bbs/posts/`
- **Per wave merge:** `mix precommit && mix test`
- **Phase gate:** `mix precommit && mix test` — full suite green before verification

### Wave 0 Gaps

- [ ] `test/foglet_bbs/boards/boards_test.exs` — context tests (BOARD-01, BOARD-07, BOARD-08, BOARD-10)
- [ ] `test/foglet_bbs/boards/board_server_test.exs` — GenServer + property test (BOARD-06)
- [ ] `test/foglet_bbs/threads/threads_test.exs` — context tests (BOARD-02, BOARD-09, BOARD-12)
- [ ] `test/foglet_bbs/posts/posts_test.exs` — context tests (BOARD-03, BOARD-04, BOARD-11)
- [ ] `test/foglet_bbs/markdown_test.exs` — render output tests (BOARD-05)
- [ ] `test/support/boards_fixtures.ex` — board, category, thread, post creation helpers
- [ ] Add `{Registry, keys: :unique, name: Foglet.BoardRegistry}` to test application start if not already present

---

## Security Domain

### Applicable ASVS Categories (ASVS L1)

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No (no new auth in Phase 2) | — |
| V4 Access Control | Partial | Thread lock/sticky/move are mod/sysop-only — enforced at context layer; Phase 2 adds the domain functions; Phase 7 enforces role gating |
| V5 Input Validation | Yes | Ecto changesets validate required fields, string lengths, and enum values |
| V7 Error Handling | Partial | Board Server `handle_call` returns `{:error, reason}` on Multi failure; callers must handle |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Post body injection (ANSI escape injection) | Tampering | Store raw Markdown; `Foglet.Markdown.render/1` generates ANSI escapes from parsed AST — user cannot inject raw escape codes (MDEx parses Markdown, not passthrough HTML) |
| Message-number race (concurrent inserts bypassing Board Server) | Tampering | DB-level `UNIQUE (board_id, message_number)` is the backstop; application enforces via GenServer serialization |
| Post edit by non-author | Elevation of Privilege | `edit_post/3` takes `user_id`; context validates `post.user_id == user_id`; mods use a separate pathway |
| Soft-delete bypass (read deleted posts) | Information Disclosure | Queries filter `WHERE deleted_at IS NULL` by default; deleted post body shown as tombstone text |
| Thread move exposing private board posts | Information Disclosure | Phase 2 implements move; access control enforcement is Phase 7; document that `readable_by` checks are Phase 3+ |
| Concurrent subscribe_to_defaults duplicate | — | Upsert with `on_conflict: :nothing` prevents duplicate subscription rows |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | MDEx version `~> 0.2` is current stable | Standard Stack | Check hex.pm for latest; MDEx is actively developed |
| A2 | MDEx ships pre-compiled NIF binaries for macOS arm64 and Linux x86_64 | Pitfall 8 | If not, Rust toolchain required in CI — add to CI config |
| A3 | `body_tsv` generated column should be omitted from Ecto schema in Phase 2 | Pitfall 4 | If Phase 9 adds it to the schema, no migration needed — just add the field declaration |
| A4 | Thread move should NOT renumber posts (accepts message number gaps in new board) | Pitfall 7 | DATA_MODEL.md says "without breaking message-number continuity" — could mean renumbering; interpretation is that continuity = no gaps IN ORIGINAL BOARD, not in new board |
| A5 | Default seeds: one category ("General"), one board ("General", `default_subscription: true`) | Code Examples | Sysop can create more from Phase 8 TUI; one default board is sufficient for Phase 3 testing |
| A6 | `subscribe_to_defaults/1` should be called AFTER user insert, not inside the user Multi | Pattern 8 | CONTEXT.md says "either is fine; prefer the Multi for atomicity" — if inside Multi, test that subscription failure doesn't roll back user creation |

---

## Open Questions

1. **Thread move and message-number continuity:**
   - BOARD-12 says "moved between boards without breaking message-number continuity"
   - DATA_MODEL.md unique constraint is `(board_id, message_number)` — moved posts would have numbers that exist in the destination board
   - Resolution: "continuity" means the ORIGINAL board's sequence isn't broken; the moved posts carry their original numbers into the new board. This CAN create conflicts. Practical solution: new board numbers don't re-check moved posts' numbers (they belong to a different thread origin). **Document this limitation in the thread move code.** No redesign needed in Phase 2.

2. **Board Server and the `boards.next_message_number` counter:**
   - D-05 says the Server reloads from `MAX(message_number)` on crash, but also says `next_message_number` is updated on every insert
   - If we reload from `MAX(message_number)` on startup, the persisted counter is a warm cache but not strictly needed
   - Resolution: Keep updating `next_message_number` on every insert (it's in the Multi, cheap), and reload from `MAX(message_number)` on startup (as D-05 specifies). Both are consistent with DATA_MODEL.md.

---

## Sources

### Primary (HIGH confidence)
- `docs/DATA_MODEL.md` — authoritative schema definitions, migration notes, insertion flow diagrams
- `docs/ARCHITECTURE.md` — supervision tree target shape (§2), ephemeral state (§6), DynamicSupervisor pattern
- `.planning/phases/02-domain-core/02-CONTEXT.md` — locked decisions D-01 through D-06
- `lib/foglet_bbs/accounts.ex` — existing `create_user/1` interface (what Phase 2 modifies)
- `lib/foglet_bbs/application.ex` — current supervision tree (what Phase 2 extends)
- `lib/foglet_bbs/schema.ex` — existing `Foglet.Schema` macro (all new schemas use this)
- `mix.exs` — confirms StreamData in deps; no MDEx yet
- `CLAUDE.md` — project-specific guidelines (Ecto types, OTP naming, test patterns)

### Secondary (MEDIUM confidence)
- Hex.pm/MDEx documentation — `to_html!/2` API, extension options
- Ecto.Adapters.SQL.Sandbox.allow/3 documentation — concurrent test sandbox sharing
- ExUnitProperties / StreamData docs — property test patterns

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — verified against existing mix.exs, DATA_MODEL.md, existing code
- Architecture: HIGH — DATA_MODEL.md and ARCHITECTURE.md are authoritative references
- Pitfalls: HIGH — sourced from Ecto/OTP behavior analysis and CLAUDE.md constraints
- MDEx API: MEDIUM — verified against hex.pm readme; specific options may need adjustment

**Research date:** 2026-04-18
**Valid until:** 2026-05-18 (stable ecosystem)

## Project Constraints (from CLAUDE.md)

| Directive | Impact on Phase 2 |
|-----------|------------------|
| `use Layouts.app flash={@flash}` in LiveViews | Not applicable — no LiveViews in Phase 2 |
| Use `mix precommit` alias for quality gate | Each commit must pass `mix precommit` |
| Use `Req` for HTTP; avoid httpoison/tesla | Not applicable — no HTTP calls in Phase 2 |
| Lists do not support index access `list[i]` | Use `Enum.at/2` if index access needed in contexts |
| Bind result of `if`/`case`/`cond` outside block | Critical for socket pattern; applies to any conditional in GenServer state updates |
| Never nest multiple modules in same file | 11 new schema/context/supervisor files — each in its own file |
| Never use map access syntax on structs | `Ecto.Changeset.get_field/2` for changeset reads; `struct.field` for schema fields |
| `validate_number/2` does not support `:allow_nil` | Avoid on any numeric changeset validation (message_number, post_count, etc.) |
| Fields set programmatically must not be in `cast` | `user_id`, `board_id`, `thread_id`, `message_number`, `edit_count` — set explicitly, not cast |
| Use `start_supervised!/1` in tests | Board Server tests must use this |
| Avoid `Process.sleep/1` in tests | Use `:sys.get_state/1` for GenServer synchronization |
| `Ecto.Schema` fields use `:string` even for text | `field :body, :string` not `:text`; `field :previous_body, :string` not `:text` |
| Run `mix ecto.gen.migration` to generate migrations | Required — never create migration files manually |
| Predicate functions must not start with `is_` | `locked?/1`, `sticky?/1`, `deleted?/1` — not `is_locked`, `is_sticky` |
| `Task.async_stream` with `timeout: :infinity` | Use for concurrent enumeration in property tests and board boot |

---

## RESEARCH COMPLETE

Phase 2 research is complete. Key findings:

1. **One new dependency:** MDEx (`~> 0.2`) for Markdown rendering — add to `mix.exs`.
2. **Circular FK complexity:** `threads.first_post_id` requires three-step Multi (thread → post → update thread). A separate `alter table` step handles the FK after posts table exists.
3. **Generated column:** `posts.body_tsv` uses raw SQL (`execute/1`) in the migration; omit from Ecto schema in Phase 2.
4. **Board Server boot order:** Registry must be started before Boards.Supervisor; board servers boot AFTER application supervision tree is up.
5. **Thread move complexity:** Moving a thread requires updating `posts.board_id` for all posts in the thread; message number gaps in the destination board are acceptable and documented.
6. **Ecto sandbox for concurrent tests:** `Sandbox.allow/3` required for property tests spawning concurrent tasks.
7. **9 new migrations** required (categories, boards, board_subscriptions, board_read_pointers, threads, posts, post_edits, upvotes, thread_read_pointers).
8. **Phase split recommendation:** No — 12 requirements map naturally to 4-5 plans (migrations + schemas, Board Server, contexts + seed, Markdown + tests).
