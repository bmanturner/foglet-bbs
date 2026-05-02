defmodule Foglet.Boards.Board do
  @moduledoc "Schema for BBS boards — discussion areas within a category."
  use Foglet.Schema

  @type t :: %__MODULE__{}

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
    field :required_subscription, :boolean, default: false

    field :chat_enabled, :boolean, default: false

    field :chat_storage_mode, Ecto.Enum,
      values: [:ephemeral, :permanent],
      default: :ephemeral

    field :chat_message_ttl_seconds, :integer, default: 7200

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
      :chat_enabled,
      :chat_storage_mode,
      :chat_message_ttl_seconds,
      :category_id
    ])
    |> validate_required([
      :slug,
      :name,
      :category_id,
      :chat_enabled,
      :chat_storage_mode,
      :chat_message_ttl_seconds
    ])
    |> validate_required_subscription_policy()
    |> validate_length(:slug, min: 1, max: 50)
    |> validate_format(:slug, ~r/^[a-z0-9_-]+$/,
      message: "must be lowercase alphanumeric with _ or -"
    )
    |> validate_length(:name, min: 1, max: 100)
    |> validate_inclusion(:chat_storage_mode, [:ephemeral, :permanent])
    |> validate_chat_ttl_bounds()
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:category_id)
    |> check_constraint(:required_subscription,
      name: :boards_required_subscription_requires_default_subscription,
      message: "requires default_subscription to be true"
    )
    |> check_constraint(:chat_storage_mode,
      name: :boards_chat_storage_mode_allowed,
      message: "must be ephemeral or permanent"
    )
    |> check_constraint(:chat_message_ttl_seconds,
      name: :boards_chat_message_ttl_seconds_range,
      message: "must be between 60 and 86400 seconds when chat is ephemeral"
    )
  end

  defp validate_chat_ttl_bounds(changeset) do
    chat_enabled = get_field(changeset, :chat_enabled)
    storage_mode = get_field(changeset, :chat_storage_mode)
    ttl = get_field(changeset, :chat_message_ttl_seconds)

    if chat_enabled == true and storage_mode == :ephemeral do
      cond do
        not is_integer(ttl) ->
          add_error(changeset, :chat_message_ttl_seconds, "is invalid")

        ttl < 60 or ttl > 86_400 ->
          add_error(
            changeset,
            :chat_message_ttl_seconds,
            "must be between 60 and 86400 seconds"
          )

        true ->
          changeset
      end
    else
      changeset
    end
  end

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
