defmodule Foglet.TUI.Screens.Account.ProfileForm do
  @moduledoc """
  PROFILE tab body for Account (D-10, D-13, D-16, Phase 25 Plan 02).

  Delegates rendering and event handling to Modal.Form (D-01 / Pattern 1).
  Draft keys are atoms matching `Foglet.TUI.Screens.Account.State`.

  Per RESEARCH Pitfall 4: this module renders Modal.Form body-only — no
  outer box/border. The screen chrome (ScreenFrame) provides the border.

  Per RESEARCH Pitfall 2 / Codex Concern 4: submit payloads are captured
  via `Modal.Form.SubmitStash` rather than raw `Process.put/get`.
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
  def handle_key(event, %State{} = state, current_user) do
    if form_event?(event) do
      do_handle_key(event, state, current_user)
    else
      :no_match
    end
  end

  defp do_handle_key(event, %State{profile_form: form} = state, current_user) do
    {new_form, action} = ModalForm.handle_event(event, form)
    state = %{state | profile_form: new_form}

    case action do
      :submitted ->
        SubmitStash.with_stashed(__MODULE__, fn
          nil ->
            {:ok, state, []}

          {:profile, payload} ->
            errors = validate_profile(payload)

            if map_size(errors) == 0 do
              attrs = %{
                location: payload.location,
                tagline: payload.tagline,
                real_name: payload.real_name
              }

              {:ok, %{state | profile_dirty?: false, status_message: "Profile ready to save."},
               [{:account_save_profile, attrs}]}
            else
              {:ok, %{state | profile_form: ModalForm.set_errors(new_form, errors)}, []}
            end
        end)

      :cancelled ->
        reseeded = State.seed_from_user(state, current_user)
        {:ok, %{reseeded | status_message: "Profile changes discarded."}, []}

      _ ->
        dirty? = action == nil and text_input_event?(event)

        {:ok, %{state | profile_dirty?: state.profile_dirty? or dirty?}, []}
    end
  end

  defp validate_profile(payload) do
    max_lengths = %{location: 80, tagline: 120, real_name: 120}

    Enum.reduce(max_lengths, %{}, fn {field, max_len}, errors ->
      value = Map.get(payload, field) || ""

      if String.length(value) > max_len do
        Map.put(errors, field, "must be at most #{max_len} characters")
      else
        errors
      end
    end)
  end

  defp text_input_event?(%{key: :char}), do: true
  defp text_input_event?(%{key: :backspace}), do: true
  defp text_input_event?(_), do: false

  # Events that a text form should process — everything that has meaning inside
  # a text field, plus form navigation (Tab/Shift-Tab) and form commands
  # (Enter/Esc). Function keys, mouse events, and other unknown keys are
  # forwarded as :no_match so the screen layer can handle them.
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
