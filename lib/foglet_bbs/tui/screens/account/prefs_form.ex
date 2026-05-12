defmodule Foglet.TUI.Screens.Account.PrefsForm do
  @moduledoc """
  PREFS tab selectable read-mode field list plus one-field edit overlay launcher.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Effect
  alias Foglet.TUI.Layout
  alias Foglet.TUI.Modal
  alias Foglet.TUI.Screens.Account.State
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.List.SelectableFieldList
  alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

  @fields [:timezone, :time_format, :theme, :handle_color]

  @spec render(State.t(), Theme.t(), keyword()) :: any()
  def render(%State{} = state, %Theme{} = theme, opts \\ []) do
    fields = State.prefs_fields(state.prefs_draft) |> Enum.map(&friendly_value/1)
    selected = selected_index(state.prefs_focus)
    width = Keyword.get(opts, :width, 80)
    height = Keyword.get(opts, :height, 12)
    terminal_size = Keyword.get(opts, :terminal_size, {width, height})

    list =
      SelectableFieldList.render(fields, selected,
        theme: theme,
        width: list_width(width, terminal_size),
        height: height
      )

    detail = inspector(fields, selected, theme)

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
    field = state.prefs_editing_field || state.prefs_focus || :timezone
    value = Map.get(payload, field)
    draft = Map.put(state.prefs_draft, field, value)

    attrs = %{
      timezone: Map.get(draft, :timezone, "Etc/UTC"),
      preferences: %{"time_format" => Map.get(draft, :time_format, "12h")},
      theme: Map.get(draft, :theme, "gray"),
      handle_color: Map.get(draft, :handle_color)
    }

    {%{
       state
       | prefs_draft: draft,
         prefs_focus: field,
         prefs_errors: %{},
         candidate_theme_id: nil,
         status_message: nil
     }, [{:account_save_prefs, attrs}]}
  end

  @spec preview_field_change(State.t(), ModalForm.t()) :: State.t()
  def preview_field_change(%State{prefs_editing_field: :theme} = state, %ModalForm{} = form) do
    %{state | candidate_theme_id: ModalForm.field_value(form, :theme), status_message: nil}
  end

  def preview_field_change(%State{prefs_editing_field: :handle_color} = state, %ModalForm{}) do
    %{state | candidate_theme_id: nil, status_message: nil}
  end

  def preview_field_change(%State{} = state, %ModalForm{}), do: %{state | candidate_theme_id: nil}

  @spec cancel_field(State.t()) :: State.t()
  def cancel_field(%State{} = state) do
    %{state | candidate_theme_id: nil, prefs_editing_field: nil}
  end

  @spec error_modal(State.t(), map()) :: Effect.t()
  def error_modal(%State{} = state, errors) do
    field = state.prefs_editing_field || state.prefs_focus || :timezone
    form = State.build_prefs_field_form(state.prefs_draft, field, errors)

    Effect.open_modal(%Modal{
      type: :form,
      title: form.title,
      message: form,
      on_cancel: :dismiss_modal,
      change_target: {:account, :prefs_field}
    })
  end

  defp move_selection(event, %State{} = state) do
    idx =
      SelectableFieldList.move(
        selected_index(state.prefs_focus),
        length(@fields),
        action_key(event)
      )

    {:ok, %{state | prefs_focus: Enum.at(@fields, idx), candidate_theme_id: nil}, []}
  end

  defp open_selected_field(%State{} = state) do
    field = state.prefs_focus || :timezone
    form = State.build_prefs_field_form(state.prefs_draft, field)

    modal = %Modal{
      type: :form,
      title: form.title,
      message: form,
      on_cancel: :dismiss_modal,
      change_target: {:account, :prefs_field}
    }

    {:ok, %{state | prefs_editing_field: field, prefs_errors: %{}, candidate_theme_id: nil},
     [Effect.open_modal(modal)]}
  end

  defp selected_index(field), do: Enum.find_index(@fields, &(&1 == field)) || 0

  defp action_key(%{key: :char, char: char}), do: char
  defp action_key(%{key: key} = event) when key in [:tab, :shift_tab, :backtab], do: event
  defp action_key(%{key: key}), do: key

  defp friendly_value(%{name: :theme, value: value} = field),
    do: %{field | value: String.capitalize(to_string(value))}

  defp friendly_value(%{name: :handle_color, value: value} = field) do
    display = if value in [nil, ""], do: "BBS default", else: value

    Map.merge(field, %{
      value: display,
      swatch_color: value,
      description: "Use #RRGGBB, like #ff8800. Blank uses the BBS default."
    })
  end

  defp friendly_value(field), do: field

  defp list_width(width, terminal_size) do
    if Layout.enhanced?(terminal_size), do: max(div(width * 3, 5) - 2, 40), else: width
  end

  defp inspector(fields, selected, %Theme{} = theme) do
    field = Enum.at(fields, selected) || hd(fields)
    label = Map.get(field, :label, "Field")
    value = display_value(Map.get(field, :value))
    description = Map.get(field, :description) || prefs_help(Map.fetch!(field, :name))

    column style: %{gap: 1, padding: 1} do
      [
        text("PREFERENCE PREVIEW", fg: theme.dim.fg, style: [:bold]),
        text(label, fg: theme.primary.fg, style: [:bold]),
        text(value, fg: theme.selected.fg),
        divider(char: "─", style: %{fg: theme.border.fg}),
        text(description, fg: theme.unselected.fg),
        text(preview_note(Map.fetch!(field, :name)), fg: theme.dim.fg)
      ]
    end
  end

  defp prefs_help(:timezone), do: "Controls how timestamps are localized around the BBS."
  defp prefs_help(:time_format), do: "Choose the clock style used in chrome and message metadata."

  defp prefs_help(:theme),
    do: "Preview a different terminal palette before saving it to your account."

  defp prefs_help(:handle_color),
    do: "Personalizes your handle color where member identity is rendered."

  defp prefs_help(_field), do: "Review this preference before editing."

  defp preview_note(:theme), do: "Opening this field previews themes."
  defp preview_note(:handle_color), do: "Use #RRGGBB; blank falls back to the BBS default."
  defp preview_note(_field), do: "Press E or Enter to edit this preference."

  defp display_value(nil), do: "—"
  defp display_value(""), do: "—"
  defp display_value(value), do: to_string(value)
end
