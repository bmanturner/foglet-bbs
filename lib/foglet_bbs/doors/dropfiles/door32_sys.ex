defmodule Foglet.Doors.Dropfiles.Door32Sys do
  @moduledoc false

  alias Foglet.Doors.Dropfiles.Metadata

  @spec lines(Metadata.t()) :: [String.t()]
  def lines(%Metadata{} = metadata) do
    [
      "0",
      "0",
      "38400",
      Foglet.AppName.name(),
      metadata.user_id,
      metadata.display_name,
      metadata.handle,
      metadata.security_level,
      metadata.time_remaining_minutes,
      metadata.node_number,
      metadata.session_id
    ]
  end
end
