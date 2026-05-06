defmodule Foglet.Doors.Dropfiles.DoorSys do
  @moduledoc false

  alias Foglet.Doors.Dropfiles.Metadata

  @spec lines(Metadata.t()) :: [String.t()]
  def lines(%Metadata{} = metadata) do
    [
      "COM0:",
      "0",
      "38400",
      "Foglet BBS",
      metadata.handle,
      metadata.display_name,
      metadata.location,
      "",
      to_string(metadata.terminal_cols),
      to_string(metadata.terminal_rows),
      "GR",
      "1",
      "1",
      "12/31/99",
      "1440",
      "1440",
      "GR",
      "9999",
      "01/01/80",
      metadata.user_id,
      "0",
      "N",
      "",
      "",
      "N",
      "N",
      "N",
      "0",
      "0",
      "0",
      "9999",
      "01/01/80",
      metadata.role,
      "",
      "0",
      "0",
      "0",
      to_string(metadata.terminal_cols),
      to_string(metadata.terminal_rows),
      metadata.session_id
    ]
  end
end
