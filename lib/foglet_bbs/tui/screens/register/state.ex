defmodule Foglet.TUI.Screens.Register.State do
  @moduledoc """
  Screen-local state for `Foglet.TUI.Screens.Register`.

  `Foglet.TUI.Screens.Register.init/1` builds this map and
  `Register.update/3` owns all invite-code, combined-form, registration, and
  pending-approval transitions. App stores the returned value under
  `state.screen_state[:register]` and only interprets emitted effects.

  Steps:
    * `:invite_code` — first step for `"invite_only"` mode
    * `:combined`    — handle / email / password / confirm form

  The combined step focus cycle is:
    `:handle` → `:email` → `:password` → `:confirm_password` → `:handle`
  """

  alias Foglet.Accounts.User
  alias Foglet.TUI.Widgets.Input.TextInput

  @focus_cycle [:handle, :email, :password, :confirm_password]

  @doc """
  Returns a minimal `"open"`-mode stub (AUDIT-19 / D-05).

  Always `mode: "open"`, `step: :combined`. For mode-aware
  initialisation see `for_mode/1`.
  """
  @spec default() :: map()
  def default do
    %{
      mode: "open",
      step: :combined,
      focused_field: :handle,
      invite_code_input: TextInput.init([]),
      handle_input: TextInput.init(max_length: User.handle_max()),
      email_input: TextInput.init([]),
      password_input: TextInput.init(mask_char: "*"),
      confirm_input: TextInput.init(mask_char: "*"),
      collected: %{},
      error: nil
    }
  end

  @doc """
  Builds a mode-aware initial screen state.

  `"invite_only"` mode starts on `:invite_code` step; all others start on
  `:combined`.
  """
  @spec for_mode(String.t()) :: map()
  def for_mode(mode) do
    step = if mode == "invite_only", do: :invite_code, else: :combined
    focused = if step == :invite_code, do: :invite_code, else: :handle

    %{
      mode: mode,
      step: step,
      focused_field: focused,
      invite_code_input: TextInput.init([]),
      handle_input: TextInput.init(max_length: User.handle_max()),
      email_input: TextInput.init([]),
      password_input: TextInput.init(mask_char: "*"),
      confirm_input: TextInput.init(mask_char: "*"),
      collected: %{},
      error: nil
    }
  end

  @doc "Reads the register screen-state map from the app state."
  @spec get(Foglet.TUI.App.t()) :: map() | nil
  def get(state) do
    Map.get(state.screen_state || %{}, :register)
  end

  @doc "Writes an updated register screen-state map into the app state."
  @spec put(Foglet.TUI.App.t(), map()) :: Foglet.TUI.App.t()
  def put(state, reg) do
    new_screen_state = Map.put(state.screen_state || %{}, :register, reg)
    %{state | screen_state: new_screen_state}
  end

  @doc "Removes the register screen state from the app state."
  @spec clear(Foglet.TUI.App.t()) :: Foglet.TUI.App.t()
  def clear(state) do
    new_screen_state = Map.delete(state.screen_state || %{}, :register)
    %{state | screen_state: new_screen_state}
  end

  @doc "Advances focus to the next field in the combined-step cycle."
  @spec next_field(atom()) :: atom()
  def next_field(current) do
    idx = Enum.find_index(@focus_cycle, &(&1 == current)) || 0
    Enum.at(@focus_cycle, rem(idx + 1, length(@focus_cycle)))
  end

  @typedoc "Atoms for the register screen's focus cycle (incl. invite-code step)."
  @type focused_field ::
          :invite_code | :handle | :email | :password | :confirm_password

  @typedoc "Keys into the register screen-state map for each input widget."
  @type input_field ::
          :invite_code_input
          | :handle_input
          | :email_input
          | :password_input
          | :confirm_input

  @doc "Returns the input map key for a given focused field atom."
  @spec input_key(focused_field()) :: input_field()
  def input_key(:invite_code), do: :invite_code_input
  def input_key(:handle), do: :handle_input
  def input_key(:email), do: :email_input
  def input_key(:password), do: :password_input
  def input_key(:confirm_password), do: :confirm_input

  @doc """
  Validates that an invite code string meets the accepted format.

  Codes must be 16–64 alphanumeric characters (case-insensitive).
  """
  @spec valid_invite_code?(String.t() | any()) :: boolean()
  def valid_invite_code?(code) when is_binary(code) and byte_size(code) > 0 do
    Regex.match?(~r/\A[A-Z0-9]{16,64}\z/i, code)
  end

  def valid_invite_code?(_), do: false

  @doc "Formats an Ecto.Changeset error map into a single display string."
  @spec changeset_error_text(Ecto.Changeset.t()) :: String.t()
  def changeset_error_text(cs) do
    Enum.map_join(cs.errors, "; ", fn {field, {msg, _}} -> "#{field}: #{msg}" end)
  end
end
