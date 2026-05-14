defmodule Foglet.TimeAgo do
  @moduledoc """
  Short-form relative time formatter for Foglet BBS (WIDGET-02).

  Produces compact human-readable strings like "30s", "5m", "2h",
  "3d", "2w", "6mo", "2y". No external dependencies — stdlib only.

  Used by Thread list rows (LIST-03, Phase 3).
  """

  @doc """
  Returns a compact relative-time string for a given DateTime compared to now.

  Examples:
    iex> Foglet.TimeAgo.format(DateTime.add(DateTime.utc_now(), -45, :second))
    "45s"
    iex> Foglet.TimeAgo.format(DateTime.add(DateTime.utc_now(), -7, :minute))
    "7m"
    iex> Foglet.TimeAgo.format(DateTime.add(DateTime.utc_now(), -3, :hour))
    "3h"
  """
  @spec format(DateTime.t() | nil | any()) :: String.t()
  def format(%DateTime{} = dt) do
    format(dt, DateTime.utc_now())
  end

  def format(nil), do: "?"
  def format(_), do: "?"

  @spec format(DateTime.t() | nil | any(), DateTime.t()) :: String.t()
  def format(%DateTime{} = dt, %DateTime{} = now) do
    seconds = DateTime.diff(now, dt, :second)
    format_seconds(max(seconds, 0))
  end

  def format(nil, %DateTime{}), do: "?"
  def format(_, %DateTime{}), do: "?"

  @spec format_seconds(non_neg_integer()) :: String.t()
  defp format_seconds(s) when s < 60, do: "#{s}s"
  defp format_seconds(s) when s < 3_600, do: "#{div(s, 60)}m"
  defp format_seconds(s) when s < 86_400, do: "#{div(s, 3_600)}h"
  defp format_seconds(s) when s < 604_800, do: "#{div(s, 86_400)}d"
  defp format_seconds(s) when s < 2_592_000, do: "#{div(s, 604_800)}w"
  defp format_seconds(s) when s < 31_536_000, do: "#{div(s, 2_592_000)}mo"
  defp format_seconds(s), do: "#{div(s, 31_536_000)}y"
end
