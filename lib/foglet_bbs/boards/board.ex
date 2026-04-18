defmodule Foglet.Boards.Board do
  @moduledoc "Schema for BBS boards — discussion areas within a category."
  use Foglet.Schema

  schema "boards" do
    field :slug, :string
    field :name, :string
    field :description, :string
    field :display_order, :integer, default: 0
    field :next_message_number, :integer, default: 1
    field :readable_by, Ecto.Enum, values: [:public, :members], default: :public
    field :postable_by, Ecto.Enum, values: [:members, :mods_only, :sysop_only], default: :members
    field :archived, :boolean, default: false
    field :default_subscription, :boolean, default: false

    belongs_to :category, Foglet.Boards.Category

    has_many :threads, Foglet.Threads.Thread
    has_many :posts, Foglet.Posts.Post
    has_many :subscriptions, Foglet.Boards.Subscription

    timestamps()
  end

  @doc "Changeset for sysop board creation/editing."
  def changeset(board, attrs) do
    board
    |> cast(attrs, [
      :slug,
      :name,
      :description,
      :display_order,
      :readable_by,
      :postable_by,
      :archived,
      :default_subscription,
      :category_id
    ])
    |> validate_required([:slug, :name, :category_id])
    |> validate_length(:slug, min: 1, max: 50)
    |> validate_format(:slug, ~r/^[a-z0-9_-]+$/, message: "must be lowercase alphanumeric with _ or -")
    |> validate_length(:name, min: 1, max: 100)
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:category_id)
  end
end
