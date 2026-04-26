defmodule Foglet.TUI.Screens.Account.PrefsForm do
  @moduledoc """
  PREFS tab body and Account-local theme preview behavior (D-10, D-15, D-16, Phase 25 Plan 02).

  Delegates rendering and event handling to Modal.Form (D-01 / Pattern 1).

  Live theme preview (A1 / D-03 / Pitfall 5): after every handle_event/2 call,
  `Modal.Form.field_value(form, :theme)` is diffed against the previous value.
  When changed, `state.candidate_theme_id` is updated to trigger the instant
  theme preview in Account's render path (account.ex account_theme/2).

  Per RESEARCH Pitfall 4: body-only render — no outer box/border.
  Per RESEARCH Pitfall 2 / Codex Concern 4: SubmitStash for submit payloads.
  """

  alias Foglet.TUI.Screens.Account.State
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm
  alias Foglet.TUI.Widgets.Modal.Form.SubmitStash

  @spec render(State.t(), Theme.t()) :: any()
  def render(%State{prefs_form: form}, %Theme{} = theme) do
    ModalForm.render(form, theme: theme)
  end

  @spec handle_key(map(), State.t(), map() | struct() | nil) ::
          {:ok, State.t(), list()} | :no_match
  def handle_key(%{key: key} = event, %State{} = state, current_user)
      when key in [:char, :backspace, :enter, :escape, :tab, :shift_tab, :up, :down] do
    do_handle_key(event, state, current_user)
  end

  def handle_key(_event, %State{}, _current_user), do: :no_match

  defp do_handle_key(event, %State{prefs_form: form} = state, current_user) do
    # Capture current theme value before event for diffing (A1 / Pitfall 5)
    old_theme = ModalForm.field_value(form, :theme)

    {new_form, action} = ModalForm.handle_event(event, form)

    # Diff theme enum value after every event — live preview side effect
    new_theme = ModalForm.field_value(new_form, :theme)

    state =
      state
      |> Map.put(:prefs_form, new_form)
      |> maybe_update_candidate_theme(old_theme, new_theme)

    case action do
      :submitted ->
        {:prefs, payload} = SubmitStash.pop(__MODULE__)

        attrs = %{
          timezone: payload.timezone,
          preferences: %{"time_format" => payload.time_format},
          theme: payload.theme
        }

        {:ok,
         %{
           state
           | prefs_dirty?: false,
             status_message: "Preferences ready to save.",
             candidate_theme_id: nil
         }, [{:account_save_prefs, attrs}]}

      :cancelled ->
        reseeded = State.seed_from_user(state, current_user)

        {:ok, %{reseeded | status_message: "Preference changes discarded."}, []}

      _ ->
        dirty? = action == nil and text_input_event?(event)
        {:ok, %{state | prefs_dirty?: state.prefs_dirty? or dirty?}, []}
    end
  end

  defp maybe_update_candidate_theme(state, old_theme, new_theme)
       when old_theme != new_theme and not is_nil(new_theme) do
    %{state | candidate_theme_id: new_theme}
  end

  defp maybe_update_candidate_theme(state, _old, _new), do: state

  defp text_input_event?(%{key: :char}), do: true
  defp text_input_event?(%{key: :backspace}), do: true
  defp text_input_event?(_), do: false
end
