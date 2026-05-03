defmodule Foglet.TUI.Effect do
  @moduledoc """
  Explicit runtime effect values produced by Phase 34 screen reducers.

  Screens return these values from `Foglet.TUI.Screen.update/3`; the App
  runtime interprets them as navigation, task, modal, publication, session,
  terminal, or quit requests.
  """

  @type navigate :: %__MODULE__{
          type: :navigate,
          payload: %{screen: atom(), params: map()}
        }

  @type task :: %__MODULE__{
          type: :task,
          payload: %{op: atom(), screen_key: term(), fun: (-> term())}
        }

  @type modal_open :: %__MODULE__{
          type: :modal,
          payload: {:open, term()}
        }

  @type modal_dismiss :: %__MODULE__{
          type: :modal,
          payload: :dismiss
        }

  @type modal :: modal_open() | modal_dismiss()

  @type modal_submit :: %__MODULE__{
          type: :modal_submit,
          payload: %{screen_key: term(), kind: atom(), payload: term()}
        }

  @type publish :: %__MODULE__{
          type: :publish,
          payload: %{topic: term(), message: term()}
        }

  @type session :: %__MODULE__{
          type: :session,
          payload: term()
        }

  @type terminal :: %__MODULE__{
          type: :terminal,
          payload: {:size, {pos_integer(), pos_integer()}}
        }

  @type door :: %__MODULE__{
          type: :door,
          payload: %{
            action: :launch,
            manifest: Foglet.Doors.Manifest.t(),
            output: function() | nil
          }
        }

  @type quit :: %__MODULE__{
          type: :quit,
          payload: nil
        }

  @type t ::
          navigate()
          | task()
          | modal()
          | modal_submit()
          | publish()
          | session()
          | terminal()
          | door()
          | quit()

  defstruct [:type, :payload]

  @doc "Requests navigation to `screen` with route params."
  @spec navigate(atom(), map()) :: navigate()
  def navigate(screen, params \\ %{}) do
    %__MODULE__{type: :navigate, payload: %{screen: screen, params: params}}
  end

  @doc """
  Requests a zero-arity task for `screen_key`.

  The function is stored, not executed, so App can dispatch it through
  `Foglet.TUI.Command.task/2`.
  """
  @spec task(atom(), term(), (-> term())) :: task()
  def task(op, screen_key, fun) when is_atom(op) and is_function(fun, 0) do
    %__MODULE__{type: :task, payload: %{op: op, screen_key: screen_key, fun: fun}}
  end

  @doc "Requests opening a modal."
  @spec open_modal(term()) :: modal_open()
  def open_modal(modal) do
    %__MODULE__{type: :modal, payload: {:open, modal}}
  end

  @doc "Requests dismissing the active modal."
  @spec dismiss_modal() :: modal_dismiss()
  def dismiss_modal do
    %__MODULE__{type: :modal, payload: :dismiss}
  end

  @doc "Requests routing a modal submit payload to a target screen reducer."
  @spec modal_submit(term(), atom(), term()) :: modal_submit()
  def modal_submit(screen_key, kind, payload) when is_atom(kind) do
    %__MODULE__{
      type: :modal_submit,
      payload: %{screen_key: screen_key, kind: kind, payload: payload}
    }
  end

  @doc "Requests publishing a message to a topic."
  @spec publish(term(), term()) :: publish()
  def publish(topic, message) do
    %__MODULE__{type: :publish, payload: %{topic: topic, message: message}}
  end

  @doc "Requests sending a message to the session process."
  @spec session(term()) :: session()
  def session(message) do
    %__MODULE__{type: :session, payload: message}
  end

  @doc "Requests a terminal size update."
  @spec terminal_size({pos_integer(), pos_integer()}) :: terminal()
  def terminal_size(size) do
    %__MODULE__{type: :terminal, payload: {:size, size}}
  end

  @doc "Requests a supervised door launch through the app runtime boundary."
  @spec launch_door(Foglet.Doors.Manifest.t(), keyword()) :: door()
  def launch_door(manifest, opts \\ []) do
    %__MODULE__{
      type: :door,
      payload: %{action: :launch, manifest: manifest, output: Keyword.get(opts, :output)}
    }
  end

  @doc "Requests runtime termination."
  @spec quit() :: quit()
  def quit do
    %__MODULE__{type: :quit, payload: nil}
  end

  @doc """
  Unwraps the double-`:ok` shape Raxol task results arrive in.

  Raxol wraps task return values in an outer `{:ok, …}` (the task
  succeeded) regardless of the inner contract. Domain functions
  typically return their own `{:ok, value}` / `{:error, reason}` tuple,
  yielding `{:ok, {:ok, v}}` or `{:ok, {:error, r}}` at the screen
  reducer. This helper collapses those to a single-level tuple.

  Previously duplicated in BoardList, Moderation, and inline pattern
  matches in PostReader / PostComposer (IN-04).
  """
  @spec unwrap_task_result(term()) :: {:ok, term()} | {:error, term()}
  def unwrap_task_result({:ok, {:ok, value}}), do: {:ok, value}
  def unwrap_task_result({:ok, {:error, reason}}), do: {:error, reason}
  def unwrap_task_result({:ok, value}), do: {:ok, value}
  def unwrap_task_result({:error, reason}), do: {:error, reason}
  def unwrap_task_result(other), do: {:error, other}
end
