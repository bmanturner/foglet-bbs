defmodule Foglet.TUI.HandleColorSurfacesTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.RenderHelpers

  alias Foglet.TUI.Context
  alias Foglet.TUI.Screens.ChatRoom
  alias Foglet.TUI.Screens.ChatRoom.State, as: ChatState
  alias Foglet.TUI.Screens.MainMenu.Render, as: MainMenuRender
  alias Foglet.TUI.Screens.MainMenu.State, as: MainMenuState
  alias Foglet.TUI.Screens.OnlineNow
  alias Foglet.TUI.Screens.OnlineNow.State, as: OnlineNowState
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Post.PostCard

  defp text_nodes(tree) do
    tree
    |> flatten_nodes()
    |> Enum.filter(&(Map.get(&1, :type) == :text))
  end

  defp flatten_nodes(node), do: do_flatten_nodes(node, [])

  defp do_flatten_nodes(nodes, acc) when is_list(nodes),
    do: Enum.flat_map(nodes, &do_flatten_nodes(&1, acc))

  defp do_flatten_nodes(%{} = node, _acc) do
    [node | do_flatten_nodes(Map.get(node, :children, []), [])]
  end

  defp do_flatten_nodes(_other, _acc), do: []

  defp colored_text?(tree, content, color) do
    Enum.any?(text_nodes(tree), fn node ->
      Map.get(node, :content) == content and Map.get(node, :fg) == color
    end)
  end

  test "post headers use saved handle color without recoloring body content" do
    tree =
      PostCard.render(
        %{
          body: "hello @brendan",
          inserted_at: DateTime.add(DateTime.utc_now(), -60, :second),
          user: %{handle: "brendan", handle_color: "#66ccff"}
        },
        80,
        Theme.default()
      )

    assert colored_text?(tree, "@brendan", "#66ccff")

    refute Enum.any?(text_nodes(tree), fn node ->
             Map.get(node, :content) == "hello @brendan" and Map.get(node, :fg) == "#66ccff"
           end)
  end

  test "online now row uses saved handle color for the selected handle segment" do
    local =
      OnlineNowState.from_rows(OnlineNow.init(context()), [
        %{
          user_id: "u1",
          handle: "alice",
          handle_color: "#ff8800",
          role: :user,
          presence_label: "Online",
          user: %{id: "u1", handle: "alice", handle_color: "#ff8800"}
        }
      ])

    tree = OnlineNow.render(local, context())

    assert colored_text?(tree, "> @alice", "#ff8800")
    assert Enum.join(collect_text_values(tree), "") =~ "> @alice"
  end

  test "main-menu oneliner author handle uses saved color while body remains primary" do
    theme = Theme.default()

    tree =
      %MainMenuState{
        recent_oneliners: [
          %{id: "ol1", body: "hello @alice", user: %{handle: "alice", handle_color: "#44aaee"}}
        ],
        selected_oneliner_index: 0
      }
      |> MainMenuRender.render(context())

    assert colored_text?(tree, "> @alice", "#44aaee")
    assert colored_text?(tree, "  hello @alice", theme.primary.fg)
  end

  test "chat transcript and sidebar use saved handle color from resolved user map" do
    state = %ChatState{
      board: %{id: "b1", chat_storage_mode: :ephemeral},
      board_id: "b1",
      user_id: "u1",
      messages: [%{id: "m1", body: "hello @bob", user_id: "u1"}],
      handles: %{"u1" => %{handle: "alice", handle_color: "#bb55ff"}},
      online: [%{user_id: "u1", tab: :chat}],
      loaded?: true
    }

    tree = ChatRoom.render(state, context(terminal_size: {100, 30}, current_user: %{id: "u1"}))

    assert colored_text?(tree, "alice", "#bb55ff")
    assert colored_text?(tree, "• alice (you)", "#bb55ff")
  end

  defp context(opts \\ []) do
    Context.new(
      current_user: Keyword.get(opts, :current_user, %{id: "viewer", handle: "viewer"}),
      terminal_size: Keyword.get(opts, :terminal_size, {80, 24}),
      session_context: %{}
    )
  end
end
