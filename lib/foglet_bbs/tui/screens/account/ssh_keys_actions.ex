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
        {:ok, SSHKeysState.with_error(state, "No SSH key is selected.")}
    end
  end

  def revoke_selected(%User{}, %SSHKeysState{} = state) do
    {:ok, SSHKeysState.with_error(state, "No SSH key is selected.")}
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
        {:ok, SSHKeysState.with_error(state, "That SSH key could not be found.")}
    end
  end

  defp changeset_errors(%Changeset{} = changeset) do
    changeset
    |> Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.into(%{}, fn {field, messages} -> {field, Enum.join(messages, ", ")} end)
  end
end
