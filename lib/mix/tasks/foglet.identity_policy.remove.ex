defmodule Mix.Tasks.Foglet.IdentityPolicy.Remove do
  @moduledoc "Remove an operator identity policy rule."
  @shortdoc "Remove identity policy rule"
  use Mix.Task
  @requirements ["app.config"]
  alias Foglet.{Accounts.IdentityPolicy, MixTaskHelpers}

  def run([id]) do
    MixTaskHelpers.start_app!()
    {:ok, rule} = IdentityPolicy.remove_rule(id)
    Mix.shell().info("removed id=#{rule.id}")
  end

  def run(_), do: MixTaskHelpers.fail("Usage: mix foglet.identity_policy.remove RULE_ID")
end
