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

  @doc """
  Changeset that flips `archived` to true. Used by `Foglet.Boards.archive_category/2`.
  Defensively scoped: only `:archived` is cast, nothing else can be mutated through this path.
  Mirrors `Foglet.Boards.Board.archive_changeset/1` (D-11).
  """
  def archive_changeset(category) do
    category
    |> cast(%{archived: true}, [:archived])
    |> validate_required([:archived])
  end
end
