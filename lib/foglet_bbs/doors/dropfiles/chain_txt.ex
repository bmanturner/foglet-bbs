defmodule Foglet.Doors.Dropfiles.ChainTxt do
  @moduledoc false

  alias Foglet.Doors.Dropfiles.Metadata

  @spec lines(Metadata.t()) :: [String.t()]
  def lines(%Metadata{} = metadata) do
    [
      metadata.handle,
      metadata.display_name,
      to_string(metadata.terminal_cols),
      to_string(metadata.terminal_rows),
      metadata.role,
      metadata.user_id
    ]
  end
end
