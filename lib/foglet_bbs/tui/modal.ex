defmodule Foglet.TUI.Modal do
  @moduledoc "Typed modal state for Foglet.TUI.App."

  @type modal_type :: :info | :error | :warning | :confirm | :form

  @type callback ::
          (Foglet.TUI.App.t() -> {Foglet.TUI.App.t(), list()} | tuple())
          | :dismiss_modal
          | nil

  @type t :: %__MODULE__{
          type: modal_type(),
          title: String.t() | nil,
          message: String.t() | struct() | nil,
          on_confirm: callback(),
          on_cancel: callback()
        }

  # NO @enforce_keys — some flows (e.g. terminate_after_modal) merge callbacks
  # onto existing modals via Map.merge/2.
  defstruct [:type, :title, :message, :on_confirm, :on_cancel]
end
