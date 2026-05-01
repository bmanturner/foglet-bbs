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

  alias Foglet.Accounts.{Invites, User}
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
  @spec get(map()) :: map() | nil
  def get(state) do
    Map.get(state.screen_state || %{}, :register)
  end

  @doc "Writes an updated register screen-state map into the app state."
  @spec put(map(), map()) :: map()
  def put(state, reg) do
    new_screen_state = Map.put(state.screen_state || %{}, :register, reg)
    %{state | screen_state: new_screen_state}
  end

  @doc "Removes the register screen state from the app state."
  @spec clear(map()) :: map()
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

  @doc """
  Verifies that an invite code is well-formed and currently consumable.

  Returns `:ok` if the code passes the format check and the invite exists with
  status `:available`. Returns `{:error, :format}` for format failures and
  `{:error, :unavailable}` when the invite is missing, revoked, or already
  consumed. Performs no consumption — that remains the responsibility of the
  final registration step (see `Foglet.Accounts.register_user/1` for the
  `invite_only` path).
  """
  @spec verify_invite_code(String.t() | any(), module()) ::
          :ok | {:error, :format | :unavailable}
  def verify_invite_code(code, invites_mod \\ Invites)

  def verify_invite_code(code, invites_mod) when is_binary(code) do
    if valid_invite_code?(code) do
      case invites_mod.get_invite_status(code) do
        {:ok, %{status: :available}} -> :ok
        {:ok, _other} -> {:error, :unavailable}
        {:error, :not_found} -> {:error, :unavailable}
      end
    else
      {:error, :format}
    end
  end

  def verify_invite_code(_code, _invites_mod), do: {:error, :format}

  @generic_error "Please double-check the form and try again."

  @doc """
  Maps the **first** error on an `Ecto.Changeset` from
  `Foglet.Accounts.User.registration_changeset/2` to a user-facing sentence.

  Copy is sourced from FOG-53 §3.6a; unrecognized `{field, error}` shapes
  collapse to a generic safe message so raw atoms or Ecto internals never
  reach the user. Only the first failure is surfaced — no field-name
  prefixes, no concatenation.
  """
  @spec changeset_error_text(Ecto.Changeset.t()) :: String.t()
  def changeset_error_text(%Ecto.Changeset{errors: []}), do: @generic_error

  def changeset_error_text(%Ecto.Changeset{errors: [first | _]}) do
    translate_error(first)
  end

  defp translate_error({field, {_msg, opts}}) do
    cond do
      Keyword.get(opts, :validation) == :required -> required_sentence(field)
      Keyword.get(opts, :validation) == :format -> format_sentence(field)
      Keyword.get(opts, :validation) == :length -> length_sentence(field, opts)
      Keyword.get(opts, :validation) == :unsafe_unique -> unique_sentence(field)
      Keyword.get(opts, :constraint) == :unique -> unique_sentence(field)
      true -> @generic_error
    end
  end

  defp required_sentence(:handle), do: "Pick a handle."
  defp required_sentence(:email), do: "Enter an email address."
  defp required_sentence(:password), do: "Pick a password."
  defp required_sentence(_), do: @generic_error

  defp unique_sentence(:handle), do: "That handle is already in use. Pick another."
  defp unique_sentence(:email), do: "That email is already on file."
  defp unique_sentence(_), do: @generic_error

  defp format_sentence(:handle),
    do: "Handles can only use letters, numbers, dashes, and underscores."

  defp format_sentence(:email), do: "That doesn't look like an email address."
  defp format_sentence(_), do: @generic_error

  defp length_sentence(:handle, opts) do
    case Keyword.get(opts, :kind) do
      :min -> "Handles need to be at least #{Keyword.get(opts, :count)} characters."
      :max -> "Handles can't be longer than #{Keyword.get(opts, :count)} characters."
      _ -> @generic_error
    end
  end

  defp length_sentence(:email, opts) do
    case Keyword.get(opts, :kind) do
      :max -> "Emails can't be longer than #{Keyword.get(opts, :count)} characters."
      _ -> @generic_error
    end
  end

  defp length_sentence(:password, opts) do
    case Keyword.get(opts, :kind) do
      :min -> "Passwords need to be at least #{Keyword.get(opts, :count)} characters."
      :max -> "Passwords can't be longer than #{Keyword.get(opts, :count)} characters."
      _ -> @generic_error
    end
  end

  defp length_sentence(_field, _opts), do: @generic_error
end
