defmodule Foglet.TUI.BufferSnapshotTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.Test

  @clock ~U[2026-01-01 17:43:00Z]
  @size [width: 64, height: 22]

  setup_all do
    {:ok, _} = Application.ensure_all_started(:tzdata)
    :ok
  end

  test "door list default fixture matches the full buffer snapshot" do
    assert_screen(render_fixture(:door_list, fixture_opts()), ~B"""
    ┌ Foglet ▸ Door Games ───────────────────────── @alice | 11:43 ┐
    │Choose a door game.                                           │
    │Doors may take over the terminal, then return here.           │
    │                                                              │
    │> Usurper Reborn — Game                                       │
    │                                                              │
    │Enter Launch  Q Back                                          │
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
    │                                                              │
    │                                                              │
    │                                                              │
    └ Q Back  ↑/↓ Select   Enter Launch ───────────────────────────┘
    """)
  end

  test "main menu default fixture matches the full buffer snapshot" do
    assert_screen(render_fixture(:main_menu, fixture_opts()), ~B"""
    ┌ Foglet ▸ Home ─────────────────────────────── @alice | 11:43 ┐
    │┌─ Navigation ─────────┐ ┌─ Oneliners ───────────────────────┐│
    ││ ● Boards          [B]│ │> @unknown  Welcome to Foglet      ││
    ││ ✎ Compose         [C]│ │  @unknown  New thread in /ge      ││
    ││ ✉ Inbox       [3] [I]│ │                                   ││
    ││ ✉ BBS Mail        [L]│ │                                   ││
    ││ ◌ Online Now (0)  [N]│ │                                   ││
    ││ ▸ Door Games      [D]│ │                                   ││
    ││ ◇ Account         [A]│ │                                   ││
    ││ ⚑ Moderation      [M]│ │                                   ││
    ││ ▣ Sysop           [S]│ │                                   ││
    ││ ↯ Logout          [Q]│ │                                   ││
    ││                      │ │                                   ││
    ││                      │ │                                   ││
    ││                      │ │                                   ││
    ││                      │ │                                   ││
    ││                      │ │                                   ││
    ││                      │ │                                   ││
    ││                      │ │                                   ││
    ││                      │ │                                   ││
    │└──────────────────────┘ └───────────────────────────────────┘│
    └ H Hide oneliner  ! Report  O Oneliner   ↑/↓ Select ──────────┘
    """)
  end

  test "board list default fixture matches the full buffer snapshot" do
    assert_screen(render_fixture(:board_list, fixture_opts()), ~B"""
    ┌ Foglet ▸ Boards ───────────────────────────── @alice | 11:43 ┐
    │▾ main                                                        │
    │▌ ◆✓    general                                 3 unread  2w  │
    │  ✓     tech                                    all read  2w  │
    │  ◆✓    lounge                                  1 unread  2w  │
    │general • subscribed • 3 unread • 2w ago                      │
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
    │                                                              │
    │                                                              │
    │                                                              │
    │                                                              │
    └ Q Back   Enter Open  ↑/↓ Select   s/u Sub/Unsub ─────────────┘
    """)
  end

  defp fixture_opts do
    Keyword.merge(@size, seed_state: %{"session_context" => %{"clock_now" => @clock}})
  end
end
