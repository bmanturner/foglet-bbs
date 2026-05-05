defmodule Foglet.TUI.Screens.Sysop.UsersViewTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Effect
  alias Foglet.TUI.Screens.Sysop.UsersView

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

  test "V no-ops when there is no selected row" do
    view = %UsersView{rows: [], selection_index: 0}

    assert {^view, []} = UsersView.handle_key(%{key: :char, char: "v"}, view)
  end
end
