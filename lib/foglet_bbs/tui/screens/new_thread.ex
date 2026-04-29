defmodule Foglet.TUI.Screens.NewThread do
  @moduledoc """
  New-thread compose wizard (Audit #9 fix).

  Phase 37 makes NewThread screen-owned: board picker state, board-load
  results, compose drafts, validation, submit status/result, and cancel origin
  live in `%NewThread.State{}` and flow through `update/3`.

  Step 1 — :board   : pick a subscribed board (j/k / ↑↓ to navigate, Enter to select, Esc to cancel).
  Step 2 — :compose : enter title (Tab-switch focus) and body (MultiLineInput state, rendered as plain text/2).
                       Ctrl+S to submit, Ctrl+C to cancel.

  State lives in `state.screen_state[:new_thread]` as a `%NewThread.State{}`.
  See init_screen_state/1.

  On submit: calls Foglet.Threads.create_thread/3 (board_id, user_id, %{title:, body:}).
  On success: navigates to :thread_list with the new thread pre-loaded.
  """

  @behaviour Foglet.TUI.Screen

  alias Foglet.Config
  alias Foglet.TUI.{Context, Effect}
  alias Foglet.TUI.Screens.Domain
  alias Foglet.TUI.Screens.NewThread.State
  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Compose
  alias Foglet.TUI.Widgets.Composer.EditorFrame
  alias Foglet.TUI.Widgets.Input.TextInput
  alias Foglet.TUI.Widgets.List.{ListRow, SelectionList}
  alias Foglet.TUI.Widgets.Post.MarkdownBody
  alias Raxol.UI.Components.Input.MultiLineInput

  import Raxol.Core.Renderer.View

  @default_max_post_length 8192
  @default_terminal_size {80, 24}

  @impl true
  @spec init(Context.t()) :: State.t()
  def init(%Context{} = context), do: State.from_context(context)

  @impl true
  @spec update(term(), State.t(), Context.t()) :: {State.t(), [Effect.t()]}
  def update(:load, %State{} = state, %Context{} = context) do
    boards_mod = boards_module(context)
    current_user = context.current_user

    new_state = %{state | load_status: :loading, error: nil}

    effect =
      Effect.task(:load_boards_for_new_thread, :new_thread, fn ->
        directory = boards_mod.board_directory_for(current_user)
        {subscribed_boards(directory), active_board_count(directory)}
      end)

    {new_state, [effect]}
  end

  def update(
        {:task_result, :load_boards_for_new_thread, {:ok, {boards, active_board_count}}},
        %State{} = state,
        %Context{}
      )
      when is_list(boards) do
    status = if boards == [], do: :empty, else: :loaded

    {%{
       state
       | boards: boards,
         active_board_count: active_board_count,
         selected_board_index: 0,
         load_status: status,
         error: nil
     }, []}
  end

  def update(
        {:task_result, :load_boards_for_new_thread, {:ok, boards}},
        %State{} = state,
        %Context{} = context
      )
      when is_list(boards) do
    update(
      {:task_result, :load_boards_for_new_thread, {:ok, {boards, nil}}},
      state,
      context
    )
  end

  def update(
        {:task_result, :load_boards_for_new_thread, {:error, reason}},
        %State{} = state,
        %Context{}
      ) do
    {%{state | load_status: {:error, reason}, error: format_error(reason)}, []}
  end

  def update({:task_result, :create_thread, result}, %State{} = state, %Context{} = context) do
    handle_create_thread_result(result, state, context)
  end

  def update({:key, key_event}, %State{step: :board} = state, %Context{}) do
    handle_board_key_event(key_event, state)
  end

  def update({:key, key_event}, %State{step: :compose} = state, %Context{} = context) do
    handle_compose_key_event(key_event, state, context)
  end

  def update(_message, %State{} = state, %Context{}), do: {state, []}

  @impl true
  @spec render(State.t(), Context.t()) :: any()
  def render(%State{} = state, %Context{} = context) do
    frame_state = frame_state(state, context)

    case state.step do
      :board -> render_board_step(frame_state, state)
      :compose -> render_compose_step(frame_state, state)
    end
  end

  @doc """
  Build the initial screen_state map for the new-thread wizard.
  Boards are passed in immediately (already loaded) or left nil to show "Loading…".
  """
  @impl true
  @spec init_screen_state(keyword()) :: State.t()
  def init_screen_state(opts \\ []) do
    opts
    |> Keyword.put_new(:max_title_length, max_thread_title_length())
    |> State.new()
  end

  @impl true
  @spec render(map()) :: any()
  # Phase 39 cleanup: legacy render/1 remains for older smoke tests only.
  # Phase 37 flow state is screen-owned by render/2 and %NewThread.State{}.
  def render(state) do
    ss = screen_state(state)

    case ss.step do
      :board -> render_board_step(state, ss)
      :compose -> render_compose_step(state, ss)
    end
  end

  defp render_board_step(state, ss) do
    theme = Theme.from_state(state)

    board_content =
      case ss.boards do
        nil ->
          column style: %{gap: 0} do
            [text("Loading boards…", fg: theme.dim.fg)]
          end

        [] ->
          column style: %{gap: 0} do
            [text(empty_board_message(ss), fg: theme.warning.fg)]
          end

        boards ->
          SelectionList.render(boards, ss.selected_board_index, fn {board, _idx, selected} ->
            ListRow.render(board.name, selected, theme)
          end)
      end

    ScreenFrame.render(state, %{}, board_content, [
      {"j/k", "Select"},
      {"Enter", "Choose"},
      {"Esc", "Cancel"}
    ])
  end

  defp render_compose_step(state, ss) do
    theme = Theme.from_state(state)
    {width, height} = state.terminal_size || @default_terminal_size
    cap = max_thread_title_length()
    title_value = ss.title_input_state.raxol_state.value
    body_value = ss.body_input_state.value

    content =
      EditorFrame.render(
        mode: ss.mode,
        focused?: ss.focused == :body and ss.mode == :edit,
        context: compose_context(ss, title_value, width, theme),
        title: render_title_input(ss, theme),
        body: render_body_section(state, ss, theme),
        budgets: [
          %{label: "Title", count: String.length(title_value), limit: cap},
          %{label: "Body", count: String.length(body_value), limit: max_body_length(state)}
        ],
        error: ss.error,
        width: max(width - 4, 20),
        height: max(height - 6, 10),
        theme: theme
      )

    ScreenFrame.render(state, %{}, content, [
      {"Tab", compose_tab_hint(ss)},
      {"Ctrl+S", "Submit"},
      {"Ctrl+C", "Cancel"}
    ])
  end

  defp empty_board_message(%State{active_board_count: 0}) do
    "No active boards are available."
  end

  defp empty_board_message(%State{active_board_count: count})
       when is_integer(count) and count > 0 do
    "You aren't subscribed to any boards. Subscribe from Boards."
  end

  defp empty_board_message(_ss) do
    "You aren't subscribed to any boards. Subscribe from Boards."
  end

  defp compose_tab_hint(%{focused: :body, mode: :edit}), do: "Preview"
  defp compose_tab_hint(%{focused: :body, mode: :preview}), do: "Edit"
  defp compose_tab_hint(_ss), do: "Switch field"

  defp compose_context(ss, title_value, width, theme) do
    available = max(width - 10, 20)
    board_name = ss.board && Map.get(ss.board, :name, "Unknown board")

    [
      text("Board #{TextWidth.truncate(board_name || "Unknown board", available)}",
        fg: theme.dim.fg
      ),
      title_context(title_value, available, theme)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp title_context("", _available, _theme), do: nil

  defp title_context(title_value, available, theme) do
    text("Draft #{TextWidth.truncate(title_value, available)}", fg: theme.dim.fg)
  end

  defp render_title_input(ss, theme) do
    title_focused = ss.focused == :title
    title_label_fg = if title_focused, do: theme.accent.fg, else: theme.primary.fg
    title_label_style = if title_focused, do: [:bold], else: []

    row style: %{gap: 0} do
      [
        text("Title: ", fg: title_label_fg, style: title_label_style),
        TextInput.render(ss.title_input_state,
          bordered: false,
          focused: title_focused,
          theme: theme
        )
      ]
    end
  end

  defp render_body_section(state, ss, theme) do
    body_focused = ss.focused == :body
    {w, _h} = state.terminal_size || @default_terminal_size
    body_width = max(w - 4, 20)

    case ss.mode do
      :edit ->
        # D-09: delegate to shared widget. NewThread preserves its legacy
        # single-space placeholder for empty lines (see Plan 04-01's opt).
        render_body_input(ss.body_input_state, body_focused, theme, body_width)

      :preview ->
        MarkdownBody.render(ss.body_input_state.value, body_width, theme)
    end
  end

  defp render_body_input(input, focused?, theme, width),
    do: Compose.render_input(input, focused?, theme, width: width, empty_line_placeholder: " ")

  # Key handler
  # ---------------------------------------------------------------------------
  @impl true
  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  # Phase 39 cleanup: legacy handle_key/2 remains for compatibility tests.
  # It must not be the source of truth for the Phase 37 App runtime path.
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
        {w, _h} = state.terminal_size || @default_terminal_size

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

  defp handle_board_key_event(%{key: :escape}, %State{} = state) do
    {state, [Effect.navigate(origin_for(state), %{})]}
  end

  defp handle_board_key_event(%{key: :char, char: "j"}, %State{} = state),
    do: board_move_state(state, +1)

  defp handle_board_key_event(%{key: :down}, %State{} = state), do: board_move_state(state, +1)

  defp handle_board_key_event(%{key: :char, char: "k"}, %State{} = state),
    do: board_move_state(state, -1)

  defp handle_board_key_event(%{key: :up}, %State{} = state), do: board_move_state(state, -1)

  defp handle_board_key_event(%{key: :enter}, %State{} = state) do
    boards = state.boards || []

    case Enum.at(boards, state.selected_board_index) do
      nil -> {state, []}
      board -> {%{state | step: :compose, board: board}, []}
    end
  end

  defp handle_board_key_event(_key, %State{} = state), do: {state, []}

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

  defp board_move_state(%State{} = state, delta) do
    boards = state.boards || []

    if boards == [] do
      {state, []}
    else
      new_idx =
        (state.selected_board_index + delta)
        |> max(0)
        |> min(length(boards) - 1)

      {%{state | selected_board_index: new_idx}, []}
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

  # Title field: delegate to TextInput while preserving cap behavior contract.
  # D-14: the soft title cap is still enforced from Config.
  defp handle_compose_key(key_event, state, %{focused: :title} = ss) do
    before = ss.title_input_state.raxol_state.value
    {new_input, _action} = TextInput.handle_event(key_event, ss.title_input_state)
    after_value = new_input.raxol_state.value

    cond do
      after_value != before ->
        {:update, put_ss(state, %{ss | title_input_state: new_input}), []}

      match?(%{key: :backspace}, key_event) ->
        {:update, put_ss(state, %{ss | title_input_state: new_input}), []}

      true ->
        :no_match
    end
  end

  # Body field: forward to MultiLineInput.
  # NOTE: source order matters for handle_key/2 clauses — do not reorder.
  # NOTE: The Ctrl+C (cancel) and Ctrl+S (submit) clauses at lines 250 and 270
  # MUST remain above this clause in source order. Compose.apply_key/2
  # intentionally passes ctrl+char combos through as typed input for
  # terminal-native workflows; the screen-level pattern-matches above intercept
  # Ctrl+S and Ctrl+C before they can reach this fallthrough. Moving those
  # clauses below this one would cause Ctrl+S on body focus to insert "s" into
  # the body text instead of submitting.
  defp handle_compose_key(key_event, state, %{focused: :body} = ss) do
    case Compose.apply_key(ss.body_input_state, key_event) do
      {:ok, new_input_st} ->
        {:update, put_ss(state, %{ss | body_input_state: new_input_st}), []}

      :error ->
        :no_match
    end
  end

  defp handle_compose_key_event(
         %{key: :char, char: "c", ctrl: true},
         %State{} = state,
         %Context{}
       ) do
    {state, [Effect.navigate(origin_for(state), %{})]}
  end

  defp handle_compose_key_event(%{key: :escape}, %State{} = state, %Context{}) do
    {state, [Effect.navigate(origin_for(state), %{})]}
  end

  defp handle_compose_key_event(%{key: :tab}, %State{} = state, %Context{}) do
    if state.focused == :body do
      new_mode = if state.mode == :edit, do: :preview, else: :edit
      {%{state | mode: new_mode}, []}
    else
      {%{state | focused: :body}, []}
    end
  end

  defp handle_compose_key_event(
         %{key: :char, char: "s", ctrl: true},
         %State{} = state,
         %Context{} = context
       ) do
    submit_from_state(state, context)
  end

  defp handle_compose_key_event(key_event, %State{focused: :title} = state, %Context{}) do
    before = state.title_input_state.raxol_state.value
    {new_input, _action} = TextInput.handle_event(key_event, state.title_input_state)
    after_value = new_input.raxol_state.value

    cond do
      after_value != before ->
        {%{state | title_input_state: new_input}, []}

      match?(%{key: :backspace}, key_event) ->
        {%{state | title_input_state: new_input}, []}

      true ->
        {state, []}
    end
  end

  defp handle_compose_key_event(key_event, %State{focused: :body} = state, %Context{}) do
    case Compose.apply_key(state.body_input_state, key_event) do
      {:ok, new_input_st} -> {%{state | body_input_state: new_input_st}, []}
      :error -> {state, []}
    end
  end

  defp submit_from_state(%State{} = state, %Context{} = context) do
    title = String.trim(state.title_input_state.raxol_state.value)
    body = state.body_input_state.value
    board = state.board
    max = max_body_length(context)
    user_id = context.current_user && context.current_user.id

    cond do
      title == "" ->
        {%{state | error: "Title cannot be empty."}, []}

      String.trim(body) == "" ->
        {%{state | error: "Post body cannot be empty."}, []}

      String.length(body) > max ->
        {%{state | error: "Post body exceeds maximum length of #{max} characters."}, []}

      is_nil(user_id) ->
        {%{state | error: "You must be logged in to create a thread."}, []}

      is_nil(board) ->
        {%{state | error: "Select a board before creating a thread."}, []}

      true ->
        threads_mod = threads_module(context)
        attrs = %{title: title, body: body}

        effect =
          Effect.task(:create_thread, :new_thread, fn ->
            threads_mod.create_thread(board.id, user_id, attrs)
          end)

        {%{state | submission_status: :submitting, error: nil}, [effect]}
    end
  end

  defp handle_create_thread_success(thread, result, %State{} = state, %Context{}) do
    board = state.board

    params = %{
      board: board,
      board_id: board && board.id,
      select_thread_id: Map.get(thread, :id)
    }

    new_state = %{state | submission_status: :submitted, submit_result: result, error: nil}
    {new_state, [Effect.navigate(:thread_list, params)]}
  end

  defp handle_create_thread_result({:ok, {:ok, %{thread: thread} = result}}, state, context) do
    handle_create_thread_success(thread, result, state, context)
  end

  defp handle_create_thread_result({:ok, %{thread: thread} = result}, state, context) do
    handle_create_thread_success(thread, result, state, context)
  end

  defp handle_create_thread_result({:ok, {:error, reason}}, state, _context) do
    {%{state | submission_status: {:error, reason}, error: format_error(reason)}, []}
  end

  defp handle_create_thread_result({:error, reason}, state, _context) do
    {%{state | submission_status: {:error, reason}, error: format_error(reason)}, []}
  end

  defp do_submit(state, ss) do
    title = String.trim(ss.title_input_state.raxol_state.value)
    body = ss.body_input_state.value
    board = ss.board
    max = max_body_length(state)

    cond do
      title == "" ->
        {:update, put_ss(state, %{ss | error: "Title cannot be empty."}), []}

      String.trim(body) == "" ->
        {:update, put_ss(state, %{ss | error: "Post body cannot be empty."}), []}

      String.length(body) > max ->
        {:update,
         put_ss(state, %{ss | error: "Post body exceeds maximum length of #{max} characters."}),
         []}

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
         | modal: %Foglet.TUI.Modal{
             type: :error,
             message: "You must be logged in to create a thread."
           }
       }, []}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp screen_state(state) do
    case Map.get(state.screen_state, :new_thread) do
      %State{} = ss -> ss
      _ -> init_screen_state()
    end
  end

  defp put_ss(state, ss) do
    new_screen_state = Map.put(state.screen_state, :new_thread, ss)
    %{state | screen_state: new_screen_state}
  end

  defp threads_module(%Context{} = context) do
    case domain_module(context, :threads) do
      {:ok, mod} -> mod
      {:error, :not_configured} -> Foglet.Threads
    end
  end

  defp threads_module(state) do
    ctx = Map.get(state, :session_context) || %{}

    case Domain.get(ctx, :threads) do
      {:ok, mod} -> mod
      {:error, :not_configured} -> Foglet.Threads
    end
  end

  defp boards_module(%Context{} = context) do
    case domain_module(context, :boards) do
      {:ok, mod} -> mod
      {:error, :not_configured} -> Foglet.Boards
    end
  end

  defp domain_module(%Context{domain: domain}, key) when is_map(domain) do
    case Map.get(domain, key) do
      mod when is_atom(mod) and not is_nil(mod) -> {:ok, mod}
      _ -> Domain.get(%{domain: domain}, key)
    end
  end

  defp domain_module(%Context{session_context: ctx}, key), do: Domain.get(ctx || %{}, key)

  defp subscribed_boards(directory) do
    directory
    |> Enum.flat_map(& &1.boards)
    |> Enum.filter(& &1.subscribed?)
    |> Enum.map(& &1.board)
  end

  defp active_board_count(directory) do
    Enum.reduce(directory, 0, fn category, acc -> acc + length(category.boards) end)
  end

  defp origin_for(%State{origin: origin}) when is_atom(origin), do: origin
  defp origin_for(_state), do: :main_menu

  defp frame_state(%State{} = state, %Context{} = context) do
    %{
      current_screen: :new_thread,
      current_user: context.current_user,
      current_board: state.board,
      session_context: context.session_context,
      terminal_size: context.terminal_size,
      route: context.route,
      route_params: context.route_params
    }
  end

  defp format_error(:posting_not_allowed), do: "You are not allowed to post on this board."
  defp format_error(:thread_locked), do: "This thread is locked"

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

  defp max_body_length(state) do
    sc = Map.get(state, :session_context) || %{}

    case Map.get(sc, :max_post_length) do
      n when is_integer(n) and n > 0 ->
        n

      _ ->
        safe_config_get("max_post_length", @default_max_post_length)
    end
  end

  defp safe_config_get(key, default) do
    case Config.get!(key) do
      n when is_integer(n) and n > 0 -> n
      _ -> default
    end
  rescue
    _ -> default
  end
end
