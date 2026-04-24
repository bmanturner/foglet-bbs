defmodule Foglet.TUI.Widgets.Chrome.ClockFormatter do
  @moduledoc """
  Pure preference-aware formatter for chrome clock text.

  Uses the Phase 5 user preference snapshot and never reads persistence.
  """

  @default_timezone "Etc/UTC"
  @default_time_format "12h"
  @time_formats [@default_time_format, "24h"]

  @spec format(DateTime.t(), map() | nil) :: String.t()
  def format(%DateTime{} = now_utc, user) do
    timezone = user_timezone(user)
    time_format = user_time_format(user)

    now_utc
    |> convert(timezone)
    |> format_local(time_format)
  end

  defp user_timezone(user) do
    user
    |> field(:timezone)
    |> valid_timezone()
  end

  defp user_time_format(user) do
    user
    |> preferences()
    |> Map.get("time_format")
    |> valid_time_format()
  end

  defp field(%{timezone: timezone}, :timezone), do: timezone
  defp field(_, _), do: nil

  defp preferences(%{preferences: preferences}) when is_map(preferences), do: preferences
  defp preferences(_), do: %{}

  defp valid_timezone(timezone) when is_binary(timezone) do
    timezone = String.trim(timezone)

    if timezone != "" and Timex.Timezone.exists?(timezone) do
      timezone
    else
      @default_timezone
    end
  end

  defp valid_timezone(_), do: @default_timezone

  defp valid_time_format(time_format) when time_format in @time_formats, do: time_format
  defp valid_time_format(_), do: @default_time_format

  defp convert(now_utc, timezone) do
    case Timex.Timezone.convert(now_utc, timezone) do
      %DateTime{} = localized -> localized
      _ -> Timex.Timezone.convert(now_utc, @default_timezone)
    end
  rescue
    _ -> Timex.Timezone.convert(now_utc, @default_timezone)
  end

  defp format_local(%DateTime{} = datetime, "24h") do
    Calendar.strftime(datetime, "%H:%M")
  end

  defp format_local(%DateTime{} = datetime, "12h") do
    Calendar.strftime(datetime, "%I:%M %p")
  end
end
