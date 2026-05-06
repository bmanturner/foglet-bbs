defmodule Foglet.AppName do
  @moduledoc """
  Runtime boundary for the public application name.

  The OTP application and Elixir namespaces remain `:foglet_bbs` / `Foglet`;
  this module only governs user-visible branding text. Values come from
  runtime configuration so deploys can white-label public output without code
  changes.
  """

  alias Foglet.TUI.TextWidth

  @default_name "Foglet"
  @max_display_width 32
  @ansi_escape ~r/\e\[[0-?]*[ -\/]*[@-~]/u
  @line_controls ~r/[\r\n]+/u
  @control_chars ~r/[[:cntrl:]]+/u

  @doc "Returns the sanitized, width-safe public app name."
  @spec name() :: String.t()
  def name do
    (Application.get_env(:foglet_bbs, :app_name) || System.get_env("FOGLET_APP_NAME") ||
       @default_name)
    |> normalize()
  end

  @doc "Prepends the configured public app name to breadcrumb suffix parts."
  @spec breadcrumb([term()]) :: [String.t()]
  def breadcrumb(parts \\ []) when is_list(parts) do
    [name() | parts]
  end

  defp normalize(value) when is_binary(value) do
    value
    |> String.replace(@ansi_escape, "")
    |> String.replace(@line_controls, "")
    |> String.replace(@control_chars, " ")
    |> String.trim()
    |> fallback_if_blank()
    |> clip(@max_display_width)
  end

  defp normalize(_other), do: @default_name

  defp fallback_if_blank(""), do: @default_name
  defp fallback_if_blank(value), do: value

  defp clip(value, max_width) do
    value
    |> String.graphemes()
    |> Enum.reduce_while({[], 0}, fn grapheme, {parts, width} ->
      grapheme_width = TextWidth.display_width(grapheme)

      if width + grapheme_width <= max_width do
        {:cont, {[grapheme | parts], width + grapheme_width}}
      else
        {:halt, {parts, width}}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.join()
  end
end
