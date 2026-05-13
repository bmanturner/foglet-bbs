defmodule Mix.Tasks.Foglet.IdentityPolicy.List do
  @moduledoc "List operator identity policy rules."
  @shortdoc "List identity policy rules"
  use Mix.Task
  @requirements ["app.config"]
  alias Foglet.{Accounts.IdentityPolicy, MixTaskHelpers}
  alias Mix.Tasks.Foglet.IdentityPolicy.Helpers

  def run(_args) do
    MixTaskHelpers.start_app!()
    Enum.each(IdentityPolicy.list_rules(), &Helpers.print_rule/1)
  end
end
