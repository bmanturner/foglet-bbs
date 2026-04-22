defmodule Foglet.Config.UnknownKeyError do
  @moduledoc """
  Raised by `Foglet.Config.put!/3` when the key is not declared in
  `Foglet.Config.Schema`.
  """

  defexception [:key]

  @type t :: %__MODULE__{key: String.t()}

  @impl true
  def message(%__MODULE__{key: key}) do
    "unknown config key #{inspect(key)} — add it to Foglet.Config.Schema or use Foglet.Config.Entry directly"
  end
end
