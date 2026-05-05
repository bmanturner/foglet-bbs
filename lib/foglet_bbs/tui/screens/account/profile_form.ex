defmodule Foglet.TUI.Screens.Account.ProfileForm do
  @moduledoc """
  PROFILE tab selectable read-mode field list plus one-field edit overlay launcher.
  """

  alias Foglet.TUI.Effect
  alias Foglet.TUI.Modal
  alias Foglet.TUI.Screens.Account.State
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.List.SelectableFieldList

  @fields [:location, :tagline, :real_name]

  @spec render(State.t(), Theme.t(), keyword()) :: any()
  def render(%State{} = state, %Theme{} = theme, opts \\ []) do
    fields = State.profile_fields(state.profile_draft)
    selected = selected_index(state.profile_focus)

    SelectableFieldList.render(fields, selected,
      theme: theme,
      width: Keyword.get(opts, :width, 80),
      height: Keyword.get(opts, :height, 12)
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
  defp action_key(%{key: key}), do: key
end
