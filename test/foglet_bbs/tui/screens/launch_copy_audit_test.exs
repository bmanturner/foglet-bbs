defmodule Foglet.TUI.Screens.LaunchCopyAuditTest do
  use ExUnit.Case, async: true

  @audited_globs [
    "README.md",
    "lib/foglet_bbs/tui/screens/**/*.ex",
    "lib/mix/tasks/**/*.ex"
  ]

  @forbidden_launch_claims [
    ~r/browser admin/i,
    ~r/end-user browser/i,
    ~r/webhook notification/i,
    ~r/email digest/i,
    ~r/daily\/weekly/i,
    ~r/delivery retry queue/i,
    ~r/outbound delivery logs/i,
    ~r/full case-management/i
  ]

  test "terminal-visible launch copy avoids unsupported feature claims" do
    audited_files = audited_files()

    assert "README.md" in audited_files
    assert Enum.any?(audited_files, &String.starts_with?(&1, "lib/foglet_bbs/tui/screens/"))
    assert Enum.any?(audited_files, &String.starts_with?(&1, "lib/mix/tasks/"))

    failures =
      for path <- audited_files,
          source = File.read!(path),
          source = source_without_readme_caveats(path, source),
          pattern <- @forbidden_launch_claims,
          Regex.match?(pattern, source) do
        "#{path}:#{inspect(pattern)}"
      end

    assert failures == [],
           "Unsupported launch claims found:\n" <> Enum.join(failures, "\n")
  end

  test "allowed infrastructure references remain permitted" do
    allowed_copy = """
    Phoenix LiveDashboard remains an operational endpoint.
    SMTP email delivery can be configured for verification and reset flows.
    Sysop terminal tasks provide break-glass operations.
    """

    refute Enum.any?(@forbidden_launch_claims, &Regex.match?(&1, allowed_copy))
  end

  defp audited_files do
    @audited_globs
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.filter(&File.regular?/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp source_without_readme_caveats("README.md", source) do
    source
    |> String.split("\n")
    |> Enum.reject(&readme_caveat_line?/1)
    |> Enum.join("\n")
  end

  defp source_without_readme_caveats(_path, source), do: source

  defp readme_caveat_line?(line) do
    String.contains?(line, "not a v1.2 pre-alpha capability") ||
      String.contains?(line, "not an end-user browser workflow")
  end
end
