defmodule Foglet.TUI.TerminalAlert do
  @moduledoc """
  Privacy-safe terminal alert payloads for new-notification attention cues.

  This module never includes notification or user-generated content in raw
  terminal escape output. OSC mode uses a fixed generic message only.
  """

  @default_mode :terminal_bell
  @preference_key "notification_alert"
  @quiet_window_ms 2_000

  @type mode :: :off | :terminal_bell | :desktop_osc_best_effort

  @doc "Returns the persisted notification-alert mode for a user, defaulting to terminal bell."
  @spec mode_from_user(map() | struct() | nil) :: mode()
  def mode_from_user(user) do
    user
    |> preferences_from_user()
    |> preference_value()
    |> normalize_mode()
  end

  @doc "Normalizes a user-supplied preference value into a supported alert mode."
  @spec normalize_mode(term()) :: mode()
  def normalize_mode(:off), do: :off
  def normalize_mode("off"), do: :off
  def normalize_mode(:terminal_bell), do: :terminal_bell
  def normalize_mode("terminal_bell"), do: :terminal_bell
  def normalize_mode(:desktop_osc_best_effort), do: :desktop_osc_best_effort
  def normalize_mode("desktop_osc_best_effort"), do: :desktop_osc_best_effort
  def normalize_mode(_value), do: @default_mode

  @doc "Serializes the selected alert mode into a safe terminal control sequence."
  def sequence(mode, notification \\ nil)

  def sequence(:off, _notification), do: nil
  def sequence("off", _notification), do: nil
  def sequence(:terminal_bell, _notification), do: <<7>>
  def sequence("terminal_bell", _notification), do: <<7>>

  def sequence(:desktop_osc_best_effort, _notification),
    do: "\e]9;Foglet: new notification\a"

  def sequence("desktop_osc_best_effort", notification),
    do: sequence(:desktop_osc_best_effort, notification)

  def sequence(other, notification), do: other |> normalize_mode() |> sequence(notification)

  @doc "Applies a small per-session quiet window to prevent repeated alert storms."
  @spec check_rate_limit(map(), integer()) ::
          {:emit, %{:last_notification_alert_at_ms => integer(), optional(any()) => any()}}
          | {:suppress, map()}
  def check_rate_limit(state, now_ms) when is_map(state) and is_integer(now_ms) do
    last = Map.get(state, :last_notification_alert_at_ms)

    if is_integer(last) and now_ms - last < @quiet_window_ms do
      {:suppress, state}
    else
      {:emit, Map.put(state, :last_notification_alert_at_ms, now_ms)}
    end
  end

  @doc "Returns attrs with a normalized notification-alert preference merged in."
  @spec put_preference(map(), term()) :: %{:preferences => map(), optional(any()) => any()}
  def put_preference(attrs, value) when is_map(attrs) do
    preferences = Map.get(attrs, :preferences, %{}) || %{}
    mode = normalize_mode(value) |> Atom.to_string()
    Map.put(attrs, :preferences, Map.put(preferences, @preference_key, mode))
  end

  defp preferences_from_user(nil), do: %{}
  defp preferences_from_user(user) when is_map(user), do: Map.get(user, :preferences, %{}) || %{}

  defp preference_value(preferences) when is_map(preferences),
    do: Map.get(preferences, @preference_key) || Map.get(preferences, :notification_alert)
end
