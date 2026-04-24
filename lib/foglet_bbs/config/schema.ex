defmodule Foglet.Config.Schema do
  @moduledoc """
  Pure-data source of truth for runtime-editable sysop configuration.

  This module declares the schematized config keys, their types, defaults,
  and validation constraints (enum membership, integer min/max bounds).

  It is deliberately kept free of any `Ecto` or `Repo` dependency so it can
  be loaded by tests, docs, and read-only introspection without pulling in
  database layers. Side effects (seeding, ETS caching, DB writes) live in
  `Foglet.Config` and `priv/repo/seeds.exs`.

  See `docs/DATA_MODEL.md` §11 for the high-level narrative.

  ## Scope

  Only the 8 currently-seeded keys are schematized here. "Aspirational"
  keys listed in `docs/DATA_MODEL.md` §11 (e.g. `archive_enabled`,
  `themes_available`) are intentionally **not** schematized in this phase
  — they will be added as they graduate from aspirational to seeded.

  ## Error payload shape

  `validate/2` returns either `:ok`, `{:error, {:unknown_key, key}}`, or
  `{:error, %{reason: atom(), expected: term(), got: term()}}`. The map
  shape is used (rather than a keyword list) so the raise site in
  `Foglet.Config.put!/3` can pattern-match cleanly without keyword
  destructuring.

  The `:above_max` reason is reserved for future schematized keys with
  maximum bounds; no current key uses it, but the clause is retained in
  `Foglet.Config.InvalidValueError` for symmetry.
  """

  @typedoc """
  Shape of a schematized config spec. `enum`, `min`, and `max` are `nil`
  when the constraint does not apply to a given key.
  """
  @type entry :: %{
          key: String.t(),
          type: :string | :integer | :boolean,
          default: term(),
          description: String.t(),
          enum: nil | [String.t()],
          min: nil | integer(),
          max: nil | integer()
        }

  @entries [
    %{
      key: "registration_mode",
      type: :string,
      default: "open",
      description: "Account registration policy (D-02/D-03): open | invite_only | sysop_approved",
      enum: ["open", "invite_only", "sysop_approved"],
      min: nil,
      max: nil
    },
    %{
      key: "invite_code_generators",
      type: :string,
      default: "sysop_only",
      description: "Who may generate invite codes (D-04): sysop_only | mods | any_user",
      enum: ["sysop_only", "mods", "any_user"],
      min: nil,
      max: nil
    },
    %{
      key: "max_post_length",
      type: :integer,
      default: 8192,
      description: "Maximum post body length in characters (D-31)",
      enum: nil,
      min: 1,
      max: nil
    },
    %{
      key: "max_thread_title_length",
      type: :integer,
      default: 60,
      description: "Maximum thread title length in characters (D-13, phase-03-polish Phase 4)",
      enum: nil,
      min: 1,
      max: nil
    },
    %{
      key: "delivery_mode",
      type: :string,
      default: "no_email",
      description: "Outbound transactional delivery mode (MAIL-01): email | no_email",
      enum: ["email", "no_email"],
      min: nil,
      max: nil
    },
    %{
      key: "require_email_verification",
      type: :boolean,
      default: true,
      description:
        "When false, new registrations skip verify and existing confirmed_at: nil users gain access on login (Phase 6 D-01)",
      enum: nil,
      min: nil,
      max: nil
    },
    %{
      key: "email_verify_resend_cooldown_seconds",
      type: :integer,
      default: 60,
      description:
        "Minimum seconds between resend-code presses on the Verify screen (Phase 6 D-02)",
      enum: nil,
      min: 1,
      max: nil
    },
    %{
      key: "invite_generation_per_user_limit",
      type: :integer,
      default: 0,
      description:
        "Per-user invite generation cap when invite_code_generators == \"any_user\" (INVT-07 D-04). 0 = unlimited.",
      enum: nil,
      min: 0,
      max: nil
    }
  ]

  @spec_map Map.new(@entries, &{&1.key, &1})
  @defaults_map Map.new(@entries, &{&1.key, &1.default})

  @doc """
  Return the ordered list of schematized config specs.

  The order matches the canonical seed order and is load-bearing: re-seeding
  an existing DB iterates this list, so changing the order only affects the
  order of `[seed] already present` log lines on re-seed.
  """
  @spec entries() :: [entry()]
  def entries, do: @entries

  @doc """
  Look up the spec map for `key`. Returns `{:ok, spec}` on hit, `:error` on
  miss — matches the `Map.fetch/2` / `Keyword.fetch/2` stdlib shape.
  """
  @spec fetch_spec(String.t()) :: {:ok, entry()} | :error
  def fetch_spec(key) when is_binary(key), do: Map.fetch(@spec_map, key)

  @doc """
  Return a map of every schematized key to its declared default value.

  Useful for fallbacks and for asserting post-seed state.
  """
  @spec defaults() :: %{optional(String.t()) => term()}
  def defaults, do: @defaults_map

  @doc """
  Validate a `value` against the schema for `key`.

  Returns:
    * `:ok` on success.
    * `{:error, {:unknown_key, key}}` if `key` is not in the schema.
    * `{:error, %{reason: reason, expected: expected, got: value}}` for
      type / enum / range violations, where `reason` is one of
      `:type_mismatch`, `:not_in_enum`, `:below_min`, `:above_max`.
  """
  @spec validate(String.t(), term()) ::
          :ok
          | {:error, {:unknown_key, String.t()}}
          | {:error, %{reason: atom(), expected: term(), got: term()}}
  def validate(key, value) when is_binary(key) do
    case fetch_spec(key) do
      {:ok, spec} -> check(spec, value)
      :error -> {:error, {:unknown_key, key}}
    end
  end

  # ---------- Private ----------

  @allowed_types [:string, :integer, :boolean]

  # Type dispatch — uses struct-style dot access per CLAUDE.md gotcha
  # (plain maps would allow Access, but we're explicit for readability).
  #
  # String values additionally require valid UTF-8 (no embedded nulls or
  # malformed code points) — prevents garbage binaries from slipping into
  # jsonb for any future non-enum string key.
  defp check(%{type: :string} = spec, value) when is_binary(value) do
    if String.valid?(value) do
      check_enum(spec, value)
    else
      {:error, %{reason: :type_mismatch, expected: :string, got: value}}
    end
  end

  defp check(%{type: :integer} = spec, value) when is_integer(value), do: check_range(spec, value)

  defp check(%{type: :boolean}, value) when is_boolean(value), do: :ok

  # Guard against schema drift: if a new type is added to @type entry
  # without a matching check/2 clause, fail loudly instead of emitting a
  # misleading :type_mismatch report.
  defp check(%{type: type}, _value) when type not in @allowed_types do
    raise ArgumentError,
          "Foglet.Config.Schema: unsupported type #{inspect(type)} — extend check/2 when adding a new type to @type entry"
  end

  defp check(%{type: type}, value),
    do: {:error, %{reason: :type_mismatch, expected: type, got: value}}

  defp check_enum(%{enum: nil}, _value), do: :ok

  defp check_enum(%{enum: allowed}, value) do
    if value in allowed do
      :ok
    else
      {:error, %{reason: :not_in_enum, expected: allowed, got: value}}
    end
  end

  defp check_range(%{min: min, max: max}, value) do
    cond do
      is_integer(min) and value < min ->
        {:error, %{reason: :below_min, expected: min, got: value}}

      is_integer(max) and value > max ->
        {:error, %{reason: :above_max, expected: max, got: value}}

      true ->
        :ok
    end
  end
end
