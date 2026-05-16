defmodule Foglet.SSH.AccessRuleAuthorizationTest do
  use FogletBbs.DataCase, async: true

  alias Foglet.SSH
  alias Foglet.SSH.AccessRule
  alias FogletBbs.Repo

  import FogletBbs.AccountsFixtures

  describe "actor-aware access rule management" do
    test "regular users cannot list or mutate access policy rules" do
      user = user_fixture() |> Ecto.Changeset.change(role: :user) |> Repo.update!()

      assert {:error, :forbidden} = SSH.list_access_rules(user)

      assert {:error, :forbidden} =
               SSH.create_access_rule(user, %{mode: :deny, address: "192.0.2.1"})

      assert {:error, :forbidden} = SSH.enable_access_rule(user, Ecto.UUID.generate())
      assert {:error, :forbidden} = SSH.disable_access_rule(user, Ecto.UUID.generate())
      assert {:error, :forbidden} = SSH.remove_access_rule(user, Ecto.UUID.generate())
    end

    test "sysops can manage rules through the authorized context boundary" do
      sysop = user_fixture() |> Ecto.Changeset.change(role: :sysop) |> Repo.update!()

      assert {:ok, %AccessRule{} = rule} =
               SSH.create_access_rule(sysop, %{
                 mode: :allow,
                 address: "2001:db8::/32",
                 reason: "ops"
               })

      assert {:ok, rules} = SSH.list_access_rules(sysop)
      assert Enum.any?(rules, &(&1.id == rule.id))
      assert {:ok, %AccessRule{enabled: false}} = SSH.disable_access_rule(sysop, rule.id)
      assert {:ok, %AccessRule{enabled: true}} = SSH.enable_access_rule(sysop, rule.id)
      assert {:ok, %AccessRule{id: removed_id}} = SSH.remove_access_rule(sysop, rule.id)
      assert removed_id == rule.id
      assert Repo.get(AccessRule, rule.id) == nil
    end
  end
end
