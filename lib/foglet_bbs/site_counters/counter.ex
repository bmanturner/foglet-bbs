defmodule Foglet.SiteCounters.Counter do
  @moduledoc false

  use Foglet.Schema

  schema "site_counters" do
    field :name, :string
    field :value, :integer, default: 0

    timestamps()
  end
end
