defmodule Foglet.TUI.CommandEntry do
  @moduledoc """
  App-owned global command entry state, reducer, rendering, and domain dispatch.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.CommandEntry.Parser
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Input.TextInput

  @browsing_screens MapSet.new([
                      :main_menu,
                      :notifications,
                      :online_now,
                      :board_list,
                      :thread_list,
                      :post_reader,
                      :door_list,
                      :account,
                      :moderation,
                      :sysop
                    ])

  defstruct input: nil,
            mode: :input,
            query: "",
            results: [],
            selected_index: 0,
            message: "Type to search messages, or jump like general:42."

  @type t :: %__MODULE__{}

  def open do
    %__MODULE__{
      input:
        TextInput.init(
          value: "",
          placeholder: "Search messages or enter board:post",
          max_length: 160
        )
    }
  end

  @spec open_key?(map(), atom()) :: boolean()
  def open_key?(%{key: :char, char: "/"}, screen), do: MapSet.member?(@browsing_screens, screen)
  def open_key?(%{key: :char, char: "k", ctrl: true}, _screen), do: true
  def open_key?(%{key: :char, char: "K", ctrl: true}, _screen), do: true
  def open_key?(_key, _screen), do: false

  @spec handle_key(t(), map(), term()) :: {t() | nil, [Effect.t()]}
  def handle_key(%__MODULE__{}, %{key: :escape}, _app_state), do: {nil, []}

  def handle_key(%__MODULE__{mode: mode} = state, %{key: :down}, _app_state)
      when mode in [:results, :no_results, :feedback] do
    {%{state | selected_index: min(state.selected_index + 1, max(length(state.results) - 1, 0))},
     []}
  end

  def handle_key(%__MODULE__{mode: mode} = state, %{key: :up}, _app_state)
      when mode in [:results, :no_results, :feedback] do
    {%{state | selected_index: max(state.selected_index - 1, 0)}, []}
  end

  def handle_key(
        %__MODULE__{mode: :results, results: [_ | _]} = state,
        %{key: :enter},
        _app_state
      ) do
    result = Enum.at(state.results, state.selected_index) || hd(state.results)
    {nil, [navigate_to_result(result)]}
  end

  def handle_key(%__MODULE__{} = state, %{key: :enter}, app_state) do
    state.input.raxol_state.value
    |> Parser.parse()
    |> submit(state, app_state)
  end

  def handle_key(%__MODULE__{} = state, %{key: :char, char: "u", ctrl: true}, _app_state) do
    {%{
       state
       | input:
           TextInput.init(
             value: "",
             placeholder: "Search messages or enter board:post",
             max_length: 160
           ),
         query: "",
         mode: :input,
         results: [],
         selected_index: 0
     }, []}
  end

  def handle_key(%__MODULE__{} = state, key_event, _app_state) do
    {input, _action} = TextInput.handle_event(key_event, state.input)
    {%{state | input: input, query: input.raxol_state.value}, []}
  end

  @spec render(t(), term()) :: term()
  def render(%__MODULE__{} = state, app_state) do
    {cols, rows} = Map.get(app_state, :terminal_size, {80, 24})
    theme = Theme.from_state(app_state)
    max_results = result_limit(rows)
    width = min(max(cols - 4, 60), 108)

    box style: %{border_fg: theme.border.fg, padding: 0}, width: width do
      column style: %{gap: 0} do
        [
          text("Command Entry  Esc cancel · Enter go", fg: theme.accent.fg, style: [:bold]),
          row style: %{gap: 1} do
            [
              text(">", fg: theme.accent.fg, style: [:bold]),
              TextInput.render(state.input,
                theme: theme,
                focused: true,
                cap_display_width: max(width - 6, 20)
              )
            ]
          end,
          text(state.message || "", fg: theme.dim.fg),
          render_results(
            Enum.take(state.results, max_results),
            state.selected_index,
            theme,
            width
          )
        ]
      end
    end
  end

  defp submit({:ok, {:search, query}}, state, app_state) do
    results =
      posts_mod(app_state).search_readable_posts(Map.get(app_state, :current_user),
        query: query,
        limit: 10
      )

    if results == [] do
      {%{
         state
         | mode: :no_results,
           query: query,
           results: [],
           selected_index: 0,
           message: "No readable matches. Try different words or a board:post jump."
       }, []}
    else
      {%{
         state
         | mode: :results,
           query: query,
           results: results,
           selected_index: 0,
           message: "#{length(results)} readable match(es). ↑/↓ select · Enter open."
       }, []}
    end
  rescue
    _ ->
      {%{
         state
         | mode: :feedback,
           results: [],
           message: "Search is temporarily unavailable. Try again."
       }, []}
  end

  defp submit({:ok, {:direct_post, slug, number}}, state, app_state) do
    case posts_mod(app_state).fetch_readable_post_by_board_slug_and_message_number(
           Map.get(app_state, :current_user),
           slug,
           number
         ) do
      {:ok, result} ->
        {nil, [navigate_to_result(result)]}

      {:error, _} ->
        {%{state | mode: :feedback, results: [], message: "Not found or not accessible."}, []}
    end
  rescue
    _ -> {%{state | mode: :feedback, results: [], message: "Not found or not accessible."}, []}
  end

  defp submit({:ok, {:slash, _command, _args}}, state, _app_state),
    do:
      {%{
         state
         | mode: :feedback,
           results: [],
           message: "Slash commands are reserved here; this command is not available yet."
       }, []}

  defp submit({:error, :blank}, state, _app_state),
    do:
      {%{
         state
         | mode: :feedback,
           results: [],
           message: "Type to search messages, or jump like general:42."
       }, []}

  defp submit({:error, _reason}, state, _app_state),
    do: {%{state | mode: :feedback, results: [], message: "Not found or not accessible."}, []}

  defp navigate_to_result(result) do
    Effect.navigate(:post_reader, %{
      board: Map.get(result, :board),
      board_id: result |> Map.get(:board) |> map_id(),
      thread: Map.get(result, :thread),
      thread_id: result |> Map.get(:thread) |> map_id(),
      load_intent:
        {:around_message_number,
         Map.get(result, :around_message_number) || get_in(result, [:post, :message_number])}
    })
  end

  defp posts_mod(app_state) do
    session_context = Map.get(app_state, :session_context) || %{}
    domain = Map.get(session_context, :domain) || %{}
    Map.get(domain, :posts, Foglet.Posts)
  end

  defp render_results([], _selected_index, _theme, _width), do: text("")

  defp render_results(results, selected_index, theme, width) do
    column style: %{gap: 0} do
      results
      |> Enum.with_index()
      |> Enum.map(fn {result, idx} ->
        marker = if idx == selected_index, do: "▶", else: " "
        style = if idx == selected_index, do: [:reverse], else: []

        text(
          truncate(
            "#{marker} #{board_slug(result)} ##{message_number(result)} · #{thread_title(result)} · #{author(result)} · #{snippet(result)}",
            max(width - 4, 20)
          ),
          fg: theme.primary.fg,
          style: style
        )
      end)
    end
  end

  defp result_limit(rows) when rows <= 22, do: 3
  defp result_limit(rows) when rows <= 24, do: 5
  defp result_limit(_rows), do: 9

  defp board_slug(result),
    do: get_in(result, [:board, :slug]) || get_in(result, [:board, "slug"]) || "board"

  defp thread_title(result),
    do: get_in(result, [:thread, :title]) || get_in(result, [:thread, "title"]) || "thread"

  defp message_number(result),
    do:
      get_in(result, [:post, :message_number]) || get_in(result, [:post, "message_number"]) ||
        Map.get(result, :around_message_number) || "?"

  defp author(result),
    do: get_in(result, [:author, :handle]) || get_in(result, [:post, :user, :handle]) || "unknown"

  defp snippet(result),
    do: result |> Map.get(:snippet, "") |> to_string() |> String.replace(~r/\s+/, " ")

  defp map_id(%{} = value), do: Map.get(value, :id) || Map.get(value, "id")
  defp map_id(_), do: nil

  defp truncate(text, width) when byte_size(text) <= width, do: text
  defp truncate(text, width), do: String.slice(text, 0, max(width - 1, 0)) <> "…"
end
