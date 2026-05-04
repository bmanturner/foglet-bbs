defmodule Foglet.TUI.Widgets.List.SmartList do
  @moduledoc """
  Smart list widget with search, pagination, and multi-select
  (D-02, D-13, D-14).

  Stateful sibling of `Foglet.TUI.Widgets.List.SelectionList`:

    * `SelectionList` — pure render, caller owns `selected_index`
      (D-03 keeps it lean).
    * `SmartList`     — stateful facade over
      `Raxol.UI.Components.Input.SelectList`, holding the search
      buffer / page index / multi-select set inside `:raxol_state`.
      Parent screens hold THIS struct in
      `state.screen_state[:screen][:smart_list]` and route key
      events through `handle_event/2` (D-15).

  When to use which:
    * Plain j/k navigation + Enter? → `SelectionList`.
    * Type-to-search, pagination, or multi-select checkbox-style? → `SmartList`.

  Honours:
    * D-07/D-09 — theme-routed colors only
    * D-13     — `theme:` keyword arg on render/2
    * D-14     — `init/1` + `handle_event/2` + `render/2` (no process)

  ## Actions returned from `handle_event/2`

      {:item_selected, value}       — Enter (single-select mode)
      {:items_selected, [values]}    — Enter (multi-select mode)
      {:search_changed, term}        — search buffer changed (enable_search: true)
      {:page_changed, page_index}    — PageUp/PageDown moved focused index to new page
      nil                            — navigation key, no semantic action
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Theme
  alias Raxol.UI.Components.Input.SelectList, as: RaxolSelectList
  alias Raxol.UI.Components.Input.SelectList.Search, as: RaxolSelectListSearch

  @default_page_size 10
  @focused_marker "▌"
  @single_marker "◇"
  @selected_marker "✓"
  @unselected_marker "◇"

  @type action ::
          {:item_selected, any()}
          | {:items_selected, [any()]}
          | {:search_changed, String.t()}
          | {:page_changed, non_neg_integer()}
          | nil

  defstruct [
    :raxol_state,
    :on_submit,
    enable_search: false,
    multiple: false,
    page_size: @default_page_size,
    last_action: nil
  ]

  @type t :: %__MODULE__{
          raxol_state: map(),
          on_submit: (any() -> any()) | nil,
          enable_search: boolean(),
          multiple: boolean(),
          page_size: pos_integer(),
          last_action: action()
        }

  @doc """
  Pure constructor.

  Options:
    * `:options`       — list of `{label, value}` tuples (required)
    * `:enable_search` — boolean (default `false`)
    * `:multiple`      — boolean (default `false`)
    * `:page_size`     — integer (default `#{@default_page_size}`)
    * `:on_submit`     — optional callback stashed in struct
  """
  @spec init(keyword()) :: t()
  def init(opts) when is_list(opts) do
    options = Keyword.fetch!(opts, :options)
    enable_search = Keyword.get(opts, :enable_search, false)
    multiple = Keyword.get(opts, :multiple, false)
    page_size = Keyword.get(opts, :page_size, @default_page_size)

    # SelectList.init/1 validates its props and accepts a MAP (Pitfall 2 exception).
    {:ok, raxol_state} =
      RaxolSelectList.init(%{
        options: options,
        enable_search: enable_search,
        multiple: multiple,
        page_size: page_size,
        show_pagination: true
      })

    %__MODULE__{
      raxol_state: raxol_state,
      enable_search: enable_search,
      multiple: multiple,
      page_size: page_size,
      on_submit: Keyword.get(opts, :on_submit),
      last_action: nil
    }
  end

  @doc """
  Pure event handler.

  Accepts a Raxol-native `%{key: atom, ...}` event map. Delegates to
  `Raxol.UI.Components.Input.SelectList.handle_event/3` and derives a
  semantic action atom from the resulting state transition.

  Returns `{new_state, action}`.
  """
  @spec handle_event(map(), t()) :: {t(), action()}
  def handle_event(event, %__MODULE__{raxol_state: rs} = st) do
    # SelectList.handle_event/3 pattern-matches on `data.key` — for character input
    # it expects the raw character string as the key (e.g. `%{key: "a"}`), not the
    # `:char` atom. Translate before wrapping.
    # Searchable lists are text-input surfaces; keep typed j/k as search text.
    # Non-search list/select surfaces accept j/k as unadvertised vertical fallback.
    navigation_event = normalize_navigation_event(event, st)
    raxol_data = translate_event_for_select_list(navigation_event)
    raxol_event = %Raxol.Core.Events.Event{type: :key, data: raxol_data}
    {raw_rs, _cmds} = RaxolSelectList.handle_event(raxol_event, rs, %{})
    # FOG-742: SelectList.update({:search, _}) defers filtering through a
    # debounced `{:apply_search, ...}` self-message and stashes a fake
    # `System.unique_integer/1` value as `:search_timer`. We have no process
    # routing those messages, so filtered_options never updated and the next
    # keystroke crashed in `Process.cancel_timer/1` on the bogus integer.
    # Apply the search synchronously here so each char/backspace updates the
    # filtered rows and counter, and clear the timer so subsequent events do
    # not try to cancel a non-reference.
    new_rs = apply_pending_search(rs, raw_rs)
    # IN-06: derive_action/4 receives the normalized navigation event. For searchable
    # lists this is still the original `:char` event; for non-search j/k fallbacks it
    # is the equivalent arrow event so navigation stays semantically quiet.
    action = derive_action(rs, new_rs, navigation_event, st.multiple)
    {%{st | raxol_state: new_rs, last_action: action}, action}
  end

  defp apply_pending_search(prev_rs, %{enable_search: true, search_buffer: buffer} = rs) do
    prev_buffer = Map.get(prev_rs, :search_buffer, "")
    quiescent? = buffer == prev_buffer and Map.get(rs, :search_timer) == nil

    if quiescent? do
      rs
    else
      rs
      |> RaxolSelectListSearch.update_search_state(buffer)
      |> Map.put(:search_timer, nil)
    end
  end

  defp apply_pending_search(_prev_rs, rs), do: rs

  @doc """
  Pure renderer.

  Options:
    * `:theme` — `%Foglet.TUI.Theme{}` (required)
  """
  @spec render(t(), keyword()) :: any()
  def render(%__MODULE__{raxol_state: rs}, opts) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)

    box style: %{border_fg: theme.border.fg, padding: 0} do
      column style: %{gap: 0} do
        render_options(rs, theme) ++ render_affordances(rs, theme)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private — event translation
  # ---------------------------------------------------------------------------

  defp normalize_navigation_event(%{key: :char, char: _} = event, %__MODULE__{enable_search: true}),
       do: event

  defp normalize_navigation_event(%{key: :char, char: "j"}, %__MODULE__{}), do: %{key: :down}
  defp normalize_navigation_event(%{key: :char, char: "k"}, %__MODULE__{}), do: %{key: :up}
  defp normalize_navigation_event(event, %__MODULE__{}), do: event

  # SelectList.handle_event/3 pattern-matches on `data.key`. For navigation and
  # selection keys it expects atoms (:down, :up, :enter, :space, etc.). For
  # character input (search) it expects the raw character string as the key
  # (e.g. %{key: "a"}) — the component's `single_character?/1` guard checks
  # `is_binary(key) and byte_size(key) == 1`. Our callers pass the Raxol
  # canonical `%{key: :char, char: "a"}` form; translate it here before wrapping.
  defp translate_event_for_select_list(%{key: :char, char: c} = event)
       when is_binary(c) do
    Map.put(event, :key, c)
  end

  defp translate_event_for_select_list(event), do: event

  # ---------------------------------------------------------------------------
  # Private — action derivation
  # ---------------------------------------------------------------------------

  defp derive_action(before_rs, _after_rs, %{key: :enter}, true = _multiple?) do
    # In multi-select mode, Enter is a confirmation gesture. The SelectList's
    # handle_event/3 toggles the focused item on Enter — so we read selected_indices
    # from BEFORE the event to capture what the user had accumulated, not the
    # post-toggle snapshot.
    selected = selected_values(before_rs)
    {:items_selected, selected}
  end

  defp derive_action(_before_rs, after_rs, %{key: :enter}, false = _multiple?) do
    case focused_value(after_rs) do
      nil -> nil
      value -> {:item_selected, value}
    end
  end

  defp derive_action(before_rs, after_rs, %{key: :char}, _multiple?) do
    before_buf = Map.get(before_rs, :search_buffer, "")
    after_buf = Map.get(after_rs, :search_buffer, "")

    if before_buf != after_buf, do: {:search_changed, after_buf}, else: nil
  end

  defp derive_action(before_rs, after_rs, %{key: key}, _multiple?)
       when key in [:page_up, :page_down] do
    # Navigation moves focused_index by visible_items; detect page boundary crossing.
    before_page = page_for(before_rs)
    after_page = page_for(after_rs)

    if before_page != after_page, do: {:page_changed, after_page}, else: nil
  end

  defp derive_action(_before_rs, _after_rs, _event, _multiple?), do: nil

  # ---------------------------------------------------------------------------
  # Private — value extraction
  # ---------------------------------------------------------------------------

  defp selected_values(rs) do
    options = Map.get(rs, :options, [])
    indices = Map.get(rs, :selected_indices, MapSet.new())

    options
    |> Enum.with_index()
    |> Enum.filter(fn {_opt, idx} -> MapSet.member?(indices, idx) end)
    |> Enum.map(fn {{_label, value}, _idx} -> value end)
  end

  defp focused_value(rs) do
    options = Map.get(rs, :options, [])
    idx = Map.get(rs, :focused_index, 0)

    case Enum.at(options, idx) do
      {_label, value} -> value
      _ -> nil
    end
  end

  defp page_for(rs) do
    page_size = Map.get(rs, :page_size, @default_page_size)
    focused = Map.get(rs, :focused_index, 0)

    if page_size > 0, do: div(focused, page_size), else: 0
  end

  # ---------------------------------------------------------------------------
  # Private — theme building
  # ---------------------------------------------------------------------------

  defp render_options(rs, theme) do
    options = Map.get(rs, :filtered_options) || Map.get(rs, :options, [])
    visible_items = Map.get(rs, :visible_items) || Map.get(rs, :page_size, @default_page_size)
    scroll_offset = Map.get(rs, :scroll_offset, 0)
    focused_index = Map.get(rs, :focused_index, 0)

    options
    |> empty_or_rows(rs, theme, scroll_offset, visible_items, focused_index)
  end

  defp empty_or_rows([], rs, theme, _scroll_offset, _visible_items, _focused_index) do
    empty_text =
      if Map.get(rs, :search_buffer, "") == "" do
        "No items"
      else
        "No matches"
      end

    [text("#{empty_text}\n", fg: theme.dim.fg)]
  end

  defp empty_or_rows(options, rs, theme, scroll_offset, visible_items, focused_index) do
    selected_indices = Map.get(rs, :selected_indices, MapSet.new())
    multiple? = Map.get(rs, :multiple, false)

    options
    |> Enum.slice(scroll_offset, visible_items)
    |> Enum.with_index(scroll_offset)
    |> Enum.map(fn {{label, _value}, index} ->
      selected? = MapSet.member?(selected_indices, index)
      focused? = index == focused_index
      marker = marker_for(multiple?, selected?, focused?)
      content = "#{marker} #{label}\n"

      row_style(focused?, selected?, theme)
      |> then(fn {fg, bg, style} -> text(content, fg: fg, bg: bg, style: style) end)
    end)
  end

  defp marker_for(true, true, _focused?), do: @selected_marker
  defp marker_for(true, false, _focused?), do: @unselected_marker
  defp marker_for(false, _selected?, true), do: @focused_marker
  defp marker_for(false, _selected?, false), do: @single_marker

  defp row_style(true, _selected?, theme), do: {theme.selected.fg, theme.selected.bg, [:bold]}
  defp row_style(false, true, theme), do: {theme.success.fg, nil, [:bold]}
  defp row_style(false, false, theme), do: {theme.unselected.fg, nil, []}

  defp render_affordances(rs, theme) do
    [
      search_affordance(rs, theme),
      pagination_affordance(rs, theme)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp search_affordance(%{enable_search: true} = rs, theme) do
    text("Search: #{Map.get(rs, :search_buffer, "")}\n", fg: theme.accent.fg, style: [:bold])
  end

  defp search_affordance(_rs, _theme), do: nil

  defp pagination_affordance(rs, theme) do
    page_size = Map.get(rs, :page_size, @default_page_size)
    options = Map.get(rs, :filtered_options) || Map.get(rs, :options, [])

    if length(options) > page_size do
      text("Page #{page_for(rs) + 1}\n", fg: theme.dim.fg)
    else
      text("", fg: theme.dim.fg)
    end
  end
end
