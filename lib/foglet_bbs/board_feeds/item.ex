defmodule Foglet.BoardFeeds.Item do
  @moduledoc "Sanitized cached item from a board feed."
  use Foglet.Schema

  schema "board_feed_items" do
    field :external_id, :string
    field :title, :string
    field :url, :string
    field :author, :string
    field :summary, :string
    field :published_at, :utc_datetime_usec
    field :fetched_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :feed, Foglet.BoardFeeds.Feed, foreign_key: :board_feed_id
    belongs_to :board, Foglet.Boards.Board

    timestamps()
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :external_id,
      :title,
      :url,
      :author,
      :summary,
      :published_at,
      :fetched_at,
      :metadata,
      :board_feed_id,
      :board_id
    ])
    |> validate_required([:external_id, :title, :fetched_at, :board_feed_id, :board_id])
    |> validate_length(:external_id, min: 1, max: 500)
    |> validate_length(:title, min: 1, max: 300)
    |> validate_length(:url, max: 2048)
    |> validate_length(:author, max: 120)
    |> validate_length(:summary, max: 1000)
    |> foreign_key_constraint(:board_feed_id)
    |> foreign_key_constraint(:board_id)
    |> unique_constraint([:board_feed_id, :external_id])
  end
end
