defmodule Foglet.TUI.Screens.NewThread do
  @moduledoc """
  New-thread compose wizard (Audit #9 fix).

  Step 1 — :board   : pick a subscribed board (j/k / ↑↓ to navigate, Enter to select, Esc to cancel).
  Step 2 — :compose : enter title (Tab-switch focus) and body (MultiLineInput state, rendered as plain text/2).
                       Ctrl+S to submit, Ctrl+C to cancel.

  State lives in state.screen_state[:new_thread].  See init_screen_state/1.

  On submit: calls Foglet.Threads.create_thread/3 (board_id, user_id, %{title:, body:}).
  On success: navigates to :post_reader with the new thread loaded.
  If the function is not exported, shows a friendly "coming soon" modal.
  """

  alias Foglet.TUI.Widgets.{KeyBar, StatusBar}
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
      error: nil
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
    boards = ss.boards || []
    rows = render_board_rows(boards, ss.selected_board_index)

    box style: %{border: :single, padding: 1} do
      column style: %{gap: 0} do
        [
          text(" New Thread — pick a board ", style: [:bold]),
          divider(),
          StatusBar.render(%{
            handle: state.current_user && state.current_user.handle,
            location: "New Thread: Board"
          }),
          column style: %{gap: 0} do
            rows
          end,
          KeyBar.render([{"j/k", "Select"}, {"Enter", "Choose"}, {"Esc", "Cancel"}])
        ]
      end
    end
  end

  defp render_board_rows([], _idx) do
    [text("Loading boards…", style: [:dim])]
  end

  defp render_board_rows(boards, selected_index) do
    Enum.with_index(boards)
    |> Enum.map(fn {board, idx} ->
      marker = if idx == selected_index, do: "> ", else: "  "

      if idx == selected_index do
        text("#{marker}#{board.name}", fg: :green, style: [:bold])
      else
        text("#{marker}#{board.name}", fg: :green)
      end
    end)
  end

  defp render_compose_step(state, ss) do
    board = ss.board
    board_name = (board && board.name) || "?"

    title_line =
      if ss.focused == :title do
        text("Title: #{ss.title_input}█", fg: :green, style: [:bold])
      else
        text("Title: #{ss.title_input}", fg: :green)
      end

    body_focused = ss.focused == :body
    body_col = render_body(ss.body_input_state, body_focused)

    error_items =
      if ss.error do
        [text(""), text(ss.error, fg: :red)]
      else
        []
      end

    box style: %{border: :single, padding: 1} do
      column style: %{gap: 0} do
        [
          text(" New Thread — #{board_name} ", style: [:bold]),
          divider(),
          StatusBar.render(%{
            handle: state.current_user && state.current_user.handle,
            location: "New Thread: Compose"
          }),
          text(""),
          title_line,
          text(""),
          text("Body:", fg: :green),
          body_col
        ] ++
          error_items ++
          [
            text(""),
            KeyBar.render([
              {"Tab", "Switch field"},
              {"Ctrl+S", "Submit"},
              {"Ctrl+C", "Cancel"}
            ])
          ]
      end
    end
  end

  # Renders MultiLineInput state as plain text/2 — avoids MultiLineInput.render/2
  # which crashes the layout engine (Bug B).
  defp render_body(input_st, focused?) do
    lines =
      input_st.value
      |> String.split("\n")
      |> case do
        [] -> [""]
        ls -> ls
      end

    {cursor_row, cursor_col} = Map.get(input_st, :cursor_pos, {0, 0})

    column style: %{gap: 0} do
      lines
      |> Enum.with_index()
      |> Enum.map(fn {line, idx} ->
        rendered =
          if focused? and idx == cursor_row do
            {before, after_} = String.split_at(line, cursor_col)
            "#{before}█#{after_}"
          else
            line
          end

        # Use a placeholder space for empty lines so the element is non-empty.
        display = if rendered == "", do: " ", else: rendered
        text(display, fg: :green)
      end)
    end
  end

  # ---------------------------------------------------------------------------
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

  defp handle_compose_key(%{key: :char, char: "c", ctrl: true}, state, _ss) do
    {:update, %{state | current_screen: :main_menu}, []}
  end

  defp handle_compose_key(%{key: :escape}, state, _ss) do
    {:update, %{state | current_screen: :main_menu}, []}
  end

  defp handle_compose_key(%{key: :tab}, state, ss) do
    new_focus = if ss.focused == :title, do: :body, else: :title
    {:update, put_ss(state, %{ss | focused: new_focus}), []}
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
  defp handle_compose_key(%{key: :char, char: c}, state, %{focused: :title} = ss) do
    {:update, put_ss(state, %{ss | title_input: ss.title_input <> c}), []}
  end

  defp handle_compose_key(_key, _state, %{focused: :title}), do: :no_match

  # Body field: forward to MultiLineInput
  defp handle_compose_key(key_event, state, %{focused: :body} = ss) do
    case translate_key(key_event) do
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
  # Board loading (called by App.update/2 on {:load_boards_for_new_thread})
  # ---------------------------------------------------------------------------

  @doc """
  Loads subscribed boards into the new_thread screen state.
  Called from App.update/2 in response to {:load_boards_for_new_thread}.
  """
  @spec load_boards(map()) :: {map(), list()}
  def load_boards(state) do
    boards_mod = domain_module(state, :boards)

    boards =
      if function_exported?(boards_mod, :list_subscribed_boards, 1) do
        boards_mod.list_subscribed_boards(state.current_user)
      else
        []
      end

    ss = screen_state(state)
    new_ss = %{ss | boards: boards}
    {put_ss(state, new_ss), []}
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
        threads_mod = domain_module(state, :threads)
        user_id = state.current_user && state.current_user.id

        if function_exported?(threads_mod, :create_thread, 3) and user_id do
          case threads_mod.create_thread(board.id, user_id, %{title: title, body: body}) do
            {:ok, %{thread: thread}} ->
              new_state = %{
                state
                | current_screen: :post_reader,
                  current_board: board,
                  current_thread: thread,
                  screen_state:
                    Map.merge(state.screen_state, %{
                      new_thread: nil,
                      post_reader: %{selected_post_index: 0}
                    })
              }

              {:update, new_state, [{:load_posts, thread.id}]}

            {:error, cs} ->
              msg = format_error(cs)
              {:update, put_ss(state, %{ss | error: msg}), []}
          end
        else
          # Phase 2 create_thread not available — friendly stub
          modal = %{
            type: :info,
            # Phase 2 needs to implement Foglet.Threads.create_thread/3.
            message: "Thread creation coming soon — Phase 2 not yet wired."
          }

          {:update, %{state | modal: modal, current_screen: :main_menu}, []}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Key translation (same as PostComposer)
  # ---------------------------------------------------------------------------

  # Translate Raxol-native event data maps to MultiLineInput.update/2 messages.
  defp translate_key(%{key: :backspace}), do: {:backspace}
  defp translate_key(%{key: :delete}), do: {:delete}
  defp translate_key(%{key: :enter}), do: {:enter}
  defp translate_key(%{key: :up}), do: {:move_cursor, :up}
  defp translate_key(%{key: :down}), do: {:move_cursor, :down}
  defp translate_key(%{key: :left}), do: {:move_cursor, :left}
  defp translate_key(%{key: :right}), do: {:move_cursor, :right}
  defp translate_key(%{key: :home}), do: {:move_cursor_line_start}
  defp translate_key(%{key: :end}), do: {:move_cursor_line_end}
  defp translate_key(%{key: :page_up}), do: {:move_cursor_page, :up}
  defp translate_key(%{key: :page_down}), do: {:move_cursor_page, :down}

  # Typed character — %{key: :char, char: grapheme_string}.
  # Spacebar arrives as char: " " naturally.
  defp translate_key(%{key: :char, char: c}) do
    case String.to_charlist(c) do
      [cp | _] when cp >= 32 -> {:input, cp}
      _ -> nil
    end
  end

  defp translate_key(_), do: nil

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

  defp domain_module(state, key) do
    ctx = Map.get(state, :session_context) || %{}
    get_in(ctx, [:domain, key]) || default_domain(key)
  end

  defp default_domain(:boards), do: Foglet.Boards
  defp default_domain(:threads), do: Foglet.Threads
  defp default_domain(other), do: other

  defp format_error(%Ecto.Changeset{} = cs) do
    Enum.map_join(cs.errors, ", ", fn {field, {msg, _}} -> "#{field}: #{msg}" end)
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
