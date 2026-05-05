defmodule Foglet.TUI.Screens.Account.ProfileFormTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Screens.Account.ProfileForm
  alias Foglet.TUI.Screens.Account.State
  alias Foglet.TUI.Widgets.Modal.Form

  test "profile form routes cursor and delete keys into populated text fields" do
    user = %{
      id: "u1",
      handle: "alice",
      role: :user,
      status: :active,
      location: "Birmingham",
      tagline: "hello",
      real_name: "Alice"
    }

    state = State.new(current_user: user)

    assert {:ok, state, []} = ProfileForm.handle_key(%{key: :left}, state, user)
    assert {:ok, state, []} = ProfileForm.handle_key(%{key: :delete}, state, user)
    assert Form.field_value(state.profile_form, :location) == "Birmingha"

    assert {:ok, state, []} = ProfileForm.handle_key(%{key: :char, char: "m"}, state, user)
    assert Form.field_value(state.profile_form, :location) == "Birmingham"
  end
end
