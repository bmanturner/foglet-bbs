defmodule Mix.Tasks.Foglet.IpAccess.Enable do
  @moduledoc "Enable an operator SSH IP access rule by id."
  @shortdoc "Enable SSH IP access rule"
  use Mix.Task
  @requirements ["app.config"]
  alias Foglet.{MixTaskHelpers, SSH}

  def run(args) do
    MixTaskHelpers.start_app!()

    {_opts, [id]} =
      MixTaskHelpers.parse_args!(args, [], "Usage: mix foglet.ip_access.enable RULE_ID")

    case SSH.enable_access_rule(id) do
      {:ok, _rule} ->
        Mix.shell().info("enabled id=#{id}")

      {:error, :not_found} ->
        MixTaskHelpers.fail("Rule not found: #{id}")

      {:error, changeset} ->
        MixTaskHelpers.fail_changeset("Could not enable SSH IP access rule.", changeset)
    end
  end
end
