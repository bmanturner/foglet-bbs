---
quick_id: 260422-irb
phase: quick-260422-irb
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - lib/foglet_bbs/config/schema.ex
  - lib/foglet_bbs/config/unknown_key_error.ex
  - lib/foglet_bbs/config/invalid_value_error.ex
  - lib/foglet_bbs/config.ex
  - priv/repo/seeds.exs
  - test/foglet_bbs/config_test.exs
  - lib/foglet_bbs/accounts.ex
  - lib/foglet_bbs/ssh/cli_handler.ex
  - lib/foglet_bbs/tui/screens/verify.ex
  - docs/DATA_MODEL.md
autonomous: true
requirements: [260422-irb]
tags: [config, schema, validation, typed-accessors, elixir, ecto]

must_haves:
  truths:
    - "Foglet.Config.Schema.entries/0 returns exactly 6 spec maps: registration_mode, invite_code_generators, max_post_length, max_thread_title_length, require_email_verification, email_verify_resend_cooldown_seconds"
    - "Foglet.Config.Schema.validate/2 returns :ok for valid values and {:error, %{reason: ..., expected: ..., got: ...}} for type/enum/range violations, and {:error, {:unknown_key, key}} for keys not in the schema"
    - "Foglet.Config.fetch/1 returns {:ok, value} on present key (matching Map.fetch/2 stdlib shape) and :error on Ecto.NoResultsError"
    - "Foglet.Config.put!/3 raises Foglet.Config.UnknownKeyError when the key is not in Foglet.Config.Schema"
    - "Foglet.Config.put!/3 raises Foglet.Config.InvalidValueError when the value fails type/enum/range validation against the schema"
    - "Foglet.Config.put!/3 still succeeds (DB upsert + ETS invalidation) for valid schematized values — no regression to existing behaviour"
    - "Six typed accessors exist on Foglet.Config — registration_mode/0, invite_code_generators/0, max_post_length/0, max_thread_title_length/0, require_email_verification?/0, email_verify_resend_cooldown_seconds/0 — each with @spec and @doc"
    - "priv/repo/seeds.exs iterates Foglet.Config.Schema.entries/0 and inserts each default with description on first insert (existing rows unchanged)"
    - "The 4 identified callsites (accounts.ex, cli_handler.ex:340, cli_handler.ex:347, verify.ex:278) use typed accessors"
    - "docs/DATA_MODEL.md §11 line 686 no longer states the dot-form is deprecated/aspirational — it states snake_case is the canonical form"
    - "mix precommit passes (compile --warnings-as-errors, format, credo --strict, sobelow, dialyzer) and the full test suite is green"
  artifacts:
    - path: "lib/foglet_bbs/config/schema.ex"
      provides: "Pure data module with @entries list, @spec_map lookup, entries/0, fetch_spec/1, validate/2, defaults/0"
      contains: "defmodule Foglet.Config.Schema"
    - path: "lib/foglet_bbs/config/unknown_key_error.ex"
      provides: "defexception for put!/3 on keys outside the schema"
      contains: "defexception [:key]"
    - path: "lib/foglet_bbs/config/invalid_value_error.ex"
      provides: "defexception for put!/3 on values that fail validation"
      contains: "defexception [:key, :reason, :expected, :got]"
    - path: "lib/foglet_bbs/config.ex"
      provides: "fetch/1, validated put!/3, 6 typed accessors — preserves get!/1, get/2, init_cache/0, invalidate/1"
      exports: ["fetch/1", "registration_mode/0", "invite_code_generators/0", "max_post_length/0", "max_thread_title_length/0", "require_email_verification?/0", "email_verify_resend_cooldown_seconds/0"]
    - path: "priv/repo/seeds.exs"
      provides: "Config block regenerated from Foglet.Config.Schema.entries/0"
      contains: "Schema.entries()"
    - path: "test/foglet_bbs/config_test.exs"
      provides: "Cache tests rewritten against real schema keys; new tests for fetch/1, validation exceptions, typed accessors"
    - path: "docs/DATA_MODEL.md"
      provides: "§11 line 686 updated — snake_case stated as canonical, deprecated-note removed"
  key_links:
    - from: "lib/foglet_bbs/config.ex (put!/3)"
      to: "lib/foglet_bbs/config/schema.ex (validate/2)"
      via: "Schema.validate(key, value) called before DB write; :ok proceeds, {:error, _} raises"
      pattern: "Schema\\.validate\\("
    - from: "lib/foglet_bbs/config.ex (put!/3)"
      to: "Foglet.Config.UnknownKeyError, Foglet.Config.InvalidValueError"
      via: "raise on validate/2 error tuple"
      pattern: "raise Foglet\\.Config\\.(UnknownKey|InvalidValue)Error"
    - from: "lib/foglet_bbs/config.ex (fetch/1)"
      to: "Foglet.Config.get!/1 + Ecto.NoResultsError rescue"
      via: "rescue clause converts exception → :error"
      pattern: "rescue\\s+Ecto\\.NoResultsError"
    - from: "priv/repo/seeds.exs"
      to: "Foglet.Config.Schema.entries/0"
      via: "Enum.each over entries, calls Config.put!/3 then sets description on first insert"
      pattern: "Schema\\.entries\\(\\)"
    - from: "lib/foglet_bbs/accounts.ex post_login_screen/1"
      to: "Foglet.Config.require_email_verification?/0"
      via: "direct call; replaces Foglet.Config.get(\"require_email_verification\", true)"
      pattern: "Config\\.require_email_verification\\?"
    - from: "lib/foglet_bbs/ssh/cli_handler.ex"
      to: "Foglet.Config.registration_mode/0 and Foglet.Config.max_post_length/0"
      via: "direct calls replace get!/1 try/rescue blocks"
      pattern: "Config\\.(registration_mode|max_post_length)\\(\\)"
    - from: "lib/foglet_bbs/tui/screens/verify.ex resend_cooldown_seconds/0"
      to: "Foglet.Config.email_verify_resend_cooldown_seconds/0"
      via: "direct call replaces Foglet.Config.get/2 with integer guard"
      pattern: "Config\\.email_verify_resend_cooldown_seconds"
---

<objective>
Build a typed config schema (`Foglet.Config.Schema`) that serves as the source of truth for the 6 currently-seeded runtime configuration keys, add strict write-time validation to `Foglet.Config.put!/3`, introduce stdlib-canonical `Foglet.Config.fetch/1` (`{:ok, value} | :error`), expose explicit typed accessors for each schematized key, regenerate `priv/repo/seeds.exs` from the schema, rewrite cache-behaviour tests against real schema keys, migrate the 4 identified callsites to typed accessors, and retire the "dot-form deprecated" note in `docs/DATA_MODEL.md` §11.

Purpose: Today `Foglet.Config` is stringly-typed and permissive — `get/2` conflates "key missing" with "DB returned default", and there is no central declaration of what a valid config key or value looks like. This plan establishes a pure-data schema module that is easy to iterate (seeds), introspect (future sysop TUI), and validate (write-time), without pulling Ecto into the schema module itself. The test carve-out uses real schema keys (Option B1 from RESEARCH.md) so there's no `put_raw!` escape hatch to maintain.

Output: Working, tested, Dialyzer-clean typed config schema with 6 schematized keys, strict `put!/3`, and `fetch/1`. All existing `Foglet.Config` public API (`get!/1`, `get/2`, `put!/3`, `invalidate/1`, `init_cache/0`) preserved. `mix precommit` green.
</objective>

<execution_context>
@/Users/brendan.turner/Dev/personal/foglet_bbs/.claude/get-shit-done/workflows/execute-plan.md
@/Users/brendan.turner/Dev/personal/foglet_bbs/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@/Users/brendan.turner/Dev/personal/foglet_bbs/.planning/quick/260422-irb-build-a-typed-config-schema-with-accesso/260422-irb-CONTEXT.md
@/Users/brendan.turner/Dev/personal/foglet_bbs/.planning/quick/260422-irb-build-a-typed-config-schema-with-accesso/260422-irb-RESEARCH.md
@/Users/brendan.turner/Dev/personal/foglet_bbs/CLAUDE.md
@/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/config.ex
@/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/config/entry.ex
@/Users/brendan.turner/Dev/personal/foglet_bbs/priv/repo/seeds.exs
@/Users/brendan.turner/Dev/personal/foglet_bbs/test/foglet_bbs/config_test.exs
@/Users/brendan.turner/Dev/personal/foglet_bbs/docs/DATA_MODEL.md

<interfaces>
<!-- Key contracts executors must respect. Extracted from codebase + RESEARCH.md. -->
<!-- Do not re-explore the codebase for these — they are the contracts. -->

Existing, unchanged contracts (from `lib/foglet_bbs/config/entry.ex` and `lib/foglet_bbs/config.ex`):

```elixir
# Foglet.Config.Entry — Ecto schema (unchanged by this plan)
schema "configuration" do
  field :key, :string
  field :value, :map           # values are wrapped as %{"v" => actual} for jsonb
  field :description, :string
  belongs_to :updated_by, Foglet.Accounts.User
  timestamps(type: :utc_datetime_usec)
end

# Foglet.Config public API (preserved — additions layer on top)
@spec init_cache() :: :ok
@spec get!(String.t()) :: term()                         # raises Ecto.NoResultsError on miss
@spec get(String.t(), term()) :: term()                  # default on miss; DB errors propagate
@spec put!(String.t(), term(), String.t() | nil) :: Entry.t()
@spec invalidate(String.t()) :: :ok
```

New contracts to be established by this plan:

```elixir
# lib/foglet_bbs/config/schema.ex — PURE DATA. No Repo/Ecto deps.
defmodule Foglet.Config.Schema do
  # @entries is a compile-time literal list of 6 maps, shape:
  #   %{key: String.t(), type: :string | :integer | :boolean,
  #     default: term(), description: String.t(),
  #     enum: [String.t()] | nil, min: integer() | nil, max: integer() | nil}

  @spec entries() :: [map()]
  @spec fetch_spec(String.t()) :: {:ok, map()} | :error
  @spec defaults() :: %{optional(String.t()) => term()}
  @spec validate(String.t(), term()) ::
          :ok
          | {:error, {:unknown_key, String.t()}}
          | {:error, %{reason: atom(), expected: term(), got: term()}}
end

# lib/foglet_bbs/config/unknown_key_error.ex
defmodule Foglet.Config.UnknownKeyError do
  defexception [:key]
  @impl true
  def message(%__MODULE__{key: key}), do: "unknown config key #{inspect(key)} ..."
end

# lib/foglet_bbs/config/invalid_value_error.ex
defmodule Foglet.Config.InvalidValueError do
  defexception [:key, :reason, :expected, :got]
  @impl true
  def message(%__MODULE__{...}), do: ...   # one clause per reason
end

# Additions to Foglet.Config
@spec fetch(String.t()) :: {:ok, term()} | :error
# (matches Map.fetch/2 / Keyword.fetch/2 / Access.fetch/2 — D-03)

@spec registration_mode() :: String.t()
@spec invite_code_generators() :: String.t()
@spec max_post_length() :: integer()
@spec max_thread_title_length() :: integer()
@spec require_email_verification?() :: boolean()
@spec email_verify_resend_cooldown_seconds() :: integer()
```

The 6 schematized keys (D-06 — authoritative; matches seeds.exs today):

| key | type | default | enum | min | max |
|---|---|---|---|---|---|
| registration_mode | :string | "open" | ["open", "invite_only", "sysop_approved"] | nil | nil |
| invite_code_generators | :string | "sysop_only" | ["sysop_only", "mods", "any_user"] | nil | nil |
| max_post_length | :integer | 8192 | nil | 1 | nil |
| max_thread_title_length | :integer | 60 | nil | 1 | nil |
| require_email_verification | :boolean | true | nil | nil | nil |
| email_verify_resend_cooldown_seconds | :integer | 60 | nil | 0 | nil |

Descriptions (from current seeds.exs lines 43-55 — preserve verbatim so re-seeding a clean DB produces identical description text):

- registration_mode: "Account registration policy (D-02/D-03): open | invite_only | sysop_approved"
- invite_code_generators: "Who may generate invite codes (D-04): sysop_only | mods | any_user"
- max_post_length: "Maximum post body length in characters (D-31)"
- max_thread_title_length: "Maximum thread title length in characters (D-13, phase-03-polish Phase 4)"
- require_email_verification: "When false, new registrations skip verify and existing confirmed_at: nil users gain access on login (Phase 6 D-01)"
- email_verify_resend_cooldown_seconds: "Minimum seconds between resend-code presses on the Verify screen (Phase 6 D-02)"
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Build Foglet.Config.Schema + exception modules (pure data layer)</name>
  <files>
    lib/foglet_bbs/config/schema.ex,
    lib/foglet_bbs/config/unknown_key_error.ex,
    lib/foglet_bbs/config/invalid_value_error.ex,
    test/foglet_bbs/config/schema_test.exs
  </files>
  <behavior>
    Schema.entries/0:
      - Returns a list of exactly 6 maps in the order listed in the interface table above.
      - Each map has keys :key, :type, :default, :description, :enum, :min, :max (enum/min/max are nil when not applicable).

    Schema.fetch_spec/1 (binary key):
      - "registration_mode" → {:ok, %{key: "registration_mode", type: :string, default: "open", enum: ["open","invite_only","sysop_approved"], ...}}
      - "not_a_real_key" → :error
      - Shape matches Map.fetch/2 (stdlib-canonical).

    Schema.defaults/0:
      - Returns %{"registration_mode" => "open", "invite_code_generators" => "sysop_only", "max_post_length" => 8192, "max_thread_title_length" => 60, "require_email_verification" => true, "email_verify_resend_cooldown_seconds" => 60}.

    Schema.validate/2:
      - ("registration_mode", "open") → :ok
      - ("registration_mode", "nonsense") → {:error, %{reason: :not_in_enum, expected: ["open","invite_only","sysop_approved"], got: "nonsense"}}
      - ("registration_mode", 42) → {:error, %{reason: :type_mismatch, expected: :string, got: 42}}
      - ("max_post_length", 8192) → :ok
      - ("max_post_length", 0) → {:error, %{reason: :below_min, expected: 1, got: 0}}
      - ("max_post_length", "nope") → {:error, %{reason: :type_mismatch, expected: :integer, got: "nope"}}
      - ("require_email_verification", true) → :ok
      - ("require_email_verification", "true") → {:error, %{reason: :type_mismatch, expected: :boolean, got: "true"}}
      - ("email_verify_resend_cooldown_seconds", 0) → :ok   # min: 0 inclusive
      - ("email_verify_resend_cooldown_seconds", -1) → {:error, %{reason: :below_min, expected: 0, got: -1}}
      - ("not_a_real_key", anything) → {:error, {:unknown_key, "not_a_real_key"}}

    UnknownKeyError:
      - Exception.message(%UnknownKeyError{key: "foo"}) contains the string "foo" and the substring "unknown config key".

    InvalidValueError:
      - For reason: :type_mismatch, message mentions key, expected (type atom), got.
      - For reason: :not_in_enum, message mentions allowed values and got.
      - For reason: :below_min, message mentions min and got.
      - For reason: :above_max, message mentions max and got (even though no current key uses :max — keep the clause for symmetry and future schematized keys).
  </behavior>
  <action>
    Implement three files per the interfaces block. Strictly one module per file (CLAUDE.md gotcha).

    1. `lib/foglet_bbs/config/schema.ex` — plain data module. Per RESEARCH.md §"Recommended validate/2 shape" and D-02:

       - `@moduledoc` explains this is the source of truth for runtime-editable sysop config, references `docs/DATA_MODEL.md` §11, and notes that aspirational keys listed in DATA_MODEL.md are intentionally NOT schematized in this phase (per D-06).
       - `@entries` — literal compile-time list of 6 maps in the order from the interfaces table above. Use the exact description strings from the interfaces block (verbatim from current seeds.exs) so re-seeding a clean DB is byte-identical for the description column.
       - `@spec_map` — derived at compile time via `Map.new(@entries, &{&1.key, &1})` for O(1) lookup.
       - `entries/0`, `fetch_spec/1`, `defaults/0` as specified. All public functions get `@spec` and `@doc`. `fetch_spec/1` guards on `is_binary(key)`.
       - `validate/2`: returns maps, NOT keyword lists, for the error payload (per Claude's Discretion note in RESEARCH.md §"Raise site" — cleaner than destructuring keywords at the raise site). Shape: `:ok | {:error, {:unknown_key, String.t()}} | {:error, %{reason: atom(), expected: term(), got: term()}}`.
       - Internal `check/2` private function dispatches on `spec.type`. Use pattern matching on the map shape (NOT Access, per CLAUDE.md gotcha — `spec.type`, not `spec[:type]`). Handle :string, :integer, :boolean. Any other type is a bug — let it fail the function-clause match loudly.
       - `check_enum/2` — if `spec.enum` is nil, `:ok`; else `if value in allowed, do: :ok, else: {:error, %{reason: :not_in_enum, expected: allowed, got: value}}`.
       - `check_range/2` — walk min then max. Inclusive bounds (min: 0 allows 0; min: 1 rejects 0).
       - NO `String.to_atom/1` anywhere (CLAUDE.md). Types are hardcoded atoms in `@entries`.
       - NO `Ecto`, NO `Repo`, NO `alias` pointing at either. Pure data.

    2. `lib/foglet_bbs/config/unknown_key_error.ex`:

       - `defexception [:key]`
       - `@impl true` on `message/1`. Message form: `~s(unknown config key #{inspect(key)} — add it to Foglet.Config.Schema or use Foglet.Config.Entry directly)`.
       - `@moduledoc` one-liner pointing at `Foglet.Config.Schema`.

    3. `lib/foglet_bbs/config/invalid_value_error.ex`:

       - `defexception [:key, :reason, :expected, :got]`.
       - Four `message/1` clauses, one per `:type_mismatch | :not_in_enum | :below_min | :above_max`. Use `@impl true` on each (or once at the top of the clause group — `@impl true` carries through adjacent clauses; match the Raxol/project style if inspecting `lib/`). Message text per RESEARCH.md §"Exception modules".
       - Even though no current key uses `:max`, include the `:above_max` clause so future schematized keys don't crash on format.

    4. `test/foglet_bbs/config/schema_test.exs` — new test file. Use `use ExUnit.Case, async: true` (pure data, no DB). Test each behaviour bullet. Group with `describe` per public function. Include at least one assertion that `Exception.message(%Foglet.Config.InvalidValueError{...})` produces a string containing the expected substrings for each `:reason`.

    Do NOT touch `Foglet.Config` (lib/foglet_bbs/config.ex) in this task — that is Task 2. Keep this task focused on the pure-data layer so Task 2 can build against stable contracts.

    `mix precommit`-specific reminders:
      - Every public function gets `@spec` (dialyzer gate).
      - Every public function gets `@doc` (credo --strict preference).
      - Format with `mix format` before committing.
      - Credo may complain about the `:above_max` clause being unreachable — that's acceptable because the message callback is an exhaustive handler; if credo does flag it, keep the clause and add a moduledoc line noting "`:above_max` is reserved for future schematized keys with max bounds."
  </action>
  <verify>
    <automated>mix test test/foglet_bbs/config/schema_test.exs --trace</automated>
    <automated>mix compile --warnings-as-errors --force 2>&1 | grep -E "(warning|error)" || echo "clean"</automated>
    <automated>mix format --check-formatted lib/foglet_bbs/config/schema.ex lib/foglet_bbs/config/unknown_key_error.ex lib/foglet_bbs/config/invalid_value_error.ex test/foglet_bbs/config/schema_test.exs</automated>
  </verify>
  <done>
    - Three new source files exist, one module per file, under `lib/foglet_bbs/config/`.
    - `Foglet.Config.Schema.entries/0` returns 6 maps with the locked specs (key, type, default, description, enum, min, max).
    - `Foglet.Config.Schema.validate/2` round-trips all behaviour cases from the `<behavior>` block as asserted by `test/foglet_bbs/config/schema_test.exs`.
    - `Foglet.Config.UnknownKeyError` and `Foglet.Config.InvalidValueError` produce human-readable messages via `Exception.message/1` for every reason atom.
    - `mix compile --warnings-as-errors --force` reports no warnings or errors.
    - `mix format --check-formatted` passes for the 4 new files.
    - `mix test test/foglet_bbs/config/schema_test.exs` is green.
  </done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Integrate Schema into Foglet.Config — fetch/1, validated put!/3, 6 typed accessors</name>
  <files>
    lib/foglet_bbs/config.ex,
    test/foglet_bbs/config_test.exs
  </files>
  <behavior>
    Foglet.Config.fetch/1 (binary key):
      - On key present in DB → {:ok, value} (same value get!/1 would return; uses ETS cache just like get!/1 does).
      - On key missing → :error (NOT {:error, :not_found}; stdlib-canonical per D-03).
      - Populates ETS on the present path, exactly like get!/1 (reuses get!/1 internally so ETS caching is not reimplemented).
      - DB connection errors propagate (not rescued).

    Foglet.Config.put!/3 (wrapping Schema.validate/2):
      - put!("registration_mode", "invite_only", nil) → succeeds; DB write + ETS invalidation as before.
      - put!("registration_mode", "bogus", nil) → raises Foglet.Config.InvalidValueError{key: "registration_mode", reason: :not_in_enum, expected: ["open","invite_only","sysop_approved"], got: "bogus"}.
      - put!("max_post_length", 0, nil) → raises Foglet.Config.InvalidValueError{key: "max_post_length", reason: :below_min, expected: 1, got: 0}.
      - put!("max_post_length", "nope", nil) → raises Foglet.Config.InvalidValueError{key: "max_post_length", reason: :type_mismatch, expected: :integer, got: "nope"}.
      - put!("not_a_real_key", 1, nil) → raises Foglet.Config.UnknownKeyError{key: "not_a_real_key"}. DB is NOT written, ETS is NOT touched.
      - put!("require_email_verification", false, nil) → succeeds; subsequent get!/1 returns false.
      - Must preserve existing behaviour for all valid writes (ETS invalidation, description untouched, updated_by_id propagated).

    Six typed accessors, each backed by get!/1:
      - Foglet.Config.registration_mode() → "open" (in a freshly-seeded DB)
      - Foglet.Config.invite_code_generators() → "sysop_only"
      - Foglet.Config.max_post_length() → 8192
      - Foglet.Config.max_thread_title_length() → 60
      - Foglet.Config.require_email_verification?() → true
      - Foglet.Config.email_verify_resend_cooldown_seconds() → 60

    ETS cache tests rewritten against real schema keys (registration_mode for string, max_post_length for integer, require_email_verification for boolean) — round-trip, ETS caching, invalidate, put!/3 invalidation, get/2 default — all preserved at the behaviour level, just using real keys.

    get!/1 on a key that exists in the schema but not in the DB still raises Ecto.NoResultsError (nothing changes for the read path when Schema is purely a write-validation layer).
  </behavior>
  <action>
    Modify `lib/foglet_bbs/config.ex` in place. Additions layer on top; do NOT break or remove any existing public function.

    Additions (in this recommended order inside the module):

    1. Add `alias Foglet.Config.Schema` and, where convenient, `alias Foglet.Config.{InvalidValueError, UnknownKeyError}` at the top.

    2. `fetch/1` (new public function, placed near get!/1 and get/2):

       ```
       @doc ~S"""
       Structured lookup: returns `{:ok, value}` if the key is present in the
       configuration DB, `:error` if it is missing. Matches the stdlib
       `Map.fetch/2` / `Keyword.fetch/2` shape.

       DB errors propagate as exceptions; only missing-key is converted to `:error`.
       """
       @spec fetch(String.t()) :: {:ok, term()} | :error
       def fetch(key) when is_binary(key) do
         {:ok, get!(key)}
       rescue
         Ecto.NoResultsError -> :error
       end
       ```

       Reuses `get!/1` so the ETS caching path is shared and there is no second code path to keep in sync.

    3. Refactor `put!/3` to validate against `Schema` BEFORE touching the DB. Per RESEARCH.md §"Raise site" — but use the cleaner map-shaped validate/2 payload (since Task 1 returned `%{reason, expected, got}` maps, not keyword lists):

       ```
       def put!(key, value, updated_by_id \\ nil) when is_binary(key) do
         case Schema.validate(key, value) do
           :ok ->
             do_put!(key, value, updated_by_id)

           {:error, {:unknown_key, ^key}} ->
             raise UnknownKeyError, key: key

           {:error, %{reason: reason, expected: expected, got: got}} ->
             raise InvalidValueError,
               key: key, reason: reason, expected: expected, got: got
         end
       end
       ```

       Move the existing body of put!/3 into a private `do_put!/3` (init_cache, wrapped, Entry upsert, invalidate, return entry). Do NOT duplicate logic — the existing ETS/DB interaction stays byte-identical, only gated behind validation.

       Note the block-rebind gotcha (CLAUDE.md): bind the whole `case` expression if you capture a result — don't try to mutate inside branches.

    4. Six typed accessors (one `@doc` + one `@spec` each). Place at the end of the module's public section, before `# ---------- Private ----------`:

       ```
       @doc "Account registration policy (D-02/D-03). See Foglet.Config.Schema."
       @spec registration_mode() :: String.t()
       def registration_mode, do: get!("registration_mode")

       @doc "Who may generate invite codes (D-04)."
       @spec invite_code_generators() :: String.t()
       def invite_code_generators, do: get!("invite_code_generators")

       @doc "Maximum post body length in characters (D-31)."
       @spec max_post_length() :: integer()
       def max_post_length, do: get!("max_post_length")

       @doc "Maximum thread title length in characters (D-13)."
       @spec max_thread_title_length() :: integer()
       def max_thread_title_length, do: get!("max_thread_title_length")

       @doc "Whether new registrations must verify email before gaining access (Phase 6 D-01)."
       @spec require_email_verification?() :: boolean()
       def require_email_verification?, do: get!("require_email_verification")

       @doc "Minimum seconds between resend-code presses on the Verify screen (Phase 6 D-02)."
       @spec email_verify_resend_cooldown_seconds() :: integer()
       def email_verify_resend_cooldown_seconds, do: get!("email_verify_resend_cooldown_seconds")
       ```

       Note the `?` suffix ONLY on the boolean accessor — matches Elixir naming convention and D-04 from CONTEXT.md.

    5. Rewrite `test/foglet_bbs/config_test.exs`:

       - Keep `use FogletBbs.DataCase, async: false` (the ETS table is shared; Ecto sandbox handles DB isolation but ETS state is global).
       - Replace the `@test_keys` module attribute with a list of real schema keys used by the tests: `["registration_mode", "max_post_length", "require_email_verification"]`.
       - `setup` block: call `Config.init_cache()` and invalidate each real key used. **Critical:** after each test, values need to be reset to the seeded default because Ecto sandbox rolls back the DB, but the ETS entry persists in-memory across tests within the same process. The simplest pattern: `on_exit(fn -> for k <- @test_keys, do: Config.invalidate(k) end)`. The Ecto sandbox rollback then reverts the DB row, so the next test's seed default is re-read.
       - The current DB has been seeded (so registration_mode already exists in DB with value "open"). Use `put!/3` in each test to set the value, assert via get!/1 or typed accessor, then rely on sandbox rollback + on_exit invalidation for isolation.
       - Rewrite the existing describe blocks:
         - `"put!/3 + get!/1"` round-trip tests: use "registration_mode" for string (values must pass enum — use "open", "invite_only"), "max_post_length" for integer, "require_email_verification" for boolean.
         - `"get!/1 caches in ETS"` — use "registration_mode"; the DB-direct mutation must use a valid enum value or the test will assert the wrong thing. Use "invite_only" as the DB-direct value. The assertion pattern is unchanged in shape.
         - `"put!/3 invalidates the ETS cache"` — use "max_post_length" with 4096 then 2048.
         - `"get!/1 on missing key"` — change to use a clearly-not-in-DB key. Because put!/3 now rejects unknown keys, you cannot insert a test-missing-key via put!/3. Options: use a schema key whose DB row you delete (too invasive), OR assert against a schema key that has never been seeded in test DB (risky — all 6 are seeded). Cleanest: stage a non-schema key by inserting directly via `Repo.insert!(%Entry{key: "legacy_key", value: %{"v" => 1}})` in the test setup to bypass validation, then Repo.delete it again — but actually simpler: just test that `get!/1` raises by inserting directly and then deleting. Cleanest of all: split this describe into two tests: (a) `fetch/1` returns `:error` when the DB row is absent — delete a schema row via `Repo.delete_all(from e in Entry, where: e.key == "registration_mode")` then assert `Config.fetch("registration_mode") == :error` and `get!/1` raises Ecto.NoResultsError. The sandbox rollback restores for subsequent tests.
         - `"get/2"` default test: delete a schema row in a single test (via Repo) and assert `Config.get("registration_mode", :fallback) == :fallback`.

       - ADD new describe blocks:
         - `"fetch/1"` — returns `{:ok, value}` on present, `:error` on missing (pair with the delete-row pattern above).
         - `"put!/3 validation"` — assert_raise UnknownKeyError on an unknown key; assert_raise InvalidValueError on wrong type (`put!("max_post_length", "nope", nil)`); on enum violation (`put!("registration_mode", "bogus", nil)`); on range violation (`put!("max_post_length", 0, nil)`). Each assert_raise should inspect the exception fields (`%UnknownKeyError{key: "nope"}` shape) so a reviewer can see the structured payload is correct.
         - `"typed accessors"` — one test per accessor asserting it returns the seeded default value in a fresh (unmutated) test DB. For the boolean accessor, explicitly assert the `?`-suffixed name.

       - Remove any reference to `test.key.*` dot-form fixtures — they no longer validate.

    `mix precommit` reminders:
      - Every new public function on Foglet.Config has @spec (dialyzer).
      - Credo --strict: predicate-bool function is `require_email_verification?/0` with `?` suffix — matches credo predicate-name rule, avoids the `is_*` warning trap CLAUDE.md mentions.
      - Sobelow: `Schema.validate/2` is the only gate; `put!/3` values are from trusted sysop code, not web input. No `String.to_atom/1` on any path (types are hardcoded atoms in Schema).
      - Do not add `put_raw!/3` or any escape hatch (D-08). The rewritten tests should not need one.
  </action>
  <verify>
    <automated>mix test test/foglet_bbs/config_test.exs --trace</automated>
    <automated>mix test test/foglet_bbs/config/schema_test.exs test/foglet_bbs/config_test.exs</automated>
    <automated>mix compile --warnings-as-errors --force 2>&1 | grep -E "(warning|error)" || echo "clean"</automated>
    <automated>mix format --check-formatted lib/foglet_bbs/config.ex test/foglet_bbs/config_test.exs</automated>
  </verify>
  <done>
    - `Foglet.Config.fetch/1` exists with `@spec fetch(String.t()) :: {:ok, term()} | :error` and rescues `Ecto.NoResultsError` → `:error`.
    - `Foglet.Config.put!/3` calls `Schema.validate/2` before any DB work; raises `UnknownKeyError` on unknown keys and `InvalidValueError` on validation failures (type/enum/range) with the correct structured fields.
    - All 6 typed accessors exist with `@spec` + `@doc` — boolean one uses `?` suffix per D-04.
    - `test/foglet_bbs/config_test.exs` has been rewritten against real schema keys, covers fetch/1, validation-exception paths, and each typed accessor, and contains no references to `test.key.*` fixtures.
    - `mix test test/foglet_bbs/config_test.exs` and `test/foglet_bbs/config/schema_test.exs` both pass.
    - `mix compile --warnings-as-errors` clean.
    - `mix format --check-formatted` passes.
  </done>
</task>

<task type="auto">
  <name>Task 3: Regenerate seeds, migrate callsites, update DATA_MODEL, run precommit</name>
  <files>
    priv/repo/seeds.exs,
    lib/foglet_bbs/accounts.ex,
    lib/foglet_bbs/ssh/cli_handler.ex,
    lib/foglet_bbs/tui/screens/verify.ex,
    docs/DATA_MODEL.md
  </files>
  <action>
    Wire the new schema into the rest of the codebase and run the authoritative gate.

    1. **`priv/repo/seeds.exs` regeneration (lines 42–73, the `default_config` block):**

       Replace the hardcoded `default_config` list and its `Enum.each` with an iteration over `Foglet.Config.Schema.entries/0`. Preserve the existing "description set on first insert only" behaviour (D-07) — this is load-bearing; sysop description edits should not be clobbered on re-seed.

       Add `alias Foglet.Config.Schema` near the top (alongside existing `alias Foglet.Config`). Helper stays inline — do NOT pull `Repo` into the pure Schema module (D-07).

       New block shape (preserving surrounding `# --- Default configuration entries ---` comment and trailing `IO.puts("Seeds complete.")`):

       ```
       # --- Default configuration entries ---
       Enum.each(Schema.entries(), fn %{key: key, default: default, description: description} ->
         case Repo.get_by(Entry, key: key) do
           nil ->
             Config.put!(key, default, nil)

             # Set description on first insert (put!/3 doesn't touch description)
             Entry
             |> Repo.get_by!(key: key)
             |> Ecto.Changeset.change(%{description: description})
             |> Repo.update!()

             IO.puts("  [seed] inserted config #{key} = #{inspect(default)}")

           _existing ->
             IO.puts("  [seed] config #{key} already present")
         end
       end)
       ```

       Order and description text in `@entries` must remain byte-identical to the current seeds output for re-seeding a live DB to be a no-op. Task 1 already locked descriptions from the current seeds.exs verbatim.

    2. **Callsite migrations** (from constraints block):

       **`lib/foglet_bbs/accounts.ex` around line 172** — in `post_login_screen/1`:

       Before:
       ```
       Foglet.Config.get("require_email_verification", true) == false ->
       ```

       After:
       ```
       Foglet.Config.require_email_verification?() == false ->
       ```

       The default fallback (`true`) is no longer needed — the typed accessor calls `get!/1` which raises if the seeded key is missing, and seeded defaults cover production/dev/test paths. This is the correct signal that seeds haven't run (per D-03 Claude's Discretion note in RESEARCH.md).

       **`lib/foglet_bbs/ssh/cli_handler.ex` around line 340** — in the `try do Foglet.Config.get!("registration_mode") rescue _ -> "open" end` block:

       Replace the entire try/rescue with a direct call to `Foglet.Config.registration_mode()`. The rescue clause was a paranoid fallback for an unseeded DB; with the typed accessor, a missing key means the app is mis-configured and raising is correct. Remove the `reg_mode = try do ... end` binding and inline `Foglet.Config.registration_mode()` at the use site, OR keep `reg_mode = Foglet.Config.registration_mode()` for local readability — planner's call; pick whatever keeps the diff minimal.

       **`lib/foglet_bbs/ssh/cli_handler.ex` around line 347** — same pattern, replace the try/rescue around `max_post_length` with `Foglet.Config.max_post_length()`.

       **`lib/foglet_bbs/tui/screens/verify.ex` line 278** — in `resend_cooldown_seconds/0`:

       Before:
       ```
       case Foglet.Config.get("email_verify_resend_cooldown_seconds", 60) do
         n when is_integer(n) and n > 0 -> n
         _ -> 60
       end
       ```

       After:
       ```
       Foglet.Config.email_verify_resend_cooldown_seconds()
       ```

       The `is_integer(n) and n > 0` guard is now redundant — Schema's min: 0 guarantees integer ≥ 0, and put!/3 enforces it. If the local intent is "at least 1 second, never 0" (e.g., to avoid division-by-zero elsewhere), keep the guard AND switch the default path to the typed accessor. Read the surrounding function — if `resend_cooldown_seconds/0` is used as a divisor or as a minimum-sleep, keep `max(Foglet.Config.email_verify_resend_cooldown_seconds(), 1)`. Default-case most likely: just switch to the typed accessor and delete the guard, because min: 0 was the old (and possibly incorrect) spec — the schema captures the contract now.

    3. **`docs/DATA_MODEL.md` §11 line 686:**

       Before:
       ```
       Keys use `snake_case` separators (the `.` form shown in earlier drafts was aspirational and is deprecated).
       ```

       After:
       ```
       Keys use `snake_case` separators. This is the canonical form.
       ```

       (Per D-01. Single-sentence replacement. Nothing else in §11 changes.)

       Optional nice-to-have (planner's discretion allowed per CONTEXT.md Claude's-Discretion bullet): add one line pointing readers to `Foglet.Config.Schema` as the source of truth:

       ```
       > Programmatic access: `Foglet.Config.Schema` declares the seeded keys with their types, defaults, and constraints. `Foglet.Config` exposes typed accessors (e.g., `registration_mode/0`, `max_post_length/0`, `require_email_verification?/0`).
       ```

       Place immediately after the `Seeded by priv/repo/seeds.exs:` list if included.

    4. **Run the authoritative gate.** Per CLAUDE.md, `mix precommit` runs `compile --warnings-as-errors`, `format`, `credo --strict`, `sobelow`, `dialyzer`. Fix anything it surfaces (typical candidates: missing `@spec`, format, predicate-name violations). Do NOT bypass with `--no-verify` or equivalent.

       Then run the full test suite to catch any downstream breakage from the callsite migrations (especially `mix test test/foglet_bbs/accounts_test.exs` and any ssh/tui integration tests that exercise verify flow).

    Constraints recap:
      - No `String.to_atom/1` (sobelow + CLAUDE.md).
      - One module per file (CLAUDE.md gotcha) — already satisfied by Task 1.
      - Block expressions rebind, don't mutate — applies to any `if`/`case` you add in seeds.exs.
      - Structs don't implement Access — all spec maps in Schema are plain maps, accessed via `.key` / pattern match.

    If `mix precommit` flags the `Foglet.Config.InvalidValueError` exhaustiveness (credo occasionally warns about unreachable `:above_max` clause), add a moduledoc note explaining that `:above_max` is reserved for future schematized keys with max bounds and is intentionally included. Do NOT delete the clause.
  </action>
  <verify>
    <automated>mix precommit</automated>
    <automated>mix test</automated>
    <automated>grep -nE "test\.key\." test/foglet_bbs/config_test.exs || echo "no legacy dot-form fixtures"</automated>
    <automated>grep -n "aspirational" docs/DATA_MODEL.md | grep -v "^$" || echo "aspirational-deprecated note removed"</automated>
    <automated>grep -n 'Foglet\.Config\.get("require_email_verification"' lib/foglet_bbs/accounts.ex || echo "accounts.ex migrated"</automated>
    <automated>grep -nE 'Foglet\.Config\.get!\("(registration_mode|max_post_length)"\)' lib/foglet_bbs/ssh/cli_handler.ex || echo "cli_handler.ex migrated"</automated>
    <automated>grep -n 'Foglet\.Config\.get("email_verify_resend_cooldown_seconds"' lib/foglet_bbs/tui/screens/verify.ex || echo "verify.ex migrated"</automated>
  </verify>
  <done>
    - `priv/repo/seeds.exs` iterates `Foglet.Config.Schema.entries/0`; description-set-on-first-insert behaviour preserved; re-running `mix run priv/repo/seeds.exs` against a seeded DB is a no-op (prints "already present" for each of the 6 keys).
    - `lib/foglet_bbs/accounts.ex` `post_login_screen/1` uses `Foglet.Config.require_email_verification?()`.
    - `lib/foglet_bbs/ssh/cli_handler.ex` uses `Foglet.Config.registration_mode()` and `Foglet.Config.max_post_length()`; try/rescue blocks removed.
    - `lib/foglet_bbs/tui/screens/verify.ex` `resend_cooldown_seconds/0` uses `Foglet.Config.email_verify_resend_cooldown_seconds()`.
    - `docs/DATA_MODEL.md` §11 line 686 area no longer claims the dot form is deprecated — snake_case stated as canonical form.
    - `mix precommit` exits 0 (compile clean, formatted, credo --strict clean, sobelow clean, dialyzer clean).
    - `mix test` is green with no skipped or failed tests.
  </done>
</task>

</tasks>

<verification>
End-to-end phase checks (run after all three tasks complete):

1. `mix precommit` — authoritative gate (CLAUDE.md). Must exit 0.
2. `mix test` — full suite green.
3. Seeds idempotency: `MIX_ENV=dev mix run priv/repo/seeds.exs` against an already-seeded DB prints "already present" for each of the 6 config keys (does not clobber descriptions or values).
4. Fresh DB seed: against an empty DB, `MIX_ENV=dev mix ecto.reset` produces the same 6 `configuration` rows as before (byte-identical `description` column values — verified by comparing `SELECT key, description FROM configuration ORDER BY key` before/after if manually checked).
5. Typed accessors resolve via IEx smoke test: `iex -S mix` → `Foglet.Config.registration_mode()` returns `"open"` in a freshly-seeded dev DB; `Foglet.Config.require_email_verification?()` returns `true`.
6. Exception shapes: `iex -S mix` → `Foglet.Config.put!("registration_mode", "bogus", nil)` raises `Foglet.Config.InvalidValueError` whose `Exception.message/1` mentions the allowed enum.
7. `grep -rn "test\.key\." test/` returns no matches — legacy fixtures removed.
8. `grep -n "aspirational" docs/DATA_MODEL.md | grep -i deprecated` returns no matches.
</verification>

<success_criteria>
- `Foglet.Config.Schema` is the single source of truth for the 6 seeded config keys; `entries/0`, `fetch_spec/1`, `defaults/0`, `validate/2` all behave per the `<behavior>` blocks in Task 1.
- `Foglet.Config.fetch/1` returns `{:ok, value} | :error` (stdlib-canonical per D-03).
- `Foglet.Config.put!/3` is strict: unknown key → `UnknownKeyError`; type/enum/range violation → `InvalidValueError` with `{key, reason, expected, got}` payload.
- Six typed accessors exist on `Foglet.Config` with `@spec` + `@doc`; boolean accessor uses `?` suffix per D-04.
- `priv/repo/seeds.exs` regenerated from `Schema.entries/0`; description-on-first-insert preserved.
- 4 callsites migrated to typed accessors (accounts.ex, cli_handler.ex × 2, verify.ex).
- `docs/DATA_MODEL.md` §11 line 686 updated to state snake_case is canonical; no more "aspirational/deprecated" language.
- `test/foglet_bbs/config_test.exs` rewritten against real schema keys; no `put_raw!` escape hatch introduced (per D-08).
- `mix precommit` passes; `mix test` green; no changes to `Foglet.Config.Entry` or the `configuration` DB schema.
</success_criteria>

<output>
After completion, write `/Users/brendan.turner/Dev/personal/foglet_bbs/.planning/quick/260422-irb-build-a-typed-config-schema-with-accesso/SUMMARY.md` summarising:
- What was built (Schema module, 2 exceptions, fetch/1, strict put!/3, 6 typed accessors)
- Files created/modified (exact list matches files_modified frontmatter)
- Tests added (Schema unit tests + rewritten Config cache tests + new validation-exception tests + typed-accessor tests)
- Precommit gate result (compile, format, credo, sobelow, dialyzer all green)
- Any surprises or deviations from the plan
- Quick-task status: complete
</output>
