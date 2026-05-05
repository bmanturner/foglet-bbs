defmodule Foglet.TUI.Screens.Account.PrefsForm do
  @moduledoc """
  PREFS tab body and Account-local theme preview behavior (D-10, D-15, D-16, Phase 25 Plan 02).

  Delegates rendering and event handling to Modal.Form (D-01 / Pattern 1).

  Live theme preview (A1 / D-03 / Pitfall 5): after every handle_event/2 call,
  `Modal.Form.field_value(form, :theme)` is diffed against the previous value.
  When changed, `state.candidate_theme_id` is updated to trigger the instant
  theme preview in Account's render path (account.ex account_theme/2).

  Per RESEARCH Pitfall 4: body-only render — no outer box/border.
  Submit payloads are carried explicitly by `Foglet.TUI.Effect.modal_submit/3`.

  Honest Esc (Phase 28 FORM-06 / D-10, D-11): pressing Esc reseeds drafts
  via `State.seed_from_user/2` (which clears `candidate_theme_id`); the
  visible signal is the field values reverting on the next render. No
  flash status row — Account screens already advertise [Esc] Cancel in
  the global command bar.
  """

  alias Foglet.TUI.Effect
  alias Foglet.TUI.Screens.Account.State
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

  @spec render(State.t(), Theme.t(), keyword()) :: any()
  def render(%State{prefs_form: form}, %Theme{} = theme, opts \\ []) do
    form_opts = Keyword.merge([theme: theme, show_title: false], opts)
    ModalForm.render(form, form_opts)
  end

  @spec handle_key(map(), State.t(), map() | struct() | nil) ::
          {:ok, State.t(), list()} | :no_match
  def handle_key(%{key: key} = event, %State{} = state, current_user)
      when key in [
             :char,
             :backspace,
             :delete,
             :left,
             :right,
             :home,
             :end,
             :enter,
             :escape,
             :tab,
             :shift_tab,
             :backtab,
             :up,
             :down
           ] do
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
      {:submitted, %Effect{type: :modal_submit, payload: %{kind: :prefs, payload: payload}}} ->
        attrs = %{
          timezone: payload.timezone,
          preferences: %{"time_format" => payload.time_format},
          theme: payload.theme
        }

        {:ok,
         %{
           state
           | prefs_dirty?: false,
             status_message: nil,
             candidate_theme_id: nil
         }, [{:account_save_prefs, attrs}]}

      :cancelled ->
        # FORM-06 / D-10, D-11: Esc reseeds drafts (which clears
        # candidate_theme_id via seed_from_user); no flash status row.
        reseeded = State.seed_from_user(state, current_user)

        {:ok, %{reseeded | status_message: nil}, []}

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
  defp text_input_event?(%{key: :delete}), do: true
  defp text_input_event?(_), do: false
end
