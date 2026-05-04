defmodule Foglet.TUI.Screens.Shared.InvitesSurfaceTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.RenderHelpers

  alias Foglet.TUI.Screens.Shared.InvitesState
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

  describe "visible?/3" do
    test "hides every role in open registration mode" do
      for role <- [:sysop, :mod, :user], policy <- ["sysop_only", "mods", "any_user", nil] do
        refute InvitesSurface.visible?(%{role: role}, policy, "open")
      end
    end

    test "returns true for role :sysop in invite-backed modes when policy is configured" do
      for mode <- ["invite_only", "sysop_approved"],
          policy <- ["sysop_only", "mods", "any_user"] do
        assert InvitesSurface.visible?(%{role: :sysop}, policy, mode)
      end
    end

    test "returns false for sysop in invite-backed modes when policy is unavailable" do
      refute InvitesSurface.visible?(%{role: :sysop}, nil, "invite_only")
    end

    test "returns true for role :mod when policy is \"mods\" and registration is invite-backed" do
      assert InvitesSurface.visible?(%{role: :mod}, "mods", "invite_only")
      assert InvitesSurface.visible?(%{role: :mod}, "mods", "sysop_approved")
    end

    test "returns true for role :user when policy is \"any_user\" and registration is invite-backed" do
      assert InvitesSurface.visible?(%{role: :user}, "any_user", "invite_only")
      assert InvitesSurface.visible?(%{role: :user}, "any_user", "sysop_approved")
    end

    test "returns false for role :user when policy is \"sysop_only\"" do
      refute InvitesSurface.visible?(%{role: :user}, "sysop_only", "invite_only")
    end

    test "returns false for role :mod when policy is \"sysop_only\"" do
      refute InvitesSurface.visible?(%{role: :mod}, "sysop_only", "invite_only")
    end

    test "returns false when user is nil" do
      refute InvitesSurface.visible?(nil, "any_user", "invite_only")
      refute InvitesSurface.visible?(nil, "mods", "invite_only")
      refute InvitesSurface.visible?(nil, nil, "invite_only")
    end

    test "returns false for unknown role/policy/mode combinations" do
      refute InvitesSurface.visible?(%{role: :user}, "mods", "invite_only")
      refute InvitesSurface.visible?(%{role: :mod}, "any_user", "invite_only")
      refute InvitesSurface.visible?(%{role: :user}, nil, "invite_only")
      refute InvitesSurface.visible?(%{role: :sysop}, "sysop_only", nil)
      refute InvitesSurface.visible?(%{role: :sysop}, "sysop_only", "disabled")
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

      assert String.contains?(
               joined,
               "No invites yet. Generate one when someone is ready to join."
             )

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

      # FOG-130 Item 5: detail labels are user-friendly, not schema names.
      assert String.contains?(joined, "AVAILABLECODE001")
      assert String.contains?(joined, "issued by: issuer-1")
      assert String.contains?(joined, "issued: 2026-04-24 01:00:00Z")
      assert String.contains?(joined, "available")
      assert String.contains?(joined, "CONSUMEDCODE001")
      assert String.contains?(joined, "consumed")
      assert String.contains?(joined, "used: 2026-04-24 01:05:00Z")
      assert String.contains?(joined, "used by: consumer-1")
      assert String.contains?(joined, "REVOKEDCODE001")
      assert String.contains?(joined, "revoked")
      assert String.contains?(joined, "revoked: 2026-04-24 01:10:00Z")
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

      assert String.contains?(joined, "Invite code ready: NEWCODE001")
      assert String.contains?(joined, "Invite generation limit reached.")
      assert String.contains?(joined, "G Generate")
      assert String.contains?(joined, "R Refresh")
      assert String.contains?(joined, "D Revoke")
      assert String.contains?(joined, "↑/↓ Select")
    end
  end

  # ---------------------------------------------------------------------------
  # INVITES focused-row highlight (D-24, SYSOP-06, Phase 29 Plan 04)
  # ---------------------------------------------------------------------------

  describe "INVITES focused-row highlight (D-24, SYSOP-06)" do
    @describetag :invites_focus_highlight

    setup do
      theme = Theme.default()

      items = [
        %{
          code: "ALPHACODE0001",
          status: :unused,
          issuer_id: "issuer-1",
          inserted_at: ~U[2026-04-24 01:00:00Z],
          consumed_at: nil,
          consumed_by_user_id: nil,
          revoked_at: nil
        },
        %{
          code: "BETACODE00002",
          status: :unused,
          issuer_id: "issuer-2",
          inserted_at: ~U[2026-04-24 01:00:00Z],
          consumed_at: nil,
          consumed_by_user_id: nil,
          revoked_at: nil
        },
        %{
          code: "GAMMACODE0003",
          status: :unused,
          issuer_id: "issuer-3",
          inserted_at: ~U[2026-04-24 01:00:00Z],
          consumed_at: nil,
          consumed_by_user_id: nil,
          revoked_at: nil
        }
      ]

      %{theme: theme, items: items}
    end

    test "at 80×24, focused-row tokens carry theme.selected styling and unfocused rows do not",
         %{theme: theme, items: items} do
      # InvitesState rendering path — what the live Sysop INVITES tab uses.
      state = InvitesState.new(items: items, selected_index: 1)

      tree = InvitesSurface.render(state, theme)

      # Walk the rendered tree and find every text node with the row's code.
      # Focused row (index 1, code "BETACODE...") should have :fg/:bg matching
      # the theme.selected slot; unfocused rows (ALPHA / GAMMA) should not.
      focus_codes = ["ALPHACODE0001", "BETACODE00002", "GAMMACODE0003"]

      tokens_by_code =
        for code <- focus_codes, into: %{} do
          {code, find_text_nodes_containing(tree, code)}
        end

      # Every code's row must produce at least one matching text token.
      for {code, nodes} <- tokens_by_code do
        assert nodes != [],
               "Expected at least one rendered text node containing #{inspect(code)}; tree=#{inspect(tree, limit: :infinity, printable_limit: :infinity)}"
      end

      focused_nodes = Map.fetch!(tokens_by_code, "BETACODE00002")
      unfocused_alpha = Map.fetch!(tokens_by_code, "ALPHACODE0001")
      unfocused_gamma = Map.fetch!(tokens_by_code, "GAMMACODE0003")

      assert Enum.any?(focused_nodes, &has_selected_styling?(&1, theme)),
             "Expected focused row (BETA) to carry theme.selected.fg/bg; got #{inspect(focused_nodes)}"

      refute Enum.any?(unfocused_alpha, &has_selected_styling?(&1, theme)),
             "Expected unfocused row (ALPHA) NOT to carry theme.selected.fg/bg; got #{inspect(unfocused_alpha)}"

      refute Enum.any?(unfocused_gamma, &has_selected_styling?(&1, theme)),
             "Expected unfocused row (GAMMA) NOT to carry theme.selected.fg/bg; got #{inspect(unfocused_gamma)}"
    end

    test "at 80×24, the focused row preserves the row's value text (no truncation regression)",
         %{theme: theme, items: items} do
      state = InvitesState.new(items: items, selected_index: 1)
      tree = InvitesSurface.render(state, theme)
      joined = tree |> collect_text_values() |> Enum.join(" ")

      assert String.contains?(joined, "BETACODE00002")
    end

    test "no leading marker (▸) is rendered on focused INVITES row (D-24 explicit rejection)" do
      contents = File.read!("lib/foglet_bbs/tui/screens/shared/invites_surface.ex")

      refute String.contains?(contents, "▸"),
             "D-24 explicitly rejects a leading marker on focused INVITES rows"
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

  # ---------------------------------------------------------------------------
  # Private helpers — focus-highlight tree walkers
  # ---------------------------------------------------------------------------

  # Walks the Raxol render tree and returns every :text node whose :content
  # contains the given substring. Returns the full node maps so callers can
  # inspect the :fg / :bg / :style fields populated by Components.Text.new/2.
  defp find_text_nodes_containing(tree, substring) do
    tree |> collect_text_nodes([]) |> Enum.filter(&node_contains?(&1, substring))
  end

  defp collect_text_nodes(node, acc) when is_map(node) do
    acc =
      case Map.get(node, :type) do
        :text -> [node | acc]
        _ -> acc
      end

    node |> Map.get(:children, []) |> collect_text_nodes(acc)
  end

  defp collect_text_nodes(nodes, acc) when is_list(nodes) do
    Enum.reduce(nodes, acc, fn n, a -> collect_text_nodes(n, a) end)
  end

  defp collect_text_nodes(_other, acc), do: acc

  defp node_contains?(%{content: c}, substring) when is_binary(c),
    do: String.contains?(c, substring)

  defp node_contains?(_, _), do: false

  # A text node is "selected-styled" when EITHER its :fg matches
  # theme.selected.fg or its :bg matches theme.selected.bg. This mirrors
  # the UsersView idiom at users_view.ex:193-194 which sets BOTH fg and bg.
  defp has_selected_styling?(node, %Theme{} = theme) do
    sel_fg = theme.selected.fg
    sel_bg = theme.selected.bg
    Map.get(node, :fg) == sel_fg or Map.get(node, :bg) == sel_bg
  end
end
