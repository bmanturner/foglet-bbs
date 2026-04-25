defmodule Foglet.TUI.Widgets.Modal.Form.SubmitStash do
  @moduledoc """
  Per-process submit-payload stash for `Modal.Form.on_submit` callbacks.

  `Modal.Form` deliberately discards the `on_submit` callback return value
  (form.ex — `_ = state.on_submit.(payload)`), so screens that need to
  capture the submitted payload park it in the process dictionary and read
  it back from `handle_event/2`'s caller after the event returns.

  This helper centralizes the pattern (Phase 25, Codex review Concern 4) so
  every consumer uses the same key shape and cleanup discipline. Always
  prefer `with_stashed/2` over manual `stash`/`pop` to guarantee cleanup
  even on exceptions.

  ## Usage

      # In the on_submit callback:
      on_submit: fn payload ->
        SubmitStash.stash(__MODULE__, payload)
      end

      # In the screen's handle_event caller after Form.handle_event/2:
      SubmitStash.with_stashed(__MODULE__, fn
        nil     -> :no_submit
        payload -> handle_save(payload)
      end)
  """

  @type module_key :: module()
  @type payload :: term()

  @doc "Stash a payload keyed by the calling module."
  @spec stash(module_key(), payload()) :: :ok
  def stash(mod, payload) when is_atom(mod) do
    Process.put({__MODULE__, mod}, payload)
    :ok
  end

  @doc "Pop a stashed payload (and delete it). Returns nil when absent."
  @spec pop(module_key()) :: payload() | nil
  def pop(mod) when is_atom(mod) do
    Process.delete({__MODULE__, mod})
  end

  @doc """
  Run `fun` with the stashed payload (or `nil`) and guarantee deletion.

  The stashed entry is deleted in an `after` clause so cleanup is guaranteed
  even when `fun` raises.

      SubmitStash.with_stashed(__MODULE__, fn
        nil     -> :no_submit
        payload -> handle_save(payload)
      end)
  """
  @spec with_stashed(module_key(), (payload() | nil -> term())) :: term()
  def with_stashed(mod, fun) when is_atom(mod) and is_function(fun, 1) do
    try do
      fun.(Process.get({__MODULE__, mod}))
    after
      Process.delete({__MODULE__, mod})
    end
  end
end
