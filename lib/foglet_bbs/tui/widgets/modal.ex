defmodule Foglet.TUI.Widgets.Modal do
  @moduledoc """
  Modal widget for errors, info, and confirmation prompts (D-20).

  Types:
    * :info    — neutral message with [Enter] OK hint
    * :error   — red-accent message with [Enter] OK hint
    * :confirm — message + [Y]es / [N]o hints
  """

  import Raxol.Core.Renderer.View

  @type modal_spec :: %{
          required(:message) => String.t(),
          optional(:type) => :info | :error | :confirm,
          optional(:title) => String.t()
        }

  @spec render(modal_spec()) :: any()
  def render(%{message: msg} = spec) do
    type = Map.get(spec, :type, :info)
    title = Map.get(spec, :title, title_for(type))

    box style: %{border: :double, padding: 1} do
      column style: %{gap: 0} do
        [
          text(" #{title} ", style: [:bold]),
          divider(),
          text(msg, fg: color_for(type)),
          text(key_hint_for(type), style: [:dim])
        ]
      end
    end
  end

  defp title_for(:info), do: "Info"
  defp title_for(:error), do: "Error"
  defp title_for(:confirm), do: "Confirm"

  defp color_for(:error), do: :red
  defp color_for(:confirm), do: :yellow
  defp color_for(_), do: :green

  defp key_hint_for(:confirm), do: "[Y] Yes   [N] No"
  defp key_hint_for(_), do: "[Enter] OK"
end
