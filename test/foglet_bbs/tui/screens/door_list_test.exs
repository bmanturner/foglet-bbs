defmodule Foglet.TUI.Screens.DoorListTest do
  use ExUnit.Case, async: true

  alias Foglet.Accounts.User
  alias Foglet.Config
  alias Foglet.Doors.Manifest
  alias Foglet.TUI.App
  alias Foglet.TUI.AsciiRenderer
  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Modal
  alias Foglet.TUI.RenderFixtures
  alias Foglet.TUI.Screens.DoorList
  alias Foglet.TUI.Screens.DoorList.State
  alias Foglet.TUI.TextWidth

  setup_all do
    Config.init_cache()

    Enum.each(Foglet.Config.Schema.defaults(), fn {key, value} ->
      :ets.insert(:foglet_config, {key, value})
    end)

    {:ok, _} = Application.ensure_all_started(:tzdata)
    :ok
  end

  defp user(role \\ :user), do: %User{id: "u1", handle: "alice", role: role, status: :active}

  defp context(opts \\ []) do
    Context.new(
      current_user: Keyword.get(opts, :user, user()),
      session_context: %{theme: Foglet.TUI.Theme.default()},
      terminal_size: Keyword.get(opts, :terminal_size, {80, 24}),
      route: :door_list,
      route_params: %{}
    )
  end

  test "init lists launchable built-in native and external demo doors" do
    assert %State{doors: doors, selected_index: 0} = DoorList.init(context())

    assert Enum.map(doors, & &1.id) == [
             "native-hello",
             "external-echo",
             "python-context-demo",
             "classic-dropfile-demo"
           ]

    assert Enum.all?(doors, &match?(%Manifest{}, &1))
  end

  test "up/down and j/k clamp selection to available doors" do
    ctx = context()
    state = DoorList.init(ctx)

    assert {%State{selected_index: 1}, []} = DoorList.update({:key, %{key: :down}}, state, ctx)

    assert {%State{selected_index: 2}, []} =
             DoorList.update({:key, %{key: :char, char: "j"}}, %{state | selected_index: 1}, ctx)

    assert {%State{selected_index: 3}, []} =
             DoorList.update({:key, %{key: :down}}, %{state | selected_index: 2}, ctx)

    assert {%State{selected_index: 3}, []} =
             DoorList.update({:key, %{key: :char, char: "j"}}, %{state | selected_index: 3}, ctx)

    assert {%State{selected_index: 2}, []} =
             DoorList.update({:key, %{key: :char, char: "k"}}, %{state | selected_index: 3}, ctx)

    assert {%State{selected_index: 0}, []} = DoorList.update({:key, %{key: :up}}, state, ctx)
  end

  test "enter opens a launch confirmation modal instead of spawning from reducer" do
    ctx = context()
    state = DoorList.init(ctx)

    assert {^state, [%Effect{type: :modal, payload: {:open, %Modal{type: :confirm} = modal}}]} =
             DoorList.update({:key, %{key: :enter}}, state, ctx)

    assert modal.message =~ "Launch Native Hello?"
  end

  test "modal submit emits explicit launch_door effect for selected visible door" do
    ctx = context()
    state = DoorList.init(ctx)

    assert {%State{status_message: message}, effects} =
             DoorList.update(
               {:modal_submit, :launch_door, %{door_id: "external-echo"}},
               state,
               ctx
             )

    assert message == "Launching External Echo. The door has the terminal until it exits."
    assert Enum.any?(effects, &match?(%Effect{type: :door, payload: %{action: :launch}}, &1))
    refute Enum.any?(effects, &match?(%Effect{type: :modal}, &1))
  end

  test "q returns to main menu" do
    ctx = context()
    state = DoorList.init(ctx)

    assert {^state, [%Effect{type: :navigate, payload: %{screen: :main_menu}}]} =
             DoorList.update({:key, %{key: :char, char: "q"}}, state, ctx)
  end

  test "door intro stays bounded and preserves controls at supported breakpoints" do
    for {width, height} = size <- [{64, 22}, {80, 24}, {100, 30}] do
      ascii =
        :door_list
        |> RenderFixtures.state_for(size)
        |> App.view()
        |> AsciiRenderer.render(size)

      lines = String.split(ascii, "\n", trim: false)

      assert length(lines) == height
      assert Enum.all?(lines, &(TextWidth.display_width(&1) <= width))

      choose_line = Enum.find_index(lines, &String.contains?(&1, "Choose a door game."))
      warning_line = Enum.find_index(lines, &String.contains?(&1, "return here."))
      selected_line = Enum.find_index(lines, &String.contains?(&1, "> Native Hello"))
      status_line = Enum.find_index(lines, &String.contains?(&1, "Enter Launch  Q Back"))
      command_line = Enum.find_index(lines, &String.contains?(&1, "Enter Launch"))

      assert is_integer(choose_line), "missing intro lead line at #{width}x#{height}:\n#{ascii}"

      assert is_integer(warning_line),
             "missing complete door warning at #{width}x#{height}:\n#{ascii}"

      assert warning_line == choose_line + 1

      assert is_integer(selected_line),
             "missing selected door row at #{width}x#{height}:\n#{ascii}"

      assert selected_line > warning_line

      assert is_integer(status_line),
             "missing in-body status hints at #{width}x#{height}:\n#{ascii}"

      assert is_integer(command_line),
             "missing command bar launch hint at #{width}x#{height}:\n#{ascii}"

      refute String.contains?(ascii, "then ret\n"), "warning should not be silently clipped"
    end
  end
end
