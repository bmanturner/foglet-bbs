defmodule Foglet.Schema do
  @moduledoc """
  Shared Ecto schema defaults for Foglet.

  Use at the top of every Ecto schema in the Foglet namespace:

      defmodule Foglet.Accounts.User do
        use Foglet.Schema

        schema "users" do
          field :handle, :string
          timestamps()
        end
      end

  Sets UUID v7 primary keys, UUID foreign keys, and utc_datetime_usec
  timestamps per docs/DATA_MODEL.md §Conventions.
  """

  defmacro __using__(_) do
    quote do
      use Ecto.Schema
      import Ecto.Changeset
      @primary_key {:id, Ecto.UUID, autogenerate: true}
      @foreign_key_type Ecto.UUID
      @timestamps_opts [type: :utc_datetime_usec]
    end
  end
end
