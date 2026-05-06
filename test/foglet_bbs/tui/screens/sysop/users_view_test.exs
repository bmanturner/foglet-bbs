defmodule Foglet.TUI.Screens.Sysop.UsersViewTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers, only: [assert_text_run: 3]

  alias Foglet.TUI.Effect
  alias Foglet.TUI.Screens.Sysop.UsersView
  alias Foglet.TUI.Theme

  defp user(attrs) do
    Map.merge(
      %{
        id: "u1",
        handle: "alice",
        email: "alice@example.test",
        role: :user,
        post_count: 0,
        inserted_at: ~U[2026-04-01 00:00:00Z]
      },
      attrs
    )
  end

  test "V opens a profile modal for the selected row without changing status" do
    view = %UsersView{
      rows: [
        {:pending, user(%{id: "u1", handle: "alice"})},
        {:active, user(%{id: "u2", handle: "bob", role: :mod, post_count: 9})}
      ],
      selection_index: 1
    }

    assert {^view, [%Effect{type: :modal, payload: {:open, modal}}]} =
             UsersView.handle_key(%{key: :char, char: "v"}, view)

    assert %Foglet.Accounts.PublicProfile{user_id: "u2", handle: "bob", role: :mod} =
             modal.message
  end

  test "render gives the selected sysop user row selected background and leaves peers plain" do
    theme = Theme.default()

    view = %UsersView{
      rows: [
        {:pending, user(%{id: "u1", handle: "alice"})},
        {:active, user(%{id: "u2", handle: "bob", role: :mod, post_count: 9})}
      ],
      selection_index: 1
    }

    tree = UsersView.render(view, theme)

    assert_text_run(tree, "@bob", fg: theme.selected.fg, bg: theme.selected.bg)
    assert_text_run(tree, "@alice", fg: theme.primary.fg)
  end

  test "V no-ops when there is no selected row" do
    view = %UsersView{rows: [], selection_index: 0}

    assert {^view, []} = UsersView.handle_key(%{key: :char, char: "v"}, view)
  end
end
