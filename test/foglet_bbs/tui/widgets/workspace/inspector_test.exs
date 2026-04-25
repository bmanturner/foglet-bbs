defmodule Foglet.TUI.Widgets.Workspace.InspectorTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.WidgetHelpers,
    only: [color_atom_leaked?: 2, color_names: 0, flatten_text: 1]

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Workspace.Inspector

  setup do
    %{theme: Theme.default()}
  end

  describe "render/2 wide selection details" do
    test "renders board details and supplied actions", %{theme: theme} do
      flat = board_selection() |> Inspector.render(theme: theme, width: 132) |> flatten_text()

      assert flat =~ "Board"
      assert flat =~ "Name"
      assert flat =~ "Slug"
      assert flat =~ "Category"
      assert flat =~ "Posting"
      assert flat =~ "Edit"
      assert flat =~ "Archive"
    end

    test "renders user details and supplied actions", %{theme: theme} do
      flat = user_selection() |> Inspector.render(theme: theme, width: 132) |> flatten_text()

      assert flat =~ "User"
      assert flat =~ "Handle"
      assert flat =~ "Email"
      assert flat =~ "Status"
      assert flat =~ "Role"
      assert flat =~ "Suspend"
      refute flat =~ "Archive"
    end

    test "renders invite details and supplied actions", %{theme: theme} do
      flat = invite_selection() |> Inspector.render(theme: theme, width: 132) |> flatten_text()

      assert flat =~ "Invite"
      assert flat =~ "Code"
      assert flat =~ "Issuer"
      assert flat =~ "Revoke"
      refute flat =~ "Suspend"
    end

    test "renders no-selection state at wide width", %{theme: theme} do
      assert Inspector.render(nil, theme: theme, width: 132) |> flatten_text() == "No selection"
    end
  end

  describe "render/2 compact collapse" do
    test "collapses below wide-terminal threshold", %{theme: theme} do
      assert Inspector.render(board_selection(), theme: theme, width: 64) |> flatten_text() == ""
      assert Inspector.render(board_selection(), theme: theme, width: 80) |> flatten_text() == ""
    end
  end

  describe "theme hygiene" do
    test "does not leak hardcoded terminal color atoms", %{theme: theme} do
      serialized =
        board_selection()
        |> Inspector.render(theme: theme, width: 132)
        |> inspect(printable_limit: :infinity, limit: :infinity)

      for color <- color_names() do
        refute color_atom_leaked?(serialized, color), "leaked :#{color} atom"
      end
    end
  end

  defp board_selection do
    %{
      title: "Board",
      details: [
        %{label: "Name", value: "General"},
        %{label: "Slug", value: "general"},
        %{label: "Category", value: "Main"},
        %{label: "Posting", value: "open"}
      ],
      actions: [
        %{key: "E", label: "Edit", role: :accent},
        %{key: "A", label: "Archive", role: :destructive}
      ]
    }
  end

  defp user_selection do
    %{
      title: "User",
      details: [
        %{label: "Handle", value: "alice"},
        %{label: "Email", value: "alice@example.test"},
        %{label: "Status", value: "pending"},
        %{label: "Role", value: "moderator"}
      ],
      actions: [
        %{key: "S", label: "Suspend", role: :destructive}
      ]
    }
  end

  defp invite_selection do
    %{
      title: "Invite",
      details: [
        %{label: "Code", value: "INVITE1"},
        %{label: "Status", value: "pending"},
        %{label: "Issuer", value: "alice"},
        %{label: "Inserted", value: "2026-04-25"}
      ],
      actions: [
        %{key: "R", label: "Revoke", role: :destructive}
      ]
    }
  end
end
