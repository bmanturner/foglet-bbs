defmodule Mix.Tasks.Foglet.IdentityPolicy.Enable do
  @moduledoc "Enabled an operator identity policy rule."
  @shortdoc "Enabled identity policy rule"
  use Mix.Task
  @requirements ["app.config"]
  alias Foglet.{Accounts.IdentityPolicy, MixTaskHelpers}

  def run([id]) do
    MixTaskHelpers.start_app!()

    case IdentityPolicy.enable_rule(id) do
      {:ok, rule} ->
        Mix.shell().info("enabled id=#{rule.id}")

      {:error, changeset} ->
        MixTaskHelpers.fail_changeset("Could not enable identity policy rule.", changeset)
    end
  end

  def run(_), do: MixTaskHelpers.fail("Usage: mix foglet.identity_policy.enable RULE_ID")
end
