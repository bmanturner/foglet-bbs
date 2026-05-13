defmodule Foglet.Accounts.IdentityPolicyTest do
  use FogletBbs.DataCase, async: false

  alias Foglet.Accounts
  alias Foglet.Accounts.IdentityPolicy
  alias Foglet.TUI.Screens.Sysop.AccessRulesView
  alias FogletBbs.AccountsFixtures

  describe "registration identity policy" do
    test "blocks reserved and banned handles case-insensitively with terse errors" do
      {:ok, _} =
        IdentityPolicy.create_rule(%{kind: :reserved_handle, value: "SysOp", reason: "system"})

      {:ok, _} =
        IdentityPolicy.create_rule(%{kind: :banned_handle, value: "Griefer", reason: "abuse"})

      for handle <- ["sysop", "GRIEFER"] do
        attrs =
          AccountsFixtures.valid_user_attributes(%{
            handle: handle,
            email: "#{handle}@example.com"
          })

        assert {:error, changeset} = Accounts.register_user(attrs)
        assert %{handle: ["is unavailable"]} = errors_on(changeset)
        refute inspect(changeset) =~ "SysOp"
        refute inspect(changeset) =~ "Griefer"
      end
    end

    test "blocks exact banned email case-insensitively" do
      {:ok, _} =
        IdentityPolicy.create_rule(%{
          kind: :banned_email,
          value: "Blocked@Example.COM",
          reason: "abuse"
        })

      attrs =
        AccountsFixtures.valid_user_attributes(%{
          handle: "newuser",
          email: " blocked@example.com "
        })

      assert {:error, changeset} = Accounts.register_user(attrs)
      assert %{email: ["is unavailable"]} = errors_on(changeset)
    end

    test "blocks banned domains including subdomains without suffix bypasses" do
      {:ok, _} =
        IdentityPolicy.create_rule(%{
          kind: :banned_email_domain,
          value: "example.com",
          reason: "abuse"
        })

      for {email, blocked?} <- [
            {"person@example.com", true},
            {"person@mail.example.com", true},
            {"person@badexample.com", false}
          ] do
        attrs =
          AccountsFixtures.valid_user_attributes(%{
            handle: String.replace(email, ~r/[^a-z]/, "") |> String.slice(0, 20),
            email: email
          })

        if blocked? do
          assert {:error, changeset} = Accounts.register_user(attrs)
          assert %{email: ["is unavailable"]} = errors_on(changeset)
        else
          assert {:ok, _user} = Accounts.register_user(attrs)
        end
      end
    end

    test "ignores disabled rules" do
      {:ok, rule} =
        IdentityPolicy.create_rule(%{kind: :banned_handle, value: "paused", reason: "old"})

      {:ok, _} = IdentityPolicy.disable_rule(rule.id)

      attrs =
        AccountsFixtures.valid_user_attributes(%{handle: "paused", email: "paused@example.com"})

      assert {:ok, _user} = Accounts.register_user(attrs)
    end
  end

  describe "rule management" do
    test "actor-aware public boundary forbids non-sysops from mutating identity rules" do
      actor = AccountsFixtures.user_fixture(%{handle: "regular", email: "regular@example.com"})

      assert {:error, :forbidden} =
               Accounts.create_identity_rule(actor, %{
                 kind: :banned_email_domain,
                 value: "blocked.example",
                 reason: "qa"
               })

      assert [] = IdentityPolicy.list_rules()

      {:ok, rule} =
        IdentityPolicy.create_rule(%{
          kind: :banned_email_domain,
          value: "existing.example",
          reason: "trusted setup"
        })

      assert {:error, :forbidden} = Accounts.disable_identity_rule(actor, rule.id)
      assert {:error, :forbidden} = Accounts.enable_identity_rule(actor, rule.id)
      assert {:error, :forbidden} = Accounts.remove_identity_rule(actor, rule.id)
      assert [%{id: id, enabled: true}] = IdentityPolicy.list_rules()
      assert id == rule.id
    end

    test "ACCESS TUI identity mutations use actor-aware authorization" do
      actor = AccountsFixtures.user_fixture(%{handle: "tuiuser", email: "tuiuser@example.com"})

      state = %AccessRulesView{
        current_user: actor,
        section: :identity,
        identity_form_mode: :banned_email_domain,
        identity_draft: %{
          "value" => "tui-bypass.example",
          "reason" => "qa",
          "comment" => ""
        }
      }

      {_state, [effect]} = AccessRulesView.handle_key(%{key: :enter}, state)

      assert {:error, :forbidden} = effect.payload.fun.()
      assert [] = IdentityPolicy.list_rules()
    end

    test "normalizes values and rejects malformed domains" do
      assert {:ok, rule} =
               IdentityPolicy.create_rule(%{
                 kind: "banned_email",
                 value: "  USER@Example.COM ",
                 reason: "abuse"
               })

      assert rule.normalized_value == "user@example.com"

      assert {:error, changeset} =
               IdentityPolicy.create_rule(%{
                 kind: :banned_email_domain,
                 value: "bad domain",
                 reason: "oops"
               })

      assert %{value: [_]} = errors_on(changeset)
    end

    test "reports conflicts without mutating matching existing users" do
      user = AccountsFixtures.user_fixture(%{handle: "Legacy", email: "legacy@example.com"})

      {:ok, rule} =
        IdentityPolicy.create_rule(%{
          kind: :banned_email_domain,
          value: "example.com",
          reason: "cleanup"
        })

      conflicts = IdentityPolicy.conflicts_for_rule(rule)

      assert [%{id: id, handle: "Legacy", email: "legacy@example.com"}] = conflicts
      assert id == user.id
      assert Accounts.get_user!(user.id).status == :active
    end
  end
end
