defmodule Foglet.TUI.Screens.Account.SSHKeysActions do
  @moduledoc """
  Live actions for the Account SSH KEYS tab.

  All durable behavior delegates to `Foglet.Accounts`; this module only maps
  terminal events to screen-local state transitions.
  """

  alias Ecto.Changeset
  alias Foglet.Accounts
  alias Foglet.Accounts.User
  alias Foglet.TUI.Screens.Account.SSHKeysState

  @type action_result :: {:ok, SSHKeysState.t()} | :no_match

  @spec load(User.t(), SSHKeysState.t()) :: {:ok, SSHKeysState.t()}
  def load(%User{} = actor, %SSHKeysState{} = state) do
    {:ok, SSHKeysState.loaded(state, Accounts.list_ssh_keys(actor))}
  end

  @spec refresh(User.t(), SSHKeysState.t()) :: {:ok, SSHKeysState.t()}
  def refresh(%User{} = actor, %SSHKeysState{} = state), do: load(actor, state)

  @spec add(User.t(), SSHKeysState.t(), map()) :: {:ok, SSHKeysState.t()}
  def add(%User{} = actor, %SSHKeysState{} = state, attrs) when is_map(attrs) do
    attrs = %{
      label: Map.get(attrs, :label) || Map.get(attrs, "label") || "",
      public_key: Map.get(attrs, :public_key) || Map.get(attrs, "public_key") || ""
    }

    case Accounts.register_ssh_key(actor, attrs) do
      {:ok, _key} ->
        {:ok, loaded} = load(actor, %{state | mode: :list, form: %{label: "", public_key: ""}})
        {:ok, SSHKeysState.with_status(loaded, "SSH key added.")}

      {:error, %Changeset{} = changeset} ->
        {:ok, SSHKeysState.with_error(state, changeset_errors(changeset))}
    end
  end

  @spec revoke_selected(User.t(), SSHKeysState.t()) :: {:ok, SSHKeysState.t()}
  def revoke_selected(%User{} = actor, %SSHKeysState{items: items} = state) when is_list(items) do
    case Enum.at(items, SSHKeysState.selected_index(state)) do
      %{id: id} ->
        revoke_key(actor, id, state)

      _missing ->
        {:ok, SSHKeysState.with_error(state, "Select an SSH key first.")}
    end
  end

  def revoke_selected(%User{}, %SSHKeysState{} = state) do
    {:ok, SSHKeysState.with_error(state, "Select an SSH key first.")}
  end

  @spec select_next(SSHKeysState.t()) :: SSHKeysState.t()
  def select_next(%SSHKeysState{} = state), do: SSHKeysState.select_next(state)

  @spec select_prev(SSHKeysState.t()) :: SSHKeysState.t()
  def select_prev(%SSHKeysState{} = state), do: SSHKeysState.select_prev(state)

  @spec handle_key(term(), User.t(), SSHKeysState.t()) :: action_result()
  def handle_key(key, %User{}, %SSHKeysState{mode: :list} = state)
      when key in ["a", "A"] do
    {:ok, SSHKeysState.start_add(state)}
  end

  def handle_key(key, %User{} = actor, %SSHKeysState{mode: :list} = state)
      when key in ["r", "R"] do
    refresh(actor, state)
  end

  def handle_key(key, %User{} = actor, %SSHKeysState{mode: :list} = state)
      when key in ["d", "D"] do
    revoke_selected(actor, state)
  end

  def handle_key(:down, %User{}, %SSHKeysState{mode: :list} = state),
    do: {:ok, select_next(state)}

  def handle_key(:up, %User{}, %SSHKeysState{mode: :list} = state), do: {:ok, select_prev(state)}

  def handle_key(:tab, %User{}, %SSHKeysState{mode: :add} = state),
    do: {:ok, SSHKeysState.toggle_focus(state)}

  def handle_key(:enter, %User{} = actor, %SSHKeysState{mode: :add, form: form} = state),
    do: add(actor, state, form)

  def handle_key(:escape, %User{}, %SSHKeysState{mode: :add} = state),
    do: {:ok, SSHKeysState.cancel_add(state)}

  def handle_key(:backspace, %User{}, %SSHKeysState{mode: :add} = state),
    do: {:ok, SSHKeysState.backspace_focused(state)}

  def handle_key(char, %User{}, %SSHKeysState{mode: :add} = state) when is_binary(char),
    do: {:ok, SSHKeysState.append_focused(state, char)}

  def handle_key(_key, %User{}, %SSHKeysState{}), do: :no_match

  defp revoke_key(actor, id, state) do
    case Accounts.revoke_ssh_key(actor, id) do
      {:ok, _key} ->
        {:ok, loaded} = load(actor, state)
        {:ok, SSHKeysState.with_status(loaded, "SSH key revoked.")}

      {:error, :not_found} ->
        {:ok, SSHKeysState.with_error(state, "That SSH key is no longer here. Refresh the list.")}
    end
  end

  # Translate domain validation messages into the friendly user-facing strings
  # specified in FOG-127. Unknown messages fall through with the field name so
  # we never silently drop validation feedback.
  defp changeset_errors(%Changeset{} = changeset) do
    changeset
    |> Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.into(%{}, fn {field, messages} ->
      raw = Enum.join(messages, ", ")
      {field, friendly_ssh_error(field, raw)}
    end)
  end

  defp friendly_ssh_error(:label, msg) do
    cond do
      String.contains?(msg, "blank") or String.contains?(msg, "required") ->
        "Label is required."

      String.contains?(msg, "taken") ->
        "You already have an SSH key with that label."

      String.contains?(msg, "at most") or String.contains?(msg, "character") ->
        "Label must be 64 characters or fewer."

      true ->
        "Label: #{msg}"
    end
  end

  defp friendly_ssh_error(:public_key, msg) do
    cond do
      String.contains?(msg, "blank") or String.contains?(msg, "required") ->
        "Public key is required."

      String.contains?(msg, "invalid") or String.contains?(msg, "OpenSSH") ->
        "Public key must be a valid OpenSSH public key."

      true ->
        "Public key: #{msg}"
    end
  end

  defp friendly_ssh_error(:fingerprint, msg) do
    if String.contains?(msg, "taken") do
      "That public key is already on this account."
    else
      "Public key: #{msg}"
    end
  end

  defp friendly_ssh_error(field, msg), do: "#{field}: #{msg}"
end
