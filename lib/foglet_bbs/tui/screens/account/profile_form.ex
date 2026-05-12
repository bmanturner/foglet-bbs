defmodule Foglet.TUI.Screens.Account.ProfileForm do
  @moduledoc """
  PROFILE tab selectable read-mode field list plus one-field edit overlay launcher.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Effect
  alias Foglet.TUI.Layout
  alias Foglet.TUI.Modal
  alias Foglet.TUI.Screens.Account.State
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.List.SelectableFieldList

  @fields [:location, :tagline, :real_name]

  @spec render(State.t(), Theme.t(), keyword()) :: any()
  def render(%State{} = state, %Theme{} = theme, opts \\ []) do
    fields = State.profile_fields(state.profile_draft)
    selected = selected_index(state.profile_focus)
    width = Keyword.get(opts, :width, 80)
    height = Keyword.get(opts, :height, 12)
    terminal_size = Keyword.get(opts, :terminal_size, {width, height})

    list =
      SelectableFieldList.render(fields, selected,
        theme: theme,
        width: list_width(width, terminal_size),
        height: height
      )

    detail = inspector(fields, selected, theme, :profile)

    Layout.left_heavy_split(list, detail,
      terminal_size: terminal_size,
      ratio: {3, 2},
      min_size: 28,
      divider_char: "  "
    )
  end

  @spec handle_key(map(), State.t(), map() | struct() | nil) ::
          {:ok, State.t(), list()} | :no_match
  def handle_key(%{key: :char, char: c}, %State{} = state, _current_user) when c in ["e", "E"] do
    open_selected_field(state)
  end

  def handle_key(%{key: :enter}, %State{} = state, _current_user) do
    open_selected_field(state)
  end

  def handle_key(%{key: key} = event, %State{} = state, _current_user)
      when key in [:up, :down, :home, :end] do
    move_selection(event, state)
  end

  def handle_key(%{key: key} = event, %State{} = state, _current_user)
      when key in [:tab, :shift_tab, :backtab] do
    move_selection(event, state)
  end

  def handle_key(%{key: :char, char: c} = event, %State{} = state, _current_user)
      when c in ["j", "J", "k", "K", "g", "G"] do
    move_selection(event, state)
  end

  def handle_key(_event, %State{}, _current_user), do: :no_match

  @spec submit_field(State.t(), map()) :: {State.t(), [{atom(), map()}]}
  def submit_field(%State{} = state, payload) do
    field = state.profile_editing_field || state.profile_focus || :location
    value = Map.get(payload, field)
    draft = Map.put(state.profile_draft, field, value)

    attrs = %{
      location: Map.get(draft, :location, ""),
      tagline: Map.get(draft, :tagline, ""),
      real_name: Map.get(draft, :real_name, "")
    }

    {%{
       state
       | profile_draft: draft,
         profile_focus: field,
         profile_errors: %{},
         status_message: nil
     }, [{:account_save_profile, attrs}]}
  end

  @spec error_modal(State.t(), map()) :: Effect.t()
  def error_modal(%State{} = state, errors) do
    field = state.profile_editing_field || state.profile_focus || :location
    form = State.build_profile_field_form(state.profile_draft, field, errors)

    Effect.open_modal(%Modal{
      type: :form,
      title: form.title,
      message: form,
      on_cancel: :dismiss_modal
    })
  end

  defp move_selection(event, %State{} = state) do
    idx =
      SelectableFieldList.move(
        selected_index(state.profile_focus),
        length(@fields),
        action_key(event)
      )

    {:ok, %{state | profile_focus: Enum.at(@fields, idx)}, []}
  end

  defp open_selected_field(%State{} = state) do
    field = state.profile_focus || :location
    form = State.build_profile_field_form(state.profile_draft, field)
    modal = %Modal{type: :form, title: form.title, message: form, on_cancel: :dismiss_modal}

    {:ok, %{state | profile_editing_field: field, profile_errors: %{}},
     [Effect.open_modal(modal)]}
  end

  defp selected_index(field), do: Enum.find_index(@fields, &(&1 == field)) || 0

  defp action_key(%{key: :char, char: char}), do: char
  defp action_key(%{key: key} = event) when key in [:tab, :shift_tab, :backtab], do: event
  defp action_key(%{key: key}), do: key

  defp list_width(width, terminal_size) do
    if Layout.enhanced?(terminal_size), do: max(div(width * 3, 5) - 2, 40), else: width
  end

  defp inspector(fields, selected, %Theme{} = theme, :profile) do
    field = Enum.at(fields, selected) || hd(fields)
    label = Map.get(field, :label, "Field")
    value = display_value(Map.get(field, :value))
    description = Map.get(field, :description) || profile_help(Map.fetch!(field, :name))

    column style: %{gap: 1, padding: 1} do
      [
        text("FIELD GUIDE", fg: theme.dim.fg, style: [:bold]),
        text(label, fg: theme.primary.fg, style: [:bold]),
        text(value, fg: theme.selected.fg),
        divider(char: "─", style: %{fg: theme.border.fg}),
        text(description, fg: theme.unselected.fg),
        text("Press E or Enter to edit this row.", fg: theme.dim.fg)
      ]
    end
  end

  defp profile_help(:location), do: "Shown on your local profile."

  defp profile_help(:tagline),
    do: "A short line of personality for account summaries and future member surfaces."

  defp profile_help(:real_name),
    do: "Optional private context for friends and sysops; leave blank to use only your handle."

  defp profile_help(_field), do: "Review this account field before editing."

  defp display_value(nil), do: "—"
  defp display_value(""), do: "—"
  defp display_value(value), do: to_string(value)
end
