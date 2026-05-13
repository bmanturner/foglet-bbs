defmodule Foglet.BoardFeeds.Feed do
  @moduledoc "Durable board RSS/Atom feed configuration and refresh state."
  use Foglet.Schema

  schema "board_feeds" do
    field :url, :string
    field :title, :string
    field :enabled, :boolean, default: true
    field :display_order, :integer, default: 0
    field :cache_ttl_seconds, :integer, default: 3600
    field :last_fetched_at, :utc_datetime_usec
    field :last_success_at, :utc_datetime_usec
    field :last_error, :string

    belongs_to :board, Foglet.Boards.Board
    has_many :items, Foglet.BoardFeeds.Item, foreign_key: :board_feed_id

    timestamps()
  end

  def changeset(feed, attrs) do
    feed
    |> cast(attrs, [
      :url,
      :title,
      :enabled,
      :display_order,
      :cache_ttl_seconds,
      :last_fetched_at,
      :last_success_at,
      :last_error,
      :board_id
    ])
    |> validate_required([:url, :title, :enabled, :display_order, :cache_ttl_seconds, :board_id])
    |> validate_length(:url, min: 1, max: 2048)
    |> validate_length(:title, min: 1, max: 200)
    |> validate_number(:cache_ttl_seconds,
      greater_than_or_equal_to: 300,
      less_than_or_equal_to: 86_400
    )
    |> foreign_key_constraint(:board_id)
    |> unique_constraint([:board_id, :url])
    |> check_constraint(:cache_ttl_seconds, name: :board_feeds_cache_ttl_seconds_range)
  end
end
