defmodule Foglet.Doors.Dropfiles.DoorSys do
  @moduledoc false

  alias Foglet.Doors.Dropfiles.Metadata

  @spec lines(Metadata.t()) :: [String.t()]
  def lines(%Metadata{} = metadata) do
    [
      "COM0:",
      "38400",
      "8",
      metadata.node_number,
      "38400",
      "Y",
      "Y",
      "Y",
      "N",
      metadata.display_name,
      metadata.location,
      "",
      "",
      "",
      "01/01/80",
      metadata.security_level,
      "0",
      "01/01/80",
      "0",
      metadata.time_remaining_minutes,
      "GR",
      to_string(metadata.terminal_rows),
      "N",
      "",
      "12/31/99",
      metadata.user_record_number,
      "",
      "0",
      "0",
      "0",
      "9999",
      "9999",
      "01/01/80",
      "",
      "",
      metadata.sysop_name,
      metadata.handle,
      "00:00",
      "N",
      metadata.session_id
    ]
  end
end
