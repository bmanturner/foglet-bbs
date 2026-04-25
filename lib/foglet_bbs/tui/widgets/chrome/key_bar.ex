defmodule Foglet.TUI.Widgets.Chrome.KeyBar do
  @moduledoc """
  Compatibility wrapper for legacy flat key hint lists.

  Legacy callers may still pass `{key, description}` tuples here, but this
  module no longer owns an independent footer implementation. It normalizes the
  legacy list into Chrome V2 command groups and delegates rendering to
  `Foglet.TUI.Widgets.Chrome.CommandBar`.
  """

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.CommandBar
  alias Foglet.TUI.Widgets.Chrome.Normalizer

  @doc """
  Renders legacy flat key hints through the grouped command bar.

  `theme` — a `%Foglet.TUI.Theme{}` struct (passed from ScreenFrame).
  `keys`  — list of `{key_label, description}` pairs,
             e.g. `[{"j/k", "Navigate"}, {"Enter", "Select"}]`.
  """
  @spec render(Theme.t(), [{String.t(), String.t()}], keyword()) :: any()
  def render(theme, keys, opts \\ []) when is_list(keys) do
    CommandBar.render(theme, Normalizer.commands(keys), opts)
  end
end
