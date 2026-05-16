defmodule Mix.Tasks.Foglet.IpAccess.Remove do
  @moduledoc "Remove an operator SSH IP access rule by id."
  @shortdoc "Remove SSH IP access rule"
  use Mix.Task
  @requirements ["app.config"]
  alias Foglet.{MixTaskHelpers, SSH}

  def run(args) do
    MixTaskHelpers.start_app!()

    {_opts, [id]} =
      MixTaskHelpers.parse_args!(args, [], "Usage: mix foglet.ip_access.remove RULE_ID")

    case SSH.remove_access_rule(id) do
      {:ok, _rule} ->
        Mix.shell().info("removed id=#{id}")

      {:error, :not_found} ->
        MixTaskHelpers.fail("Rule not found: #{id}")

      {:error, changeset} ->
        MixTaskHelpers.fail_changeset("Could not remove SSH IP access rule.", changeset)
    end
  end
end
