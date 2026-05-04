defmodule Foglet.TUI.SessionContext do
  @moduledoc """
  Typed context handed from `Foglet.SSH.CLIHandler` to `Foglet.TUI.App`
  at session start. Fields here represent the user's identity, auth
  state, and personalisation choices captured at the time of channel
  attachment.

  The struct is constructed by `Foglet.SSH.CLIHandler.build_context/3` and
  consumed by `Foglet.TUI.App.extract_context/1`. Making the contract a typed
  struct rather than a plain map gives Dialyzer a checkable boundary and
  prevents key-name drift between the two modules.

  Fields
  - `user` — the authenticated `Foglet.Accounts.User` struct, or `nil` for
    unauthenticated (guest) sessions.
  - `user_id` — UUID of the authenticated user, or `nil`.
  - `session_pid` — PID of the live `Foglet.Sessions.Session` process, or
    `nil` when the session was not started (e.g. during tests or guest mode).
  - `pubkey_authenticated` — `true` when the SSH connection presented a known
    public key that matched a registered user.
  - `registration_mode` — value of the `registration_mode` runtime config key
    at channel-attachment time (e.g. `"open"`, `"invite_only"`, `"closed"`).
  - `guest_mode_enabled` — snapshot of the `guest_mode_enabled` runtime config
    key at channel-attachment time. Downstream login/menu code uses this to
    gate intentional guest browsing without round-tripping to config storage.
  - `guest` — `true` only after the visitor intentionally enters read-only
    Guest Mode. A nil `user` with `guest: false` means login-screen
    unauthenticated, not guest browsing.
  - `max_post_length` — character cap for post bodies, sourced from the
    `max_post_length` runtime config key.
  - `timezone` — IANA timezone string from the user's preferences (or the
    system default when the user has no preference set).
  - `time_format` — display format string for timestamps, sourced from user
    preferences.
  - `theme_id` — string identifier for the active colour theme (e.g. `"gray"`).
  - `theme` — flat `%Foglet.TUI.Theme{}` snapshot resolved from `theme_id` at
    session start. Screens and widgets read colour slots directly from this
    struct to avoid per-render lookups.
  - `ssh_peer` — the SSH peer descriptor captured by `Foglet.SSH.CLIHandler`
    at channel-up time (typically `{ip_tuple, port}` or `:unknown`), or `nil`
    for non-SSH callers (tests, render fixtures). Carried into the
    guest-to-user promotion path so promotion audit logs can include peer
    context (SSH-02 / D-04).
  - `offered_ssh_public_key` — OpenSSH public-key text offered by the connecting
    SSH client when no active registered user matched it. Populated only for
    guest sessions; authenticated public-key sessions keep this as `nil`.
  - `door_handler_pid` — PID of the owning SSH channel handler when this TUI is
    attached to SSH. Door launch effects send requests back to that process so
    it can route terminal input/output while the supervised runner is active.
  """

  @type t :: %__MODULE__{
          user: Foglet.Accounts.User.t() | nil,
          user_id: String.t() | nil,
          session_pid: pid() | nil,
          pubkey_authenticated: boolean(),
          registration_mode: String.t(),
          guest_mode_enabled: boolean(),
          guest: boolean(),
          max_post_length: pos_integer(),
          timezone: String.t(),
          time_format: String.t(),
          theme_id: String.t(),
          theme: Foglet.TUI.Theme.t(),
          ssh_peer: term() | nil,
          offered_ssh_public_key: String.t() | nil,
          door_handler_pid: pid() | nil
        }

  defstruct [
    :user,
    :user_id,
    :session_pid,
    :pubkey_authenticated,
    :registration_mode,
    :timezone,
    :time_format,
    :theme_id,
    :theme,
    :ssh_peer,
    :offered_ssh_public_key,
    :door_handler_pid,
    guest_mode_enabled: true,
    guest: false,
    max_post_length: 8192
  ]

  @doc "True only for an intentional read-only guest browsing session."
  @spec guest?(t() | map()) :: boolean()
  def guest?(context) when is_map(context),
    do: Map.get(context, :guest, false) == true and is_nil(Map.get(context, :user))

  @doc "True when the session has an authenticated user identity."
  @spec authenticated?(t() | map()) :: boolean()
  def authenticated?(context) when is_map(context), do: not is_nil(Map.get(context, :user))

  @doc "True for the login-screen unauthenticated state before Guest Mode is intentionally entered."
  @spec login_unauthenticated?(t() | map()) :: boolean()
  def login_unauthenticated?(context) when is_map(context),
    do: not authenticated?(context) and not guest?(context)

  @doc "Snapshot predicate for whether Guest Mode was enabled when this context was built."
  @spec guest_mode_enabled?(t() | map()) :: boolean()
  def guest_mode_enabled?(context) when is_map(context),
    do: Map.get(context, :guest_mode_enabled, true) == true
end
