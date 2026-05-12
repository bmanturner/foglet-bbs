defmodule Foglet.TUI.Screens.Sysop.BoardsView do
  @moduledoc """
  BOARDS tab submodule (D-14, D-16, D-17, D-18, SYSO-03).

  Renders a categorized list of boards (category heading rows with indented
  board rows) and routes create/edit through `Foglet.TUI.Widgets.Modal.Form`
  (Phase 1.1), archive through `%Foglet.TUI.Modal{type: :confirm}`. Category
  CRUD is reachable via uppercase counterparts (`N`, `E`, `Shift+D`).

  Triplet contract: `init/1 + handle_key/2 + render/2` (no process). Domain
  calls funnel `state.current_user` + `:site` scope through the actor-aware
  `Foglet.Boards.*` functions added in Plan 02-02; `:forbidden` / `:db_error`
  emit `{:error_modal, msg, :main_menu}` upstream.

  ## Modal.Form on_submit adaptation (D-17 / plan narrative)

  Board/category submit callbacks return explicit
  `Foglet.TUI.Effect.modal_submit/3` values. `handle_form_event/2` consumes
  those submit effects directly and preserves the existing create/edit command
  and validation behavior without process-local payload handoff.

  Archive-confirm flow uses the simpler pattern: BoardsView stores the target
  struct directly on state (`:archive_target`) and the Y/N handler reads it.

  Pitfall 5: event routing. When `state.modal != nil`, `j`/`k` / other list
  navigation keys are no-ops; events flow to the active modal first.
  """

  alias Foglet.Boards
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Modal
  alias Foglet.TUI.ScrollKeys
  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Widgets.List.ListRow
  alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm
  alias Raxol.UI.Components.Display.Viewport

  import Raxol.Core.Renderer.View

  @type row :: {:category, map()} | {:board, map()}

  @type t :: %__MODULE__{
          current_user: Foglet.Accounts.User.t() | nil,
          categories: [map()],
          boards: [map()],
          rows: [row()],
          selection_index: non_neg_integer(),
          collapsed_category_ids: MapSet.t(),
          scroll_top: non_neg_integer(),
          modal: nil | ModalForm.t() | Modal.t(),
          modal_kind:
            nil
            | :create_board
            | :edit_board
            | :create_category
            | :edit_category
            | :archive_board
            | :archive_category,
          edit_target: nil | map(),
          archive_target: nil | map()
        }

  defstruct current_user: nil,
            categories: [],
            boards: [],
            rows: [],
            selection_index: 0,
            collapsed_category_ids: MapSet.new(),
            scroll_top: 0,
            modal: nil,
            modal_kind: nil,
            edit_target: nil,
            archive_target: nil

  @postable_choices [
    {"Members", "members"},
    {"Moderators only", "mods_only"},
    {"Sysops only", "sysop_only"}
  ]

  # FOG-349: storage-mode and TTL choices use the {label, value} tuple form
  # supported by Modal.Form. Persisted values stay "ephemeral"/"permanent" and
  # integer seconds — no schema change.
  @chat_storage_choices [
    {"In-memory (auto-expires)", "ephemeral"},
    {"Saved to database", "permanent"}
  ]

  @chat_ttl_preset_choices [
    {"15 minutes", 900},
    {"1 hour", 3600},
    {"6 hours", 21_600},
    {"24 hours (max)", 86_400}
  ]

  @chat_ttl_preset_seconds Enum.map(@chat_ttl_preset_choices, fn {_label, n} -> n end)
  @chat_ttl_default_seconds 3600

  # ---------------------------------------------------------------------------
  # Init + list load
  # ---------------------------------------------------------------------------

  @spec init(keyword()) :: t()
  def init(opts) when is_list(opts) do
    %__MODULE__{current_user: Keyword.get(opts, :current_user)}
    |> refresh_lists()
  end

  defp refresh_lists(%__MODULE__{} = state) do
    categories = Boards.list_categories()
    boards = Boards.list_boards()
    rows = build_rows(categories, boards, state.collapsed_category_ids)

    %{
      state
      | categories: categories,
        boards: boards,
        rows: rows,
        selection_index: clamp_index(state.selection_index, length(rows))
    }
  end

  defp build_rows(categories, boards, collapsed_category_ids) do
    Enum.flat_map(categories, fn c ->
      cat_boards = Enum.filter(boards, &(&1.category_id == c.id))
      category_row = {:category, c}

      if MapSet.member?(collapsed_category_ids, category_id(c)) do
        [category_row]
      else
        [category_row | Enum.map(cat_boards, fn b -> {:board, b} end)]
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @spec render(t(), map(), keyword()) :: any()
  def render(state, theme, opts \\ [])

  # FOG-670: when a modal is open, render only a calm bounded overlay so the
  # board list does not bleed through behind the form. Footer copy switches to
  # form-mode hints (save / cancel / Tab nav) so list-mode commands no longer
  # masquerade as the active controls.
  def render(%__MODULE__{modal: modal} = _state, theme, _opts) when not is_nil(modal) do
    column style: %{gap: 0} do
      [render_modal_overlay(modal, theme)]
    end
  end

  def render(%__MODULE__{} = state, theme, opts) do
    width = Keyword.get(opts, :width, 76)
    visible_height = Keyword.get(opts, :visible_height, 12)
    render_list(state, theme, width: width, visible_height: visible_height)
  end

  @doc """
  True when the BoardsView is currently displaying a modal/form. The Sysop
  screen uses this to swap the bottom command bar from tab-jump hints to
  form-mode hints (save / cancel / field navigation) so stale list-mode
  commands do not masquerade as the active controls.
  """
  @spec modal_active?(t()) :: boolean()
  def modal_active?(%__MODULE__{modal: nil}), do: false
  def modal_active?(%__MODULE__{}), do: true

  @doc """
  Returns `:form`, `:confirm`, or `nil`. Sysop render advertises Tab/Enter for
  form modals and Y/N for confirm modals based on this.
  """
  @spec modal_mode(t()) :: :form | :confirm | nil
  def modal_mode(%__MODULE__{modal: nil}), do: nil
  def modal_mode(%__MODULE__{modal: %ModalForm{}}), do: :form
  def modal_mode(%__MODULE__{modal: %Modal{type: :confirm}}), do: :confirm
  def modal_mode(%__MODULE__{}), do: :form

  @doc """
  Command-bar groups for the BOARDS list mode. Sysop.Render owns the global
  chrome, so list actions live in the bottom keybar instead of body footer copy.
  """
  @spec keybar_groups(t()) :: [map()]
  def keybar_groups(%__MODULE__{rows: []}) do
    [%{label: "Boards", commands: [%{key: "N", label: "New category", priority: 5}]}]
  end

  def keybar_groups(%__MODULE__{} = state) do
    list_group = %{
      label: "List",
      commands: [%{key: ScrollKeys.commandbar_key(), label: "Move", priority: 10}]
    }

    action_commands =
      case selected_row(state) do
        {:category, _} ->
          [
            %{key: "N", label: "New category", priority: 5},
            %{key: "E", label: "Edit category", priority: 15},
            %{key: "D", label: "Archive category", priority: 15},
            %{key: "n", label: "New board", priority: 20}
          ]

        {:board, _} ->
          [
            %{key: "n", label: "New board", priority: 5},
            %{key: "e", label: "Edit board", priority: 15},
            %{key: "D", label: "Archive board", priority: 15},
            %{key: "N", label: "New category", priority: 20}
          ]

        _ ->
          [
            %{key: "n", label: "New board", priority: 5},
            %{key: "N", label: "New category", priority: 5}
          ]
      end

    [list_group, %{label: "Boards", commands: action_commands}]
  end

  defp render_list(%__MODULE__{rows: []}, theme, _opts) do
    column style: %{gap: 0} do
      [text("No categories yet. Press N to create the first category.", fg: theme.warning.fg)]
    end
  end

  defp render_list(%__MODULE__{rows: rows, selection_index: idx} = state, theme, opts) do
    width = Keyword.get(opts, :width, 76)
    visible_height = Keyword.get(opts, :visible_height, 12)
    selected = selected_row(state)

    if width >= 116 do
      {list_width, inspector_width} = board_workspace_widths(width)

      list =
        render_board_list_body(state, rows, idx, theme,
          width: list_width,
          visible_height: visible_height
        )

      split_pane(
        direction: :horizontal,
        ratio: {3, 2},
        min_size: 28,
        divider_char: " ",
        children: [list, board_inspector(selected, state, theme, inspector_width)],
        height: max(visible_height, 1)
      )
    else
      render_board_list_body(state, rows, idx, theme,
        width: width,
        visible_height: visible_height
      )
    end
  end

  defp render_board_list_body(%__MODULE__{} = state, rows, idx, theme, opts) do
    width = Keyword.fetch!(opts, :width)
    visible_height = Keyword.fetch!(opts, :visible_height)

    children =
      rows
      |> Enum.with_index()
      |> Enum.map(fn {row, row_idx} -> render_row(row, row_idx == idx, theme, state, width) end)

    {:ok, viewport} =
      Viewport.init(%{
        id: "sysop-boards-viewport",
        children: children,
        scroll_top: clamped_scroll_top(state, visible_height),
        visible_height: max(visible_height, 1),
        show_scrollbar: length(children) > visible_height,
        style: %{gap: 0, width: width}
      })

    body = Viewport.render(viewport, %{})

    hint =
      if length(children) > visible_height do
        [
          text(
            TextWidth.truncate(
              "More boards above/below — use ↑/↓ to move; Enter collapses categories.",
              width
            ),
            fg: theme.dim.fg
          )
        ]
      else
        []
      end

    column style: %{gap: 0} do
      [body] ++ hint
    end
  end

  defp board_workspace_widths(width) do
    available = max(width - 1, 0)
    list_width = max(div(available * 3, 5), 54)
    inspector_width = max(available - list_width, 36)

    {list_width, inspector_width}
  end

  defp board_inspector(nil, _state, theme, _width) do
    column style: %{gap: 0} do
      [text("No board selected.", fg: theme.dim.fg)]
    end
  end

  defp board_inspector({:category, category}, state, theme, width) do
    board_count =
      state.boards
      |> Enum.count(&(&1.category_id == category_id(category)))
      |> Integer.to_string()

    rows = [
      {"Name", category.name},
      {"Boards", board_count},
      {"Order", Map.get(category, :display_order, 0)},
      {"State", archived_label(category)}
    ]

    inspector_panel(
      "Selected category settings",
      rows,
      "N new cat  E edit cat  D archive",
      theme,
      width
    )
  end

  defp board_inspector({:board, board}, state, theme, width) do
    category = Enum.find(state.categories, &(&1.id == board.category_id))

    rows = [
      {"Slug", board.slug},
      {"Name", board.name},
      {"Category", category && category.name},
      {"Posting", Map.get(board, :postable_by, :members)},
      {"Subscription", subscription_label(board)},
      {"Chat", chat_label(board)},
      {"State", archived_label(board)}
    ]

    inspector_panel(
      "Selected board settings",
      rows,
      "n new board  e edit board  D archive",
      theme,
      width
    )
  end

  defp inspector_panel(title, rows, actions, theme, width) do
    detail_lines =
      Enum.map(rows, fn {label, value} ->
        label = String.pad_trailing(to_string(label), 12)
        text(TextWidth.truncate("#{label} #{value || "—"}", width), fg: theme.unselected.fg)
      end)

    column style: %{gap: 0} do
      [
        text(title, fg: theme.accent.fg),
        text("Actions", fg: theme.primary.fg),
        text(TextWidth.truncate(actions, width), fg: theme.dim.fg)
      ] ++ detail_lines
    end
  end

  defp subscription_label(%{required_subscription: true}), do: "required"
  defp subscription_label(%{default_subscription: true}), do: "default"
  defp subscription_label(_board), do: "optional"

  defp chat_label(%{chat_enabled: true}), do: "enabled"
  defp chat_label(_board), do: "disabled"

  defp archived_label(%{archived_at: nil}), do: "active"
  defp archived_label(%{archived_at: _}), do: "archived"
  defp archived_label(_), do: "active"

  defp render_row({:category, cat}, selected?, theme, state, width) do
    marker = if MapSet.member?(state.collapsed_category_ids, category_id(cat)), do: "▸", else: "▾"
    label = TextWidth.truncate("#{marker} #{cat.name}", width)

    if selected? do
      text(label, fg: theme.selected.fg, bg: theme.selected.bg, style: [:bold])
    else
      text(label, fg: theme.accent.fg, style: [:bold])
    end
  end

  defp render_row({:board, board}, selected?, theme, _state, width) do
    label = TextWidth.truncate("    #{board.slug} — #{board.name}", width)
    ListRow.render(label, selected?, theme)
  end

  # FOG-670: render the active modal as a full-width form surface (no extra
  # bordered box) and use Modal.Form's `:max_visible` viewport so the form
  # body fits within the surrounding ScreenFrame chrome at 80x24 / 64x22
  # without overlapping the bottom border or interleaving with neighbour
  # fields. The screen-level command bar (set in Sysop.Render) advertises the
  # form-mode actions, so a separate bordered chrome here would just consume
  # rows we need for content.
  defp render_modal_overlay(%ModalForm{} = form, theme) do
    column style: %{gap: 0} do
      [ModalForm.render(form, theme: theme, max_visible: form_max_visible_fields())]
    end
  end

  defp render_modal_overlay(%Modal{} = modal, theme) do
    column justify: :center, align: :center do
      [
        box style: %{border: :double, padding: 1, border_fg: theme.border.fg} do
          Foglet.TUI.Widgets.Modal.render(modal, theme)
        end
      ]
    end
  end

  # FOG-670: window size tuned for an 80x24 viewport with the Sysop screen
  # frame (breadcrumb + tabs + command bar). Each rendered field is roughly
  # 2–3 rows (label + widget, plus optional description), so 4 fields fit in
  # the available content area without clipping at 80x24 or 64x22 while still
  # leaving room for scroll-indicator rows.
  defp form_max_visible_fields, do: 4

  # ---------------------------------------------------------------------------
  # Key handling
  # ---------------------------------------------------------------------------

  @spec handle_key(map(), t()) :: {t(), [{atom(), any()} | tuple()]}

  # ---- Modal-open branch (Pitfall 5 gating) -----------------------------------

  def handle_key(event, %__MODULE__{modal: %ModalForm{}} = state) do
    handle_form_event(event, state)
  end

  def handle_key(event, %__MODULE__{modal: %Modal{type: :confirm}} = state) do
    handle_confirm_event(event, state)
  end

  # ---- No modal: list navigation + open-modal keys ----------------------------

  def handle_key(%{key: :escape}, state), do: {state, []}

  def handle_key(%{key: key} = event, state) when key in [:up, :down],
    do: {move(state, ScrollKeys.vertical_delta(event)), []}

  def handle_key(%{key: :char, char: char} = event, state) when char in ["j", "k"],
    do: {move(state, ScrollKeys.vertical_delta(event)), []}

  def handle_key(%{key: :enter}, state), do: {toggle_selected_category(state), []}
  def handle_key(%{key: :char, char: " "}, state), do: {toggle_selected_category(state), []}

  # Create board (lowercase n)
  def handle_key(%{key: :char, char: "n"} = e, state) do
    if modifier?(e), do: {state, []}, else: {open_create_board(state), []}
  end

  # Create category (uppercase N — no ctrl/meta)
  def handle_key(%{key: :char, char: "N"} = e, state) do
    if modifier?(e), do: {state, []}, else: {open_create_category(state), []}
  end

  # Edit (lowercase e = board, uppercase E = category)
  def handle_key(%{key: :char, char: "e"} = e, state) do
    if modifier?(e), do: {state, []}, else: {open_edit_board(state), []}
  end

  def handle_key(%{key: :char, char: "E"} = e, state) do
    if modifier?(e), do: {state, []}, else: {open_edit_category(state), []}
  end

  # Archive board (D without shift-D-category distinction in event shape):
  # Raxol char events don't carry a :shift key for letter chars; uppercase
  # chars are the shift indicator. We treat plain "D" as archive-board and
  # rely on the event-shape key :shift (if ever present) OR the secondary key
  # char combination for archive-category; for now, we disambiguate by
  # checking whether a board or category is highlighted. The plan's explicit
  # "Shift+D" for category archive is realised as "D on a category row".
  def handle_key(%{key: :char, char: "D"} = e, state) do
    if modifier?(e) do
      {state, []}
    else
      case selected_row(state) do
        {:category, cat} -> {open_archive_category(state, cat), []}
        {:board, board} -> {open_archive_board(state, board), []}
        nil -> {state, []}
      end
    end
  end

  def handle_key(_event, state), do: {state, []}

  defp modifier?(event), do: Map.get(event, :ctrl) || Map.get(event, :meta)

  # ---- Navigation ------------------------------------------------------------

  defp move(%__MODULE__{rows: []} = state, _delta), do: state

  defp move(%__MODULE__{rows: rows, selection_index: idx} = state, delta) do
    n = length(rows)
    next_idx = Integer.mod(idx + delta, n)

    %{state | selection_index: next_idx}
    |> scroll_to_selection()
  end

  defp selected_row(%__MODULE__{rows: rows, selection_index: idx}) do
    Enum.at(rows, idx)
  end

  defp toggle_selected_category(%__MODULE__{} = state) do
    case selected_row(state) do
      {:category, cat} ->
        cat_id = category_id(cat)

        collapsed =
          if MapSet.member?(state.collapsed_category_ids, cat_id) do
            MapSet.delete(state.collapsed_category_ids, cat_id)
          else
            MapSet.put(state.collapsed_category_ids, cat_id)
          end

        rows = build_rows(state.categories, state.boards, collapsed)

        %{
          state
          | collapsed_category_ids: collapsed,
            rows: rows,
            selection_index: clamp_index(state.selection_index, length(rows))
        }
        |> scroll_to_selection()

      _ ->
        state
    end
  end

  defp scroll_to_selection(%__MODULE__{selection_index: idx, scroll_top: top} = state) do
    cond do
      idx < top -> %{state | scroll_top: idx}
      idx >= top + 8 -> %{state | scroll_top: max(idx - 7, 0)}
      true -> state
    end
  end

  defp clamped_scroll_top(%__MODULE__{} = state, visible_height) do
    max_scroll = max(length(state.rows) - max(visible_height, 1), 0)
    min(state.scroll_top, max_scroll)
  end

  defp clamp_index(_idx, 0), do: 0
  defp clamp_index(idx, count), do: idx |> max(0) |> min(count - 1)

  defp category_id(%{id: id}), do: id

  # ---- Modal.Form open helpers -----------------------------------------------

  defp open_create_board(%__MODULE__{categories: []} = state), do: state

  defp open_create_board(state) do
    default_cat = default_category_for(state)

    form =
      ModalForm.init(
        title: "New board",
        fields: board_fields(state, default_cat.id, %{}),
        on_submit: modal_submitter(:create_board),
        on_cancel: &noop/0
      )

    %{state | modal: form, modal_kind: :create_board, edit_target: nil}
  end

  defp open_edit_board(state) do
    case selected_row(state) do
      {:board, board} ->
        form =
          ModalForm.init(
            title: "Edit board — #{board.slug}",
            fields: board_fields(state, board.category_id, board_values(board)),
            on_submit: modal_submitter(:edit_board),
            on_cancel: &noop/0
          )

        %{state | modal: form, modal_kind: :edit_board, edit_target: board}

      _ ->
        state
    end
  end

  defp open_create_category(state) do
    form =
      ModalForm.init(
        title: "New category",
        fields: category_fields(%{}),
        on_submit: modal_submitter(:create_category),
        on_cancel: &noop/0
      )

    %{state | modal: form, modal_kind: :create_category, edit_target: nil}
  end

  defp open_edit_category(state) do
    case selected_row(state) do
      {:category, cat} ->
        form =
          ModalForm.init(
            title: "Edit category — #{cat.name}",
            fields: category_fields(category_values(cat)),
            on_submit: modal_submitter(:edit_category),
            on_cancel: &noop/0
          )

        %{state | modal: form, modal_kind: :edit_category, edit_target: cat}

      _ ->
        state
    end
  end

  defp open_archive_board(state, board) do
    # D-07: destructive actions (Archive board, Archive category) route through
    # `Foglet.TUI.Presentation.theme_mappings().commands.destructive` which maps
    # to `:error`. The confirm modal uses `type: :confirm` so the Modal widget
    # can render it with the appropriate destructive emphasis via theme.error.
    # Do NOT hardcode color atoms — use `Map.fetch!(theme, :error)` in render.
    %{
      state
      | modal: %Modal{
          type: :confirm,
          title: "Archive board",
          message:
            "Archive \"#{board.name}\"? Members will stop seeing it in active board lists. Existing threads are kept. [Y] Archive board   [N/Esc] Keep board"
        },
        modal_kind: :archive_board,
        archive_target: board
    }
  end

  defp open_archive_category(state, category) do
    # D-07: see open_archive_board/2 comment above — same destructive routing.
    %{
      state
      | modal: %Modal{
          type: :confirm,
          title: "Archive category",
          message:
            "Archive \"#{category.name}\"? Boards in this category will stop appearing in active board lists. [Y] Archive category   [N/Esc] Keep category"
        },
        modal_kind: :archive_category,
        archive_target: category
    }
  end

  defp default_category_for(%__MODULE__{} = state) do
    case selected_row(state) do
      {:category, cat} -> cat
      {:board, board} -> Enum.find(state.categories, &(&1.id == board.category_id))
      _ -> hd(state.categories)
    end || hd(state.categories)
  end

  # ---- Field spec builders ---------------------------------------------------

  defp board_fields(%__MODULE__{categories: categories}, default_cat_id, values) do
    cat_choices = Enum.map(categories, fn c -> {c.name, c.id} end)

    [
      %{
        name: :slug,
        type: :text,
        label: "Slug",
        max_length: 50,
        value: Map.get(values, :slug, "")
      },
      %{
        name: :name,
        type: :text,
        label: "Name",
        max_length: 100,
        value: Map.get(values, :name, "")
      },
      %{
        name: :description,
        type: :textarea,
        label: "Description",
        value: Map.get(values, :description, "") || ""
      },
      %{
        name: :category_id,
        type: :enum,
        label: "Category",
        choices: cat_choices,
        value: Map.get(values, :category_id, default_cat_id)
      },
      %{
        name: :display_order,
        type: :integer,
        label: "Display order",
        value: Map.get(values, :display_order, 0) |> to_string()
      },
      %{
        name: :postable_by,
        type: :enum,
        label: "Postable by",
        choices: @postable_choices,
        value: Map.get(values, :postable_by, "members")
      },
      %{
        name: :default_subscription,
        type: :boolean,
        label: "Default subscription",
        value: Map.get(values, :default_subscription, false)
      },
      %{
        name: :required_subscription,
        type: :boolean,
        label: "Required subscription",
        value: Map.get(values, :required_subscription, false)
      },
      %{
        name: :chat_enabled,
        type: :boolean,
        label: "Chat",
        description:
          "When on, this board adds a CHAT tab next to THREADS. Off keeps the board threads-only. Storage and retention below appear once chat is on.",
        value: Map.get(values, :chat_enabled, false)
      },
      %{
        name: :chat_storage_mode,
        type: :enum,
        label: "Chat storage",
        description: "Where chat messages live. The picker shows what each option means.",
        choices: @chat_storage_choices,
        value: Map.get(values, :chat_storage_mode, "ephemeral"),
        visible_when: fn vals -> vals[:chat_enabled] == true end
      },
      %{
        name: :chat_message_ttl_seconds,
        type: :enum,
        label: "Chat retention",
        description: "How long messages stay before they expire.",
        choices: chat_ttl_choices(Map.get(values, :chat_message_ttl_seconds)),
        value: Map.get(values, :chat_message_ttl_seconds, @chat_ttl_default_seconds),
        visible_when: fn vals ->
          vals[:chat_enabled] == true and vals[:chat_storage_mode] == "ephemeral"
        end
      }
    ]
  end

  # FOG-349: when an existing board carries a TTL outside the preset list (e.g.
  # legacy 7200s default), prepend a synthetic "{n} seconds (custom)" choice so
  # the value renders as selected and is not silently rounded. Once the operator
  # cycles off it, `drop_legacy_ttl_choice/1` strips the synthetic head from
  # subsequent renders.
  defp chat_ttl_choices(nil), do: @chat_ttl_preset_choices

  defp chat_ttl_choices(value) when is_integer(value) do
    if value in @chat_ttl_preset_seconds do
      @chat_ttl_preset_choices
    else
      [{"#{value} seconds (custom)", value} | @chat_ttl_preset_choices]
    end
  end

  defp chat_ttl_choices(_), do: @chat_ttl_preset_choices

  defp category_fields(values) do
    [
      %{
        name: :name,
        type: :text,
        label: "Name",
        max_length: 100,
        value: Map.get(values, :name, "")
      },
      %{
        name: :description,
        type: :textarea,
        label: "Description",
        value: Map.get(values, :description, "") || ""
      },
      %{
        name: :display_order,
        type: :integer,
        label: "Display order",
        value: Map.get(values, :display_order, 0) |> to_string()
      }
    ]
  end

  defp board_values(board) do
    %{
      slug: board.slug,
      name: board.name,
      description: board.description || "",
      category_id: board.category_id,
      display_order: board.display_order,
      postable_by: to_string(board.postable_by),
      default_subscription: board.default_subscription,
      required_subscription: board.required_subscription,
      chat_enabled: board.chat_enabled,
      chat_storage_mode: to_string(board.chat_storage_mode),
      chat_message_ttl_seconds: board.chat_message_ttl_seconds
    }
  end

  defp category_values(cat) do
    %{
      name: cat.name,
      description: cat.description || "",
      display_order: cat.display_order
    }
  end

  # ---- Modal.Form event handling --------------------------------------------

  defp modal_submitter(kind) do
    fn payload -> Effect.modal_submit(:sysop, kind, payload) end
  end

  defp noop, do: :ok

  defp handle_form_event(event, %__MODULE__{modal: form} = state) do
    {new_form, action} = ModalForm.handle_event(event, form)
    new_form = drop_legacy_ttl_choice(new_form)

    case action do
      {:submitted, submit_result} ->
        handle_submit_result(submit_result, %{state | modal: new_form})

      :cancelled ->
        {%{state | modal: nil, modal_kind: nil, edit_target: nil}, []}

      _ ->
        {%{state | modal: new_form}, []}
    end
  end

  # FOG-349: once the operator cycles away from a legacy "{n} seconds (custom)"
  # TTL entry, drop the synthetic head from the choices list so it does not
  # reappear. The TTL field stores its selection as an integer index into
  # `choices`; dropping the head while the selection is past it requires
  # shifting the index down by one to keep pointing at the same value.
  defp drop_legacy_ttl_choice(%ModalForm{} = form) do
    case Enum.find_index(form.fields, &(&1.name == :chat_message_ttl_seconds)) do
      nil ->
        form

      idx ->
        spec = Enum.at(form.fields, idx)
        cur = Enum.at(form.field_states, idx)

        case ttl_legacy_head(spec) do
          {:legacy, rest} when is_integer(cur) and cur > 0 ->
            new_spec = %{spec | choices: rest}
            new_states = List.replace_at(form.field_states, idx, cur - 1)
            new_fields = List.replace_at(form.fields, idx, new_spec)
            %{form | fields: new_fields, field_states: new_states}

          _ ->
            form
        end
    end
  end

  defp ttl_legacy_head(%{choices: [{label, _value} | rest]}) when is_binary(label) do
    if String.ends_with?(label, "(custom)"), do: {:legacy, rest}, else: :no_legacy
  end

  defp ttl_legacy_head(_), do: :no_legacy

  defp handle_submit_result(
         %Effect{
           type: :modal_submit,
           payload: %{screen_key: :sysop, kind: kind, payload: payload}
         },
         %__MODULE__{modal_kind: kind} = state
       ) do
    handle_submit_payload(payload, state)
  end

  defp handle_submit_result(_submit_result, state), do: {state, []}

  defp handle_submit_payload(nil, state), do: {state, []}

  defp handle_submit_payload(
         %{display_order: nil},
         %__MODULE__{modal_kind: kind} = state
       )
       when kind in [:create_board, :edit_board, :create_category, :edit_category] do
    form = set_modal_errors(state.modal, %{display_order: "is invalid"})
    {%{state | modal: form}, []}
  end

  defp handle_submit_payload(payload, %__MODULE__{modal_kind: kind} = state) do
    case dispatch_submit(kind, payload, state) do
      {:ok, _result} ->
        new_state =
          state
          |> refresh_lists()
          |> clamp_selection()

        {%{new_state | modal: nil, modal_kind: nil, edit_target: nil}, []}

      {:error, %Ecto.Changeset{} = cs} ->
        errors = changeset_errors(cs)
        form = set_modal_errors(state.modal, errors)
        {%{state | modal: form}, []}

      {:error, :forbidden} ->
        {reset_modal(state),
         [{:error_modal, "Your role changed. Board changes were not saved.", :main_menu}]}

      {:error, reason} when is_atom(reason) ->
        {reset_modal(state), [{:error_modal, db_error_message(reason), :main_menu}]}
    end
  end

  defp dispatch_submit(:create_board, payload, state) do
    {cat_id, attrs} = Map.pop(payload, :category_id)
    Boards.create_board(state.current_user, cat_id, normalize_board_attrs(attrs))
  end

  defp dispatch_submit(:edit_board, payload, state) do
    # category_id change goes through the same update_board call to stay within
    # the plan's scope (Board.changeset casts :category_id). normalize_board_attrs/1
    # only touches :postable_by, so passing the full payload preserves :category_id.
    Boards.update_board(
      state.current_user,
      state.edit_target,
      normalize_board_attrs(payload)
    )
  end

  defp dispatch_submit(:create_category, payload, state) do
    Boards.create_category(state.current_user, normalize_category_attrs(payload))
  end

  defp dispatch_submit(:edit_category, payload, state) do
    Boards.update_category(
      state.current_user,
      state.edit_target,
      normalize_category_attrs(payload)
    )
  end

  defp set_modal_errors(%ModalForm{} = form, errors) do
    form
    |> ModalForm.set_errors(errors)
    |> ModalForm.set_submit_state({:error, "validation"})
  end

  defp normalize_board_attrs(attrs) do
    attrs
    |> Map.update(:postable_by, "members", fn
      nil -> "members"
      v -> v
    end)
  end

  defp normalize_category_attrs(attrs) do
    attrs
    |> Map.update(:display_order, 0, fn
      n when is_integer(n) -> n
      value -> value
    end)
  end

  defp changeset_errors(%Ecto.Changeset{} = cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
    |> Enum.map(fn {k, msgs} -> {k, Enum.join(msgs, "; ")} end)
    |> Map.new()
  end

  defp db_error_message(:board_server_unavailable),
    do: "Board service is not ready. Try again in a moment."

  defp db_error_message(:create_board), do: "Could not save board changes."
  defp db_error_message(:edit_board), do: "Could not save board changes."
  defp db_error_message(:archive_board), do: "Could not archive board."
  defp db_error_message(:create_category), do: "Could not save category changes."
  defp db_error_message(:edit_category), do: "Could not save category changes."
  defp db_error_message(:archive_category), do: "Could not archive category."

  defp db_error_message(reason) when is_atom(reason),
    do: "Could not finish that board action."

  defp db_error_message(_), do: "Could not finish that board action."

  defp reset_modal(state),
    do: %{
      state
      | modal: nil,
        modal_kind: nil,
        edit_target: nil,
        archive_target: nil
    }

  defp clamp_selection(%__MODULE__{rows: []} = state), do: %{state | selection_index: 0}

  defp clamp_selection(%__MODULE__{rows: rows, selection_index: idx} = state) do
    %{state | selection_index: min(idx, length(rows) - 1)}
  end

  # ---- Confirm modal (archive) ----------------------------------------------

  defp handle_confirm_event(%{key: :escape}, state),
    do: {reset_modal(state), []}

  defp handle_confirm_event(%{key: :char, char: c}, state) when c in ["y", "Y"] do
    kind = state.modal_kind
    target = state.archive_target

    result =
      case kind do
        :archive_board ->
          Boards.archive_board(state.current_user, target)

        :archive_category ->
          Boards.archive_category(state.current_user, target)

        other ->
          require Logger

          Logger.error("BoardsView confirm: unexpected modal_kind #{inspect(other)}")

          {:error, :unknown_confirm_kind}
      end

    case result do
      {:ok, _} ->
        new_state =
          state
          |> reset_modal()
          |> refresh_lists()
          |> clamp_selection()

        {new_state, []}

      {:error, :forbidden} ->
        {reset_modal(state),
         [{:error_modal, "Your role changed. Board changes were not saved.", :main_menu}]}

      {:error, _} ->
        {reset_modal(state), [{:error_modal, db_error_message(kind), :main_menu}]}
    end
  end

  defp handle_confirm_event(%{key: :char, char: c}, state) when c in ["n", "N"] do
    {reset_modal(state), []}
  end

  defp handle_confirm_event(_event, state), do: {state, []}
end
