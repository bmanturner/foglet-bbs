defmodule Mix.Tasks.Foglet.IpAccess.RemoveTest do
  use FogletBbs.DataCase, async: false

  import ExUnit.CaptureIO

  alias Foglet.SSH
  alias Foglet.SSH.AccessRule
  alias FogletBbs.Repo

  setup do
    Mix.shell(Mix.Shell.IO)
    :ok
  end

  test "removes an access rule by id" do
    {:ok, rule} = SSH.create_access_rule(%{mode: :deny, address: "198.51.100.9", reason: "old"})

    output =
      capture_io(fn ->
        Mix.Tasks.Foglet.IpAccess.Remove.run([rule.id])
      end)

    assert output =~ "removed id=#{rule.id}"
    assert Repo.get(AccessRule, rule.id) == nil
  end

  test "missing access rule exits non-zero" do
    output =
      capture_io(:stderr, fn ->
        assert catch_exit(Mix.Tasks.Foglet.IpAccess.Remove.run([Ecto.UUID.generate()])) ==
                 {:shutdown, 1}
      end)

    assert output =~ "Rule not found"
  end
end
