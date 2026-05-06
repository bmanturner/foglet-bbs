defmodule Foglet.SSH.CLIHandler.PubkeyIdentity do
  @moduledoc """
  Resolves stashed SSH public-key offers into the identity shape consumed by
  `Foglet.SSH.CLIHandler` channel startup.

  This helper keeps pubkey correlation, account gate checks, and initial session
  process startup outside the SSH callback module while preserving ownership:
  CLIHandler still decides when channel-up succeeds and owns teardown.
  """

  alias Foglet.Accounts.Auth
  alias Foglet.Sessions
  alias Foglet.Sessions.Preferences

  @doc """
  Pops the stashed key for `peer` and returns a map describing the matched user,
  auth gate, and offered OpenSSH text for guest registration.
  """
  def resolve(peer) do
    case Foglet.SSH.PubkeyStash.pop_offer(peer) do
      {:ok, %{openssh_text: openssh_text}} when is_binary(openssh_text) ->
        resolve_offer(openssh_text)

      :miss ->
        %{user: nil, offered_ssh_public_key: nil}
    end
  end

  @doc """
  Starts the initial session process for a pubkey resolution.

  Authorized users get a member session. Guests, unmatched keys, and gated
  users start as guest sessions so the TUI can show the appropriate login or
  gate flow.
  """
  def start_session(%{kind: :authorized, user: user}), do: start_authenticated_session(user)

  def start_session(_pubkey_resolution) do
    case Sessions.Supervisor.start_guest_session() do
      {:ok, pid} -> pid
      _ -> nil
    end
  end

  defp resolve_offer(openssh_text) do
    case Auth.lookup_by_public_key(openssh_text) do
      {:ok, %{user: user}} -> resolve_matched(user, openssh_text)
      {:error, :not_found} -> %{user: nil, offered_ssh_public_key: openssh_text}
    end
  end

  defp resolve_matched(user, openssh_text) do
    case Auth.authorize_session(user) do
      {:ok, :authorized, _authorized_user} ->
        case Auth.authenticate_by_public_key(openssh_text) do
          {:ok, user} ->
            %{kind: :authorized, user: user, gate: nil, offered_ssh_public_key: nil}

          {:error, :not_found} ->
            %{kind: :guest, user: nil, gate: nil, offered_ssh_public_key: nil}
        end

      {:ok, :verify, user} ->
        %{kind: :gated, user: user, gate: :verify, offered_ssh_public_key: nil}

      {:error, gate} ->
        %{kind: :gated, user: user, gate: gate, offered_ssh_public_key: nil}
    end
  end

  defp start_authenticated_session(user) do
    preferences = Preferences.from_user(user)

    case Sessions.Supervisor.start_session(
           user_id: user.id,
           handle: user.handle,
           role: user.role,
           timezone: preferences.timezone,
           time_format: preferences.time_format,
           theme_id: preferences.theme_id,
           theme: preferences.theme
         ) do
      {:ok, pid} -> pid
      _ -> nil
    end
  end
end
