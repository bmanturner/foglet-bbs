defmodule Foglet.TUI.Screens.Shared.InvitesSurfaceTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.RenderHelpers

  alias Foglet.TUI.Screens.Shared.InvitesSurface
  alias Foglet.TUI.Theme

  # ---------------------------------------------------------------------------
  # title/0
  # ---------------------------------------------------------------------------

  describe "title/0" do
    test "returns \"INVITES\"" do
      assert InvitesSurface.title() == "INVITES"
    end
  end

  # ---------------------------------------------------------------------------
  # default_state/0
  # ---------------------------------------------------------------------------

  describe "default_state/0" do
    test "returns a struct with items: [] (placeholder, not loading)" do
      state = InvitesSurface.default_state()
      # items: [] means placeholder branch (D-12: nil = loading, [] = scaffold)
      assert %{items: []} = state
      # Must be [] not nil — Phase 0 default is placeholder, not loading
      refute is_nil(state.items)
    end
  end

  # ---------------------------------------------------------------------------
  # visible?/2
  # ---------------------------------------------------------------------------

  describe "visible?/2" do
    test "returns true for role :sysop regardless of policy" do
      assert InvitesSurface.visible?(%{role: :sysop}, "sysop_only")
      assert InvitesSurface.visible?(%{role: :sysop}, "mods")
      assert InvitesSurface.visible?(%{role: :sysop}, "any_user")
      assert InvitesSurface.visible?(%{role: :sysop}, nil)
    end

    test "returns true for role :mod when policy is \"mods\"" do
      assert InvitesSurface.visible?(%{role: :mod}, "mods")
    end

    test "returns true for role :user when policy is \"any_user\"" do
      assert InvitesSurface.visible?(%{role: :user}, "any_user")
    end

    test "returns false for role :user when policy is \"sysop_only\"" do
      refute InvitesSurface.visible?(%{role: :user}, "sysop_only")
    end

    test "returns false for role :mod when policy is \"sysop_only\"" do
      refute InvitesSurface.visible?(%{role: :mod}, "sysop_only")
    end

    test "returns false when user is nil" do
      refute InvitesSurface.visible?(nil, "any_user")
      refute InvitesSurface.visible?(nil, "mods")
      refute InvitesSurface.visible?(nil, nil)
    end

    test "returns false for unknown role/policy combinations" do
      refute InvitesSurface.visible?(%{role: :user}, "mods")
      refute InvitesSurface.visible?(%{role: :mod}, "any_user")
      refute InvitesSurface.visible?(%{role: :user}, nil)
    end
  end

  # ---------------------------------------------------------------------------
  # render/2
  # ---------------------------------------------------------------------------

  describe "render/2" do
    setup do
      %{theme: Theme.default()}
    end

    test "with %{items: nil} state renders loading branch", %{theme: theme} do
      result = InvitesSurface.render(%{items: nil}, theme)
      flat = collect_text_values(result)

      assert Enum.any?(flat, fn t -> String.contains?(t, "Loading") end),
             "Expected loading text in: #{inspect(flat)}"
    end

    test "with %{items: []} state renders placeholder copy that is obviously scaffold-only",
         %{theme: theme} do
      result = InvitesSurface.render(%{items: []}, theme)
      flat = collect_text_values(result)
      joined = Enum.join(flat, " ")

      assert String.contains?(joined, "scaffold") or
               String.contains?(joined, "not yet") or
               String.contains?(joined, "later phase"),
             "Expected scaffold-only copy in: #{inspect(flat)}"
    end

    test "with %{items: [_|_]} state does NOT crash (future-facing)", %{theme: theme} do
      result = InvitesSurface.render(%{items: [%{code: "XYZ"}]}, theme)

      assert is_map(result) or is_list(result),
             "Expected a map or list render tree, got: #{inspect(result)}"
    end
  end

  # ---------------------------------------------------------------------------
  # Forbidden-function guard (T-00-04)
  # ---------------------------------------------------------------------------

  describe "forbidden functions" do
    test "InvitesSurface defines no fake generate/revoke/save/approve functions" do
      refute function_exported?(InvitesSurface, :generate_invite, 1)
      refute function_exported?(InvitesSurface, :revoke_invite, 1)
      refute function_exported?(InvitesSurface, :save_invite, 1)
      refute function_exported?(InvitesSurface, :approve_invite, 1)
    end
  end
end
