defmodule Foglet.TUI.Modal do
  @moduledoc """
  Typed modal state for `Foglet.TUI.App`.

  ## Callback contract (`:on_confirm` / `:on_cancel`)

  A modal callback may take one of three shapes. `App.do_update/2` dispatches
  through this contract for `{:confirm_modal, answer}` and for key-driven
  dismissal of `:info`, `:success`, `:error`, and `:warning` modals that opt into callbacks:

  - `Enter` / `Space` use `:on_confirm`.
  - `Escape` uses `:on_cancel`.
  - Modal key dismissal without callbacks remains a plain dismiss.

  1. `nil` — no callback. The modal is dismissed (state.modal → nil) and
     no further action is taken.
  2. `:dismiss_modal` — same effect as `nil`. Useful as an explicit "do
     nothing on this side" marker (e.g. a confirm-only modal sets
     `on_cancel: :dismiss_modal`).
  3. `(state -> {state, [Command.t()]} | message)` — a 1-arity function
     receiving the App state with the modal already cleared.
     - When the function returns `{%App{}, [commands]}`, App passes the
       commands through `wrap_commands/1` (turning `{:terminate, _}` into
       `Command.quit/0`) and emits them.
     - When the function returns any other value, App treats that value
       as a message and routes it through `do_update/2`. This lets
       callbacks return tuples like `{:navigate, :main_menu}` for terse
       follow-up reducer dispatch.

  Returning a value the callback contract does not anticipate (e.g. an
  Effect struct, an unwrapped %Command{}, or a raw atom) will hit the
  message branch and reach `do_update/2`'s catch-all clause as a no-op.
  Be deliberate about which shape a given callback returns.
  """

  @type modal_type ::
          :info
          | :success
          | :error
          | :warning
          | :confirm
          | :form
          | :reply_context
          | :public_profile

  @typedoc """
  See the moduledoc for the full callback contract.
  """
  @type callback ::
          (Foglet.TUI.App.t() -> {Foglet.TUI.App.t(), list()} | tuple())
          | :dismiss_modal
          | nil

  @type t :: %__MODULE__{
          type: modal_type(),
          title: String.t() | nil,
          message: String.t() | struct() | nil,
          on_confirm: callback(),
          on_cancel: callback(),
          change_target: {atom(), atom()} | nil
        }

  # NO @enforce_keys — some flows (e.g. terminate_after_modal) merge callbacks
  # onto existing modals via Map.merge/2.
  defstruct [:type, :title, :message, :on_confirm, :on_cancel, :change_target]
end
