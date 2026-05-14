defmodule Foglet.TUI.Screens.Login.ResetRecovery do
  @moduledoc """
  Unified reducer for the Login recovery surface.

  The surface exposes reset-token request and reset-token consumption together,
  while preserving the existing `:reset_request` and `:reset_token` task atoms
  for async result routing.
  """

  alias Foglet.TUI.Effect
  alias Foglet.TUI.KeyBinding
  alias Foglet.TUI.Screens.Login.{ResetConsume, ResetRequest}
  alias Foglet.TUI.Screens.Login.State, as: LoginState
  alias Foglet.TUI.Screens.Shared.FocusInput
  alias Foglet.TUI.Widgets.Input.TextInput

  @spec handle_key(map(), map()) ::
          :no_match | {:update, map(), [Effect.t()]} | {map(), [Effect.t()]}
  def handle_key(%{key: :right} = event, state) do
    if switch_right?(state), do: switch_pane(state, :token), else: delegate_active(event, state)
  end

  def handle_key(%{key: :left} = event, state) do
    if switch_left?(state), do: switch_pane(state, :request), else: delegate_active(event, state)
  end

  def handle_key(event, state) do
    if KeyBinding.cancel?(event) do
      {:update, LoginState.put(state, LoginState.default()), []}
    else
      delegate_active(event, state)
    end
  end

  defp delegate_active(event, state) do
    case active_pane(LoginState.get(state)) do
      :request -> ResetRequest.handle_key(event, state)
      :token -> ResetConsume.handle_key(event, state)
    end
  end

  defp switch_right?(state) do
    login_ss = LoginState.get(state)
    active_pane(login_ss) == :request and cursor_at_end?(login_ss.identifier_input)
  end

  defp switch_left?(state) do
    login_ss = LoginState.get(state)
    active_pane(login_ss) == :token and cursor_at_start?(focused_token_input(login_ss))
  end

  defp switch_pane(state, pane) do
    login_ss = LoginState.get(state)

    {:update,
     LoginState.put(state, %{login_ss | active_pane: pane, focused_field: initial_focus(pane)}),
     []}
  end

  defp active_pane(%{active_pane: :token}), do: :token
  defp active_pane(_state_or_substate), do: :request

  defp initial_focus(:request), do: :identifier
  defp initial_focus(:token), do: :token

  defp focused_token_input(login_ss) do
    FocusInput.get_focused(login_ss, &LoginState.input_key/1, :token)
  end

  defp cursor_at_start?(%TextInput{raxol_state: %{cursor_pos: cursor_pos}}), do: cursor_pos == 0

  defp cursor_at_end?(%TextInput{raxol_state: %{cursor_pos: cursor_pos, value: value}}) do
    cursor_pos == length(String.graphemes(value || ""))
  end
end
