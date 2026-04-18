defmodule Foglet.Boards.Category do
  @moduledoc "Schema for BBS categories — top-level groupings of boards."
  use Foglet.Schema

  schema "categories" do
    field :name, :string
    field :description, :string
    field :display_order, :integer, default: 0
    field :archived, :boolean, default: false

    has_many :boards, Foglet.Boards.Board

    timestamps()
  end

  @doc "Changeset for sysop category creation/editing."
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :description, :display_order, :archived])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
  end
end
