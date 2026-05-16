defmodule Foglet.TUI.Screens.Sysop.AccessRulesViewTest do
  use ExUnit.Case, async: true

  alias Foglet.Accounts.IdentityRule
  alias Foglet.SSH.AccessRule
  alias Foglet.TUI.AsciiRenderer
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Screens.Sysop.AccessRulesView
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.CommandBar

  describe "render/2" do
    test "renders loaded network and identity rules in one ACCESS policy surface" do
      state = %AccessRulesView{
        rules: [
          %AccessRule{id: 1, mode: :deny, enabled: true, address: "192.0.2.0/24", reason: "spam"}
        ],
        identity_rules: [
          %IdentityRule{
            id: 3,
            kind: :banned_email_domain,
            enabled: true,
            value: "example.com",
            reason: "abuse"
          }
        ],
        selection_index: 0,
        identity_selection_index: 0,
        allowlist_enabled?: true
      }

      assert AccessRulesView.render(state, Theme.default())
    end

    test "renders the create form with allowlist-mode lockout guidance" do
      state = %AccessRulesView{
        section: :network,
        form_mode: :create_allow,
        allowlist_enabled?: true,
        draft: %{"address" => "", "reason" => "", "comment" => ""}
      }

      assert AccessRulesView.render(state, Theme.default())
    end

    test "renders the identity create form with conflict warning guidance" do
      state = %AccessRulesView{
        section: :identity,
        identity_form_mode: :banned_email_domain,
        identity_draft: %{"value" => "example.com", "reason" => "abuse", "comment" => ""}
      }

      assert AccessRulesView.render(state, Theme.default())
    end

    test "identity list masks exact banned email values and shows conflict status" do
      state = %AccessRulesView{
        section: :identity,
        identity_rules: [
          %IdentityRule{
            id: 13,
            kind: :banned_email,
            enabled: true,
            value: "abuse@example.com",
            reason: "spam"
          }
        ]
      }

      rendered =
        state
        |> AccessRulesView.render(Theme.default(), width: 96, visible_height: 28)
        |> AsciiRenderer.render({100, 30})

      assert rendered =~ "Conflicts"
      assert rendered =~ "a***@example.com"
      assert rendered =~ "check failed"
      refute rendered =~ "abuse@example.com"
    end

    test "cramped identity list preserves active policy table and drops explanatory paragraphs" do
      state = %AccessRulesView{
        section: :identity,
        identity_rules: [
          %IdentityRule{
            id: 14,
            kind: :banned_email_domain,
            enabled: true,
            value: "example.com",
            reason: "abuse"
          }
        ]
      }

      rendered =
        state
        |> AccessRulesView.render(Theme.default(), width: 60, visible_height: 18)
        |> AsciiRenderer.render({64, 22})

      assert rendered =~ "Identity rules"
      assert rendered =~ "example.com"
      refute rendered =~ "Identity rules cover"
      refute rendered =~ "Conflict counts are sysop-only"
    end

    test "cramped identity list command bar keeps Remove before section switching" do
      groups = [
        %{label: "System", commands: [%{key: "Q", label: "Back", priority: 0}]},
        %{label: "Tabs", commands: [%{key: "←/→", label: "Tabs", priority: 10}]}
        | AccessRulesView.keybar_groups(%AccessRulesView{section: :identity})
      ]

      keybar = CommandBar.render_text(groups, width: 60)

      assert keybar =~ "A Add"
      assert keybar =~ "E Enable/disable"
      assert keybar =~ "X Remove"
      refute keybar =~ "Network/IP"
    end
  end

  describe "list key handling" do
    test "tab switches between network and identity policy sections" do
      state = %AccessRulesView{}

      {state, effects} = AccessRulesView.handle_key(%{key: :tab}, state)

      assert effects == []
      assert state.section == :identity
    end

    test "left and right switch list-mode ACCESS policy sections" do
      network_state = %AccessRulesView{section: :network}
      identity_state = %AccessRulesView{section: :identity}

      {state, effects} = AccessRulesView.handle_key(%{key: :right}, network_state)
      assert effects == []
      assert state.section == :identity

      {state, effects} = AccessRulesView.handle_key(%{key: :left}, identity_state)
      assert effects == []
      assert state.section == :network
    end

    test "toggle and remove require a second confirming keypress for network rules" do
      state = %AccessRulesView{
        section: :network,
        rules: [
          %AccessRule{id: 7, mode: :allow, enabled: true, address: "192.0.2.44", reason: "ops"}
        ],
        allowlist_enabled?: true
      }

      {warned, effects} = AccessRulesView.handle_key(%{key: :char, char: "e"}, state)
      assert effects == []
      assert warned.pending_action == {:network, :toggle, 7}

      {_confirmed, effects} = AccessRulesView.handle_key(%{key: :char, char: "e"}, warned)
      assert [%Effect{type: :task, payload: %{op: :sysop_load_access_rules}}] = effects
    end

    test "toggle and remove require a second confirming keypress for identity rules" do
      state = %AccessRulesView{
        section: :identity,
        identity_rules: [
          %IdentityRule{
            id: 11,
            kind: :reserved_handle,
            enabled: true,
            value: "admin",
            reason: "system"
          }
        ]
      }

      {warned, effects} = AccessRulesView.handle_key(%{key: :char, char: "e"}, state)
      assert effects == []
      assert warned.pending_action == {:identity, :toggle, 11}

      {_confirmed, effects} = AccessRulesView.handle_key(%{key: :char, char: "e"}, warned)
      assert [%Effect{type: :task, payload: %{op: :sysop_load_access_rules}}] = effects
    end
  end

  describe "form key handling" do
    test "q is entered as normal reason metadata while the network form owns focus" do
      state = %AccessRulesView{
        section: :network,
        form_mode: :create_allow,
        form_field: :reason,
        draft: %{"address" => "198.51.100.73", "reason" => "", "comment" => ""}
      }

      {state, effects} = AccessRulesView.handle_key(%{key: :char, char: "q"}, state)

      assert effects == []
      assert state.form_mode == :create_allow
      assert state.form_field == :reason
      assert state.draft["reason"] == "q"
    end

    test "identity add form supports tab fields, kind arrows, cancel, and submit" do
      {form, effects} =
        AccessRulesView.handle_key(%{key: :char, char: "a"}, %AccessRulesView{section: :identity})

      assert effects == []
      assert form.identity_form_mode == :reserved_handle
      assert form.identity_form_field == :kind

      {form, []} = AccessRulesView.handle_key(%{key: :right}, form)
      assert form.identity_form_mode == :banned_handle

      {form, []} = AccessRulesView.handle_key(%{key: :tab}, form)
      assert form.identity_form_field == :value

      {form, []} = AccessRulesView.handle_key(%{key: :char, char: "b"}, form)
      assert form.identity_draft["value"] == "b"

      {cancelled, []} = AccessRulesView.handle_key(%{key: :escape}, form)
      assert cancelled.identity_form_mode == nil

      {_state, effects} = AccessRulesView.handle_key(%{key: :enter}, form)
      assert [%Effect{type: :task, payload: %{op: :sysop_load_access_rules}}] = effects
    end

    test "Ctrl+S submits the network access-rule form like the advertised command bar" do
      state = %AccessRulesView{
        section: :network,
        form_mode: :create_deny,
        draft: %{"address" => "192.0.2.44", "reason" => "spam", "comment" => "manual block"}
      }

      {_state, effects} = AccessRulesView.handle_key(%{key: :char, char: "s", ctrl: true}, state)

      assert [%Effect{type: :task, payload: %{op: :sysop_load_access_rules}}] = effects
    end

    test "Ctrl+S submits the identity rule form with kind and policy value" do
      state = %AccessRulesView{
        section: :identity,
        identity_form_mode: :banned_handle,
        identity_draft: %{"value" => "Sysop2", "reason" => "impersonation", "comment" => ""}
      }

      {_state, effects} = AccessRulesView.handle_key(%{key: :char, char: "s", ctrl: true}, state)

      assert [%Effect{type: :task, payload: %{op: :sysop_load_access_rules}}] = effects
    end
  end
end
