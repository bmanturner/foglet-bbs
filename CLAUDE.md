This is a web application written using the Phoenix web framework.

## Project guidelines

- Run `mix precommit` when you are done with all changes and fix any pending issues. It runs `compile --warnings-as-errors`, `format`, `credo --strict`, `sobelow`, and `dialyzer` — trust it to catch formatting, predicate names, `String.to_atom` misuse, list-Access warnings, and type/security issues so this file doesn't have to.
- Use the already included `:req` (`Req`) library for HTTP requests. **Avoid** `:httpoison`, `:tesla`, and `:httpc`.
- Prefer Elixir's stdlib (`Time`, `Date`, `DateTime`, `Calendar`) for date/time work. **Never** add a dep for this unless asked — `date_time_parser` is the only sanctioned exception (parsing).

## Project docs

Consult these before making non-trivial changes in the relevant area:

- `docs/ARCHITECTURE.md` — system architecture, module boundaries, the "why" behind major structural decisions.
- `docs/DATA_MODEL.md` — schemas, relationships, invariants. Read before touching Ecto schemas or migrations.
- `docs/ROADMAP.md` — milestone scope and sequencing.
- `docs/raxol/` — vendored Raxol documentation. Reach for this whenever you're reading or writing Raxol code; start at `docs/raxol/README.md`.
  - **TUI work:** `docs/raxol/getting-started/WIDGET_GALLERY.md` for the primitives we have available, plus `lib/foglet_bbs/tui/widgets/README.md` for an overview of the themed widgets we have in foglet_bbs
  - **ADRs / deeper dives:** `docs/raxol/adr/`, `docs/raxol/core/`, `docs/raxol/guides/`.
- `.planning/` — GSD planning artifacts (requirements, ADRs, phase plans, verification). Search here for the reasoning behind existing decisions before proposing changes to them.

## Elixir gotchas

These aren't caught by precommit — keep them in mind:

- **Block expressions rebind, they don't mutate.** In `if`/`case`/`cond`, bind the whole expression to a variable; don't try to reassign inside the block:

      # INVALID — rebind inside `if` is lost
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        else
          socket
        end

- **Never nest multiple modules in the same file** — causes cyclic dependency and compilation headaches.
- **Structs don't implement `Access`.** Use `my_struct.field` directly, or `Ecto.Changeset.get_field/2` for changesets — never `struct[:field]`.
- **OTP primitives need names in the child spec.** `DynamicSupervisor` and `Registry` require `name:` in their child_spec so you can address them later:

      {DynamicSupervisor, name: MyApp.MyDynamicSup}

- **Concurrent enumeration:** use `Task.async_stream(collection, callback, options)` with `timeout: :infinity` in almost all cases — it gives you back-pressure for free.

## Mix

- Read `mix help <task>` before reaching for unfamiliar tasks.
- Debug a single test file with `mix test path/to/test.exs`; re-run only failures with `mix test --failed`.
- `mix deps.clean --all` is almost never the right answer — diagnose first.

## Test guidelines

- **Always use `start_supervised!/1`** to start processes in tests — it guarantees cleanup between tests.
- **Avoid `Process.sleep/1` and `Process.alive?/1`.** Synchronize deterministically instead:
  - To wait for a process to finish, monitor it and assert on `:DOWN`:

        ref = Process.monitor(pid)
        assert_receive {:DOWN, ^ref, :process, ^pid, :normal}

  - To wait until a process has handled prior messages, use `_ = :sys.get_state(pid)`.

## Phoenix

- Phoenix router `scope` blocks carry an optional alias that prefixes every route inside. Don't double-alias — `scope "/admin", AppWeb.Admin do live "/users", UserLive end` already resolves to `AppWeb.Admin.UserLive`.

## Ecto

- **Preload associations** in the query when they'll be accessed later (templates, JSON serializers) — don't rely on lazy loads that don't exist.
- Remember to `import Ecto.Query` (and friends) when writing `seeds.exs`.
- `Ecto.Schema` uses `:string` for both `:string` and `:text` DB columns: `field :name, :string`.
- Programmatically-set fields like `user_id` must **not** appear in `cast/3` — set them explicitly on the struct before changeset construction.
- Generate migrations with `mix ecto.gen.migration migration_name_using_underscores` so timestamps and naming stay consistent.