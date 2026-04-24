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

  test "README does not claim unsupported target-state launch capabilities" do
    readme = File.read!("README.md")

    for phrase <- @unsupported_target_state_claims do
      refute readme =~ phrase
    end
  end
end
