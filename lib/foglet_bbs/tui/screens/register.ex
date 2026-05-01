defmodule Foglet.TUI.Screens.Register do
  @moduledoc """
  Screen-owned registration wizard (SSH-04, post-Phase-2 two-step form).

  Wizard structure by mode:
    * "open" / "sysop_approved"  →  :combined step (handle, email, password, confirm) → submit
    * "invite_only"              →  :invite_code step → :combined step → submit

  State is local to this screen and owned by
  `Foglet.TUI.Screens.Register.State`. App stores it, routes messages, and
  interprets effects; registration and verification delivery work is requested
  through task effects and completed through `update/3` task results
  (Phase 35 D-11/D-13).

  Terminal outcomes:
    * "open" / "invite_only" success → transition to :verify with a built code
    * "sysop_approved" success       → Accounts.register_pending_user/1 + terminate

  SSH keys are only offered as an opt-in carry-through when the SSH connection
  already presented an unmatched public key.

  Register owns invite and combined-form local state, registration outcomes,
  verification-routing decisions, and pending-approval termination requests
  through `init/1`, `update/3`, and `render/2`.
  """

  alias Foglet.{Accounts, Config}
  alias Foglet.Accounts.{Invites, SSHKey, Verification}
  alias Foglet.TUI.{Context, Effect, Input}
  alias Foglet.TUI.Screens.Register.State, as: RegisterState
  alias Foglet.TUI.Screens.Shared.{AppStateBridge, FocusInput}
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Input.Checkbox
  alias Foglet.TUI.Widgets.Input.TextInput

  @behaviour Foglet.TUI.Screen

  import Raxol.Core.Renderer.View

  @impl true
  @spec init(Context.t()) :: map()
  def init(%Context{} = context) do
    RegisterState.for_mode(registration_mode(context))
  end

  @impl true
  @spec render(map() | nil, Context.t()) :: any()
  def render(local_state, %Context{} = context) do
    reg = local_state || init(context)
    state = app_state_from_local(reg, context)
    theme = Theme.from_state(state)

    content =
      column style: %{gap: 0} do
        [
          case reg.step do
            :invite_code -> render_invite_step(reg, theme)
            :combined -> render_combined_step(reg, theme, context)
          end
        ]
      end

    ScreenFrame.render(
      state,
      %{breadcrumb_parts: ["Foglet", "Register"]},
      content,
      keys_for(reg.step)
    )
  end

  @impl true
  @spec update(term(), map() | nil, Context.t()) :: {map(), [Effect.t()]}
  def update({:key, %{key: :escape}}, local_state, %Context{} = context) do
    {local_state || init(context), [Effect.navigate(:login, %{})]}
  end

  def update({:key, key_event}, local_state, %Context{} = context) do
    local_state
    |> app_state_from_local(context)
    |> reduce_key(key_event)
    |> local_result(local_state || init(context))
  end

  def update({:wizard, {:cancel}}, local_state, %Context{} = context) do
    {local_state || init(context), [Effect.navigate(:login, %{})]}
  end

  def update({:wizard, {:submit_step, :invite_code, value}}, local_state, %Context{} = context) do
    reg = local_state || init(context)
    state = app_state_from_local(reg, context)

    case verify_invite_code(state, value) do
      :ok ->
        new_reg = %{
          reg
          | step: :combined,
            focused_field: :handle,
            collected: Map.put(reg.collected, :invite_code, value),
            error: nil
        }

        {new_reg, []}

      {:error, reason} ->
        {%{reg | error: invite_step_error(reason)}, []}
    end
  end

  def update({:wizard, {:submit_step, :combined, _value}}, local_state, %Context{} = context) do
    state = app_state_from_local(local_state, context)

    state
    |> get_register_ss()
    |> validate_and_submit(state)
    |> local_result(local_state || init(context))
  end

  def update({:task_result, :register, {:ok, result}}, local_state, %Context{} = context) do
    local_state
    |> app_state_from_local(context)
    |> handle_register_result(result)
    |> local_result(local_state || init(context))
  end

  def update({:task_result, :register, {:error, _reason}}, local_state, %Context{} = context) do
    modal = %Foglet.TUI.Modal{
      type: :error,
      message: "We couldn't finish your registration. Try again in a minute."
    }

    {local_state || init(context), [Effect.open_modal(modal)]}
  end

  def update({:task_result, :verification_delivery, result}, local_state, context),
    do: update({:task_result, :register, result}, local_state, context)

  def update(_message, local_state, %Context{} = context), do: {local_state || init(context), []}

  # §3 Private key handlers

  defp reduce_key(state, key_event) do
    reg = get_register_ss(state)

    case reg.step do
      :invite_code -> handle_invite_key(key_event, state)
      :combined -> handle_combined_key(key_event, state)
    end
  end

  # --- :invite_code step key handlers ---

  defp handle_invite_key(%{key: :enter}, state) do
    reg = get_register_ss(state)
    value = reg.invite_code_input.raxol_state.value
    handle_invite_submission(value, state)
  end

  defp handle_invite_key(event, state) do
    if Input.backward_tab?(event) or Input.forward_tab?(event) do
      {:update, state, []}
    else
      handle_invite_input_key(event, state)
    end
  end

  defp handle_invite_input_key(event, state) do
    reg = get_register_ss(state)
    {new_input, _action} = TextInput.handle_event(event, reg.invite_code_input)
    new_reg = %{reg | invite_code_input: new_input}
    {:update, RegisterState.put(state, new_reg), []}
  end

  # --- :combined step key handlers ---

  defp handle_combined_key(event, state) do
    cond do
      Input.backward_tab?(event) ->
        move_combined_focus(state, :previous)

      Input.forward_tab?(event) ->
        move_combined_focus(state, :next)

      true ->
        handle_combined_input_key(event, state)
    end
  end

  defp move_combined_focus(state, :next) do
    reg = get_register_ss(state)
    has_offered_key? = offered_ssh_key?(state)

    new_reg = %{
      reg
      | focused_field: RegisterState.next_field(reg.focused_field, has_offered_key?),
        error: nil
    }

    {:update, RegisterState.put(state, new_reg), []}
  end

  defp move_combined_focus(state, :previous) do
    reg = get_register_ss(state)
    has_offered_key? = offered_ssh_key?(state)

    new_reg = %{
      reg
      | focused_field: RegisterState.prev_field(reg.focused_field, has_offered_key?),
        error: nil
    }

    {:update, RegisterState.put(state, new_reg), []}
  end

  defp handle_combined_input_key(%{key: :enter}, state) do
    reg = get_register_ss(state)
    has_offered_key? = offered_ssh_key?(state)

    case reg.focused_field do
      :confirm_password ->
        if has_offered_key? do
          new_reg = %{reg | focused_field: :ssh_key_opt_in, error: nil}
          {:update, RegisterState.put(state, new_reg), []}
        else
          validate_and_submit(reg, state)
        end

      :ssh_key_opt_in ->
        validate_and_submit(reg, state)

      field ->
        new_reg = %{
          reg
          | focused_field: RegisterState.next_field(field, has_offered_key?),
            error: nil
        }

        {:update, RegisterState.put(state, new_reg), []}
    end
  end

  defp handle_combined_input_key(%{key: :space}, state), do: toggle_ssh_key_opt_in(state)

  defp handle_combined_input_key(%{key: :char, char: " "}, state) do
    reg = get_register_ss(state)

    if reg.focused_field == :ssh_key_opt_in do
      toggle_ssh_key_opt_in(state)
    else
      handle_text_input_key(%{key: :char, char: " "}, state)
    end
  end

  defp handle_combined_input_key(event, state) do
    reg = get_register_ss(state)

    if reg.focused_field == :ssh_key_opt_in do
      {:update, state, []}
    else
      handle_text_input_key(event, state)
    end
  end

  defp handle_text_input_key(event, state) do
    {new_input, _action} = TextInput.handle_event(event, focused_input(state))
    {:update, update_focused_input(state, new_input), []}
  end

  defp toggle_ssh_key_opt_in(state) do
    reg = get_register_ss(state)

    if reg.focused_field == :ssh_key_opt_in and offered_ssh_key?(state) do
      new_reg = %{reg | save_offered_ssh_key?: !Map.get(reg, :save_offered_ssh_key?, false)}
      {:update, RegisterState.put(state, new_reg), []}
    else
      {:update, state, []}
    end
  end

  # --- Focus + validation helpers ---

  defp validate_and_submit(reg, state) do
    pw = reg.password_input.raxol_state.value
    cpw = reg.confirm_input.raxol_state.value

    if pw == cpw do
      submit(reg, state)
    else
      new_reg = %{reg | error: "Those two passwords don't match."}
      {:update, RegisterState.put(state, new_reg), []}
    end
  end

  defp focused_input(state) do
    FocusInput.get_focused(RegisterState.get(state), &RegisterState.input_key/1, :handle)
  end

  defp update_focused_input(state, new_input) do
    reg = RegisterState.get(state)
    new_reg = FocusInput.update_focused(reg, new_input, &RegisterState.input_key/1, :handle)
    RegisterState.put(state, new_reg)
  end

  # §5 Private render helpers

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
            TextInput.render(reg.invite_code_input, bordered: false, focused: true, theme: theme)
          ]
        end
      ] ++ error_items
    end
  end

  defp render_combined_step(reg, theme, context) do
    focused = reg.focused_field
    offered_key = offered_ssh_public_key(context)

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
            TextInput.render(input, bordered: false, focused: focused == field, theme: theme)
          ]
        end
      end)

    rows = rows ++ ssh_key_opt_in_rows(reg, focused, offered_key, theme)

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

  defp ssh_key_opt_in_rows(_reg, _focused, nil, _theme), do: []

  defp ssh_key_opt_in_rows(reg, focused, offered_key, theme) do
    selected? = Map.get(reg, :save_offered_ssh_key?, false)
    focus_marker = if focused == :ssh_key_opt_in, do: "> ", else: "  "
    fg = if focused == :ssh_key_opt_in, do: theme.accent.fg, else: theme.primary.fg
    st = if focused == :ssh_key_opt_in, do: [:bold], else: []

    [
      text(""),
      row style: %{gap: 0} do
        [
          text(focus_marker, fg: fg, style: st),
          Checkbox.render("Use this SSH key for future logins",
            checked?: selected?,
            marker_style: :ascii,
            theme: theme
          )
        ]
      end,
      text("  Fingerprint: #{offered_key_fingerprint(offered_key)}", fg: theme.dim.fg)
    ]
  end

  defp keys_for(:invite_code) do
    [
      %{
        label: "Actions",
        commands: [
          %{key: "Enter", label: "Submit", priority: 30},
          %{key: "Esc", label: "Cancel", priority: 30}
        ]
      }
    ]
  end

  defp keys_for(:combined) do
    [
      %{
        label: "Field",
        commands: [%{key: "Tab", label: "Switch field", priority: 10}]
      },
      %{
        label: "Actions",
        commands: [
          %{key: "Enter", label: "Next/Submit", priority: 30},
          %{key: "Esc", label: "Cancel", priority: 30}
        ]
      }
    ]
  end

  # §6 Private state plumbing

  defp get_register_ss(state) do
    RegisterState.get(state) || state_for_mode(state)
  end

  defp state_for_mode(state) do
    RegisterState.for_mode(registration_mode(state))
  end

  defp app_state_from_local(local_state, %Context{} = context) do
    AppStateBridge.from_context(local_state, context, :register, fn -> init(context) end)
  end

  defp local_result({:update, state, effects}, _local_state) do
    {RegisterState.get(state), effects}
  end

  defp local_result({state, effects}, _local_state) when is_list(effects) do
    {RegisterState.get(state), effects}
  end

  defp handle_invite_submission(value, state) do
    reg = get_register_ss(state)

    case verify_invite_code(state, value) do
      :ok ->
        new_reg = %{
          reg
          | step: :combined,
            focused_field: :handle,
            collected: Map.put(reg.collected, :invite_code, value),
            error: nil
        }

        {:update, RegisterState.put(state, new_reg), []}

      {:error, reason} ->
        {:update, RegisterState.put(state, %{reg | error: invite_step_error(reason)}), []}
    end
  end

  defp verify_invite_code(state, value) do
    invites_mod = domain_module(state, :invites)
    RegisterState.verify_invite_code(value, invites_mod)
  end

  defp invite_step_error(:format), do: "Invalid or expired invite code."
  defp invite_step_error(:unavailable), do: "Invalid or expired invite code."

  # §7 Private domain plumbing

  defp submit(%{mode: "sysop_approved"} = reg, state) do
    data =
      %{
        handle: reg.handle_input.raxol_state.value,
        email: reg.email_input.raxol_state.value,
        password: reg.password_input.raxol_state.value
      }
      |> maybe_put_offered_ssh_key(reg, state)

    accounts_mod = domain_module(state, :accounts)
    submitting_state = RegisterState.put(state, %{reg | error: nil})

    effect =
      Effect.task(:register, :register, fn ->
        case accounts_mod.register_pending_user(data) do
          {:ok, user} -> {:ok, :pending_approval, user}
          {:error, changeset} -> {:error, changeset}
        end
      end)

    {:update, submitting_state, [effect]}
  end

  defp submit(%{mode: mode} = reg, state) when mode in ["open", "invite_only"] do
    data =
      %{
        handle: reg.handle_input.raxol_state.value,
        email: reg.email_input.raxol_state.value,
        password: reg.password_input.raxol_state.value,
        invite_code: Map.get(reg.collected, :invite_code)
      }
      |> maybe_put_offered_ssh_key(reg, state)

    accounts_mod = domain_module(state, :accounts)
    verification_mod = domain_module(state, :verification)
    submitting_state = RegisterState.put(state, %{reg | error: nil})

    effect =
      Effect.task(:register, :register, fn ->
        register_user(accounts_mod, verification_mod, data)
      end)

    {:update, submitting_state, [effect]}
  end

  # Only attempt verification delivery when the post-login screen is :verify.
  # For :main_menu, skip delivery by short-circuiting to {:ok, nil}.
  defp maybe_deliver_verification_code(verification_mod, :verify, user),
    do: verification_mod.deliver_verification_code(user)

  defp maybe_deliver_verification_code(_verification_mod, :main_menu, _user), do: {:ok, nil}

  defp register_user(accounts_mod, verification_mod, data) do
    with {:ok, user} <- accounts_mod.register_user(data),
         screen <- accounts_mod.post_login_screen(user),
         {:ok, delivery_or_nil} <- maybe_deliver_verification_code(verification_mod, screen, user) do
      {:ok, user, screen, delivery_or_nil}
    end
  end

  defp handle_register_result(state, {:ok, :pending_approval, _user}) do
    modal = %Foglet.TUI.Modal{
      type: :info,
      title: "Account waiting for approval",
      message: pending_approval_message(Config.delivery_mode())
    }

    {RegisterState.put(state, RegisterState.default()),
     [Effect.open_modal(modal), Effect.session({:terminate_after_modal, :pending_approval})]}
  end

  defp handle_register_result(state, {:ok, user, :verify, :attempted}) do
    {RegisterState.put(state, RegisterState.default()),
     [Effect.session({:set_current_user, user}), Effect.navigate(:verify, %{})]}
  end

  defp handle_register_result(state, {:ok, user, :verify, delivery}) do
    require Logger

    Logger.warning(
      "[Register] unexpected verify delivery shape #{inspect(delivery)}; " <>
        "treating as :attempted and routing to verify screen"
    )

    {RegisterState.put(state, RegisterState.default()),
     [Effect.session({:set_current_user, user}), Effect.navigate(:verify, %{})]}
  end

  defp handle_register_result(state, {:ok, user, :main_menu, _delivery}) do
    {RegisterState.put(state, RegisterState.default()),
     [Effect.session({:promote_session, user})]}
  end

  defp handle_register_result(state, {:error, changeset})
       when is_struct(changeset, Ecto.Changeset) do
    if Keyword.has_key?(changeset.errors, :invite_code) do
      modal = %Foglet.TUI.Modal{
        type: :error,
        message: "Invite is no longer valid. Please request a new code from the sysop."
      }

      reg = get_register_ss(state)
      reset_reg = %{reg | step: :invite_code, focused_field: :invite_code, error: nil}
      {:update, RegisterState.put(state, reset_reg), [Effect.open_modal(modal)]}
    else
      reg = get_register_ss(state)

      new_reg = %{
        reg
        | error: RegisterState.changeset_error_text(changeset),
          focused_field: :handle
      }

      {:update, RegisterState.put(state, new_reg), []}
    end
  end

  defp handle_register_result(state, {:error, :unavailable}) do
    modal = %Foglet.TUI.Modal{
      type: :error,
      message:
        "This Foglet has email turned off, so we can't send a verification code. Ask the sysop."
    }

    {state, [Effect.open_modal(modal)]}
  end

  defp handle_register_result(state, {:error, {:ssh_key, _message}}) do
    reg = get_register_ss(state)

    new_reg = %{
      reg
      | error: "That SSH key couldn't be saved. Uncheck it to finish registration.",
        focused_field: if(offered_ssh_key?(state), do: :ssh_key_opt_in, else: :handle)
    }

    {:update, RegisterState.put(state, new_reg), []}
  end

  defp handle_register_result(state, {:error, _delivery_error}) do
    modal = %Foglet.TUI.Modal{
      type: :error,
      message: "We couldn't send the verification email. Try again in a minute."
    }

    {state, [Effect.open_modal(modal)]}
  end

  # IN-05: previously had two heads (`%Context{}` and any-term) with
  # identical bodies — the catch-all already accepts a `%Context{}` and
  # `session_ctx/1` resolves both shapes via `Map.get(:session_context)`.
  defp registration_mode(state) do
    case Map.get(session_ctx(state), :registration_mode) do
      nil -> Config.get("registration_mode", "open")
      mode -> mode
    end
  end

  defp session_ctx(state), do: Map.get(state, :session_context) || %{}

  defp offered_ssh_key?(state), do: not is_nil(offered_ssh_public_key(state))

  defp offered_ssh_public_key(%Context{} = context) do
    offered_ssh_public_key(%{session_context: context.session_context})
  end

  defp offered_ssh_public_key(state) do
    case Map.get(session_ctx(state), :offered_ssh_public_key) do
      key when is_binary(key) ->
        case String.trim(key) do
          "" -> nil
          trimmed -> trimmed
        end

      _other ->
        nil
    end
  end

  defp maybe_put_offered_ssh_key(data, reg, state) do
    if Map.get(reg, :save_offered_ssh_key?, false) do
      case offered_ssh_public_key(state) do
        nil -> data
        offered_key -> Map.put(data, :offered_ssh_public_key, offered_key)
      end
    else
      data
    end
  end

  defp offered_key_fingerprint(offered_key) do
    case SSHKey.compute_fingerprint(offered_key) do
      {:ok, fingerprint} -> fingerprint
      {:error, _reason} -> "unavailable"
    end
  end

  defp domain_module(state, key) do
    domain = Map.get(state, :domain) || %{}

    case Map.get(domain, key) do
      mod when is_atom(mod) and not is_nil(mod) -> mod
      _other -> default_domain_module(key)
    end
  end

  defp default_domain_module(:accounts), do: Accounts
  defp default_domain_module(:verification), do: Verification
  defp default_domain_module(:invites), do: Invites

  defp pending_approval_message("email") do
    "Your account has been created and is pending sysop approval. " <>
      "You'll receive an email when a sysop reviews your request."
  end

  defp pending_approval_message("no_email") do
    "Your account has been created and is pending sysop approval. " <>
      "A sysop will review your request and contact you directly."
  end

  defp pending_approval_message(other) do
    require Logger

    Logger.warning(
      "[Register] unknown delivery_mode #{inspect(other)}; using no_email pending-approval copy"
    )

    pending_approval_message("no_email")
  end
end
