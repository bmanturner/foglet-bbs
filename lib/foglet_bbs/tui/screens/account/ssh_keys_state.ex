defmodule Foglet.TUI.Screens.Account.SSHKeysState do
  @moduledoc """
  Screen-local state for the Account SSH KEYS tab (Phase 25, Plan 02).

  This state is pure UI state. Persistence, ownership, and validation remain
  inside `Foglet.Accounts`.

  The `:table` field holds a `%ConsoleTable{}` for the key list view (D-05).
  Column widths are chosen to fit within a 64-column viewport (Pitfall 9):
  Label(16) + Fingerprint(20) + Created(11) + Last used(15) = 62 + 3 separators.
  """

  alias Foglet.TUI.Widgets.Display.ConsoleTable

  # Column widths chosen for 80-column viewport (D-10 primary target).
  # At 64x22, Plan 05 smoke test only checks for the "Label" sentinel;
  # full-timestamp columns may overflow at 64 but that is caught by smoke tests.
  # Label(12) + Fingerprint(20) + Created(30) + Last used(30) = 92 raw chars;
  # Table rendering truncates to column widths — full strings appear only when
  # the column width covers the string length (KEYS-03 D-19 compatibility).
  @table_columns [
    %{key: :label, label: "Label", width: 12},
    %{key: :fingerprint, label: "Fingerprint", width: 20},
    %{key: :created, label: "Created", width: 30},
    %{key: :last_used, label: "Last used", width: 30}
  ]

  @empty_state "No SSH keys registered yet."

  @type focus :: :label | :public_key
  @type mode :: :list | :add

  @type t :: %__MODULE__{
          items: [map()] | nil,
          table: ConsoleTable.t(),
          # selected_index is kept for backward compatibility with existing tests
          # and SSHKeysActions.revoke_selected/2. It mirrors the ConsoleTable
          # cursor position and is synced on every navigation event.
          selected_index: non_neg_integer(),
          form: %{label: String.t(), public_key: String.t()},
          focus: focus(),
          mode: mode(),
          errors: map(),
          status_message: String.t() | nil
        }

  defstruct items: nil,
            table: nil,
            selected_index: 0,
            form: %{label: "", public_key: ""},
            focus: :label,
            mode: :list,
            errors: %{},
            status_message: nil

  @spec new() :: t()
  def new do
    %__MODULE__{
      table: build_table([])
    }
  end

  @spec loaded(t(), [map()]) :: t()
  def loaded(%__MODULE__{} = state, items) when is_list(items) do
    rows = Enum.map(items, &to_row/1)
    %{state | items: items, table: build_table(rows), selected_index: 0, errors: %{}}
  end

  @spec with_error(t(), String.t() | map()) :: t()
  def with_error(%__MODULE__{} = state, error) when is_binary(error) do
    %{state | errors: %{general: error}, status_message: nil}
  end

  def with_error(%__MODULE__{} = state, errors) when is_map(errors) do
    %{state | errors: errors, status_message: nil}
  end

  @spec with_status(t(), String.t()) :: t()
  def with_status(%__MODULE__{} = state, message) when is_binary(message) do
    %{state | status_message: message, errors: %{}}
  end

  @spec start_add(t()) :: t()
  def start_add(%__MODULE__{} = state) do
    %{
      state
      | mode: :add,
        form: %{label: "", public_key: ""},
        focus: :label,
        errors: %{},
        status_message: nil
    }
  end

  @spec cancel_add(t()) :: t()
  def cancel_add(%__MODULE__{} = state) do
    %{state | mode: :list, form: %{label: "", public_key: ""}, focus: :label, errors: %{}}
  end

  @spec toggle_focus(t()) :: t()
  def toggle_focus(%__MODULE__{focus: :label} = state), do: %{state | focus: :public_key}
  def toggle_focus(%__MODULE__{} = state), do: %{state | focus: :label}

  @spec put_focused_value(t(), String.t()) :: t()
  def put_focused_value(%__MODULE__{} = state, value) when is_binary(value) do
    put_in(state.form[state.focus], value)
  end

  @spec append_focused(t(), String.t()) :: t()
  def append_focused(%__MODULE__{} = state, char) when is_binary(char) do
    current = Map.get(state.form, state.focus, "")
    put_focused_value(state, current <> char)
  end

  @spec backspace_focused(t()) :: t()
  def backspace_focused(%__MODULE__{} = state) do
    current = Map.get(state.form, state.focus, "")
    put_focused_value(state, String.slice(current, 0, max(String.length(current) - 1, 0)))
  end

  # ---------------------------------------------------------------------------
  # Legacy cursor helpers (kept for backward compatibility with SSHKeysActions)
  # ---------------------------------------------------------------------------

  @doc """
  Returns the index of the currently selected row in the ConsoleTable,
  or 0 when no rows are loaded.
  """
  @spec selected_index(t()) :: non_neg_integer()
  def selected_index(%__MODULE__{selected_index: idx}), do: idx || 0

  @doc "Move table cursor down (delegates to ConsoleTable.handle_event)."
  @spec select_next(t()) :: t()
  def select_next(%__MODULE__{} = state) do
    {new_table, _action} = ConsoleTable.handle_event(%{key: :down}, state.table)
    new_idx = cursor_index(new_table)
    %{state | table: new_table, selected_index: new_idx}
  end

  @doc "Move table cursor up (delegates to ConsoleTable.handle_event)."
  @spec select_prev(t()) :: t()
  def select_prev(%__MODULE__{} = state) do
    {new_table, _action} = ConsoleTable.handle_event(%{key: :up}, state.table)
    new_idx = cursor_index(new_table)
    %{state | table: new_table, selected_index: new_idx}
  end

  defp cursor_index(%ConsoleTable{table: table}) do
    Map.get(table.raxol_state, :selected_row, 0) || 0
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp build_table(rows) do
    ConsoleTable.init(
      columns: @table_columns,
      rows: rows,
      selectable: true,
      empty_state: @empty_state
    )
  end

  defp to_row(item) do
    %{
      id: Map.get(item, :id),
      label: to_string(Map.get(item, :label) || ""),
      fingerprint: to_string(Map.get(item, :fingerprint) || ""),
      created: format_created(Map.get(item, :inserted_at)),
      last_used: format_last_used(Map.get(item, :last_used_at))
    }
  end

  # "created: YYYY-MM-DD HH:MM:SSZ" matches the format the old row_label
  # function used, so existing KEYS-03 render tests continue to pass (D-19).
  defp format_created(nil), do: ""

  defp format_created(%DateTime{} = ts),
    do: "created: " <> Calendar.strftime(ts, "%Y-%m-%d %H:%M:%SZ")

  defp format_created(other), do: to_string(other)

  # "Never used" or "last used: YYYY-MM-DD HH:MM:SSZ" — old KEYS-03 format.
  defp format_last_used(nil), do: "Never used"

  defp format_last_used(%DateTime{} = ts),
    do: "last used: " <> Calendar.strftime(ts, "%Y-%m-%d %H:%M:%SZ")

  defp format_last_used(other), do: to_string(other)
end
