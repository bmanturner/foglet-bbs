defmodule Foglet.TUI.Screens.Verify do
  @moduledoc """
  Email-verification code entry screen (D-08..D-12, VERIFY-02 Phase 6).

  State (in state.verify_state):
    * buffer                — the 0..6 chars typed so far
    * attempts              — count of invalid attempts since last success
    * cooldown_until        — DateTime when the invalid-attempts cooldown ends, or nil
                              (set after @max_attempts failures; blocks code entry,
                              NOT resend)
    * resend_cooldown_until — DateTime when the resend cooldown ends, or nil
                              (set after a successful resend; blocks further resends,
                              NOT code entry)

  The two cooldowns are independent (VERIFY-02 D-10): hitting invalid 5x still
  allows a resend; hitting resend once still allows code entry.

  Resend resets `attempts` and `cooldown_until` intentionally (D-09): a fresh
  code makes any previous invalid-attempt count meaningless, so the counter is
  cleared to give the user a clean slate. This is a deliberate UX design
  decision — it does NOT bypass security, because the old code becomes invalid
  once a new one is issued.
  """

  alias Foglet.Accounts
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame

  import Raxol.Core.Renderer.View

  @max_attempts 5
  @cooldown_seconds 60
  @code_length 6

  @spec render(map()) :: any()
  def render(state) do
    vs =
      state.verify_state ||
        %{buffer: "", attempts: 0, cooldown_until: nil, resend_cooldown_until: nil}

    theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()

    status_item =
      if cooldown?(vs) do
        text("Too many attempts. Please wait.", fg: theme.error.fg, style: [:bold])
      else
        text("Attempts: #{vs.attempts}/#{@max_attempts}", fg: theme.dim.fg)
      end

    content =
      column style: %{gap: 0} do
        [
          text("Enter the 6-character code emailed to you:", fg: theme.primary.fg),
          text(""),
          text("  [#{pad_buffer_with_cursor(vs.buffer)}]", fg: theme.accent.fg, style: [:bold]),
          text(""),
          status_item
        ]
      end

    ScreenFrame.render(state, "Verify Email", content, [
      {"Enter", "Submit"},
      {"Backspace", "Delete"},
      {"R", "Resend code"},
      {"Esc", "Cancel"}
    ])
  end

  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  def handle_key(%{key: :escape}, state) do
    {:update, %{state | current_screen: :login, verify_state: nil}, []}
  end

  def handle_key(%{key: :backspace}, state) do
    vs =
      state.verify_state ||
        %{buffer: "", attempts: 0, cooldown_until: nil, resend_cooldown_until: nil}

    new_len = max(String.length(vs.buffer) - 1, 0)
    new_vs = %{vs | buffer: String.slice(vs.buffer, 0, new_len)}
    {:update, %{state | verify_state: new_vs}, []}
  end

  def handle_key(%{key: :enter}, state) do
    {new_state, cmds} = submit_raw(state)
    {:update, new_state, cmds}
  end

  def handle_key(%{key: :char, char: c}, state) when c in ["R", "r"], do: resend_code(state)

  # Typed character — Raxol native shape: %{key: :char, char: c}.
  # Only accept uppercase alphanumeric chars for the verification code.
  def handle_key(%{key: :char, char: c}, state) do
    vs =
      state.verify_state ||
        %{buffer: "", attempts: 0, cooldown_until: nil, resend_cooldown_until: nil}

    new_char = String.upcase(c)

    cond do
      cooldown?(vs) ->
        {:update, %{state | modal: cooldown_modal(vs.cooldown_until, "Too many attempts.")}, []}

      String.match?(new_char, ~r/\A[A-Z0-9]\z/) and String.length(vs.buffer) < @code_length ->
        new_vs = %{vs | buffer: vs.buffer <> new_char}
        {:update, %{state | verify_state: new_vs}, []}

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
    vs =
      state.verify_state ||
        %{buffer: "", attempts: 0, cooldown_until: nil, resend_cooldown_until: nil}

    {%{state | verify_state: %{vs | buffer: code}}, []}
  end

  def handle_verify_event({:submit}, state), do: submit_raw(state)
  def handle_verify_event({:resend}, state), do: resend_code_raw(state)

  # --- Private ---

  # Renders a 6-char code slot with a block cursor at the current position.
  # ""       → "█_____"  (cursor at first position)
  # "XK7"    → "XK7█__"  (cursor after last typed char)
  # "XK7P2Q" → "XK7P2Q" (full — no cursor needed)
  defp pad_buffer_with_cursor(buffer) when is_binary(buffer) do
    len = String.length(buffer)

    if len >= @code_length do
      buffer
    else
      remaining = @code_length - len - 1
      buffer <> "█" <> String.duplicate("_", remaining)
    end
  end

  defp cooldown?(%{cooldown_until: nil}), do: false

  defp cooldown?(%{cooldown_until: t}) do
    DateTime.compare(DateTime.utc_now(), t) == :lt
  end

  defp resend_cooldown?(%{resend_cooldown_until: nil}), do: false

  defp resend_cooldown?(%{resend_cooldown_until: t}) do
    DateTime.compare(DateTime.utc_now(), t) == :lt
  end

  # Build an :error modal that says <prefix> Wait Ns. given a DateTime
  # representing when the cooldown ends. Takes the field value directly
  # (not the whole verify_state) so the same helper serves both the
  # invalid-attempts cooldown and the resend cooldown (D-11).
  defp cooldown_modal(%DateTime{} = until, prefix) when is_binary(prefix) do
    remaining = DateTime.diff(until, DateTime.utc_now(), :second)
    %{type: :error, message: "#{prefix} Wait #{max(remaining, 0)}s."}
  end

  defp submit_raw(%{current_user: nil} = state) do
    modal = %{type: :error, message: "No user context. Please register again."}
    {%{state | modal: modal, current_screen: :login, verify_state: nil}, []}
  end

  defp submit_raw(state) do
    vs =
      state.verify_state ||
        %{buffer: "", attempts: 0, cooldown_until: nil, resend_cooldown_until: nil}

    cond do
      cooldown?(vs) ->
        {%{state | modal: cooldown_modal(vs.cooldown_until, "Too many attempts.")}, []}

      String.length(vs.buffer) != @code_length ->
        modal = %{type: :error, message: "Enter all 6 characters."}
        {%{state | modal: modal}, []}

      true ->
        case Accounts.verify_email_code(state.current_user, vs.buffer) do
          {:ok, confirmed} ->
            {%{state | current_user: confirmed, current_screen: :main_menu, verify_state: nil},
             []}

          {:error, :expired} ->
            modal = %{
              type: :error,
              message: "Code expired. Press [R] to request a new one."
            }

            {%{state | modal: modal, verify_state: %{vs | buffer: ""}}, []}

          {:error, :invalid_code} ->
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

            modal = %{type: :error, message: "Invalid code (#{new_attempts}/#{@max_attempts})."}
            {%{state | modal: modal, verify_state: new_vs}, []}
        end
    end
  end

  defp resend_code(state) do
    vs =
      state.verify_state ||
        %{buffer: "", attempts: 0, cooldown_until: nil, resend_cooldown_until: nil}

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
    case Accounts.build_verify_code(state.current_user) do
      {:ok, _code} ->
        modal = %{type: :info, message: "A new code has been sent."}

        cooldown_seconds =
          case Foglet.Config.get("email_verify_resend_cooldown_seconds", 60) do
            n when is_integer(n) and n > 0 -> n
            _ -> 60
          end

        now = DateTime.utc_now()

        vs =
          state.verify_state ||
            %{buffer: "", attempts: 0, cooldown_until: nil, resend_cooldown_until: nil}

        new_vs = %{
          vs
          | buffer: "",
            attempts: 0,
            cooldown_until: nil,
            resend_cooldown_until: DateTime.add(now, cooldown_seconds, :second)
        }

        {%{state | modal: modal, verify_state: new_vs}, []}

      {:error, _cs} ->
        modal = %{type: :error, message: "Could not generate a new code. Try again later."}
        {%{state | modal: modal}, []}
    end
  end
end
