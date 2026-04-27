defmodule Foglet.TUI.Screens.Account.ProfileForm do
  @moduledoc """
  PROFILE tab body for Account (D-10, D-13, D-16, Phase 25 Plan 02).

  Delegates rendering and event handling to Modal.Form (D-01 / Pattern 1).
  Draft keys are atoms matching `Foglet.TUI.Screens.Account.State`.

  Per RESEARCH Pitfall 4: this module renders Modal.Form body-only — no
  outer box/border. The screen chrome (ScreenFrame) provides the border.

  Per RESEARCH Pitfall 2 / Codex Concern 4: submit payloads are captured
  via `Modal.Form.SubmitStash` rather than raw `Process.put/get`.

  Honest Esc (Phase 28 FORM-06 / D-10, D-11): pressing Esc reseeds drafts
  via `State.seed_from_user/2`; the visible signal is the field values
  reverting on the next render. No flash status row — Account screens
  already advertise [Esc] Cancel in the global command bar.
  """

  alias Foglet.TUI.Screens.Account.State
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm
  alias Foglet.TUI.Widgets.Modal.Form.SubmitStash

  @spec render(State.t(), Theme.t()) :: any()
  def render(%State{profile_form: form}, %Theme{} = theme) do
    ModalForm.render(form, theme: theme)
  end

  @spec handle_key(map(), State.t(), map() | struct() | nil) ::
          {:ok, State.t(), list()} | :no_match
  def handle_key(%{key: key} = event, %State{} = state, current_user)
      when key in [:char, :backspace, :enter, :escape, :tab, :shift_tab, :backtab, :up, :down] do
    do_handle_key(event, state, current_user)
  end

  def handle_key(_event, %State{}, _current_user), do: :no_match

  defp do_handle_key(event, %State{profile_form: form} = state, current_user) do
    {new_form, action} = ModalForm.handle_event(event, form)
    state = %{state | profile_form: new_form}

    case action do
      :submitted ->
        {:profile, payload} = SubmitStash.pop(__MODULE__)

        attrs = %{
          location: payload.location,
          tagline: payload.tagline,
          real_name: payload.real_name
        }

        {:ok, %{state | profile_dirty?: false, status_message: "Profile ready to save."},
         [{:account_save_profile, attrs}]}

      :cancelled ->
        # FORM-06 / D-10, D-11: Esc reseeds drafts; the visible signal is the
        # field values reverting on the next render. No flash status row —
        # Account screens already advertise [Esc] Cancel in the global
        # command bar.
        reseeded = State.seed_from_user(state, current_user)
        {:ok, %{reseeded | status_message: nil}, []}

      _ ->
        dirty? = action == nil and text_input_event?(event)

        {:ok, %{state | profile_dirty?: state.profile_dirty? or dirty?}, []}
    end
  end

  defp text_input_event?(%{key: :char}), do: true
  defp text_input_event?(%{key: :backspace}), do: true
  defp text_input_event?(_), do: false
end
