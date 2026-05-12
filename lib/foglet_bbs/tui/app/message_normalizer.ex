defmodule Foglet.TUI.App.MessageNormalizer do
  @moduledoc """
  Bridge between Raxol's `%Event{}` types and the internal tuple wire format
  the `Foglet.TUI.App` reducer pattern-matches on.

  Raxol delivers low-level events (`:key`, `:window`, `:resize`,
  `:foglet_runtime`) as struct values. Screens and the App reducer want a
  single, easy-to-pattern-match shape. This module is the canonical place
  that translation happens, so adding a new event type (paste, mouse, focus)
  is a one-clause edit here rather than a `do_update/2` change.

  Pure module — no state, no side effects.
  """

  @doc """
  Normalizes a runtime message into the App reducer's internal wire format.

  Pass-through for anything that isn't a recognized Raxol `%Event{}` so
  app-internal messages (atoms, tagged tuples) flow unchanged.
  """
  @spec normalize(term()) :: term()
  def normalize(%Raxol.Core.Events.Event{type: :key, data: data}) do
    {:key, data}
  end

  def normalize(%Raxol.Core.Events.Event{type: :window, data: %{width: w, height: h}}) do
    {:window_change, w, h}
  end

  def normalize(%Raxol.Core.Events.Event{type: :resize, data: %{width: w, height: h}}) do
    {:window_change, w, h}
  end

  def normalize(%Raxol.Core.Events.Event{type: :foglet_runtime, data: %{message: message}}) do
    message
  end

  def normalize({:subscription, message}), do: normalize(message)

  def normalize(other), do: other
end
