defmodule Mix.Tasks.FogletIdentityPolicyTest do
  use FogletBbs.DataCase, async: false

  alias Foglet.Accounts.IdentityPolicy

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  test "create/list/disable/enable/remove manage identity rules and warn about conflicts" do
    FogletBbs.AccountsFixtures.user_fixture(%{handle: "Taken", email: "taken@example.com"})

    Mix.Tasks.Foglet.IdentityPolicy.Create.run([
      "--kind",
      "banned_email_domain",
      "--value",
      "example.com",
      "--reason",
      "abuse"
    ])

    assert_received {:mix_shell, :info, [created]}
    assert created =~ "created id="
    assert_received {:mix_shell, :info, [warning]}
    assert warning =~ "conflicts=1"

    [rule] = IdentityPolicy.list_rules()

    Mix.Tasks.Foglet.IdentityPolicy.List.run([])
    assert_received {:mix_shell, :info, [line]}
    assert line =~ "banned_email_domain"
    assert line =~ "enabled=true"

    Mix.Tasks.Foglet.IdentityPolicy.Disable.run([rule.id])
    assert_received {:mix_shell, :info, [disabled]}
    assert disabled =~ "disabled id=#{rule.id}"

    Mix.Tasks.Foglet.IdentityPolicy.Enable.run([rule.id])
    assert_received {:mix_shell, :info, [enabled]}
    assert enabled =~ "enabled id=#{rule.id}"

    Mix.Tasks.Foglet.IdentityPolicy.Remove.run([rule.id])
    assert_received {:mix_shell, :info, [removed]}
    assert removed =~ "removed id=#{rule.id}"
    assert [] = IdentityPolicy.list_rules()
  end
end
