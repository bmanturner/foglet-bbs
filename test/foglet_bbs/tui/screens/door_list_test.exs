defmodule Foglet.TUI.Screens.DoorListTest do
  use ExUnit.Case, async: true

  alias Foglet.Accounts.User
  alias Foglet.Doors.Manifest
  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Modal
  alias Foglet.TUI.Screens.DoorList
  alias Foglet.TUI.Screens.DoorList.State

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
    assert Enum.map(doors, & &1.id) == ["native-hello", "external-echo"]
    assert Enum.all?(doors, &match?(%Manifest{}, &1))
  end

  test "up/down clamps selection to available doors" do
    ctx = context()
    state = DoorList.init(ctx)

    assert {%State{selected_index: 1}, []} = DoorList.update({:key, %{key: :down}}, state, ctx)

    assert {%State{selected_index: 1}, []} =
             DoorList.update({:key, %{key: :down}}, %{state | selected_index: 1}, ctx)

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

    assert message == "Launched External Echo. You are back in Foglet."
    assert Enum.any?(effects, &match?(%Effect{type: :door, payload: %{action: :launch}}, &1))

    assert Enum.any?(
             effects,
             &match?(%Effect{type: :modal, payload: {:open, %Modal{type: :info}}}, &1)
           )
  end

  test "q returns to main menu" do
    ctx = context()
    state = DoorList.init(ctx)

    assert {^state, [%Effect{type: :navigate, payload: %{screen: :main_menu}}]} =
             DoorList.update({:key, %{key: :char, char: "q"}}, state, ctx)
  end
end
