defmodule Foglet.TUI.Screens.Shared.InvitesSurfaceTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Screens.Shared.InvitesSurface
  alias Foglet.TUI.Theme

  defp collect_text_values(node, acc \\ [])

  defp collect_text_values(node, acc) when is_map(node) do
    acc =
      case Map.get(node, :type) do
        :text ->
          content = Map.get(node, :content)

          if is_binary(content) do
            [content | acc]
          else
            acc
          end

        _ ->
          acc
      end

    node
    |> Map.get(:children, [])
    |> collect_text_values(acc)
  end

  defp collect_text_values(nodes, acc) when is_list(nodes) do
    Enum.reduce(nodes, acc, fn node, text_acc -> collect_text_values(node, text_acc) end)
  end

  test "title/0 returns \"INVITES\"" do
    assert InvitesSurface.title() == "INVITES"
  end

  test "default_state/0 returns a struct with items: [] (placeholder, not loading)" do
    state = InvitesSurface.default_state()
    # items: [] = placeholder branch (not nil = loading branch) per D-12
    assert state.items == []
  end

  describe "visible?/2" do
    test "returns true for role :sysop regardless of policy" do
      user = %Foglet.Accounts.User{id: "u1", handle: "alice", role: :sysop}
      assert InvitesSurface.visible?(user, "sysop_only")
      assert InvitesSurface.visible?(user, "mods")
      assert InvitesSurface.visible?(user, "any_user")
    end

    test "returns true for role :mod when policy is \"mods\"" do
      user = %Foglet.Accounts.User{id: "u2", handle: "bob", role: :mod}
      assert InvitesSurface.visible?(user, "mods")
    end

    test "returns true for role :user when policy is \"any_user\"" do
      user = %Foglet.Accounts.User{id: "u3", handle: "carol", role: :user}
      assert InvitesSurface.visible?(user, "any_user")
    end

    test "returns false for role :user when policy is \"sysop_only\"" do
      user = %Foglet.Accounts.User{id: "u3", handle: "carol", role: :user}
      refute InvitesSurface.visible?(user, "sysop_only")
    end

    test "returns false for role :mod when policy is \"sysop_only\"" do
      user = %Foglet.Accounts.User{id: "u2", handle: "bob", role: :mod}
      refute InvitesSurface.visible?(user, "sysop_only")
    end

    test "returns false when user is nil" do
      refute InvitesSurface.visible?(nil, "any_user")
      refute InvitesSurface.visible?(nil, "mods")
      refute InvitesSurface.visible?(nil, "sysop_only")
    end
  end

  describe "render/2" do
    test "with %{items: nil} state renders loading branch" do
      state = %{items: nil}
      theme = Theme.default()
      result = InvitesSurface.render(state, theme: theme)
      flat = collect_text_values(result)

      assert Enum.any?(flat, &String.contains?(&1, "Loading")),
             "Expected 'Loading' in render output for nil items. Got: #{inspect(flat)}"
    end

    test "with %{items: []} state renders placeholder copy that is obviously scaffold-only" do
      state = %{items: []}
      theme = Theme.default()
      result = InvitesSurface.render(state, theme: theme)
      flat = collect_text_values(result)
      scaffold_indicators = ["scaffold", "not yet", "later phase"]

      assert Enum.any?(flat, fn text ->
               Enum.any?(scaffold_indicators, &String.contains?(text, &1))
             end),
             "Expected one of #{inspect(scaffold_indicators)} in placeholder render. Got: #{inspect(flat)}"
    end

    test "with %{items: [_|_]} state does NOT crash (future-facing)" do
      state = %{items: [%{code: "XYZ"}]}
      theme = Theme.default()
      result = InvitesSurface.render(state, theme: theme)

      assert is_map(result) or is_list(result),
             "Expected render/2 to return a map or list without raising"
    end
  end

  test "InvitesSurface defines no fake generate/revoke functions" do
    refute function_exported?(InvitesSurface, :generate_invite, 1),
           "InvitesSurface must not export generate_invite/1 in Phase 0"

    refute function_exported?(InvitesSurface, :revoke_invite, 1),
           "InvitesSurface must not export revoke_invite/1 in Phase 0"

    refute function_exported?(InvitesSurface, :save_invite, 1),
           "InvitesSurface must not export save_invite/1 in Phase 0"
  end
end
