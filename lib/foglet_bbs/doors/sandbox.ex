defmodule Foglet.Doors.Sandbox do
  @moduledoc "Validated external-door sandbox contract."

  @type mode :: :none | :restricted_user_process_group
  @type process_tree :: :process_group

  @type t :: %__MODULE__{
          mode: mode(),
          user: String.t() | nil,
          group: String.t() | nil,
          process_tree: process_tree(),
          fail_closed?: boolean()
        }

  defstruct mode: :none,
            user: nil,
            group: nil,
            process_tree: :process_group,
            fail_closed?: true
end
