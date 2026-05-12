defmodule Foglet.TUI.Layout do
  @moduledoc """
  Shared terminal-size decisions and shell primitives for Foglet TUI screens.

  Screens should depend on this module for enhanced-layout breakpoints instead
  of duplicating width/height checks. The tiers are intentionally conservative:

    * `:minimum` covers the supported 64x22 baseline.
    * `:standard` covers the existing 80x24-to-119x35 experience.
    * `:enhanced` starts at 120x36 for two-pane compositions.
    * `:spacious` starts at 132x43 and may add optional utility rails.

  The helper only composes caller-provided, already-loaded render elements. It
  does not fetch data, authorize actions, or own screen state.
  """

  import Raxol.Core.Renderer.View

  @type size ::
          {pos_integer(), pos_integer()}
          | %{optional(:terminal_size) => term()}
  @type tier :: :minimum | :standard | :enhanced | :spacious

  @minimum_size {64, 22}
  @standard_size {80, 24}
  @enhanced_size {120, 36}
  @spacious_size {132, 43}

  @doc "Returns the canonical minimum supported terminal size."
  @spec minimum_size() :: {64, 22}
  def minimum_size, do: @minimum_size

  @doc "Returns the standard terminal size used by current default renders."
  @spec standard_size() :: {80, 24}
  def standard_size, do: @standard_size

  @doc "Returns the first terminal size that may render enhanced two-pane shells."
  @spec enhanced_size() :: {120, 36}
  def enhanced_size, do: @enhanced_size

  @doc "Returns the first terminal size that may render optional utility rails."
  @spec spacious_size() :: {132, 43}
  def spacious_size, do: @spacious_size

  @doc "Classifies a terminal size into Foglet's shared layout tier."
  @spec tier(size() | nil) :: tier()
  def tier(size_or_state)

  def tier({width, height}) when width >= 132 and height >= 43, do: :spacious
  def tier({width, height}) when width >= 120 and height >= 36, do: :enhanced
  def tier({width, height}) when width >= 80 and height >= 24, do: :standard
  def tier({_width, _height}), do: :minimum

  def tier(%{} = state), do: state |> terminal_size() |> tier()
  def tier(nil), do: :standard

  @doc "True when the terminal can support enhanced two-pane shells."
  @spec enhanced?(size() | nil) :: boolean()
  def enhanced?(size_or_state), do: tier(size_or_state) in [:enhanced, :spacious]

  @doc "True when the terminal can support spacious optional utility rails."
  @spec spacious?(size() | nil) :: boolean()
  def spacious?(size_or_state), do: tier(size_or_state) == :spacious

  @doc "Returns normalized `{width, height}` from a size tuple, app state, or context-like map."
  @spec terminal_size(size() | nil) :: {pos_integer(), pos_integer()}
  def terminal_size({width, height})
      when is_integer(width) and is_integer(height) and width > 0 and height > 0,
      do: {width, height}

  def terminal_size(%{} = state), do: Map.get(state, :terminal_size) |> terminal_size()
  def terminal_size(_other), do: @standard_size

  @doc "
  Renders a left-heavy list/detail shell.

  Below the enhanced tier this returns only `list`, preserving the narrow
  single-pane contract. At 120x36+ it returns a horizontal split with the list
  receiving the larger share by default.
  "
  @spec left_heavy_split(any(), any(), keyword()) :: any()
  def left_heavy_split(list, detail, opts \\ []) do
    size = Keyword.get(opts, :terminal_size)

    if enhanced?(size) do
      split_pane(
        direction: :horizontal,
        ratio: Keyword.get(opts, :ratio, {3, 2}),
        min_size: Keyword.get(opts, :min_size, 24),
        divider_char: Keyword.get(opts, :divider_char, " "),
        children: [list, detail]
      )
    else
      list
    end
  end

  @doc "
  Adds an optional right-side utility rail only at the spacious tier.

  Callers pass the primary shell as `content` and a pre-rendered `rail`. At
  smaller tiers the rail is omitted rather than faked into unavailable space.
  "
  @spec spacious_rail(any(), any(), keyword()) :: any()
  def spacious_rail(content, rail, opts \\ []) do
    size = Keyword.get(opts, :terminal_size)

    if spacious?(size) do
      split_pane(
        direction: :horizontal,
        ratio: Keyword.get(opts, :ratio, {4, 1}),
        min_size: Keyword.get(opts, :min_size, 18),
        divider_char: Keyword.get(opts, :divider_char, " "),
        children: [content, rail]
      )
    else
      content
    end
  end

  @doc "
  Filters command groups to match the current focus/mode before `CommandBar`
  applies width compaction.

  A command may declare `:focus`, `:mode`, `:focuses`, or `:modes`. Commands
  without these keys remain visible in every focus/mode. This keeps command
  bars truthful by construction while preserving each screen's existing command
  shape.
  "
  @spec commands_for([map() | struct()], keyword()) :: [map()]
  def commands_for(groups, opts \\ []) when is_list(groups) do
    focus = Keyword.get(opts, :focus)
    mode = Keyword.get(opts, :mode)

    groups
    |> Enum.map(&filter_group(&1, focus, mode))
    |> Enum.reject(&(&1.commands == []))
  end

  defp filter_group(group, focus, mode) do
    group = to_map(group)
    commands = group |> Map.get(:commands, []) |> Enum.filter(&command_visible?(&1, focus, mode))
    Map.put(group, :commands, commands)
  end

  defp command_visible?(command, focus, mode) do
    command = to_map(command)

    matches_dimension?(command, focus, :focus, :focuses) and
      matches_dimension?(command, mode, :mode, :modes)
  end

  defp matches_dimension?(_command, nil, _single_key, _many_key), do: true

  defp matches_dimension?(command, value, single_key, many_key) do
    single = Map.get(command, single_key)
    many = Map.get(command, many_key)

    cond do
      is_nil(single) and is_nil(many) -> true
      not is_nil(single) -> single == value
      is_list(many) -> value in many
      true -> false
    end
  end

  defp to_map(%_{} = struct), do: Map.from_struct(struct)
  defp to_map(map) when is_map(map), do: map
end
