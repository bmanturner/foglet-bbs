defmodule Foglet.TUI.Screens.Verify do
  @moduledoc """
  Email-verification code entry screen (D-08..D-12, VERIFY-02 Phase 6).

  State (in state.screen_state[:verify]) is owned by
  `Foglet.TUI.Screens.Verify.State`. See that module for field documentation.

  The 6-character `[ABC___]` buffer remains hand-rolled per inherited 07 D-02:
  the shared input widget cannot reproduce the slot visualization without a
  custom renderer, and its internal box would conflict with this flat slot
  display.
  """
  @behaviour Foglet.TUI.Screen

  alias Foglet.Accounts.Verification
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame

  import Raxol.Core.Renderer.View

  @max_attempts 5
  @cooldown_seconds 60
  @code_length 6

  @impl true
  @spec init_screen_state(keyword()) :: map()
  def init_screen_state(_opts \\ []), do: VerifyState.default()

  @impl true
  @spec render(map()) :: any()
  def render(state) do
    vs = VerifyState.get(state)
    theme = Theme.from_state(state)

    status_item =
      if VerifyState.cooldown?(vs) do
        text("Too many attempts. Please wait.", fg: theme.error.fg, style: [:bold])
      else
        text("Attempts: #{vs.attempts}/#{@max_attempts}", fg: theme.dim.fg)
      end

    content =
      column style: %{gap: 0} do
        [
          text("Enter the 6-character verification code:", fg: theme.primary.fg),
          text(""),
          text("  [#{pad_buffer_with_cursor(vs.buffer)}]", fg: theme.accent.fg, style: [:bold]),
          text(""),
          status_item
        ]
      end

    ScreenFrame.render(state, "Verify Email", content, [
      {"Enter", "Submit"},
      {"Backspace", "Delete"},
      {"Ctrl+R", "Resend code"},
      {"Esc", "Cancel"}
    ])
  end

  @impl true
  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  def handle_key(%{key: :escape}, state) do
    {:update, VerifyState.clear(%{state | current_screen: :login}), []}
  end

  def handle_key(%{key: :backspace}, state) do
    vs = VerifyState.get(state)
    new_len = max(String.length(vs.buffer) - 1, 0)
    new_vs = %{vs | buffer: String.slice(vs.buffer, 0, new_len)}
    {:update, VerifyState.put(state, new_vs), []}
  end

  def handle_key(%{key: :enter}, state) do
    {new_state, cmds} = submit_raw(state)
    {:update, new_state, cmds}
  end

  def handle_key(%{key: :char, char: c, ctrl: true}, state) when c in ["R", "r"],
    do: resend_code(state)

  # Typed character from Raxol: %{key: :char, char: c}.
  def handle_key(%{key: :char, char: c}, state) do
    vs = VerifyState.get(state)
    new_char = String.upcase(c)

    cond do
      VerifyState.cooldown?(vs) ->
        {:update, %{state | modal: cooldown_modal(vs.cooldown_until, "Too many attempts.")}, []}

      String.match?(new_char, ~r/\A[A-Z0-9]\z/) and String.length(vs.buffer) < @code_length ->
        new_vs = %{vs | buffer: vs.buffer <> new_char}
        {:update, VerifyState.put(state, new_vs), []}

      true ->
        :no_match
    end
  end

  def handle_key(_key, _state), do: :no_match

  @doc """
  Handle {:verify_event, _} messages (used by App.update/2 for dev-mode
  code auto-fill and resend commands originating from the commands list).
  """
  @spec handle_verify_event({:set_buffer, String.t()} | {:submit} | {:resend}, map()) ::
          {map(), list()}
  def handle_verify_event({:set_buffer, code}, state) do
    vs = VerifyState.get(state)
    {VerifyState.put(state, %{vs | buffer: code}), []}
  end

  def handle_verify_event({:submit}, state), do: submit_raw(state)
  def handle_verify_event({:resend}, state), do: resend_code_raw(state)

  defp submit_raw(%{current_user: nil} = state) do
    modal = %Foglet.TUI.Modal{type: :error, message: "No user context. Please register again."}
    {VerifyState.clear(%{state | modal: modal, current_screen: :login}), []}
  end

  defp submit_raw(state) do
    vs = VerifyState.get(state)

    cond do
      VerifyState.cooldown?(vs) ->
        {%{state | modal: cooldown_modal(vs.cooldown_until, "Too many attempts.")}, []}

      String.length(vs.buffer) != @code_length ->
        modal = %Foglet.TUI.Modal{type: :error, message: "Enter all 6 characters."}
        {%{state | modal: modal}, []}

      true ->
        verify_code(state, vs)
    end
  end

  defp resend_code(state) do
    vs = VerifyState.get(state)

    if VerifyState.resend_cooldown?(vs) do
      {:update,
       %{state | modal: cooldown_modal(vs.resend_cooldown_until, "Please wait to resend.")}, []}
    else
      {new_state, cmds} = resend_code_raw(state)
      {:update, new_state, cmds}
    end
  end

  defp resend_code_raw(%{current_user: nil} = state), do: {state, []}

  defp resend_code_raw(state) do
    case Verification.deliver_verification_code(state.current_user) do
      {:ok, :attempted} ->
        modal = %Foglet.TUI.Modal{
          type: :info,
          message: "If email delivery is available, new verification instructions have been sent."
        }

        vs = VerifyState.get(state)
        new_vs = VerifyState.after_resend(vs, resend_cooldown_seconds())

        {VerifyState.put(%{state | modal: modal}, new_vs), []}

      {:error, :unavailable} ->
        modal = %Foglet.TUI.Modal{
          type: :error,
          message: "Email verification is unavailable because email delivery is disabled."
        }

        {%{state | modal: modal}, []}

      {:error, _reason} ->
        modal = %Foglet.TUI.Modal{
          type: :error,
          message: "Verification instructions could not be sent. Please try again later."
        }

        {%{state | modal: modal}, []}
    end
  end

  # Render a 6-char slot with a block cursor at the current position.
  defp pad_buffer_with_cursor(buffer) when is_binary(buffer) do
    len = String.length(buffer)

    if len >= @code_length do
      buffer
    else
      remaining = @code_length - len - 1
      buffer <> "█" <> String.duplicate("_", remaining)
    end
  end

  # Build an :error modal saying "<prefix> Wait Ns." from a cooldown end time.
  defp cooldown_modal(%DateTime{} = until, prefix) when is_binary(prefix) do
    remaining = DateTime.diff(until, DateTime.utc_now(), :second)
    %Foglet.TUI.Modal{type: :error, message: "#{prefix} Wait #{max(remaining, 0)}s."}
  end

  defp verify_code(state, vs) do
    case Verification.verify_email_code(state.current_user, vs.buffer) do
      {:ok, confirmed} ->
        {VerifyState.clear(%{state | current_user: confirmed, current_screen: :main_menu}), []}

      {:error, :expired} ->
        modal = %Foglet.TUI.Modal{
          type: :error,
          message: "Code expired. Press [R] to request a new one."
        }

        {VerifyState.put(%{state | modal: modal}, %{vs | buffer: ""}), []}

      {:error, :invalid_code} ->
        handle_invalid_code(state, vs)
    end
  end

  defp handle_invalid_code(state, vs) do
    new_vs = VerifyState.record_invalid_attempt(vs, @max_attempts, @cooldown_seconds)

    modal = %Foglet.TUI.Modal{
      type: :error,
      message: "Invalid code (#{new_vs.attempts}/#{@max_attempts})."
    }

    {VerifyState.put(%{state | modal: modal}, new_vs), []}
  end

  defp resend_cooldown_seconds do
    Foglet.Config.email_verify_resend_cooldown_seconds()
  end
end
