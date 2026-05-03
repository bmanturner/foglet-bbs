defmodule Foglet.Doors.AuditRecord do
  @moduledoc """
  Redacted launch/exit audit contract for door sessions.

  This is intentionally a plain struct for the first slice. If Foglet later
  persists door audit records, this shape should be the schema contract: user and
  door identifiers, session terminal metadata, redacted environment exposure, and
  bounded exit status details only.
  """

  defstruct [
    :door_id,
    :user_id,
    :handle,
    :started_at,
    :ended_at,
    :terminal_size,
    :runtime,
    env: %{},
    status: %{}
  ]

  @type t :: %__MODULE__{
          door_id: String.t(),
          user_id: String.t() | nil,
          handle: String.t() | nil,
          started_at: DateTime.t(),
          ended_at: DateTime.t() | nil,
          terminal_size: {pos_integer(), pos_integer()} | nil,
          runtime: atom(),
          env: %{String.t() => String.t()},
          status: map()
        }
end
