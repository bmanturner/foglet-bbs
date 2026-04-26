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

  @time_formats ["12h", "24h"]

  @spec render(State.t(), Theme.t()) :: any()
  def render(%State{prefs_form: form}, %Theme{} = theme) do
    ModalForm.render(form, theme: theme)
  end

  @spec handle_key(map(), State.t(), map() | struct() | nil) ::
          {:ok, State.t(), list()} | :no_match
  def handle_key(event, %State{} = state, current_user) do
    if form_event?(event) do
      do_handle_key(event, state, current_user)
    else
      :no_match
    end
  end

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
        SubmitStash.with_stashed(__MODULE__, fn
          nil ->
            {:ok, state, []}

          {:prefs, payload} ->
            errors = validate_prefs(payload)

            if map_size(errors) == 0 do
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
            else
              {:ok, %{state | prefs_form: ModalForm.set_errors(new_form, errors)}, []}
            end
        end)

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

  defp validate_prefs(payload) do
    %{}
    |> maybe_put_error(:timezone, blank?(payload.timezone), "can't be blank")
    |> maybe_put_error(
      :time_format,
      payload.time_format not in @time_formats,
      "must be 12h or 24h"
    )
  end

  defp maybe_put_error(errors, field, true, message), do: Map.put(errors, field, message)
  defp maybe_put_error(errors, _field, false, _message), do: errors

  defp blank?(value), do: value in [nil, ""]

  defp text_input_event?(%{key: :char}), do: true
  defp text_input_event?(%{key: :backspace}), do: true
  defp text_input_event?(_), do: false

  defp form_event?(%{key: :char}), do: true
  defp form_event?(%{key: :backspace}), do: true
  defp form_event?(%{key: :enter}), do: true
  defp form_event?(%{key: :escape}), do: true
  defp form_event?(%{key: :tab}), do: true
  defp form_event?(%{key: :shift_tab}), do: true
  defp form_event?(%{key: :up}), do: true
  defp form_event?(%{key: :down}), do: true
  defp form_event?(_event), do: false
end
