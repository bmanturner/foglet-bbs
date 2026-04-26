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
  """

  @type t :: %__MODULE__{
          user: Foglet.Accounts.User.t() | nil,
          user_id: String.t() | nil,
          session_pid: pid() | nil,
          pubkey_authenticated: boolean(),
          registration_mode: String.t(),
          max_post_length: pos_integer(),
          timezone: String.t(),
          time_format: String.t(),
          theme_id: String.t(),
          theme: Foglet.TUI.Theme.t()
        }

  defstruct [
    :user,
    :user_id,
    :session_pid,
    :pubkey_authenticated,
    :registration_mode,
    :max_post_length,
    :timezone,
    :time_format,
    :theme_id,
    :theme
  ]
end
