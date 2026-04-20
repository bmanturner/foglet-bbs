defmodule Foglet.TUI.Screens.Register do
  @moduledoc """
  Registration wizard (SSH-04, D-01..D-07, D-22..D-24).

  Wizard steps by mode (D-23):
    * "open" / "sysop_approved"  →  handle → email → password → submit
    * "invite_only"              →  invite_code → handle → email → password → submit

  Terminal outcomes:
    * "open" / "invite_only" success → transition to :verify with a built code
    * "sysop_approved" success       → Accounts.register_pending_user/1 + terminate (D-07)

  SSH keys are NEVER collected here (D-24).
  """

  alias Foglet.Accounts
  alias Foglet.Config
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame

  import Raxol.Core.Renderer.View

  @modes ~w(open invite_only sysop_approved)

  @spec render(map()) :: any()
  def render(state) do
    w = state.register_wizard || default_wizard(state)
    theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()

    error_items =
      if w.error do
        [text(""), text(w.error, fg: theme.error.fg, style: [:bold])]
      else
        []
      end

    content =
      column style: %{gap: 0} do
        [
          text("Mode: #{w.mode}", fg: theme.dim.fg),
          text(""),
          text(prompt_for_step(w.step), fg: theme.primary.fg),
          text("> #{display_value(w.step, Map.get(w, :current_input, ""))}█",
            fg: theme.accent.fg,
            style: [:bold]
          )
        ] ++ error_items
      end

    ScreenFrame.render(state, "Register", content, [{"Enter", "Next"}, {"Esc", "Cancel"}])
  end

  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  def handle_key(%{key: :escape}, state) do
    {:update, %{state | current_screen: :login, register_wizard: nil}, []}
  end

  def handle_key(%{key: :enter}, state) do
    w = state.register_wizard || default_wizard(state)
    value = Map.get(w, :current_input, "")
    step = w.step
    # Dispatch back through App.update/2 → handle_wizard_event via command round-trip
    {:update, state, [{:register_wizard, {:submit_step, step, value}}]}
  end

  def handle_key(%{key: :backspace}, state) do
    w = state.register_wizard || default_wizard(state)
    current = Map.get(w, :current_input, "")
    new_input = String.slice(current, 0, max(String.length(current) - 1, 0))
    {:update, %{state | register_wizard: Map.put(w, :current_input, new_input)}, []}
  end

  # Typed character catch-all — Raxol native shape: %{key: :char, char: c}.
  # `c` is always a single grapheme string (guaranteed by InputParser).
  # Spacebar arrives as %{key: :char, char: " "} — no special-casing needed.
  def handle_key(%{key: :char, char: c}, state) do
    w = state.register_wizard || default_wizard(state)
    current = Map.get(w, :current_input, "")
    {:update, %{state | register_wizard: Map.put(w, :current_input, current <> c)}, []}
  end

  def handle_key(_key, _state), do: :no_match

  @doc """
  Advance the wizard in response to {:register_wizard, event} messages
  dispatched from TUI.App.update/2. Keeps wizard logic testable without
  a real keystroke stream.
  """
  @spec handle_wizard_event(
          {:submit_step, atom(), String.t()} | {:cancel},
          map()
        ) :: {map(), list()}
  def handle_wizard_event({:cancel}, state) do
    {%{state | current_screen: :login, register_wizard: nil}, []}
  end

  def handle_wizard_event({:submit_step, step, value}, state) do
    w = state.register_wizard || default_wizard(state)
    # Ensure current_input key exists (handles wizard maps created before this field was added)
    w = Map.put_new(w, :current_input, "")
    advance(w, step, value, state)
  end

  # --- Private ---

  defp default_wizard(state) do
    mode = registration_mode(state)
    %{mode: mode, step: first_step_for(mode), data: %{}, error: nil, current_input: ""}
  end

  defp registration_mode(state) do
    ctx = Map.get(state, :session_context) || %{}

    case Map.get(ctx, :registration_mode) do
      nil -> Config.get("registration_mode", "open")
      mode -> mode
    end
  end

  defp first_step_for("invite_only"), do: :invite_code
  defp first_step_for(mode) when mode in @modes, do: :handle
  defp first_step_for(_), do: :handle

  defp prompt_for_step(:invite_code), do: "Invite code:"
  defp prompt_for_step(:handle), do: "Choose a handle (2-20 chars):"
  defp prompt_for_step(:email), do: "Email address:"
  defp prompt_for_step(:password), do: "Password (min 8 chars):"
  defp prompt_for_step(:submitting), do: "Creating your account..."
  defp prompt_for_step(:done), do: "Account created."

  defp display_value(:password, current_input),
    do: String.duplicate("*", String.length(current_input))

  defp display_value(_step, current_input), do: current_input

  defp advance(w, :invite_code, value, state) do
    if valid_invite_code?(value) do
      new_w = %{
        w
        | step: :handle,
          data: Map.put(w.data, :invite_code, value),
          error: nil,
          current_input: ""
      }

      {%{state | register_wizard: new_w}, []}
    else
      modal = %{type: :error, message: "Invalid invite code."}

      new_w = %{w | step: :invite_code, error: "Invalid code.", current_input: ""}
      {%{state | modal: modal, register_wizard: new_w}, []}
    end
  end

  defp advance(w, :handle, value, state) do
    new_w = %{
      w
      | step: :email,
        data: Map.put(w.data, :handle, value),
        error: nil,
        current_input: ""
    }

    {%{state | register_wizard: new_w}, []}
  end

  defp advance(w, :email, value, state) do
    new_w = %{
      w
      | step: :password,
        data: Map.put(w.data, :email, value),
        error: nil,
        current_input: ""
    }

    {%{state | register_wizard: new_w}, []}
  end

  defp advance(w, :password, value, state) do
    new_w = %{
      w
      | step: :submitting,
        data: Map.put(w.data, :password, value),
        error: nil,
        current_input: ""
    }

    submit(new_w, state)
  end

  defp advance(_w, _unknown_step, _value, state), do: {state, []}

  defp valid_invite_code?(code) when is_binary(code) and byte_size(code) > 0 do
    if function_exported?(Foglet.Accounts, :consume_invite_code, 1) do
      # apply/3 is intentional here: Accounts.consume_invite_code/1 does not exist yet
      # (Phase 8). Using apply avoids a compile-time undefined-function warning.
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      case apply(Foglet.Accounts, :consume_invite_code, [code]) do
        :ok -> true
        _ -> false
      end
    else
      # Accept any non-empty alphanumeric code when invite_codes table isn't ready.
      # Phase 8 wires real invite code generation (D-04).
      Regex.match?(~r/\A[A-Za-z0-9]{4,32}\z/, code)
    end
  end

  defp valid_invite_code?(_), do: false

  defp submit(%{mode: "sysop_approved", data: data} = w, state) do
    case Accounts.register_pending_user(data) do
      {:ok, _user} ->
        modal = %{
          type: :info,
          title: "Account Pending",
          message:
            "Your account has been created and is pending sysop approval. You will be notified by email."
        }

        {%{state | modal: modal, register_wizard: nil},
         [{:terminate_after_modal, :pending_approval}]}

      {:error, changeset} ->
        new_w = %{w | error: changeset_error_text(changeset), step: :handle}
        {%{state | register_wizard: new_w}, []}
    end
  end

  defp submit(%{data: data} = w, state) do
    # open or invite_only — register active user, route via post_login_screen/1
    # (Phase 6 D-06: config-driven verify/main_menu decision).
    case Accounts.register_user(data) do
      {:ok, user} ->
        case Accounts.post_login_screen(user) do
          :verify ->
            {:ok, code} = Accounts.build_verify_code(user)

            if Mix.env() != :prod do
              require Logger
              Logger.info("[verify] code for @#{user.handle}: #{code}")
            end

            new_state = %{
              state
              | current_user: user,
                current_screen: :verify,
                register_wizard: nil,
                verify_state: %{
                  buffer: "",
                  attempts: 0,
                  cooldown_until: nil,
                  resend_cooldown_until: nil
                }
            }

            {new_state, []}

          :main_menu ->
            # require_email_verification is false — skip verify screen, promote
            # the session directly. {:promote_session, user} routes through the
            # App's session supervisor (SSH-05 one-session-per-user) and lands
            # the user on :main_menu (app.ex do_update/2 at line ~498-504).
            new_state = %{state | current_user: user, register_wizard: nil}
            {new_state, [{:promote_session, user}]}
        end

      {:error, changeset} ->
        new_w = %{w | error: changeset_error_text(changeset), step: :handle}
        {%{state | register_wizard: new_w}, []}
    end
  end

  defp changeset_error_text(cs) do
    Enum.map_join(cs.errors, "; ", fn {field, {msg, _}} -> "#{field}: #{msg}" end)
  end
end
