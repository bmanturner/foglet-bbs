defmodule Mix.Tasks.Foglet.IpAccess.List do
  @moduledoc "List operator SSH IP access rules."
  @shortdoc "List SSH IP access rules"
  use Mix.Task
  @requirements ["app.config"]
  alias Foglet.{MixTaskHelpers, SSH}

  def run(args) do
    MixTaskHelpers.start_app!()
    {_opts, []} = MixTaskHelpers.parse_args!(args, [], "Usage: mix foglet.ip_access.list")
    rules = SSH.list_access_rules()

    Enum.each(rules, fn rule ->
      Mix.shell().info(
        "id=#{rule.id} mode=#{rule.mode} enabled=#{rule.enabled} address=#{rule.address} reason=#{rule.reason}"
      )
    end)

    if rules == [], do: Mix.shell().info("No SSH IP access rules found.")
  end
end
