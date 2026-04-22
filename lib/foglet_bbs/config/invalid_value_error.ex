defmodule Foglet.Config.InvalidValueError do
  @moduledoc """
  Raised by `Foglet.Config.put!/3` when a value fails schema validation.

  The `:above_max` clause is reserved for future schematized keys with
  maximum bounds and is intentionally included even though no current key
  uses it — this keeps `Exception.message/1` total across every reason
  `Foglet.Config.Schema.validate/2` can emit.
  """

  defexception [:key, :reason, :expected, :got]

  @type t :: %__MODULE__{
          key: String.t(),
          reason: :type_mismatch | :not_in_enum | :below_min | :above_max,
          expected: term(),
          got: term()
        }

  @impl true
  def message(%__MODULE__{key: key, reason: :type_mismatch, expected: expected, got: got}) do
    "config #{inspect(key)} expected #{inspect(expected)}, got #{inspect(got)}"
  end

  def message(%__MODULE__{key: key, reason: :not_in_enum, expected: allowed, got: got}) do
    "config #{inspect(key)}=#{inspect(got)} is not one of #{inspect(allowed)}"
  end

  def message(%__MODULE__{key: key, reason: :below_min, expected: min, got: got}) do
    "config #{inspect(key)}=#{inspect(got)} is below minimum #{inspect(min)}"
  end

  def message(%__MODULE__{key: key, reason: :above_max, expected: max, got: got}) do
    "config #{inspect(key)}=#{inspect(got)} is above maximum #{inspect(max)}"
  end
end
