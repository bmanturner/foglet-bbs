defmodule Foglet.TUI.Screens.Account.Timezones do
  @moduledoc """
  Curated IANA timezone choices for the Account PREFS picker (FOG-131).

  The Preferences Timezone field is rendered as a Modal.Form `:enum` so users
  can pick a value with `↑/↓` instead of typing a raw IANA name from memory.
  This module owns the curated list and the rule for preserving a user's
  saved-but-non-curated timezone (so existing accounts never silently lose
  their selection when the curated list changes).

  Display order is intentional — `Etc/UTC` first, then a coverage sweep of
  Americas → Europe → Africa → Asia → Oceania. Adding a zone here is cheap;
  callers only need it to be a valid IANA name (validated on save by
  `Foglet.Accounts.User.validate_timezone/1`).
  """

  @curated [
    "Etc/UTC",
    "America/Los_Angeles",
    "America/Denver",
    "America/Chicago",
    "America/New_York",
    "America/Anchorage",
    "America/Honolulu",
    "America/Toronto",
    "America/Mexico_City",
    "America/Sao_Paulo",
    "Europe/London",
    "Europe/Paris",
    "Europe/Berlin",
    "Europe/Athens",
    "Europe/Moscow",
    "Africa/Cairo",
    "Africa/Johannesburg",
    "Asia/Dubai",
    "Asia/Kolkata",
    "Asia/Singapore",
    "Asia/Shanghai",
    "Asia/Tokyo",
    "Australia/Sydney",
    "Pacific/Auckland"
  ]

  @doc "Curated IANA timezone names in display order."
  @spec curated() :: [String.t()]
  def curated, do: @curated

  @doc """
  Returns the picker choices, ensuring `current` is always selectable.

  When the user's saved timezone is not in the curated list, it is prepended
  so the picker can render the existing selection without losing data. `nil`,
  empty strings, and already-present values fall through to `curated/0`.
  """
  @spec choices_for(String.t() | nil) :: [String.t()]
  def choices_for(nil), do: @curated
  def choices_for(""), do: @curated

  def choices_for(current) when is_binary(current) do
    if current in @curated, do: @curated, else: [current | @curated]
  end
end
