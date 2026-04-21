defmodule Foglet.TUI.Screens.NewThread do
  @moduledoc """
  New-thread compose wizard (Audit #9 fix).

  Step 1 — :board   : pick a subscribed board (j/k / ↑↓ to navigate, Enter to select, Esc to cancel).
  Step 2 — :compose : enter title (Tab-switch focus) and body (MultiLineInput state, rendered as plain text/2).
                       Ctrl+S to submit, Ctrl+C to cancel.

  State lives in state.screen_state[:new_thread].  See init_screen_state/1.

  On submit: calls Foglet.Threads.create_thread/3 (board_id, user_id, %{title:, body:}).
  On success: navigates to :thread_list with the new thread pre-loaded.
  """

  alias Foglet.Config
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Compose
  alias Foglet.TUI.Widgets.List.{ListRow, SelectionList}
  alias Foglet.TUI.Widgets.Post.MarkdownBody
  alias Raxol.UI.Components.Input.MultiLineInput

  import Raxol.Core.Renderer.View

  # ---------------------------------------------------------------------------
  # Screen-state initialiser
  # ---------------------------------------------------------------------------

  @doc """
  Build the initial screen_state map for the new-thread wizard.
  Boards are passed in immediately (already loaded) or left nil to show "Loading…".
  """
  @spec init_screen_state(keyword()) :: map()
  def init_screen_state(opts \\ []) do
    boards = Keyword.get(opts, :boards, nil)
    width = Keyword.get(opts, :width, 80)
    height = Keyword.get(opts, :height, 10)

    {:ok, body_input_state} =
      MultiLineInput.init(%{
        value: "",
        placeholder: "Write your opening post…",
        width: max(width - 4, 20),
        height: height,
        wrap: :none,
        focused: false
      })

    %{
      step: :board,
      boards: boards,
      selected_board_index: 0,
      board: nil,
      title_input: "",
      body_input_state: body_input_state,
      focused: :title,
      mode: :edit,
      error: nil,
      # Callers may override :origin to control where Ctrl+C / Esc navigate.
      # Default is :main_menu (the only entry point for the board-pick step).
      origin: :main_menu
    }
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @spec render(map()) :: any()
  def render(state) do
    ss = screen_state(state)

    case ss.step do
      :board -> render_board_step(state, ss)
      :compose -> render_compose_step(state, ss)
    end
  end

  defp render_board_step(state, ss) do
    theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()

    board_content =
      case ss.boards do
        nil ->
          column style: %{gap: 0} do
            [text("Loading boards…", fg: theme.dim.fg)]
          end

        [] ->
          column style: %{gap: 0} do
            [
              text(
                "You aren't subscribed to any boards. Ask your sysop to subscribe you.",
                fg: theme.warning.fg
              )
            ]
          end

        boards ->
          SelectionList.render(boards, ss.selected_board_index, fn {board, _idx, selected} ->
            ListRow.render(board.name, selected, theme)
          end)
      end

    ScreenFrame.render(state, "New Thread — pick a board", board_content, [
      {"j/k", "Select"},
      {"Enter", "Choose"},
      {"Esc", "Cancel"}
    ])
  end

  defp render_compose_step(state, ss) do
    board = ss.board
    board_name = (board && board.name) || "?"
    theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()

    # D-14: render the title line with a live N / cap char counter so users
    # see the soft limit as they type.
    cap = max_thread_title_length()
    title_len = String.length(ss.title_input)
    counter = "#{title_len} / #{cap} chars"

    title_line =
      if ss.focused == :title do
        text("Title: #{ss.title_input}█", fg: theme.accent.fg, style: [:bold])
      else
        text("Title: #{ss.title_input}", fg: theme.primary.fg)
      end

    title_counter_line = text(counter, fg: theme.dim.fg)

    body_section = render_body_section(state, ss, theme)

    error_items =
      if ss.error do
        [text(""), text(ss.error, fg: theme.error.fg, style: [:bold])]
      else
        []
      end

    content =
      column style: %{gap: 0} do
        [
          text(""),
          title_line,
          title_counter_line,
          text(""),
          text("Body:", fg: theme.primary.fg),
          body_section
        ] ++ error_items ++ [text("")]
      end

    ScreenFrame.render(state, "New Thread — #{board_name}", content, [
      {"Tab", compose_tab_hint(ss)},
      {"Ctrl+S", "Submit"},
      {"Ctrl+C", "Cancel"}
    ])
  end

  defp compose_tab_hint(%{focused: :body, mode: :edit}), do: "Preview"
  defp compose_tab_hint(%{focused: :body, mode: :preview}), do: "Edit"
  defp compose_tab_hint(_ss), do: "Switch field"

  defp render_body_section(state, ss, theme) do
    body_focused = ss.focused == :body

    case ss.mode do
      :edit ->
        # D-09: delegate to shared widget. NewThread preserves its legacy
        # single-space placeholder for empty lines (see Plan 04-01's opt).
        Compose.render_input(ss.body_input_state, body_focused, theme,
          empty_line_placeholder: " "
        )

      :preview ->
        {w, _h} = state.terminal_size || {80, 24}
        body_width = max(w - 4, 20)
        MarkdownBody.render(ss.body_input_state.value, body_width, theme)
    end
  end

  # Key handler
  # ---------------------------------------------------------------------------

  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  def handle_key(key_event, state) do
    ss = screen_state(state)

    case ss.step do
      :board -> handle_board_key(key_event, state, ss)
      :compose -> handle_compose_key(key_event, state, ss)
    end
  end

  # --- Board step ---

  defp handle_board_key(%{key: :escape}, state, _ss) do
    {:update, %{state | current_screen: :main_menu}, []}
  end

  defp handle_board_key(%{key: :char, char: "j"}, state, ss), do: board_move(state, ss, +1)
  defp handle_board_key(%{key: :down}, state, ss), do: board_move(state, ss, +1)
  defp handle_board_key(%{key: :char, char: "k"}, state, ss), do: board_move(state, ss, -1)
  defp handle_board_key(%{key: :up}, state, ss), do: board_move(state, ss, -1)

  defp handle_board_key(%{key: :enter}, state, ss) do
    boards = ss.boards || []

    case Enum.at(boards, ss.selected_board_index) do
      nil ->
        :no_match

      board ->
        {w, _h} = state.terminal_size || {80, 24}

        {:ok, body_input_state} =
          MultiLineInput.init(%{
            value: "",
            placeholder: "Write your opening post…",
            width: max(w - 4, 20),
            height: 10,
            wrap: :none,
            focused: false
          })

        new_ss = %{ss | step: :compose, board: board, body_input_state: body_input_state}
        {:update, put_ss(state, new_ss), []}
    end
  end

  defp handle_board_key(_key, _state, _ss), do: :no_match

  defp board_move(state, ss, delta) do
    boards = ss.boards || []

    if boards == [] do
      :no_match
    else
      new_idx =
        (ss.selected_board_index + delta)
        |> max(0)
        |> min(length(boards) - 1)

      {:update, put_ss(state, %{ss | selected_board_index: new_idx}), []}
    end
  end

  # --- Compose step ---

  # D-07: origin-aware cancel on the :compose step.
  # The board step still routes Esc to :main_menu (handle_board_key at
  # line ~237) because the board step is only reachable from MainMenu.
  defp handle_compose_key(%{key: :char, char: "c", ctrl: true}, state, ss) do
    {:update, %{state | current_screen: Map.get(ss, :origin, :main_menu)}, []}
  end

  defp handle_compose_key(%{key: :escape}, state, ss) do
    {:update, %{state | current_screen: Map.get(ss, :origin, :main_menu)}, []}
  end

  defp handle_compose_key(%{key: :tab}, state, ss) do
    if ss.focused == :body do
      # Tab on body toggles edit/preview mode (Gap 4 — matches PostComposer D-28).
      new_mode = if ss.mode == :edit, do: :preview, else: :edit
      {:update, put_ss(state, %{ss | mode: new_mode}), []}
    else
      # Tab on title advances focus to body (existing behaviour).
      new_focus = if ss.focused == :title, do: :body, else: :title
      {:update, put_ss(state, %{ss | focused: new_focus}), []}
    end
  end

  defp handle_compose_key(%{key: :char, char: "s", ctrl: true}, state, ss) do
    do_submit(state, ss)
  end

  # Title field: backspace removes last grapheme
  defp handle_compose_key(%{key: :backspace}, state, %{focused: :title} = ss) do
    new_title =
      case String.length(ss.title_input) do
        0 -> ""
        n -> String.slice(ss.title_input, 0, n - 1)
      end

    {:update, put_ss(state, %{ss | title_input: new_title}), []}
  end

  # Title field: typed character — Raxol native %{key: :char, char: c}.
  # Spacebar arrives as char: " " naturally; no special-case needed.
  # D-14: enforce the soft title cap from Foglet.Config key
  # "max_thread_title_length" (default 60). Keystrokes past the cap are
  # rejected silently. The schema-level hard cap of 300 (D-15) remains
  # as a DB backstop for sysops who raise the config.
  defp handle_compose_key(%{key: :char, char: c}, state, %{focused: :title} = ss) do
    cap = max_thread_title_length()
    new_title = ss.title_input <> c

    if String.length(new_title) > cap do
      :no_match
    else
      {:update, put_ss(state, %{ss | title_input: new_title}), []}
    end
  end

  defp handle_compose_key(_key, _state, %{focused: :title}), do: :no_match

  # Body field: forward to MultiLineInput.
  # NOTE: The Ctrl+C (cancel) and Ctrl+S (submit) clauses at lines 250 and 270
  # MUST remain above this clause in source order. Compose.translate_key/1
  # intentionally passes ctrl+char combos through as {:input, codepoint} for
  # terminal-native workflows; the screen-level pattern-matches above intercept
  # Ctrl+S and Ctrl+C before they can reach this fallthrough. Moving those
  # clauses below this one would cause Ctrl+S on body focus to insert "s" into
  # the body text instead of submitting.
  defp handle_compose_key(key_event, state, %{focused: :body} = ss) do
    case Compose.translate_key(key_event) do
      nil ->
        :no_match

      msg ->
        case MultiLineInput.update(msg, ss.body_input_state) do
          {:noreply, new_input_st, _cmds} ->
            {:update, put_ss(state, %{ss | body_input_state: new_input_st}), []}

          new_input_st when is_struct(new_input_st, MultiLineInput) ->
            {:update, put_ss(state, %{ss | body_input_state: new_input_st}), []}

          _other ->
            :no_match
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Submit
  # ---------------------------------------------------------------------------

  defp do_submit(state, ss) do
    title = String.trim(ss.title_input)
    body = ss.body_input_state.value
    board = ss.board

    cond do
      title == "" ->
        {:update, put_ss(state, %{ss | error: "Title cannot be empty."}), []}

      String.trim(body) == "" ->
        {:update, put_ss(state, %{ss | error: "Post body cannot be empty."}), []}

      true ->
        do_create_thread(state, ss, title, body, board)
    end
  end

  defp do_create_thread(state, ss, title, body, board) do
    threads_mod = threads_module(state)
    user_id = state.current_user && state.current_user.id

    if user_id do
      case threads_mod.create_thread(board.id, user_id, %{title: title, body: body}) do
        {:ok, %{thread: _thread}} ->
          # D-04: success navigates back to :thread_list with the new
          # thread pre-selected. Threads sort by last_post_at desc, so
          # a freshly created thread is always at index 0.
          thread_list_ss = %{selected_index: 0}

          new_screen_state =
            state.screen_state
            |> Map.delete(:new_thread)
            |> Map.put(:thread_list, thread_list_ss)

          new_state = %{
            state
            | current_screen: :thread_list,
              current_board: board,
              screen_state: new_screen_state
          }

          {:update, new_state, [{:load_threads, board.id}]}

        {:error, cs} ->
          msg = format_error(cs)
          {:update, put_ss(state, %{ss | error: msg}), []}
      end
    else
      # Guard against a missing current_user (unauthenticated state).
      # Should never happen in the wired flow, but crash-free is better.
      {:update,
       %{
         state
         | modal: %{type: :error, message: "You must be logged in to create a thread."}
       }, []}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp screen_state(state) do
    get_in(state.screen_state, [:new_thread]) ||
      init_screen_state()
  end

  defp put_ss(state, ss) do
    new_screen_state = Map.put(state.screen_state, :new_thread, ss)
    %{state | screen_state: new_screen_state}
  end

  defp threads_module(state) do
    ctx = Map.get(state, :session_context) || %{}
    get_in(ctx, [:domain, :threads]) || Foglet.Threads
  end

  defp format_error(%Ecto.Changeset{} = cs) do
    Enum.map_join(cs.errors, ", ", fn {field, {msg, _}} -> "#{field}: #{msg}" end)
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  @default_max_thread_title_length 60

  # D-13: safe config getter — missing key defaults to 60 rather than
  # raising. Mirrors the PostComposer.safe_config_get/2 pattern (~line 410)
  # to keep the screens decoupled from each other.
  defp max_thread_title_length do
    case Config.get!("max_thread_title_length") do
      n when is_integer(n) and n > 0 -> n
      _ -> @default_max_thread_title_length
    end
  rescue
    _ -> @default_max_thread_title_length
  end
end
