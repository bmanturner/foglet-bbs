defmodule Foglet.TUI.Widgets.Display.Badge do
  @moduledoc """
  Stateless compact state badge renderer for operator-console primitives.

  Honours:
    * D-01 — lives under the Display widget bucket as a primitive.
    * D-06 — supports required operator-console badge states.
    * D-07 — emits compact, recognizable text for flattened render output.
    * D-08 — routes badge roles through `Foglet.TUI.Presentation` mappings
      and then semantic `Foglet.TUI.Theme` slots.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Presentation
  alias Foglet.TUI.Theme

  @state_roles %{
    :required => :warning,
    :subscribed => :success,
    :locked => :warning,
    :sticky => :accent,
    :pending => :info,
    :healthy => :success,
    :error => :error,
    :neutral => :info,
    :info => :info
  }

  @state_labels %{
    :required => "required",
    :subscribed => "subscribed",
    :locked => "locked",
    :sticky => "sticky",
    :pending => "pending",
    :healthy => "healthy",
    :error => "error",
    :neutral => "neutral",
    :info => "info"
  }

  @doc """
  Renders a compact badge for an operator-console state.

  Options:
    * `:theme` — required `%Foglet.TUI.Theme{}`
    * `:label` — optional caller label, rendered as text only
    * `:role` — optional presentation badge role; unsupported roles fall
      back to `:info`
  """
  @spec render(atom() | String.t(), keyword()) :: any()
  def render(state, opts) when is_list(opts) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)

    label = Keyword.get(opts, :label, label_for(state))
    role = Keyword.get(opts, :role, role_for(state))
    slot = theme_slot_for(role)
    style = Map.fetch!(theme, slot)

    text("[#{label}]", text_opts(style))
  end

  defp label_for(state) when is_atom(state),
    do: Map.get(@state_labels, state, Atom.to_string(state))

  defp label_for(state), do: to_string(state)

  defp role_for(state) when is_atom(state), do: Map.get(@state_roles, state, :info)
  defp role_for(_state), do: :info

  defp theme_slot_for(role) do
    badges = Presentation.theme_mappings().badges

    role
    |> then(fn role -> Map.get(badges, role) || Map.fetch!(badges, :info) end)
  end

  defp text_opts(style) do
    []
    |> maybe_put(:fg, Map.get(style, :fg))
    |> maybe_put(:bg, Map.get(style, :bg))
    |> maybe_put(:style, Map.get(style, :style))
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
