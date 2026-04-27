defmodule Foglet.TUI.Screens.Login.State do
  @moduledoc """
  Screen-local state for `Foglet.TUI.Screens.Login`.

  The app stores this map at `state.screen_state[:login]`.

  Sub-states (`:sub` key):
    * `:menu`          — showing [L]/[R]/[F]/[Q] menu
    * `:login_form`    — collecting handle + password
    * `:reset_request` — collecting handle/email for reset delivery

  Login form shape:
    %{sub: :login_form, focused_field: :handle | :password,
      handle_input: %TextInput{}, password_input: %TextInput{},
      error: nil | String.t()}

  Reset request shape:
    %{sub: :reset_request, focused_field: :identifier,
      identifier_input: %TextInput{},
      error: nil | String.t(),
      message: nil | String.t(),
      message_category: nil | atom()}
  """

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
      handle_input: TextInput.init([]),
      password_input: TextInput.init(mask_char: "*"),
      error: nil
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

  @doc "Returns the current `:sub` atom from the login screen state (defaults to `:menu`)."
  @spec sub(map()) :: atom()
  def sub(state) do
    login_ss = Map.get(state.screen_state || %{}, :login) || %{}
    Map.get(login_ss, :sub) || :menu
  end

  @doc "Reads the login screen-state map from the app state."
  @spec get(map()) :: map()
  def get(state) do
    Map.get(state.screen_state || %{}, :login) ||
      %{focused_field: nil, handle_input: nil, password_input: nil, error: nil}
  end

  @doc "Writes an updated login screen-state map back into the app state."
  @spec put(map(), map()) :: map()
  def put(state, login_ss) do
    new_screen_state = Map.put(state.screen_state || %{}, :login, login_ss)
    %{state | screen_state: new_screen_state}
  end

  @doc """
  Advances focus to the next field.

  In the login form only two fields exist: `:handle` ↔ `:password`.
  """
  @spec toggle_focus(map()) :: map()
  def toggle_focus(%{focused_field: :handle} = ss), do: %{ss | focused_field: :password}
  def toggle_focus(%{focused_field: _} = ss), do: %{ss | focused_field: :handle}

  @doc "Returns the `input_key` atom for a given `focused_field`."
  @spec input_key(atom()) :: atom()
  def input_key(:handle), do: :handle_input
  def input_key(:password), do: :password_input
  def input_key(:identifier), do: :identifier_input
end
