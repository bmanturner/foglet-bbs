defmodule Foglet.TUI.Screens.Register do
  @moduledoc """
  Registration wizard (SSH-04, post-Phase-2 two-step form).

  Wizard structure by mode:
    * "open" / "sysop_approved"  →  :combined step (handle, email, password, confirm) → submit
    * "invite_only"              →  :invite_code step → :combined step → submit

  State lives in `state.screen_state[:register]` (post-Phase-2 migration from the
  top-level `state.register_wizard` field removed in AUDIT-13(b)). `register.ex`
  self-initializes on first `get_register_ss/1` call (no `app.ex` bootstrap).

  `handle_wizard_event/2` is the §6 public domain-hook dispatched from
  `app.ex:do_update({:register_wizard, event}, state)`.

  Terminal outcomes:
    * "open" / "invite_only" success → transition to :verify with a built code
    * "sysop_approved" success       → Accounts.register_pending_user/1 + terminate

  SSH keys are NEVER collected here (D-24).
  """

  alias Foglet.{Accounts, Config}
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Input.TextInput

  import Raxol.Core.Renderer.View

  # §2 Module attributes

  @log_verify_codes Application.compile_env(:foglet_bbs, :log_verify_codes, false)

  @focus_cycle [:handle, :email, :password, :confirm_password]

  # §3 init_screen_state/1 (PUBLIC — AUDIT-19, D-05)

  @doc """
  Returns a minimal "open"-mode stub suitable for pre-populating
  `screen_state[:register]` (e.g. during screen-transition bootstrapping).

  **Important:** This function always returns `mode: "open"` and `step: :combined`
  regardless of the opts or runtime configuration. Callers that need a
  mode-aware initial state (e.g. `"invite_only"` → `:invite_code` step) should
  rely on the lazy `get_register_ss/1` path — register.ex self-initializes
  via `init_screen_state_for/1` (which reads `state.session_context`) on the
  first `render/1` or `handle_key/2` call. This divergence is intentional and
  is tracked for Phase 8 when invite-code logic is fully wired (D-04, D-05).
  """
  @spec init_screen_state(keyword()) :: map()
  def init_screen_state(_opts \\ []) do
    %{
      mode: "open",
      step: :combined,
      focused_field: :handle,
      invite_code_input: TextInput.init([]),
      handle_input: TextInput.init([]),
      email_input: TextInput.init([]),
      password_input: TextInput.init(mask_char: "*"),
      confirm_input: TextInput.init(mask_char: "*"),
      collected: %{},
      error: nil
    }
  end

  # §4 render/1 (PUBLIC)

  @spec render(map()) :: any()
  def render(state) do
    reg = get_register_ss(state)
    theme = Theme.from_state(state)

    content =
      column style: %{gap: 0} do
        [
          case reg.step do
            :invite_code -> render_invite_step(reg, theme)
            :combined -> render_combined_step(reg, theme)
          end
        ]
      end

    ScreenFrame.render(state, "Register", content, keys_for(reg.step))
  end

  # §5 handle_key/2 (PUBLIC)

  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  def handle_key(%{key: :escape}, state) do
    {:update, clear_register_ss(%{state | current_screen: :login}), []}
  end

  def handle_key(key_event, state) do
    reg = get_register_ss(state)

    case reg.step do
      :invite_code -> handle_invite_key(key_event, state)
      :combined -> handle_combined_key(key_event, state)
    end
  end

  # §6 handle_wizard_event/2 (PUBLIC — §6 domain hook called from app.ex:352)

  @doc """
  Dispatched from `app.ex:do_update({:register_wizard, event}, state)`.

  Returns bare `{state, commands}` (NOT `{:update, ...}`) because the dispatch in
  app.ex passes the return directly to process_screen_commands/2.
  """
  @spec handle_wizard_event(
          {:submit_step, atom(), String.t()} | {:cancel},
          map()
        ) :: {map(), list()}
  def handle_wizard_event({:cancel}, state) do
    {clear_register_ss(%{state | current_screen: :login}), []}
  end

  def handle_wizard_event({:submit_step, :invite_code, value}, state) do
    reg = get_register_ss(state)

    if valid_invite_code?(value) do
      new_reg = %{
        reg
        | step: :combined,
          focused_field: :handle,
          collected: Map.put(reg.collected, :invite_code, value),
          error: nil
      }

      {put_register_ss(state, new_reg), []}
    else
      new_reg = %{reg | error: "Invalid code."}
      {put_register_ss(state, new_reg), []}
    end
  end

  def handle_wizard_event({:submit_step, :combined, _value}, state) do
    # Combined-step submission happens inline in handle_combined_key/2 via
    # validate_and_submit/2. This clause exists only so {:submit_step, :combined, _}
    # round-trips cleanly if anything emits it.
    {state, []}
  end

  # §7 Private key handlers

  # --- :invite_code step key handlers ---

  defp handle_invite_key(%{key: :enter}, state) do
    reg = get_register_ss(state)
    value = reg.invite_code_input.raxol_state.value
    # Round-trip through App.update/2 per D-08 Watch List (i) and Pitfall 4.
    {:update, state, [{:register_wizard, {:submit_step, :invite_code, value}}]}
  end

  defp handle_invite_key(event, state) do
    reg = get_register_ss(state)
    {new_input, _action} = TextInput.handle_event(event, reg.invite_code_input)
    new_reg = %{reg | invite_code_input: new_input}
    {:update, put_register_ss(state, new_reg), []}
  end

  # --- :combined step key handlers ---

  defp handle_combined_key(%{key: :tab}, state) do
    reg = get_register_ss(state)
    new_reg = %{reg | focused_field: next_field(reg.focused_field), error: nil}
    {:update, put_register_ss(state, new_reg), []}
  end

  defp handle_combined_key(%{key: :enter}, state) do
    reg = get_register_ss(state)

    case reg.focused_field do
      :confirm_password ->
        validate_and_submit(reg, state)

      field ->
        new_reg = %{reg | focused_field: next_field(field), error: nil}
        {:update, put_register_ss(state, new_reg), []}
    end
  end

  defp handle_combined_key(event, state) do
    {new_input, _action} = TextInput.handle_event(event, focused_input(state))
    {:update, update_focused_input(state, new_input), []}
  end

  # --- Focus + validation helpers ---

  defp validate_and_submit(reg, state) do
    pw = reg.password_input.raxol_state.value
    cpw = reg.confirm_input.raxol_state.value

    if pw == cpw do
      submit(reg, state)
    else
      new_reg = %{reg | error: "Passwords do not match."}
      {:update, put_register_ss(state, new_reg), []}
    end
  end

  defp next_field(current) do
    idx = Enum.find_index(@focus_cycle, &(&1 == current)) || 0
    Enum.at(@focus_cycle, rem(idx + 1, length(@focus_cycle)))
  end

  defp focused_input(state) do
    reg = get_register_ss(state)
    focused = Map.get(reg, :focused_field, :handle)
    Map.get(reg, input_key(focused))
  end

  defp update_focused_input(state, new_input) do
    reg = get_register_ss(state)
    focused = Map.get(reg, :focused_field, :handle)
    new_reg = Map.put(reg, input_key(focused), new_input)
    put_register_ss(state, new_reg)
  end

  defp input_key(:invite_code), do: :invite_code_input
  defp input_key(:handle), do: :handle_input
  defp input_key(:email), do: :email_input
  defp input_key(:password), do: :password_input
  defp input_key(:confirm_password), do: :confirm_input

  # §8 Private render helpers

  defp render_invite_step(reg, theme) do
    focused = reg.focused_field == :invite_code
    fg = if focused, do: theme.accent.fg, else: theme.primary.fg
    st = if focused, do: [:bold], else: []

    error_items =
      if reg.error do
        [text(""), text(reg.error, fg: theme.error.fg, style: [:bold])]
      else
        []
      end

    column style: %{gap: 0} do
      [
        row style: %{gap: 0} do
          [
            text("Invite code: ", fg: fg, style: st),
            TextInput.render(reg.invite_code_input, bordered: false, theme: theme)
          ]
        end
      ] ++ error_items
    end
  end

  defp render_combined_step(reg, theme) do
    focused = reg.focused_field

    fields = [
      {:handle, "Handle:           ", reg.handle_input},
      {:email, "Email:            ", reg.email_input},
      {:password, "Password:         ", reg.password_input},
      {:confirm_password, "Confirm password: ", reg.confirm_input}
    ]

    rows =
      Enum.map(fields, fn {field, label, input} ->
        fg = if focused == field, do: theme.accent.fg, else: theme.primary.fg
        st = if focused == field, do: [:bold], else: []

        row style: %{gap: 0} do
          [
            text(label, fg: fg, style: st),
            TextInput.render(input, bordered: false, theme: theme)
          ]
        end
      end)

    error_items =
      if reg.error do
        [text(""), text(reg.error, fg: theme.error.fg, style: [:bold])]
      else
        []
      end

    column style: %{gap: 0} do
      rows ++ error_items
    end
  end

  defp keys_for(:invite_code), do: [{"Enter", "Submit"}, {"Esc", "Cancel"}]

  defp keys_for(:combined),
    do: [{"Tab", "Switch field"}, {"Enter", "Next/Submit"}, {"Esc", "Cancel"}]

  # §9 Private state plumbing

  defp get_register_ss(state) do
    Map.get(state.screen_state || %{}, :register) || init_screen_state_for(state)
  end

  defp put_register_ss(state, reg) do
    new_screen_state = Map.put(state.screen_state || %{}, :register, reg)
    %{state | screen_state: new_screen_state}
  end

  defp clear_register_ss(state) do
    new_screen_state = Map.delete(state.screen_state || %{}, :register)
    %{state | screen_state: new_screen_state}
  end

  defp init_screen_state_for(state) do
    mode = registration_mode(state)
    step = if mode == "invite_only", do: :invite_code, else: :combined
    focused = if step == :invite_code, do: :invite_code, else: :handle

    %{
      mode: mode,
      step: step,
      focused_field: focused,
      invite_code_input: TextInput.init([]),
      handle_input: TextInput.init([]),
      email_input: TextInput.init([]),
      password_input: TextInput.init(mask_char: "*"),
      confirm_input: TextInput.init(mask_char: "*"),
      collected: %{},
      error: nil
    }
  end

  # §10 Private domain plumbing

  defp submit(%{mode: "sysop_approved"} = reg, state) do
    data = %{
      handle: reg.handle_input.raxol_state.value,
      email: reg.email_input.raxol_state.value,
      password: reg.password_input.raxol_state.value
    }

    case Accounts.register_pending_user(data) do
      {:ok, _user} ->
        modal = %{
          type: :info,
          title: "Account Pending",
          message:
            "Your account has been created and is pending sysop approval. You will be notified by email."
        }

        new_state = %{state | modal: modal}
        {:update, clear_register_ss(new_state), [{:terminate_after_modal, :pending_approval}]}

      {:error, changeset} ->
        new_reg = %{
          reg
          | error: changeset_error_text(changeset),
            focused_field: :handle
        }

        {:update, put_register_ss(state, new_reg), []}
    end
  end

  defp submit(%{mode: mode} = reg, state) when mode in ["open", "invite_only"] do
    data = %{
      handle: reg.handle_input.raxol_state.value,
      email: reg.email_input.raxol_state.value,
      password: reg.password_input.raxol_state.value,
      invite_code: Map.get(reg.collected, :invite_code)
    }

    with {:ok, user} <- Accounts.register_user(data),
         screen <- Accounts.post_login_screen(user),
         {:ok, code_or_nil} <- maybe_build_verify_code(screen, user) do
      handle_register_success(state, user, screen, code_or_nil)
    else
      {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
        new_reg = %{
          reg
          | error: changeset_error_text(changeset),
            focused_field: :handle
        }

        {:update, put_register_ss(state, new_reg), []}

      {:error, _build_code_error} ->
        modal = %{
          type: :error,
          message: "Could not generate a verification code. Please try again."
        }

        {:update, %{state | modal: modal}, []}
    end
  end

  # Only build a verify code when the post-login screen is :verify.
  # For :main_menu, skip code generation by short-circuiting to {:ok, nil}.
  defp maybe_build_verify_code(:verify, user), do: Accounts.build_verify_code(user)
  defp maybe_build_verify_code(:main_menu, _user), do: {:ok, nil}

  defp handle_register_success(state, user, :verify, code) do
    maybe_log_verify_code(user, code)

    new_state = %{
      state
      | current_user: user,
        current_screen: :verify,
        verify_state: %{
          buffer: "",
          attempts: 0,
          cooldown_until: nil,
          resend_cooldown_until: nil
        }
    }

    {:update, clear_register_ss(new_state), []}
  end

  defp handle_register_success(state, user, :main_menu, _code) do
    new_state = %{state | current_user: user}
    {:update, clear_register_ss(new_state), [{:promote_session, user}]}
  end

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

  defp changeset_error_text(cs) do
    Enum.map_join(cs.errors, "; ", fn {field, {msg, _}} -> "#{field}: #{msg}" end)
  end

  defp registration_mode(state) do
    case Map.get(session_ctx(state), :registration_mode) do
      nil -> Config.get("registration_mode", "open")
      mode -> mode
    end
  end

  defp session_ctx(state), do: Map.get(state, :session_context) || %{}

  if @log_verify_codes do
    defp maybe_log_verify_code(user, code) when not is_nil(code) do
      require Logger
      Logger.info("[verify] code for @#{user.handle}: #{code}")
    end

    defp maybe_log_verify_code(_user, _code), do: :ok
  else
    defp maybe_log_verify_code(_user, _code), do: :ok
  end
end
