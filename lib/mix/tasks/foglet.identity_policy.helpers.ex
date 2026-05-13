defmodule Mix.Tasks.Foglet.IdentityPolicy.Helpers do
  @moduledoc false
  alias Foglet.Accounts.IdentityPolicy

  def print_rule(rule) do
    Mix.shell().info(
      "id=#{rule.id} kind=#{rule.kind} value=#{rule.value} normalized=#{rule.normalized_value} enabled=#{rule.enabled} reason=#{rule.reason}"
    )
  end

  def warn_conflicts(rule) do
    case IdentityPolicy.conflicts_for_rule(rule) do
      [] ->
        :ok

      conflicts ->
        Mix.shell().info(
          "warning conflicts=#{length(conflicts)} existing matching users were not mutated"
        )
    end
  end
end
