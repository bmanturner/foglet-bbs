defmodule Foglet.TUI.Screens.Verify do
  @moduledoc """
  Screen-owned email-verification code entry flow (D-08..D-12, VERIFY-02 Phase 6).

  State is local to this screen and owned by
  `Foglet.TUI.Screens.Verify.State`. App stores it, routes messages, and
  interprets effects; verification submit/resend work is requested through
  task effects and completed through `update/3` task results
  (Phase 35 D-11/D-13).

  Verify owns the code buffer, attempt cooldown, submit/resend outcomes, and
  verification routing decisions through `init/1`, `update/3`, and `render/2`.

  The 6-character `[ABC___]` buffer remains hand-rolled per inherited 07 D-02:
  the shared input widget cannot reproduce the slot visualization without a
  custom renderer, and its internal box would conflict with this flat slot
  display.
  """
  @behaviour Foglet.TUI.Screen

  alias Foglet.Accounts.Verification
  alias Foglet.TUI.{Context, Effect}
  alias Foglet.TUI.Screens.Verify.State, as: VerifyState
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame

  import Raxol.Core.Renderer.View

  @max_attempts 5
  @cooldown_seconds 60
  @code_length 6

  @impl true
  @spec init(Context.t()) :: map()
  def init(%Context{}), do: VerifyState.default()

  @impl true
  @spec render(map() | nil, Context.t()) :: any()
  def render(local_state, %Context{} = context) do
    vs = local_state || init(context)
    state = app_state_from_local(vs, context)
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

    ScreenFrame.render(state, %{breadcrumb_parts: ["Foglet", "Verify"]}, content, [
      %{
        label: "Actions",
        commands: [
          %{key: "Enter", label: "Submit", priority: 30},
          %{key: "Backspace", label: "Delete", priority: 30},
          %{key: "Ctrl+R", label: "Resend code", priority: 30},
          %{key: "Esc", label: "Cancel", priority: 30}
        ]
      }
    ])
  end

  @impl true
  @spec update(term(), map() | nil, Context.t()) :: {map(), [Effect.t()]}
  def update({:key, %{key: :escape}}, local_state, %Context{} = context) do
    {local_state || init(context), [Effect.navigate(:login, %{})]}
  end

  def update({:key, %{key: :backspace}}, local_state, %Context{} = context) do
    vs = local_state || init(context)
    new_len = max(String.length(vs.buffer) - 1, 0)
    new_vs = %{vs | buffer: String.slice(vs.buffer, 0, new_len)}
    {new_vs, []}
  end

  def update({:key, %{key: :enter}}, local_state, %Context{} = context) do
    submit(local_state || init(context), context)
  end

  def update({:key, %{key: :char, char: c, ctrl: true}}, local_state, %Context{} = context)
      when c in ["R", "r"],
      do: resend_code(local_state || init(context), context)

  def update({:key, %{key: :char, char: c}}, local_state, %Context{} = context) do
    vs = local_state || init(context)
    new_char = String.upcase(c)

    cond do
      VerifyState.cooldown?(vs) ->
        {vs, [Effect.open_modal(cooldown_modal(vs.cooldown_until, "Too many attempts."))]}

      String.match?(new_char, ~r/\A[A-Z0-9]\z/) and String.length(vs.buffer) < @code_length ->
        {%{vs | buffer: vs.buffer <> new_char}, []}

      true ->
        {vs, []}
    end
  end

  def update({:verify, {:set_buffer, code}}, local_state, %Context{} = context) do
    {%{(local_state || init(context)) | buffer: code}, []}
  end

  def update({:verify, :submit}, local_state, %Context{} = context) do
    submit(local_state || init(context), context)
  end

  def update({:verify, :resend}, local_state, %Context{} = context) do
    resend_code(local_state || init(context), context)
  end

  def update({:task_result, :verify_submit, {:ok, result}}, local_state, %Context{} = context) do
    handle_verify_submit_result(result, local_state || init(context), context)
  end

  def update({:task_result, :verify_submit, {:error, _reason}}, local_state, %Context{} = context) do
    modal = %Foglet.TUI.Modal{
      type: :error,
      message: "Verification failed. Please try again later."
    }

    {local_state || init(context), [Effect.open_modal(modal)]}
  end

  def update({:task_result, :verify_resend, {:ok, result}}, local_state, %Context{} = context) do
    handle_verify_resend_result(result, local_state || init(context))
  end

  def update({:task_result, :verify_resend, {:error, _reason}}, local_state, %Context{} = context) do
    modal = %Foglet.TUI.Modal{
      type: :error,
      message: "Verification instructions could not be sent. Please try again later."
    }

    {local_state || init(context), [Effect.open_modal(modal)]}
  end

  def update(_message, local_state, %Context{} = context), do: {local_state || init(context), []}

  defp submit(_vs, %Context{current_user: nil}) do
    modal = %Foglet.TUI.Modal{type: :error, message: "No user context. Please register again."}
    {VerifyState.default(), [Effect.open_modal(modal), Effect.navigate(:login, %{})]}
  end

  defp submit(vs, %Context{} = context) do
    cond do
      VerifyState.cooldown?(vs) ->
        {vs, [Effect.open_modal(cooldown_modal(vs.cooldown_until, "Too many attempts."))]}

      String.length(vs.buffer) != @code_length ->
        modal = %Foglet.TUI.Modal{type: :error, message: "Enter all 6 characters."}
        {vs, [Effect.open_modal(modal)]}

      true ->
        verify_code(vs, context)
    end
  end

  defp resend_code(vs, %Context{} = context) do
    if VerifyState.resend_cooldown?(vs) do
      {vs,
       [Effect.open_modal(cooldown_modal(vs.resend_cooldown_until, "Please wait to resend."))]}
    else
      resend_code_raw(vs, context)
    end
  end

  defp resend_code_raw(vs, %Context{current_user: nil}), do: {vs, []}

  defp resend_code_raw(vs, %Context{} = context) do
    user = context.current_user
    verification_mod = domain_module(context, :verification)

    effect =
      Effect.task(:verify_resend, :verify, fn ->
        verification_mod.deliver_verification_code(user)
      end)

    {vs, [effect]}
  end

  defp verify_code(vs, %Context{} = context) do
    user = context.current_user
    code = vs.buffer
    verification_mod = domain_module(context, :verification)

    effect =
      Effect.task(:verify_submit, :verify, fn ->
        verification_mod.verify_email_code(user, code)
      end)

    {vs, [effect]}
  end

  defp handle_verify_submit_result({:ok, confirmed}, _vs, %Context{}) do
    {VerifyState.default(), [Effect.session({:promote_session, confirmed})]}
  end

  defp handle_verify_submit_result({:error, :expired}, vs, %Context{}) do
    modal = %Foglet.TUI.Modal{
      type: :error,
      message: "Code expired. Press [R] to request a new one."
    }

    {%{vs | buffer: ""}, [Effect.open_modal(modal)]}
  end

  defp handle_verify_submit_result({:error, :invalid_code}, vs, %Context{}) do
    new_vs = VerifyState.record_invalid_attempt(vs, @max_attempts, @cooldown_seconds)

    modal = %Foglet.TUI.Modal{
      type: :error,
      message: "Invalid code (#{new_vs.attempts}/#{@max_attempts})."
    }

    {new_vs, [Effect.open_modal(modal)]}
  end

  defp handle_verify_submit_result({:error, _reason}, vs, %Context{}) do
    modal = %Foglet.TUI.Modal{
      type: :error,
      message: "Verification failed. Please try again later."
    }

    {vs, [Effect.open_modal(modal)]}
  end

  defp handle_verify_resend_result({:ok, :attempted}, vs) do
    modal = %Foglet.TUI.Modal{
      type: :info,
      message: "If email delivery is available, new verification instructions have been sent."
    }

    new_vs = VerifyState.after_resend(vs, resend_cooldown_seconds())

    {new_vs, [Effect.open_modal(modal)]}
  end

  defp handle_verify_resend_result({:error, :unavailable}, vs) do
    modal = %Foglet.TUI.Modal{
      type: :error,
      message: "Email verification is unavailable because email delivery is disabled."
    }

    {vs, [Effect.open_modal(modal)]}
  end

  defp handle_verify_resend_result({:error, _reason}, vs) do
    modal = %Foglet.TUI.Modal{
      type: :error,
      message: "Verification instructions could not be sent. Please try again later."
    }

    {vs, [Effect.open_modal(modal)]}
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

  defp resend_cooldown_seconds do
    Foglet.Config.email_verify_resend_cooldown_seconds()
  end

  defp app_state_from_local(local_state, %Context{} = context) do
    %{
      current_screen: :verify,
      current_user: context.current_user,
      session_context: context.session_context,
      session_pid: context.session_pid,
      terminal_size: context.terminal_size,
      route_params: context.route_params,
      domain: context.domain,
      screen_state: %{verify: local_state || init(context)}
    }
  end

  defp domain_module(%Context{} = context, key) do
    domain = context.domain || %{}

    case Map.get(domain, key) do
      mod when is_atom(mod) and not is_nil(mod) -> mod
      _other -> default_domain_module(key)
    end
  end

  defp default_domain_module(:verification), do: Verification
end
