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
    test "returns an unloaded live invite state" do
      state = InvitesSurface.default_state()
      assert %{items: nil, selected_index: 0, error: nil, last_generated_code: nil} = state
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

    test "with %{items: []} state renders an empty invite list", %{theme: theme} do
      result = InvitesSurface.render(%{items: []}, theme)
      flat = collect_text_values(result)
      joined = Enum.join(flat, " ")

      assert String.contains?(joined, "No invites issued yet.")
      assert String.contains?(joined, "G Generate")
      assert String.contains?(joined, "R Refresh")
      assert String.contains?(joined, "D Revoke")
      assert String.contains?(joined, "↑/↓ Select")
    end

    test "with live rows renders available consumed revoked lifecycle fields", %{theme: theme} do
      inserted_at = ~U[2026-04-24 01:00:00Z]
      consumed_at = ~U[2026-04-24 01:05:00Z]
      revoked_at = ~U[2026-04-24 01:10:00Z]

      result =
        InvitesSurface.render(
          %{
            items: [
              %{
                code: "AVAILABLECODE001",
                issuer_id: "issuer-1",
                inserted_at: inserted_at,
                consumed_at: nil,
                consumed_by_user_id: nil,
                revoked_at: nil,
                status: :available
              },
              %{
                code: "CONSUMEDCODE001",
                issuer_id: "issuer-2",
                inserted_at: inserted_at,
                consumed_at: consumed_at,
                consumed_by_user_id: "consumer-1",
                revoked_at: nil,
                status: :consumed
              },
              %{
                code: "REVOKEDCODE001",
                issuer_id: "issuer-3",
                inserted_at: inserted_at,
                consumed_at: nil,
                consumed_by_user_id: nil,
                revoked_at: revoked_at,
                status: :revoked
              }
            ],
            selected_index: 1
          },
          theme
        )

      joined = result |> collect_text_values() |> Enum.join(" ")

      assert String.contains?(joined, "AVAILABLECODE001")
      assert String.contains?(joined, "issuer_id: issuer-1")
      assert String.contains?(joined, "inserted_at: 2026-04-24 01:00:00Z")
      assert String.contains?(joined, "available")
      assert String.contains?(joined, "CONSUMEDCODE001")
      assert String.contains?(joined, "consumed")
      assert String.contains?(joined, "consumed_at: 2026-04-24 01:05:00Z")
      assert String.contains?(joined, "consumed_by_user_id: consumer-1")
      assert String.contains?(joined, "REVOKEDCODE001")
      assert String.contains?(joined, "revoked")
      assert String.contains?(joined, "revoked_at: 2026-04-24 01:10:00Z")
    end

    test "renders New invite code banner, error, and key hints", %{theme: theme} do
      result =
        InvitesSurface.render(
          %{
            items: [],
            last_generated_code: "NEWCODE001",
            error: "Invite generation limit reached."
          },
          theme
        )

      joined = result |> collect_text_values() |> Enum.join(" ")

      assert String.contains?(joined, "New invite code: NEWCODE001")
      assert String.contains?(joined, "Invite generation limit reached.")
      assert String.contains?(joined, "G Generate")
      assert String.contains?(joined, "R Refresh")
      assert String.contains?(joined, "D Revoke")
      assert String.contains?(joined, "↑/↓ Select")
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
