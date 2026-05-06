defmodule Foglet.Doors.Dropfiles.DorinfoDef do
  @moduledoc false

  alias Foglet.Doors.Dropfiles.Metadata

  @spec lines(Metadata.t()) :: [String.t()]
  def lines(%Metadata{} = metadata) do
    [
      Foglet.AppName.name(),
      metadata.sysop_first_name,
      metadata.sysop_last_name,
      "COM0",
      "38400 BAUD,N,8,1",
      "0",
      metadata.handle,
      metadata.display_name,
      metadata.location,
      metadata.security_level
    ]
  end
end
