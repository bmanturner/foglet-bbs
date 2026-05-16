defmodule Foglet.TUI.Screens.DoorListTest do
  use ExUnit.Case, async: false

  import Foglet.TUI.Test

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

  @demo_doors_env "FOGLET_ENABLE_DEMO_DOORS"
  @manifest_dir_env "FOGLET_DOOR_MANIFEST_DIR"
  @clock ~U[2026-01-01 17:43:00Z]

  defmodule EmptyDoors do
    @moduledoc false
    def list_browsable(_user), do: []
    def get_visible(_user, _door_id), do: {:error, :not_found}
  end

  setup_all do
    Config.init_cache()

    Enum.each(Foglet.Config.Schema.defaults(), fn {key, value} ->
      :ets.insert(:foglet_config, {key, value})
    end)

    {:ok, _} = Application.ensure_all_started(:tzdata)
    :ok
  end

  setup do
    original = System.get_env(@demo_doors_env)
    original_manifest_dir = System.get_env(@manifest_dir_env)
    original_app_manifest_dir = Application.get_env(:foglet_bbs, :door_manifest_dir)

    System.delete_env(@demo_doors_env)
    System.delete_env(@manifest_dir_env)
    Application.delete_env(:foglet_bbs, :door_manifest_dir)

    on_exit(fn ->
      restore_env(@demo_doors_env, original)
      restore_env(@manifest_dir_env, original_manifest_dir)
      restore_app_env(:door_manifest_dir, original_app_manifest_dir)
    end)

    :ok
  end

  defp user(role \\ :user) do
    %User{
      id: "u1",
      handle: "alice",
      role: role,
      status: :active,
      timezone: "America/Chicago",
      preferences: %{"time_format" => "24h"}
    }
  end

  defp context(opts \\ []) do
    Context.new(
      current_user: Keyword.get(opts, :user, user()),
      session_context: %{theme: Foglet.TUI.Theme.default(), clock_now: @clock},
      terminal_size: Keyword.get(opts, :terminal_size, {80, 24}),
      route: :door_list,
      domain: Keyword.get(opts, :domain, %{})
    )
  end

  test "init lists bundled production manifests by default" do
    assert %State{doors: doors, selected_index: 0} = DoorList.init(context())
    assert Enum.map(doors, & &1.id) == ["usurper-reborn"]
    assert Enum.all?(doors, &match?(%Manifest{}, &1))
  end

  test "init has an empty production catalog when operator manifest directory is disabled" do
    Application.put_env(:foglet_bbs, :door_manifest_dir, "")

    assert %State{doors: [], selected_index: 0} = DoorList.init(context())
  end

  test "init supports an explicitly configured operator manifest directory" do
    configure_bundled_manifest_dir!()

    assert %State{doors: doors, selected_index: 0} = DoorList.init(context())
    assert Enum.map(doors, & &1.id) == ["usurper-reborn"]
    assert Enum.all?(doors, &match?(%Manifest{}, &1))
  end

  test "init lists launchable built-in native and external demo doors when enabled" do
    enable_demo_doors()

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
    enable_demo_doors()

    ctx = context()
    state = DoorList.init(ctx)

    assert {%State{selected_index: 1}, []} = DoorList.update({:key, %{key: :down}}, state, ctx)

    assert {%State{selected_index: 2}, []} =
             DoorList.update({:key, %{key: :char, char: "j"}}, %{state | selected_index: 1}, ctx)

    assert {%State{selected_index: 3}, []} =
             DoorList.update({:key, %{key: :down}}, %{state | selected_index: 3}, ctx)

    assert {%State{selected_index: 3}, []} =
             DoorList.update({:key, %{key: :char, char: "j"}}, %{state | selected_index: 3}, ctx)

    assert {%State{selected_index: 2}, []} =
             DoorList.update({:key, %{key: :char, char: "k"}}, %{state | selected_index: 3}, ctx)

    assert {%State{selected_index: 0}, []} = DoorList.update({:key, %{key: :up}}, state, ctx)
  end

  test "enter opens a launch confirmation modal instead of spawning from reducer" do
    enable_demo_doors()

    ctx = context()
    state = DoorList.init(ctx)

    assert {^state, [%Effect{type: :modal, payload: {:open, %Modal{type: :confirm} = modal}}]} =
             DoorList.update({:key, %{key: :enter}}, state, ctx)

    assert modal.message =~ "Launch Native Hello?"
  end

  test "modal submit emits explicit launch_door effect for selected visible door" do
    enable_demo_doors()

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
    enable_demo_doors()

    ctx = context()
    state = DoorList.init(ctx)

    assert {^state, [%Effect{type: :navigate, payload: %{screen: :main_menu}}]} =
             DoorList.update({:key, %{key: :char, char: "q"}}, state, ctx)
  end

  test "door intro stays bounded and preserves controls at supported breakpoints" do
    enable_demo_doors()

    for {width, height} = size <- [{64, 22}, {80, 24}, {100, 30}, {120, 36}] do
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

      forbidden = [
        "native elixir",
        "external pty",
        "classic dropfile",
        "DOOR32",
        "SQLite",
        "CHAIN.TXT",
        "DOOR.SYS",
        "DORINFO.DEF"
      ]

      for term <- forbidden do
        refute String.contains?(ascii, term),
               "member-facing Door Games render leaked #{inspect(term)} at #{width}x#{height}:\n#{ascii}"
      end
    end
  end

  test "empty catalog fallback has no launch affordance and enter is inert" do
    ctx = context(domain: %{doors: EmptyDoors})
    state = DoorList.init(ctx)

    assert {^state, []} = DoorList.update({:key, %{key: :enter}}, state, ctx)

    assert_screen(render_screen(DoorList, state, context: ctx, width: 64, height: 22), ~B"""
    ┌ Foglet ▸ Door Games ───────────────────────── @alice | 11:43 ┐
    │Choose a door game.                                           │
    │Doors may take over the terminal, then return here.           │
    │                                                              │
    │┌────────────────────────────────────────────────────────────┐│
    ││No door games are available right now.                      ││
    ││Check back later.                                           ││
    │└────────────────────────────────────────────────────────────┘│
    │                                                              │
    │Q Back                                                        │
    │                                                              │
    │                                                              │
    │                                                              │
    │                                                              │
    │                                                              │
    │                                                              │
    │                                                              │
    │                                                              │
    │                                                              │
    │                                                              │
    │                                                              │
    └ Q Back ──────────────────────────────────────────────────────┘
    """)
  end

  defp enable_demo_doors do
    Application.put_env(:foglet_bbs, :door_manifest_dir, "")
    System.put_env(@demo_doors_env, "true")
  end

  defp configure_bundled_manifest_dir! do
    {:ok, priv_dir} = priv_dir()
    Application.put_env(:foglet_bbs, :door_manifest_dir, Path.join(priv_dir, "doors/manifests"))
  end

  defp priv_dir do
    case :code.priv_dir(:foglet_bbs) do
      path when is_list(path) -> {:ok, List.to_string(path)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)

  defp restore_app_env(key, nil), do: Application.delete_env(:foglet_bbs, key)
  defp restore_app_env(key, value), do: Application.put_env(:foglet_bbs, key, value)
end
