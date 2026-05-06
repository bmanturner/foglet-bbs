defmodule Foglet.Doors.Dropfiles.Door32Sys do
  @moduledoc false

  alias Foglet.Doors.Dropfiles.Metadata

  @spec lines(Metadata.t()) :: [String.t()]
  def lines(%Metadata{} = metadata) do
    [
      "0",
      "0",
      "38400",
      "Foglet BBS",
      metadata.user_id,
      metadata.display_name,
      metadata.handle,
      metadata.security_level,
      "1440",
      "1",
      metadata.session_id
    ]
  end
end
