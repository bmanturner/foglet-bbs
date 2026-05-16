defmodule Mix.Tasks.Foglet.IpAccess.Create do
  @moduledoc "Create an operator SSH IP access allow/deny rule."
  @shortdoc "Create SSH IP access rule"
  use Mix.Task
  @requirements ["app.config"]
  alias Foglet.{MixTaskHelpers, SSH}

  @switches [
    mode: :string,
    address: :string,
    reason: :string,
    comment: :string,
    disabled: :boolean
  ]
  def run(args) do
    MixTaskHelpers.start_app!()
    {opts, []} = MixTaskHelpers.parse_args!(args, @switches, usage())

    attrs = %{
      mode: opts[:mode],
      address: opts[:address],
      reason: opts[:reason],
      comment: opts[:comment],
      enabled: not Keyword.get(opts, :disabled, false)
    }

    case SSH.create_access_rule(attrs) do
      {:ok, rule} ->
        Mix.shell().info("created id=#{rule.id} mode=#{rule.mode} address=#{rule.address}")

      {:error, changeset} ->
        MixTaskHelpers.fail_changeset("Could not create SSH IP access rule.", changeset)
    end
  end

  defp usage,
    do:
      "Usage: mix foglet.ip_access.create --mode allow|deny --address IP_OR_CIDR --reason TEXT [--comment TEXT] [--disabled]"
end
