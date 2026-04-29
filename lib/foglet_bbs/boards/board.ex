defmodule Foglet.Boards.Board do
  @moduledoc "Schema for BBS boards — discussion areas within a category."
  use Foglet.Schema

  @type t :: %__MODULE__{}

  schema "boards" do
    field :slug, :string
    field :slug_canonical, :string
    field :name, :string
    field :description, :string
    field :display_order, :integer, default: 0
    field :next_message_number, :integer, default: 1
    field :readable_by, Ecto.Enum, values: [:public, :members], default: :public
    field :postable_by, Ecto.Enum, values: [:members, :mods_only, :sysop_only], default: :members
    field :archived, :boolean, default: false
    field :default_subscription, :boolean, default: false
    field :required_subscription, :boolean, default: false

    belongs_to :category, Foglet.Boards.Category

    has_many :threads, Foglet.Threads.Thread
    has_many :posts, Foglet.Posts.Post
    has_many :subscriptions, Foglet.Boards.Subscription

    field :unread_count, :integer, virtual: true, default: 0

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
      :required_subscription,
      :category_id
    ])
    |> validate_required([:slug, :name, :category_id])
    |> put_slug_canonical()
    |> validate_required_subscription_policy()
    |> validate_length(:slug, min: 1, max: 50)
    |> validate_format(:slug, ~r/^[a-z0-9_-]+$/,
      message: "must be lowercase alphanumeric with _ or -"
    )
    |> validate_length(:name, min: 1, max: 100)
    |> unique_constraint(:slug)
    |> unique_constraint(:slug_canonical)
    |> foreign_key_constraint(:category_id)
    |> check_constraint(:required_subscription,
      name: :boards_required_subscription_requires_default_subscription,
      message: "requires default_subscription to be true"
    )
  end

  defp put_slug_canonical(changeset) do
    update_change(changeset, :slug, &String.trim/1)
    |> put_change(:slug_canonical, canonical_slug(get_field(changeset, :slug)))
  end

  defp canonical_slug(value) when is_binary(value) do
    value |> String.trim() |> String.downcase()
  end

  defp canonical_slug(_value), do: nil

  defp validate_required_subscription_policy(changeset) do
    default_subscription = get_field(changeset, :default_subscription)
    required_subscription = get_field(changeset, :required_subscription)

    if required_subscription == true and default_subscription != true do
      add_error(changeset, :required_subscription, "requires default_subscription to be true")
    else
      changeset
    end
  end

  @doc """
  Changeset that flips `archived` to true. Used by `Foglet.Boards.archive_board/2`.
  Defensively scoped: only `:archived` is cast, nothing else can be mutated through this path.
  """
  def archive_changeset(board) do
    board
    |> cast(%{archived: true}, [:archived])
    |> validate_required([:archived])
  end
end
