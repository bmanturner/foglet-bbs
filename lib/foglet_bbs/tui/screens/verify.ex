defmodule Foglet.TUI.Screens.Verify do
  @moduledoc """
  Email-verification code entry screen (D-08..D-12, VERIFY-02 Phase 6).

  State (in state.screen_state[:verify]):
    * buffer                - the 0..6 chars typed so far
    * attempts              - count of invalid attempts since last success
    * cooldown_until        - DateTime when the invalid-attempts cooldown ends, or nil
                              (set after @max_attempts failures; blocks code entry,
                              NOT resend)
    * resend_cooldown_until - DateTime when the resend cooldown ends, or nil
                              (set after a successful resend; blocks further resends,
                              NOT code entry)
  The two cooldowns are independent (VERIFY-02 D-10): hitting invalid 5x still
  allows a resend; hitting resend once still allows code entry.
  Resend resets `attempts` and `cooldown_until` intentionally (D-09): a fresh
  code makes any previous invalid-attempt count meaningless, so the counter is
  cleared to give the user a clean slate. This is a deliberate UX design
  decision - it does NOT bypass security, because the old code becomes invalid
  once a new one is issued.
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
  def init_screen_state(_opts \\ []), do: default_verify_ss()

  @impl true
  @spec render(map()) :: any()
  def render(state) do
    vs = get_verify_ss(state)
    theme = Theme.from_state(state)

    status_item =
      if cooldown?(vs) do
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
    {:update, clear_verify_ss(%{state | current_screen: :login}), []}
  end

  def handle_key(%{key: :backspace}, state) do
    vs = get_verify_ss(state)
    new_len = max(String.length(vs.buffer) - 1, 0)
    new_vs = %{vs | buffer: String.slice(vs.buffer, 0, new_len)}
    {:update, put_verify_ss(state, new_vs), []}
  end

  def handle_key(%{key: :enter}, state) do
    {new_state, cmds} = submit_raw(state)
    {:update, new_state, cmds}
  end

  def handle_key(%{key: :char, char: c, ctrl: true}, state) when c in ["R", "r"],
    do: resend_code(state)

  # Typed character from Raxol: %{key: :char, char: c}.
  def handle_key(%{key: :char, char: c}, state) do
    vs = get_verify_ss(state)
    new_char = String.upcase(c)

    cond do
      cooldown?(vs) ->
        {:update, %{state | modal: cooldown_modal(vs.cooldown_until, "Too many attempts.")}, []}

      String.match?(new_char, ~r/\A[A-Z0-9]\z/) and String.length(vs.buffer) < @code_length ->
        new_vs = %{vs | buffer: vs.buffer <> new_char}
        {:update, put_verify_ss(state, new_vs), []}

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
    vs = get_verify_ss(state)
    {put_verify_ss(state, %{vs | buffer: code}), []}
  end

  def handle_verify_event({:submit}, state), do: submit_raw(state)
  def handle_verify_event({:resend}, state), do: resend_code_raw(state)

  defp submit_raw(%{current_user: nil} = state) do
    modal = %Foglet.TUI.Modal{type: :error, message: "No user context. Please register again."}
    {clear_verify_ss(%{state | modal: modal, current_screen: :login}), []}
  end

  defp submit_raw(state) do
    vs = get_verify_ss(state)

    cond do
      cooldown?(vs) ->
        {%{state | modal: cooldown_modal(vs.cooldown_until, "Too many attempts.")}, []}

      String.length(vs.buffer) != @code_length ->
        modal = %Foglet.TUI.Modal{type: :error, message: "Enter all 6 characters."}
        {%{state | modal: modal}, []}

      true ->
        verify_code(state, vs)
    end
  end

  defp resend_code(state) do
    vs = get_verify_ss(state)

    if resend_cooldown?(vs) do
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

        cooldown_seconds = resend_cooldown_seconds()
        now = DateTime.utc_now()
        vs = get_verify_ss(state)

        new_vs = %{
          vs
          | buffer: "",
            attempts: 0,
            cooldown_until: nil,
            resend_cooldown_until: DateTime.add(now, cooldown_seconds, :second)
        }

        {put_verify_ss(%{state | modal: modal}, new_vs), []}

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

  defp default_verify_ss do
    %{buffer: "", attempts: 0, cooldown_until: nil, resend_cooldown_until: nil}
  end

  defp get_verify_ss(state),
    do: Map.get(state.screen_state || %{}, :verify) || default_verify_ss()

  defp put_verify_ss(state, vs) do
    %{state | screen_state: Map.put(state.screen_state || %{}, :verify, vs)}
  end

  defp clear_verify_ss(state) do
    %{state | screen_state: Map.delete(state.screen_state || %{}, :verify)}
  end

  defp cooldown?(%{cooldown_until: nil}), do: false

  defp cooldown?(%{cooldown_until: t}) do
    DateTime.compare(DateTime.utc_now(), t) == :lt
  end

  defp resend_cooldown?(%{resend_cooldown_until: nil}), do: false

  defp resend_cooldown?(%{resend_cooldown_until: t}) do
    DateTime.compare(DateTime.utc_now(), t) == :lt
  end

  defp verify_code(state, vs) do
    case Verification.verify_email_code(state.current_user, vs.buffer) do
      {:ok, confirmed} ->
        {clear_verify_ss(%{state | current_user: confirmed, current_screen: :main_menu}), []}

      {:error, :expired} ->
        modal = %Foglet.TUI.Modal{
          type: :error,
          message: "Code expired. Press [R] to request a new one."
        }

        {put_verify_ss(%{state | modal: modal}, %{vs | buffer: ""}), []}

      {:error, :invalid_code} ->
        handle_invalid_code(state, vs)
    end
  end

  defp handle_invalid_code(state, vs) do
    new_attempts = vs.attempts + 1

    new_vs =
      if new_attempts >= @max_attempts do
        %{
          vs
          | buffer: "",
            attempts: new_attempts,
            cooldown_until: DateTime.add(DateTime.utc_now(), @cooldown_seconds, :second)
        }
      else
        %{vs | buffer: "", attempts: new_attempts}
      end

    modal = %Foglet.TUI.Modal{
      type: :error,
      message: "Invalid code (#{new_attempts}/#{@max_attempts})."
    }

    {put_verify_ss(%{state | modal: modal}, new_vs), []}
  end

  defp resend_cooldown_seconds do
    Foglet.Config.email_verify_resend_cooldown_seconds()
  end
end
