defmodule Foglet.Accounts.PublicProfile do
  @moduledoc """
  Public profile-card summary boundary.

  This struct is the only payload the reusable public profile modal consumes.
  It intentionally whitelists public fields and excludes private/operator data
  such as real names, email addresses, auth/SSH fields, invite/reset tokens, and
  verification metadata.
  """

  import Ecto.Query

  alias Foglet.Accounts
  alias Foglet.Posts.Post
  alias Foglet.Posts.Upvote
  alias Foglet.Sessions.PresenceSummary
  alias FogletBbs.Repo

  @type t :: %__MODULE__{
          user_id: String.t() | nil,
          handle: String.t() | nil,
          role: atom() | nil,
          tagline: String.t() | nil,
          location: String.t() | nil,
          post_count: non_neg_integer(),
          karma: non_neg_integer(),
          joined_at: DateTime.t() | NaiveDateTime.t() | nil,
          last_seen_at: DateTime.t() | NaiveDateTime.t() | nil,
          presence: PresenceSummary.t()
        }

  defstruct [
    :user_id,
    :handle,
    :role,
    :tagline,
    :location,
    :joined_at,
    :last_seen_at,
    post_count: 0,
    karma: 0,
    presence: %PresenceSummary{}
  ]

  @spec load(String.t(), keyword()) :: {:ok, t()} | {:error, :not_found}
  def load(user_id, opts \\ []) when is_binary(user_id) do
    accounts = Keyword.get(opts, :accounts, Accounts)

    case accounts.get_user(user_id) do
      nil -> {:error, :not_found}
      user -> {:ok, from_user(user, Keyword.put(opts, :karma, karma_for_user(user_id, opts)))}
    end
  end

  @spec from_user(map(), keyword()) :: t()
  def from_user(user, opts \\ []) when is_map(user) do
    user_id = public_field(user, :id)

    %__MODULE__{
      user_id: user_id,
      handle: public_field(user, :handle),
      role: public_field(user, :role),
      tagline: blank_to_nil(public_field(user, :tagline)),
      location: blank_to_nil(public_field(user, :location)),
      post_count: public_field(user, :post_count) || 0,
      karma: Keyword.get(opts, :karma, public_field(user, :karma) || 0),
      joined_at: public_field(user, :inserted_at),
      last_seen_at: public_field(user, :last_seen_at),
      presence: PresenceSummary.for_user(user_id, opts)
    }
  end

  defp public_field(user, field) when is_atom(field) do
    Map.get(user, field) || Map.get(user, Atom.to_string(field))
  end

  defp karma_for_user(user_id, opts) do
    repo = Keyword.get(opts, :repo, Repo)

    query =
      Upvote
      |> join(:inner, [upvote], post in Post, on: post.id == upvote.post_id)
      |> where([_upvote, post], post.user_id == ^user_id)

    repo.aggregate(query, :count, :id)
  end

  defp blank_to_nil(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp blank_to_nil(value), do: value
end
