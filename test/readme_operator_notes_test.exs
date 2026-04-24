defmodule Foglet.ReadmeOperatorNotesTest do
  use ExUnit.Case, async: true

  @required_operator_phrases [
    "## Operator Notes",
    "SSH-first",
    "Email mode",
    "no-email mode",
    "delivery_mode",
    "mix foglet.user.reset_password",
    "mix foglet.user.verification_code",
    "mix foglet.user.status",
    "mix foglet.board_subscriptions",
    "nested docs"
  ]

  @unsupported_target_state_claims [
    "Opt-in email digests",
    "webhook notifications",
    "delivery retry queue",
    "outbound delivery logs",
    "full case-management",
    "end-user web UI"
  ]

  test "README includes the operator notes needed for pre-alpha operation" do
    readme = File.read!("README.md")

    for phrase <- @required_operator_phrases do
      assert readme =~ phrase
    end
  end

  test "README explains nested docs may be future-oriented or internal design material" do
    readme = File.read!("README.md")

    assert readme =~ "nested docs"
    assert readme =~ "future-oriented"
    assert readme =~ "internal design material"
  end

  test "README only mentions unsupported target-state launch capabilities as caveats" do
    readme = File.read!("README.md")

    for phrase <- @unsupported_target_state_claims do
      assert_caveat_only(readme, phrase)
    end
  end

  defp assert_caveat_only(readme, phrase) do
    matching_lines =
      readme
      |> String.split("\n")
      |> Enum.filter(&String.contains?(&1, phrase))

    assert Enum.all?(matching_lines, &String.contains?(&1, "not a v1.2 pre-alpha capability"))
  end
end
