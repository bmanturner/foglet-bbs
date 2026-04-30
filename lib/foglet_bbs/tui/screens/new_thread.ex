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

  On submit: calls Foglet.Threads.create_thread/3 (board_id, user_id, %{title:, body:}).
  On success: navigates to :thread_list with the new thread pre-loaded.
  """

  @behaviour Foglet.TUI.Screen

  alias Foglet.Config
  alias Foglet.TUI.{Context, Effect}
  alias Foglet.TUI.Screens.Domain
  alias Foglet.TUI.Screens.NewThread.Render
  alias Foglet.TUI.Screens.NewThread.State
  alias Foglet.TUI.Widgets.Compose
  alias Foglet.TUI.Widgets.Input.TextInput

  @default_max_post_length 8192
  @default_max_thread_title_length 60

  @impl true
  @spec init(Context.t()) :: State.t()
  def init(%Context{} = context), do: State.from_context(context_with_config_limits(context))

  @impl true
  @spec update(term(), State.t(), Context.t()) :: {State.t(), [Effect.t()]}
  def update(:on_route_enter, %State{} = state, %Context{} = context) do
    update(:load, state, context)
  end

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
  def render(%State{} = state, %Context{} = context), do: Render.render(state, context)

  # Key handler
  # ---------------------------------------------------------------------------
  defp handle_board_key_event(%{key: :escape}, %State{} = state) do
    {state, [Effect.navigate(origin_for(state), cancel_params(state))]}
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

  defp handle_compose_key_event(
         %{key: :char, char: "c", ctrl: true},
         %State{} = state,
         %Context{}
       ) do
    {state, [Effect.navigate(origin_for(state), cancel_params(state))]}
  end

  defp handle_compose_key_event(%{key: :escape}, %State{} = state, %Context{}) do
    {state, [Effect.navigate(origin_for(state), cancel_params(state))]}
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
    max = max_body_length(state, context)
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

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp threads_module(%Context{} = context) do
    case domain_module(context, :threads) do
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

  # When canceling back to a board-scoped origin (e.g. :thread_list), forward
  # the board context so the destination can re-mount with its breadcrumb and
  # thread query intact instead of falling into the missing-board error path.
  defp cancel_params(%State{origin: :thread_list, board: %{} = board}) do
    %{board: board, board_id: Map.get(board, :id) || Map.get(board, "id")}
  end

  defp cancel_params(%State{}), do: %{}

  defp format_error(:posting_not_allowed), do: "You are not allowed to post on this board."
  defp format_error(:thread_locked), do: "This thread is locked"

  defp format_error(%Ecto.Changeset{} = cs) do
    Enum.map_join(cs.errors, ", ", fn {field, {msg, _}} -> "#{field}: #{msg}" end)
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp context_with_config_limits(%Context{} = context) do
    session_context =
      context.session_context
      |> normalize_session_context()
      |> put_new_positive_lazy(:max_post_length, fn ->
        safe_config_get("max_post_length", @default_max_post_length)
      end)
      |> put_new_positive_lazy(:max_thread_title_length, fn ->
        safe_config_get("max_thread_title_length", @default_max_thread_title_length)
      end)

    %{context | session_context: session_context}
  end

  defp normalize_session_context(%_{} = value), do: Map.from_struct(value)
  defp normalize_session_context(value) when is_map(value), do: value
  defp normalize_session_context(_value), do: %{}

  # Only invoke the producer (which may hit the config cache / DB) when the
  # session_context does not already carry a positive integer for this key.
  # This keeps callers that pre-seed limits from paying for an unnecessary
  # config read — and lets them avoid surfacing config-read failures
  # entirely when the limit is already known.
  defp put_new_positive_lazy(map, key, producer) when is_function(producer, 0) do
    case Map.get(map, key) do
      n when is_integer(n) and n > 0 ->
        map

      _other ->
        case producer.() do
          n when is_integer(n) and n > 0 -> Map.put(map, key, n)
          _ -> map
        end
    end
  end

  defp max_body_length(state, context) do
    sc = Map.get(context, :session_context) || %{}

    case Map.get(sc, :max_post_length) do
      n when is_integer(n) and n > 0 ->
        n

      _ ->
        max_body_length_from_state(state)
    end
  end

  defp max_body_length_from_state(%State{max_post_length: n}) when is_integer(n) and n > 0,
    do: n

  defp max_body_length_from_state(_state),
    do: safe_config_get("max_post_length", @default_max_post_length)

  defp safe_config_get(key, default) do
    case Config.get!(key) do
      n when is_integer(n) and n > 0 -> n
      _ -> default
    end
  rescue
    Ecto.NoResultsError -> default
  end
end
