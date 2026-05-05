defmodule Foglet.TUI.Screens.Account.PrefsForm do
  @moduledoc """
  PREFS tab selectable read-mode field list plus one-field edit overlay launcher.
  """

  alias Foglet.TUI.Effect
  alias Foglet.TUI.Modal
  alias Foglet.TUI.Screens.Account.State
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.List.SelectableFieldList

  @fields [:timezone, :time_format, :theme]

  @spec render(State.t(), Theme.t(), keyword()) :: any()
  def render(%State{} = state, %Theme{} = theme, opts \\ []) do
    fields = State.prefs_fields(state.prefs_draft) |> Enum.map(&friendly_value/1)
    selected = selected_index(state.prefs_focus)

    SelectableFieldList.render(fields, selected,
      theme: theme,
      width: Keyword.get(opts, :width, 80),
      height: Keyword.get(opts, :height, 12)
    )
  end

  @spec handle_key(map(), State.t(), map() | struct() | nil) ::
          {:ok, State.t(), list()} | :no_match
  def handle_key(%{key: :char, char: c}, %State{} = state, _current_user) when c in ["e", "E"] do
    field = state.prefs_focus || :timezone
    form = State.build_prefs_field_form(state.prefs_draft, field)
    modal = %Modal{type: :form, title: form.title, message: form, on_cancel: :dismiss_modal}

    {:ok, %{state | prefs_editing_field: field, prefs_errors: %{}, candidate_theme_id: nil},
     [Effect.open_modal(modal)]}
  end

  def handle_key(%{key: key} = event, %State{} = state, _current_user)
      when key in [:up, :down, :home, :end] do
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
      theme: Map.get(draft, :theme, "gray")
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

  @spec error_modal(State.t(), map()) :: Effect.t()
  def error_modal(%State{} = state, errors) do
    field = state.prefs_editing_field || state.prefs_focus || :timezone
    form = State.build_prefs_field_form(state.prefs_draft, field, errors)

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
        selected_index(state.prefs_focus),
        length(@fields),
        action_key(event)
      )

    {:ok, %{state | prefs_focus: Enum.at(@fields, idx), candidate_theme_id: nil}, []}
  end

  defp selected_index(field), do: Enum.find_index(@fields, &(&1 == field)) || 0

  defp action_key(%{key: :char, char: char}), do: char
  defp action_key(%{key: key}), do: key

  defp friendly_value(%{name: :theme, value: value} = field),
    do: %{field | value: String.capitalize(to_string(value))}

  defp friendly_value(field), do: field
end
