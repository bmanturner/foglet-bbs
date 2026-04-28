defmodule Foglet.TUI.Screens.Login.State do
  @moduledoc """
  Screen-local state for `Foglet.TUI.Screens.Login`.

  The app stores this map at `state.screen_state[:login]`.

  Sub-states (`:sub` key):
    * `:menu`          — showing [L]/[R]/[F]/[T] menu
    * `:login_form`    — collecting handle + password
    * `:reset_request` — collecting handle/email for reset delivery
    * `:reset_consume` — collecting raw reset token + new password

  Login form shape:
    %{sub: :login_form, focused_field: :handle | :password,
      handle_input: %TextInput{}, password_input: %TextInput{},
      error: nil | String.t(), submitting?: boolean()}

  Reset request shape:
    %{sub: :reset_request, focused_field: :identifier,
      identifier_input: %TextInput{},
      error: nil | String.t(),
      message: nil | String.t(),
      message_category: nil | atom()}

  Reset consume shape (Plan 31-03 / D-04, D-05):
    %{sub: :reset_consume,
      focused_field: :token | :password | :password_confirmation,
      token_input: %TextInput{},
      password_input: %TextInput{} (masked),
      password_confirmation_input: %TextInput{} (masked),
      error: nil | String.t()}
  """

  alias Foglet.Accounts.User
  alias Foglet.TUI.Widgets.Input.TextInput

  @doc "Returns the minimal menu sub-state (AUDIT-19 intentional)."
  @spec default() :: map()
  def default, do: %{sub: :menu}

  @doc "Builds a fresh login form sub-state with inputs initialised."
  @spec login_form() :: map()
  def login_form do
    %{
      sub: :login_form,
      focused_field: :handle,
      handle_input: TextInput.init(max_length: User.handle_max()),
      password_input: TextInput.init(mask_char: "*"),
      error: nil,
      submitting?: false
    }
  end

  @doc "Builds a fresh reset request sub-state."
  @spec reset_request() :: map()
  def reset_request do
    %{
      sub: :reset_request,
      focused_field: :identifier,
      identifier_input: TextInput.init([]),
      error: nil,
      message: nil,
      message_category: nil
    }
  end

  @doc """
  Builds a fresh reset-consume sub-state (Plan 31-03 / D-04, D-05).

  Token field is plain text; password and confirmation fields are masked.
  Initial focus is on `:token` so the user types the raw token first.
  """
  @spec reset_consume() :: map()
  def reset_consume do
    %{
      sub: :reset_consume,
      focused_field: :token,
      token_input: TextInput.init([]),
      password_input: TextInput.init(mask_char: "*"),
      password_confirmation_input: TextInput.init(mask_char: "*"),
      error: nil
    }
  end

  @doc "Returns the current `:sub` atom from the login screen state (defaults to `:menu`)."
  @spec sub(map()) :: atom()
  def sub(state) do
    login_ss = Map.get(state.screen_state || %{}, :login) || %{}
    Map.get(login_ss, :sub) || :menu
  end

  @doc """
  Reads the login screen-state map from the app state.

  IN-003: when `state.screen_state[:login]` is missing, returns an empty
  map (`%{}`) rather than a login-form-flavored stub. The previous stub
  silently masked the missing-state condition for reset-flow callers,
  which would observe `nil` field values flowing into TextInput
  rendering. In practice `handle_key/2` routes via
  `LoginState.sub(state)` before any consumer calls `get/1`, so the
  fallback is unreachable on the live path; an empty map fails fast at
  the consumer's first `Map.fetch!/2` instead of corrupting render
  output.
  """
  @spec get(map()) :: map()
  def get(state) do
    Map.get(state.screen_state || %{}, :login) || %{}
  end

  @doc "Writes an updated login screen-state map back into the app state."
  @spec put(map(), map()) :: map()
  def put(state, login_ss) do
    new_screen_state = Map.put(state.screen_state || %{}, :login, login_ss)
    %{state | screen_state: new_screen_state}
  end

  @doc """
  Advances focus to the next field within the login form.

  Only the login form has a binary `:handle` ↔ `:password` toggle. Other
  sub-states have their own focus cycles (`next_reset_consume_focus/1` /
  `prev_reset_consume_focus/1` for `:reset_consume`); calling
  `toggle_focus/1` on any non-login-form state is a programmer error
  and will raise `FunctionClauseError` rather than silently writing
  `:handle` into a state that does not own that atom (WR-002).
  """
  @spec toggle_focus(map()) :: map()
  def toggle_focus(%{sub: :login_form, focused_field: :handle} = ss),
    do: %{ss | focused_field: :password}

  def toggle_focus(%{sub: :login_form, focused_field: :password} = ss),
    do: %{ss | focused_field: :handle}

  @typedoc """
  The exhaustive set of focused-field atoms the Login screen recognises.

  IN-002: kept narrow on purpose. `input_key/1` raises `FunctionClauseError`
  for any other atom; that is the *correct* behaviour because a state with an
  unknown focused-field is a programmer error, not a recoverable runtime
  condition. Adding a fallthrough would mask state-corruption bugs by
  falling back to `:handle` silently.
  """
  @type focused_field ::
          :handle | :password | :identifier | :token | :password_confirmation

  @doc """
  Returns the `input_key` atom for a given `focused_field`.

  Exhaustive over the `t:focused_field/0` type. Raises
  `FunctionClauseError` for any other atom — see the `t:focused_field/0`
  doc for rationale.
  """
  @spec input_key(focused_field()) :: atom()
  def input_key(:handle), do: :handle_input
  def input_key(:password), do: :password_input
  def input_key(:identifier), do: :identifier_input
  def input_key(:token), do: :token_input
  def input_key(:password_confirmation), do: :password_confirmation_input

  @doc """
  Advance focus through the reset-consume cycle:
  `:token -> :password -> :password_confirmation -> :token`.
  """
  @spec next_reset_consume_focus(atom()) :: atom()
  def next_reset_consume_focus(:token), do: :password
  def next_reset_consume_focus(:password), do: :password_confirmation
  def next_reset_consume_focus(:password_confirmation), do: :token

  @doc """
  Reverse focus through the reset-consume cycle:
  `:token -> :password_confirmation -> :password -> :token`.
  """
  @spec prev_reset_consume_focus(atom()) :: atom()
  def prev_reset_consume_focus(:token), do: :password_confirmation
  def prev_reset_consume_focus(:password_confirmation), do: :password
  def prev_reset_consume_focus(:password), do: :token
end
