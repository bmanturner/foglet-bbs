defmodule Foglet.TUI.Screens.Sysop.AccessRulesViewTest do
  use ExUnit.Case, async: true

  alias Foglet.SSH.AccessRule
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Screens.Sysop.AccessRulesView
  alias Foglet.TUI.Theme

  describe "render/2" do
    test "renders loaded access rules without corrupting the console table state" do
      state = %AccessRulesView{
        rules: [
          %AccessRule{mode: :deny, enabled: true, address: "192.0.2.0/24", reason: "spam"},
          %AccessRule{mode: :allow, enabled: false, address: "2001:db8::/32", reason: "ops"}
        ],
        selection_index: 1
      }

      assert AccessRulesView.render(state, Theme.default())
    end
  end

  describe "form key handling" do
    test "Ctrl+S submits the access-rule form like the advertised command bar" do
      state = %AccessRulesView{
        form_mode: :create_deny,
        draft: %{"address" => "192.0.2.44", "reason" => "spam", "comment" => "manual block"}
      }

      {_state, effects} = AccessRulesView.handle_key(%{key: :char, char: "s", ctrl: true}, state)

      assert [%Effect{type: :task, payload: %{op: :sysop_load_access_rules}}] = effects
    end
  end
end
