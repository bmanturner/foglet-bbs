defmodule Mix.Tasks.Foglet.IpAccess.Disable do
  @moduledoc "Disable an operator SSH IP access rule by id."
  @shortdoc "Disable SSH IP access rule"
  use Mix.Task
  @requirements ["app.config"]
  alias Foglet.{MixTaskHelpers, SSH}

  def run(args) do
    MixTaskHelpers.start_app!()

    {_opts, [id]} =
      MixTaskHelpers.parse_args!(args, [], "Usage: mix foglet.ip_access.disable RULE_ID")

    case SSH.disable_access_rule(id) do
      {:ok, _rule} ->
        Mix.shell().info("disabled id=#{id}")

      {:error, :not_found} ->
        MixTaskHelpers.fail("Rule not found: #{id}")

      {:error, changeset} ->
        MixTaskHelpers.fail_changeset("Could not disable SSH IP access rule.", changeset)
    end
  end
end
