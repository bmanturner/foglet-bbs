defmodule Foglet.TUI.Test do
  @moduledoc """
  Buffer snapshot helpers for TUI tests.

  `render_screen/3` renders a screen module through its `render/2` callback and
  `Foglet.TUI.AsciiRenderer`, using the same Raxol layout engine as production.
  `render_fixture/2` renders the synthetic in-memory fixtures used by
  `mix foglet.tui.render`.

  `~B` keeps expected buffers readable in tests. It removes one leading newline,
  one trailing newline with the closing heredoc indentation, and common heredoc
  indentation, preserving row content after that normalization.
  """

  import ExUnit.Assertions

  alias Foglet.TUI.App
  alias Foglet.TUI.AsciiRenderer
  alias Foglet.TUI.Context
  alias Foglet.TUI.RenderFixtures

  @doc """
  Renders a screen module and local state to a plain buffer string.
  """
  @spec render_screen(module(), term(), keyword()) :: String.t()
  def render_screen(screen_module, local_state, opts)
      when is_atom(screen_module) and is_list(opts) do
    %Context{} = context = Keyword.fetch!(opts, :context)
    size = render_size(opts, context)

    screen_module.render(local_state, %{context | terminal_size: size})
    |> AsciiRenderer.render(size)
  end

  @doc """
  Renders a `Foglet.TUI.RenderFixtures` screen through `App.view/1`.
  """
  @spec render_fixture(atom(), keyword()) :: String.t()
  def render_fixture(screen, opts \\ []) when is_atom(screen) and is_list(opts) do
    size = {Keyword.get(opts, :width, 80), Keyword.get(opts, :height, 24)}
    fixture_opts = Keyword.take(opts, [:substate, :seed_state])

    screen
    |> RenderFixtures.state_for(size, fixture_opts)
    |> App.view()
    |> AsciiRenderer.render(size)
  end

  @doc """
  Asserts exact buffer equality and shows a row-by-row diff on failure.
  """
  @spec assert_screen(String.t(), String.t()) :: true | no_return()
  def assert_screen(actual, expected) when is_binary(actual) and is_binary(expected) do
    if actual == expected do
      true
    else
      flunk("""
      screen buffer mismatch

      #{buffer_diff(expected, actual)}
      """)
    end
  end

  @doc """
  Multiline buffer sigil.

  The sigil removes exactly one leading newline and one trailing newline with
  the closing heredoc indentation when present, then removes common heredoc
  indentation from non-empty rows. It does not trim trailing whitespace or
  internal row content.
  """
  def sigil_B(buffer, _modifiers) when is_binary(buffer) do
    buffer
    |> strip_one_leading_newline()
    |> strip_one_trailing_newline()
    |> strip_common_indentation()
  end

  defp render_size(opts, %Context{terminal_size: {context_width, context_height}}) do
    {Keyword.get(opts, :width, context_width), Keyword.get(opts, :height, context_height)}
  end

  defp render_size(opts, %Context{}) do
    {Keyword.get(opts, :width, 80), Keyword.get(opts, :height, 24)}
  end

  defp buffer_diff(expected, actual) do
    expected_rows = String.split(expected, "\n", trim: false)
    actual_rows = String.split(actual, "\n", trim: false)
    max_rows = max(length(expected_rows), length(actual_rows))

    0..(max_rows - 1)
    |> Enum.flat_map(fn index ->
      expected_row = Enum.at(expected_rows, index)
      actual_row = Enum.at(actual_rows, index)

      if expected_row == actual_row do
        []
      else
        row_no = index + 1

        [
          "#{row_no}: - #{inspect(expected_row || :missing)}",
          "#{row_no}: + #{inspect(actual_row || :missing)}"
        ]
      end
    end)
    |> Enum.join("\n")
  end

  defp strip_one_leading_newline("\n" <> rest), do: rest
  defp strip_one_leading_newline(buffer), do: buffer

  defp strip_one_trailing_newline(buffer) do
    Regex.replace(~r/\n[ \t]*\z/, buffer, "", global: false)
  end

  defp strip_common_indentation(buffer) do
    rows = String.split(buffer, "\n", trim: false)

    indentation =
      rows
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&leading_spaces/1)
      |> Enum.min(fn -> 0 end)

    Enum.map_join(rows, "\n", fn row -> strip_leading_spaces(row, indentation) end)
  end

  defp leading_spaces(row),
    do: row |> String.length() |> Kernel.-(String.length(String.trim_leading(row, " ")))

  defp strip_leading_spaces(row, 0), do: row

  defp strip_leading_spaces(row, count),
    do: String.replace_prefix(row, String.duplicate(" ", count), "")
end
