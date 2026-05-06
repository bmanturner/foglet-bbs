defmodule Foglet.TUI.Screens.OnlineNowTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.RenderHelpers

  alias Foglet.Sessions.PresenceSummary
  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Screens.OnlineNow
  alias Foglet.TUI.Screens.OnlineNow.State

  defmodule FakeOnlineNow do
    def list(_opts \\ []) do
      [
        %{
          user_id: "u-sysop",
          handle: "alice",
          role: :sysop,
          presence_label: "Online",
          presence: %PresenceSummary{label: "Online", online?: true},
          user: %{id: "u-sysop", handle: "alice", role: :sysop}
        },
        %{
          user_id: "u-mod",
          handle: "moddy",
          role: :mod,
          presence_label: "Chatting in general",
          presence: %PresenceSummary{label: "Chatting in general", online?: true},
          user: %{id: "u-mod", handle: "moddy", role: :mod}
        },
        %{
          user_id: "u-user",
          handle: "zoe",
          role: :user,
          presence_label: "Browsing boards",
          presence: %PresenceSummary{label: "Browsing boards", online?: true},
          user: %{id: "u-user", handle: "zoe", role: :user}
        }
      ]
    end
  end

  defp context(opts \\ []) do
    Context.new(
      current_user:
        Keyword.get(opts, :current_user, %{id: "viewer", handle: "viewer", role: :user}),
      route: :online_now,
      terminal_size: Keyword.get(opts, :terminal_size, {80, 24}),
      domain: %{online_now: FakeOnlineNow}
    )
  end

  defp panel_titles(view) do
    view
    |> flatten_nodes()
    |> Enum.filter(&(Map.get(&1, :type) == :panel))
    |> Enum.map(&get_in(&1, [:attrs, :title]))
    |> Enum.reject(&is_nil/1)
  end

  defp flatten_nodes(node), do: do_flatten_nodes(node, [])

  defp do_flatten_nodes(nodes, acc) when is_list(nodes),
    do: Enum.flat_map(nodes, &do_flatten_nodes(&1, acc))

  defp do_flatten_nodes(%{} = node, _acc) do
    [node | do_flatten_nodes(Map.get(node, :children, []), [])]
  end

  defp do_flatten_nodes(_other, _acc), do: []

  test "route entry loads online rows through the runtime task boundary" do
    local = OnlineNow.init(context())

    {loading, effects} = OnlineNow.update(:on_route_enter, local, context())

    assert loading.status == :loading

    assert [
             %Effect{
               type: :task,
               payload: %{op: :load_online_now, screen_key: :online_now, fun: fun}
             }
           ] = effects

    assert length(fun.()) == 3
  end

  test "loaded rows render selection, role badge, presence labels, and profile affordance without duplicate Online Now panel chrome" do
    local = State.from_rows(OnlineNow.init(context()), FakeOnlineNow.list())

    view = OnlineNow.render(local, context())
    texts = collect_text_values(view)

    assert Enum.any?(texts, &String.contains?(&1, "Online Now"))
    refute "Online Now" in panel_titles(view)
    assert Enum.any?(texts, &String.contains?(&1, "> @alice [SYSOP]"))
    assert Enum.any?(texts, &String.contains?(&1, "Online"))
    assert Enum.any?(texts, &String.contains?(&1, "Chatting in general"))
    assert "V" in texts
    assert Enum.any?(texts, &String.contains?(&1, "Profile"))
  end

  test "empty list renders an empty state and hides profile affordance" do
    local = State.from_rows(OnlineNow.init(context()), [])

    texts = OnlineNow.render(local, context()) |> collect_text_values()

    assert Enum.any?(texts, &String.contains?(&1, "No authenticated users are online."))
    refute Enum.any?(texts, &String.contains?(&1, "V Profile"))
  end

  test "up and down move selection and keep overflow window around the selected row" do
    rows =
      for index <- 1..20 do
        %{
          user_id: "u#{index}",
          handle: "user#{index}",
          role: :user,
          presence_label: "Online",
          presence: %PresenceSummary{label: "Online", online?: true},
          user: %{id: "u#{index}", handle: "user#{index}", role: :user}
        }
      end

    local = State.from_rows(OnlineNow.init(context(terminal_size: {64, 22})), rows)

    scrolled =
      Enum.reduce(1..16, local, fn _, state ->
        {state, []} =
          OnlineNow.update({:key, %{key: :down}}, state, context(terminal_size: {64, 22}))

        state
      end)

    assert scrolled.selected_index == 16
    assert scrolled.scroll_offset > 0

    texts = OnlineNow.render(scrolled, context(terminal_size: {64, 22})) |> collect_text_values()
    assert Enum.any?(texts, &String.contains?(&1, "> @user17"))
    refute Enum.any?(texts, &String.contains?(&1, "@user1 "))
  end

  test "profile key opens the existing public profile modal for the selected row" do
    local = State.from_rows(OnlineNow.init(context()), FakeOnlineNow.list())
    {local, []} = OnlineNow.update({:key, %{key: :down}}, local, context())

    {^local, effects} = OnlineNow.update({:key, %{key: :char, char: "V"}}, local, context())

    assert [
             %Effect{
               type: :modal,
               payload: {:open, %Foglet.TUI.Modal{title: "Public Profile", message: profile}}
             }
           ] = effects

    assert %Foglet.Accounts.PublicProfile{user_id: "u-mod", handle: "moddy", role: :mod} = profile
    refute Map.has_key?(profile, :email)
  end

  test "back keys route to the main menu" do
    for key <- ["q", "Q", "b", "B"] do
      {_local, effects} =
        OnlineNow.update({:key, %{key: :char, char: key}}, OnlineNow.init(context()), context())

      assert Enum.any?(
               effects,
               &match?(%Effect{type: :navigate, payload: %{screen: :main_menu}}, &1)
             )
    end
  end
end
