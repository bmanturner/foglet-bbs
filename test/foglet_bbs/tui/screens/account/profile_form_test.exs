defmodule Foglet.TUI.Screens.Account.ProfileFormTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Effect
  alias Foglet.TUI.Modal
  alias Foglet.TUI.Screens.Account.ProfileForm
  alias Foglet.TUI.Screens.Account.State
  alias Foglet.TUI.Widgets.Modal.Form

  defp user do
    %{
      id: "u1",
      handle: "alice",
      role: :user,
      status: :active,
      location: "Birmingham",
      tagline: "hello",
      real_name: "Alice"
    }
  end

  test "profile read mode moves selected field instead of editing inline text" do
    state = State.new(current_user: user())

    assert {:ok, state, []} = ProfileForm.handle_key(%{key: :down}, state, user())
    assert state.profile_focus == :tagline
    assert Form.field_value(state.profile_form, :location) == "Birmingham"

    assert {:ok, state, []} = ProfileForm.handle_key(%{key: :end}, state, user())
    assert state.profile_focus == :real_name

    assert {:ok, state, []} = ProfileForm.handle_key(%{key: :home}, state, user())
    assert state.profile_focus == :location
  end

  test "E opens a one-field profile overlay for selected field" do
    state = %{State.new(current_user: user()) | profile_focus: :real_name}

    assert {:ok, state, [%Effect{type: :modal, payload: {:open, %Modal{} = modal}}]} =
             ProfileForm.handle_key(%{key: :char, char: "E"}, state, user())

    assert state.profile_editing_field == :real_name
    assert %Form{title: "Edit profile: Real name", fields: [field]} = modal.message
    assert field.name == :real_name
    assert field.description == "For friends and the sysop; blank uses your handle."
  end

  test "submitting selected profile field preserves untouched draft values" do
    state = %{State.new(current_user: user()) | profile_editing_field: :tagline}

    assert {state, [{:account_save_profile, attrs}]} =
             ProfileForm.submit_field(state, %{tagline: "new tagline"})

    assert state.profile_focus == :tagline
    assert state.profile_draft.tagline == "new tagline"
    assert attrs == %{location: "Birmingham", tagline: "new tagline", real_name: "Alice"}
  end

  test "failed profile save reopens the selected field overlay with errors" do
    state = %{State.new(current_user: user()) | profile_editing_field: :location}

    assert %Effect{type: :modal, payload: {:open, %Modal{} = modal}} =
             ProfileForm.error_modal(state, %{location: "Location is too long"})

    assert %Form{title: "Edit profile: Location", fields: [%{name: :location}], errors: errors} =
             modal.message

    assert errors.location == "Location is too long"
  end
end
