defmodule Foglet.TUI.Screens.Verify do
  @moduledoc """
  Email-verification code entry screen (D-08..D-12).

  State (in state.verify_state):
    * buffer         — the 0..6 chars typed so far
    * attempts       — count of invalid attempts since last success
    * cooldown_until — DateTime when cooldown ends, or nil
  """

  alias Foglet.Accounts
  alias Foglet.TUI.Widgets.KeyBar

  import Raxol.Core.Renderer.View

  @max_attempts 5
  @cooldown_seconds 60
  @code_length 6

  @spec render(map()) :: any()
  def render(state) do
    vs = state.verify_state || %{buffer: "", attempts: 0, cooldown_until: nil}

    status_item =
      if cooldown?(vs) do
        text("Too many attempts. Please wait.", fg: :red)
      else
        text("Attempts: #{vs.attempts}/#{@max_attempts}", style: [:dim])
      end

    box style: %{border: :single, padding: 1} do
      column style: %{gap: 0} do
        [
          text(" Verify Email ", style: [:bold]),
          divider(),
          column style: %{gap: 0} do
            [
              text("Enter the 6-character code emailed to you:", fg: :green),
              text(""),
              text_input(value: vs.buffer, placeholder: "XXXXXX"),
              text(""),
              status_item
            ]
          end,
          KeyBar.render([
            {"Enter", "Submit"},
            {"Backspace", "Delete"},
            {"R", "Resend code"},
            {"Esc", "Cancel"}
          ])
        ]
      end
    end
  end

  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  def handle_key(%{key: "escape"}, state) do
    {:update, %{state | current_screen: :login, verify_state: nil}, []}
  end

  def handle_key(%{key: "backspace"}, state) do
    vs = state.verify_state || %{buffer: "", attempts: 0, cooldown_until: nil}
    new_len = max(String.length(vs.buffer) - 1, 0)
    new_vs = %{vs | buffer: String.slice(vs.buffer, 0, new_len)}
    {:update, %{state | verify_state: new_vs}, []}
  end

  def handle_key(%{key: "enter"}, state) do
    {new_state, cmds} = submit_raw(state)
    {:update, new_state, cmds}
  end

  def handle_key(%{key: "R"}, state), do: resend_code(state)
  def handle_key(%{key: "r"}, state), do: resend_code(state)

  # Binary-key catch-all. String.length/1 is NOT guard-safe, so we gate the
  # single-grapheme check in the body. Multi-char named keys (up, f1, etc.)
  # that slip through fall to :no_match.
  def handle_key(%{key: key}, state) when is_binary(key) do
    vs = state.verify_state || %{buffer: "", attempts: 0, cooldown_until: nil}

    cond do
      String.length(key) != 1 ->
        :no_match

      cooldown?(vs) ->
        {:update, %{state | modal: cooldown_modal(vs)}, []}

      true ->
        new_char = String.upcase(key)

        if String.match?(new_char, ~r/\A[A-Z0-9]\z/) and
             String.length(vs.buffer) < @code_length do
          new_vs = %{vs | buffer: vs.buffer <> new_char}
          {:update, %{state | verify_state: new_vs}, []}
        else
          :no_match
        end
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
    vs = state.verify_state || %{buffer: "", attempts: 0, cooldown_until: nil}
    {%{state | verify_state: %{vs | buffer: code}}, []}
  end

  def handle_verify_event({:submit}, state), do: submit_raw(state)
  def handle_verify_event({:resend}, state), do: resend_code_raw(state)

  # --- Private ---

  defp cooldown?(%{cooldown_until: nil}), do: false

  defp cooldown?(%{cooldown_until: t}) do
    DateTime.compare(DateTime.utc_now(), t) == :lt
  end

  defp cooldown_modal(vs) do
    remaining = DateTime.diff(vs.cooldown_until, DateTime.utc_now(), :second)
    %{type: :error, message: "Too many attempts. Wait #{max(remaining, 0)}s."}
  end

  defp submit_raw(%{current_user: nil} = state) do
    modal = %{type: :error, message: "No user context. Please register again."}
    {%{state | modal: modal, current_screen: :login, verify_state: nil}, []}
  end

  defp submit_raw(state) do
    vs = state.verify_state || %{buffer: "", attempts: 0, cooldown_until: nil}

    cond do
      cooldown?(vs) ->
        {%{state | modal: cooldown_modal(vs)}, []}

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
    {new_state, cmds} = resend_code_raw(state)
    {:update, new_state, cmds}
  end

  defp resend_code_raw(%{current_user: nil} = state), do: {state, []}

  defp resend_code_raw(state) do
    case Accounts.build_verify_code(state.current_user) do
      {:ok, _code} ->
        modal = %{type: :info, message: "A new code has been sent."}
        vs = state.verify_state || %{buffer: "", attempts: 0, cooldown_until: nil}
        new_vs = %{vs | buffer: "", attempts: 0, cooldown_until: nil}
        {%{state | modal: modal, verify_state: new_vs}, []}

      {:error, _cs} ->
        modal = %{type: :error, message: "Could not generate a new code. Try again later."}
        {%{state | modal: modal}, []}
    end
  end
end
