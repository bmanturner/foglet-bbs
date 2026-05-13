defmodule Mix.Tasks.Foglet.IdentityPolicy.Disable do
  @moduledoc "Disabled an operator identity policy rule."
  @shortdoc "Disabled identity policy rule"
  use Mix.Task
  @requirements ["app.config"]
  alias Foglet.{Accounts.IdentityPolicy, MixTaskHelpers}

  def run([id]) do
    MixTaskHelpers.start_app!()

    case IdentityPolicy.disable_rule(id) do
      {:ok, rule} ->
        Mix.shell().info("disabled id=#{rule.id}")

      {:error, changeset} ->
        MixTaskHelpers.fail_changeset("Could not disable identity policy rule.", changeset)
    end
  end

  def run(_), do: MixTaskHelpers.fail("Usage: mix foglet.identity_policy.disable RULE_ID")
end
