defmodule Foglet.TUI.App.Bootstrap do
  @moduledoc """
  App-shell bootstrap helper: turns a Raxol/test context into a populated
  `%Foglet.TUI.App{}` ready for the first reducer message.

  Owns:
    * lifecycle vs. test-call context normalization (`extract_context/1`),
    * landing-screen selection by user/session status (`initial_screen/2`),
    * account-gate modal seeding for pending/rejected/suspended accounts,
    * initial screen-local state seeding via `App.Routing`.

  Kept separate from `Foglet.TUI.App` so the Raxol callback module stays a
  thin conductor and tests can exercise bootstrap branches without spinning up
  the live runtime. If account-gate logic grows beyond pending/rejected/
  suspended (bans, MFA enrollment, etc.), split it out into
  `Foglet.TUI.App.AccountGate`.
  """

  alias Foglet.Accounts
  alias Foglet.TUI.App
  alias Foglet.TUI.App.Routing
  alias Foglet.TUI.Guest

  @doc """
  Builds the initial `%App{}` from a Raxol lifecycle map or a direct test map.

  Mirrors the Raxol `init/1` callback contract: returns `{:ok, state}`.
  """
  @spec init(map()) :: {:ok, App.t()}
  def init(context) do
    {session_context, terminal_size} = extract_context(context)

    user = Map.get(session_context, :user)
    session_pid = Map.get(session_context, :session_pid)

    # Register TUI pid with the Session so it can receive replace/heartbeat msgs.
    if is_pid(session_pid) do
      Foglet.Sessions.Session.set_tui_pid(session_pid, self())
    end

    screen = initial_screen(user, session_context)

    state =
      %App{
        current_screen: screen,
        current_user: user,
        session_context: session_context,
        session_pid: session_pid,
        terminal_size: terminal_size
      }
      |> maybe_put_account_gate_modal(user)
      |> maybe_init_initial_screen_state()

    {:ok, state}
  end

  # Extract session_context + terminal_size from either:
  #   (a) Lifecycle-produced map: %{width:, height:, options: [context: %{...}]}
  #   (b) Direct test call: %{session_context: %SessionContext{} | %{...}, terminal_size: {w, h}}
  #
  # The session_context value may be a `%Foglet.TUI.SessionContext{}` struct
  # (the production path via SSH.CLIHandler) or a plain map (tests and legacy
  # callers). Both are accepted so that test helpers can pass partial maps
  # without constructing a full struct.
  @spec extract_context(map()) :: {map(), {pos_integer(), pos_integer()}}
  defp extract_context(context) do
    if is_map(context) and is_list(Map.get(context, :options)) do
      # Lifecycle path — context is in options[:context]
      opts = Map.get(context, :options, [])
      nested = Keyword.get(opts, :context, %{})
      session_context = Map.get(nested, :session_context, %Foglet.TUI.SessionContext{})
      w = Map.get(context, :width, 80)
      h = Map.get(context, :height, 24)
      terminal_size = Map.get(nested, :terminal_size, {w, h})
      {session_context, terminal_size}
    else
      # Direct/test path — session_context at top level
      session_context = Map.get(context, :session_context, %Foglet.TUI.SessionContext{})
      terminal_size = Map.get(context, :terminal_size, {80, 24})
      {session_context, terminal_size}
    end
  end

  defp initial_screen(nil, session_context) do
    if Guest.guest?(session_context), do: :main_menu, else: :login
  end

  defp initial_screen(%{status: status}, _session_context)
       when status in [:pending, :rejected, :suspended],
       do: :login

  defp initial_screen(%{status: :active, confirmed_at: nil} = user, _session_context),
    do: Accounts.post_login_screen(user)

  defp initial_screen(user, _session_context), do: Accounts.post_login_screen(user)

  # Account-gate modals: shown immediately on connect for users whose status
  # blocks them from using the BBS. If this grows beyond the current three
  # statuses (e.g., bans, MFA enrollment, ToS acceptance, age gates), split
  # the gate logic and copy out into `Foglet.TUI.App.AccountGate`.
  defp maybe_put_account_gate_modal(state, %{status: status})
       when status in [:pending, :rejected, :suspended] do
    %{state | modal: account_gate_modal(status)}
  end

  defp maybe_put_account_gate_modal(state, _user), do: state

  defp account_gate_modal(:pending) do
    %Foglet.TUI.Modal{
      type: :error,
      message: "Your account is waiting for sysop approval. Try again once you've heard back."
    }
  end

  defp account_gate_modal(:rejected) do
    %Foglet.TUI.Modal{
      type: :error,
      message: "Your registration was turned down. Reach the sysop if you think that's a mistake."
    }
  end

  defp account_gate_modal(:suspended) do
    %Foglet.TUI.Modal{
      type: :error,
      message: "Your account is suspended. Reach the sysop to ask why."
    }
  end

  # Generic initial-screen-state seeding (Phase 39 D-15, R4):
  # Routing.init_route_screen_state/3 already covers MainMenu via the
  # function_exported?(module, :init, 1) branch.
  defp maybe_init_initial_screen_state(%App{} = state) do
    Routing.init_route_screen_state(state, state.current_screen, state.route_params)
  end
end
