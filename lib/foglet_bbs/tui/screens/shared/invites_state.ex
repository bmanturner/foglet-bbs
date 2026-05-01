defmodule Foglet.TUI.Screens.Shared.InvitesState do
  @moduledoc """
  Live INVITES state shared by Account, Moderation, and Sysop shells.

  `items: nil` means loading or not-yet-loaded. A list contains status maps
  returned by `Foglet.Accounts.Invites.list_invites/1`; the TUI does not query or shape
  invite persistence directly.

  Selection is owned by `%ConsoleTable{}` in the `:table` field (D-05, Phase 25
  Plan 03). The bespoke index field has been replaced by the widget cursor inside
  `table.table.raxol_state.selected_row` (D-05 — selection owned by widget).
  """

  alias Foglet.TUI.Widgets.Display.ConsoleTable

  @invite_columns [
    %{key: :code, label: "Code", width: 8, grow: 3, priority: 100, demand: :content},
    %{key: :status, label: "Status", width: 8, priority: 60, demand: :content},
    %{key: :issued, label: "Issued", width: 10, priority: 40, demand: :content},
    %{key: :used_by, label: "Used by", width: 7, grow: 1, priority: 10, demand: :content}
  ]
  @default_width 60

  @type invite_status :: map()
  @type mode :: :list | :confirm_revoke

  @type t :: %__MODULE__{
          items: nil | [invite_status()],
          table: ConsoleTable.t(),
          selected_index: non_neg_integer(),
          loading?: boolean(),
          last_generated_code: String.t() | nil,
          error: String.t() | nil,
          mode: mode(),
          confirm_target: map() | nil,
          frame: non_neg_integer()
        }

  defstruct items: nil,
            table: nil,
            selected_index: 0,
            loading?: false,
            last_generated_code: nil,
            error: nil,
            mode: :list,
            confirm_target: nil,
            frame: 0

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    items = Keyword.get(opts, :items, nil)
    validate_items!(items)
    idx = Keyword.get(opts, :selected_index, 0)

    %__MODULE__{
      items: items,
      table: build_table(items || [], idx),
      selected_index: idx,
      loading?: Keyword.get(opts, :loading?, false),
      last_generated_code: Keyword.get(opts, :last_generated_code),
      error: Keyword.get(opts, :error),
      frame: Keyword.get(opts, :frame, 0)
    }
  end

  @spec loaded(t(), [invite_status()]) :: t()
  def loaded(%__MODULE__{} = state, items) when is_list(items) do
    # After loading new items, reset selection to first item (index 0)
    %__MODULE__{
      state
      | items: items,
        table: build_table(items, 0),
        selected_index: 0,
        loading?: false,
        error: nil
    }
  end

  @spec loading(t()) :: t()
  def loading(%__MODULE__{} = state) do
    %__MODULE__{state | loading?: true, error: nil}
  end

  @spec with_error(t(), String.t()) :: t()
  def with_error(%__MODULE__{} = state, error) when is_binary(error) do
    %__MODULE__{state | loading?: false, error: error}
  end

  @spec with_last_generated(t(), String.t()) :: t()
  def with_last_generated(%__MODULE__{} = state, code) when is_binary(code) do
    %__MODULE__{state | last_generated_code: code}
  end

  @doc """
  Returns the currently selected invite item, or nil if no selection.
  Uses `selected_index` field as the authoritative selection.
  """
  @spec selected_item(t()) :: invite_status() | nil
  def selected_item(%__MODULE__{items: items, selected_index: idx}) when is_list(items) do
    Enum.at(items, idx)
  end

  def selected_item(_state), do: nil

  @doc """
  Builds the default ConsoleTable for the INVITES tab.
  """
  @spec build_table([invite_status()], keyword() | non_neg_integer()) :: ConsoleTable.t()
  def build_table(items, opts_or_selected_idx \\ [])

  def build_table(items, opts) when is_list(opts), do: build_table(items, 0, opts)

  @spec build_table([invite_status()], non_neg_integer()) :: ConsoleTable.t()
  def build_table(items, selected_idx) when is_integer(selected_idx),
    do: build_table(items, selected_idx, [])

  @spec build_table([invite_status()], non_neg_integer(), keyword()) :: ConsoleTable.t()
  def build_table(items, _selected_idx, opts) when is_list(items) and is_list(opts) do
    rows =
      Enum.map(items, fn item ->
        status_str = item |> Map.get(:status) |> to_string()

        issued_str =
          case Map.get(item, :inserted_at) do
            %DateTime{} = dt -> Calendar.strftime(dt, "%Y-%m-%d")
            nil -> ""
            other -> to_string(other)
          end

        used_by_str =
          case Map.get(item, :consumed_by_user_id) do
            nil -> ""
            id -> to_string(id)
          end

        %{
          code: to_string(Map.get(item, :code, "")),
          status: status_str,
          issued: issued_str,
          used_by: used_by_str
        }
      end)

    ConsoleTable.init(
      columns: @invite_columns,
      rows: rows,
      selectable: true,
      width: Keyword.get(opts, :width, @default_width),
      empty_state: "No invites yet. Generate one when someone should join."
    )
  end

  @doc """
  Enter the revoke confirmation sub-mode for the currently selected invite.
  """
  @spec start_confirm_revoke(t()) :: t()
  def start_confirm_revoke(%__MODULE__{} = state) do
    case selected_item(state) do
      %{code: code} = item when is_binary(code) ->
        target = %{
          code: code,
          status: to_string(Map.get(item, :status) || "")
        }

        %{state | mode: :confirm_revoke, confirm_target: target, error: nil}

      _ ->
        %{state | error: "Select an invite first."}
    end
  end

  @doc "Cancel a pending revoke confirmation, returning to the list unchanged."
  @spec cancel_confirm_revoke(t()) :: t()
  def cancel_confirm_revoke(%__MODULE__{} = state) do
    %{state | mode: :list, confirm_target: nil, error: nil}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp validate_items!(nil), do: :ok
  defp validate_items!(items) when is_list(items), do: :ok

  defp validate_items!(other) do
    raise ArgumentError,
          "Foglet.TUI.Screens.Shared.InvitesState :items must be a list or nil; got #{inspect(other)}"
  end
end
