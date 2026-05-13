defmodule Mix.Tasks.Foglet.IdentityPolicy.Create do
  @moduledoc "Create an operator identity policy rule."
  @shortdoc "Create identity policy rule"
  use Mix.Task
  @requirements ["app.config"]
  alias Foglet.{Accounts.IdentityPolicy, MixTaskHelpers}
  alias Mix.Tasks.Foglet.IdentityPolicy.Helpers

  @switches [kind: :string, value: :string, reason: :string, comment: :string, disabled: :boolean]
  def run(args) do
    MixTaskHelpers.start_app!()
    {opts, []} = MixTaskHelpers.parse_args!(args, @switches, usage())

    attrs = %{
      kind: opts[:kind],
      value: opts[:value],
      reason: opts[:reason],
      comment: opts[:comment],
      enabled: not Keyword.get(opts, :disabled, false)
    }

    case IdentityPolicy.create_rule(attrs) do
      {:ok, rule} ->
        Mix.shell().info("created id=#{rule.id} kind=#{rule.kind} value=#{rule.value}")
        Helpers.warn_conflicts(rule)

      {:error, changeset} ->
        MixTaskHelpers.fail_changeset("Could not create identity policy rule.", changeset)
    end
  end

  defp usage,
    do:
      "Usage: mix foglet.identity_policy.create --kind reserved_handle|banned_handle|banned_email|banned_email_domain --value VALUE --reason TEXT [--comment TEXT] [--disabled]"
end
