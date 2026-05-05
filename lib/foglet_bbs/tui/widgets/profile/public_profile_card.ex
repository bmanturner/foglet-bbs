defmodule Foglet.TUI.Widgets.Profile.PublicProfileCard do
  @moduledoc """
  Stateless public profile-card modal body (D-07, D-09, D-13, D-16).

  Renders only the whitelisted `Foglet.Accounts.PublicProfile` summary and
  sanitizes user-entered text before it reaches terminal text widgets.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.Accounts.PublicProfile
  alias Foglet.TerminalText
  alias Foglet.TimeAgo
  alias Foglet.TUI.RoleBadge
  alias Foglet.TUI.Theme

  @divider_width 44

  @spec render(PublicProfile.t(), Theme.t()) :: term()
  def render(%PublicProfile{} = profile, %Theme{} = theme) do
    lines = detail_lines(profile)

    header_rows =
      [
        handle_row(profile, theme),
        role_row(profile, theme),
        text(String.duplicate("─", @divider_width), fg: theme.border.fg)
      ]
      |> Enum.reject(&is_nil/1)

    column style: %{gap: 0} do
      header_rows ++
        public_copy_rows(profile, theme) ++
        Enum.map(lines, &detail_row(&1, theme)) ++
        [text(""), text("[Enter/Esc] close", fg: theme.dim.fg)]
    end
  end

  defp handle_row(%PublicProfile{handle: handle}, theme) do
    text("@#{safe_one_line(handle || "unknown")}", fg: theme.title.fg, style: [:bold])
  end

  defp role_row(%PublicProfile{role: role}, theme) do
    case RoleBadge.badge(role) do
      nil -> nil
      badge -> text(badge, fg: theme.accent.fg, style: [:bold])
    end
  end

  defp public_copy_rows(%PublicProfile{} = profile, theme) do
    [
      profile.tagline && text(safe_one_line(profile.tagline), fg: theme.primary.fg),
      profile.location && text("⌖ " <> safe_one_line(profile.location), fg: theme.dim.fg),
      text("")
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp detail_lines(%PublicProfile{} = profile) do
    base = [
      {"Posts", Integer.to_string(profile.post_count || 0)},
      {"Joined", date_label(profile.joined_at)},
      {"Presence", profile.presence.label}
    ]

    if profile.presence.online? do
      base
    else
      base ++ last_seen_line(profile.last_seen_at)
    end
  end

  defp detail_row({label, value}, theme) do
    row style: %{gap: 0} do
      [
        text(String.pad_trailing(label <> ":", 12), fg: theme.dim.fg),
        text(safe_one_line(value), fg: theme.primary.fg)
      ]
    end
  end

  defp last_seen_line(nil), do: []
  defp last_seen_line(%DateTime{} = dt), do: [{"Last seen", TimeAgo.format(dt) <> " ago"}]

  defp last_seen_line(%NaiveDateTime{} = ndt),
    do: [{"Last seen", Calendar.strftime(ndt, "%Y-%m-%d")}]

  defp last_seen_line(_), do: []

  defp date_label(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d")
  defp date_label(%NaiveDateTime{} = ndt), do: Calendar.strftime(ndt, "%Y-%m-%d")
  defp date_label(_), do: "unknown"

  defp safe_one_line(value) do
    value
    |> to_string()
    |> TerminalText.sanitize_plain_text()
    |> String.replace(~r/[\r\n\t]+/, " ")
    |> String.trim()
  end
end
