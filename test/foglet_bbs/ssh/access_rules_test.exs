defmodule Foglet.SSH.AccessRulesTest do
  use FogletBbs.DataCase, async: true

  alias Foglet.SSH
  alias Foglet.SSH.{AccessRule, LastCaller}
  alias FogletBbs.Repo
  import FogletBbs.AccountsFixtures

  describe "access rules" do
    test "validates IPv4, IPv6, and CIDR entries and rejects malformed input" do
      assert %{valid?: true} =
               AccessRule.changeset(%AccessRule{}, %{
                 mode: :deny,
                 address: "192.0.2.4",
                 reason: "abuse"
               })

      assert %{valid?: true} =
               AccessRule.changeset(%AccessRule{}, %{
                 mode: :allow,
                 address: "2001:db8::/32",
                 reason: "office"
               })

      refute AccessRule.changeset(%AccessRule{}, %{
               mode: :deny,
               address: "not-an-ip",
               reason: "bad"
             }).valid?

      refute AccessRule.changeset(%AccessRule{}, %{
               mode: :allow,
               address: "192.0.2.1/99",
               reason: "bad"
             }).valid?
    end

    test "evaluates deny rules before allowlist mode and supports CIDR matching" do
      {:ok, _} =
        SSH.create_access_rule(%{mode: :allow, address: "192.0.2.0/24", reason: "office"})

      {:ok, _} = SSH.create_access_rule(%{mode: :deny, address: "192.0.2.66", reason: "abuse"})

      assert {:deny, %{reason: "abuse"}} =
               SSH.evaluate_access({192, 0, 2, 66}, allowlist_enabled?: true)

      assert {:allow, %{reason: "office"}} =
               SSH.evaluate_access({192, 0, 2, 12}, allowlist_enabled?: true)

      assert {:deny, %{reason: "not_allowlisted"}} =
               SSH.evaluate_access({198, 51, 100, 1}, allowlist_enabled?: true)
    end

    test "disabled rules do not match and default mode allows when allowlist is off" do
      {:ok, rule} = SSH.create_access_rule(%{mode: :deny, address: "203.0.113.7", reason: "old"})
      assert {:deny, _} = SSH.evaluate_access({203, 0, 113, 7})
      {:ok, _} = SSH.disable_access_rule(rule.id)
      assert {:allow, %{reason: "default_allow"}} = SSH.evaluate_access({203, 0, 113, 7})
    end
  end

  describe "last callers audit" do
    test "records audit rows without auth material and snapshots public visibility" do
      user =
        user_fixture() |> Ecto.Changeset.change(show_in_last_callers: false) |> Repo.update!()

      assert {:ok, caller} =
               SSH.record_last_caller(%{
                 interface: :ssh,
                 peer_ip: {0x2001, 0xDB8, 0, 0, 0, 0, 0, 1},
                 peer_port: 2222,
                 user: user,
                 outcome: :accepted,
                 reason: "login",
                 session_id: "session-1",
                 public_visible: user.show_in_last_callers
               })

      assert caller.user_id == user.id
      assert caller.peer_ip == "2001:db8::1"
      refute caller.public_visible
      assert caller.metadata == %{}
    end

    test "cleanup redacts raw IPs after default 90 day retention and can detach deleted users" do
      user = user_fixture()
      old = DateTime.utc_now() |> DateTime.add(-91, :day) |> DateTime.truncate(:microsecond)
      recent = DateTime.utc_now() |> DateTime.add(-10, :day) |> DateTime.truncate(:microsecond)

      old_row =
        Repo.insert!(%LastCaller{
          interface: :ssh,
          peer_ip: "192.0.2.10",
          outcome: :accepted,
          occurred_at: old,
          user_id: user.id,
          public_visible: true
        })

      recent_row =
        Repo.insert!(%LastCaller{
          interface: :ssh,
          peer_ip: "192.0.2.11",
          outcome: :denied,
          occurred_at: recent,
          reason: "deny",
          public_visible: false
        })

      assert {1, nil} = SSH.redact_last_caller_raw_ips_older_than()
      assert Repo.get!(LastCaller, old_row.id).peer_ip == nil
      assert Repo.get!(LastCaller, recent_row.id).peer_ip == "192.0.2.11"

      assert {1, nil} = SSH.detach_last_callers_for_user(user)
      assert Repo.get!(LastCaller, old_row.id).user_id == nil
    end
  end
end
