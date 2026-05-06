defmodule Foglet.TUI.Screens.Account.PrefsFormTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.App
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Modal
  alias Foglet.TUI.Screens.Account.PrefsForm
  alias Foglet.TUI.Screens.Account.State
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Modal.Form

  import Foglet.TUI.WidgetHelpers, only: [flatten_text: 1]

  defp user do
    %{
      id: "u1",
      handle: "alice",
      role: :user,
      status: :active,
      timezone: "America/Chicago",
      preferences: %{"time_format" => "12h"},
      theme: "gray",
      handle_color: "#FFFFFF"
    }
  end

  test "prefs read mode moves selected field instead of editing inline picker state" do
    state = State.new(current_user: user())

    assert {:ok, state, []} = PrefsForm.handle_key(%{key: :down}, state, user())
    assert state.prefs_focus == :time_format
    assert Form.field_value(state.prefs_form, :timezone) == "America/Chicago"

    assert {:ok, state, []} = PrefsForm.handle_key(%{key: :end}, state, user())
    assert state.prefs_focus == :handle_color

    assert {:ok, state, []} = PrefsForm.handle_key(%{key: :home}, state, user())
    assert state.prefs_focus == :timezone
  end

  test "E opens a searchable one-field timezone overlay and preserves non-curated saved values" do
    state =
      State.new(current_user: %{user() | timezone: "Antarctica/Troll"})
      |> Map.put(:prefs_focus, :timezone)

    assert {:ok, state, [%Effect{type: :modal, payload: {:open, %Modal{} = modal}}]} =
             PrefsForm.handle_key(%{key: :char, char: "E"}, state, user())

    assert state.prefs_editing_field == :timezone
    assert %Form{title: "Edit preferences: Timezone", fields: [field]} = modal.message
    assert %{name: :timezone, type: :select_list, max_height: 4} = field
    assert "Antarctica/Troll" in field.choices
    assert Form.field_value(modal.message, :timezone) == "Antarctica/Troll"
  end

  test "submitting time format saves only the selected value while preserving timezone and theme" do
    state = %{State.new(current_user: user()) | prefs_editing_field: :time_format}

    assert {state, [{:account_save_prefs, attrs}]} =
             PrefsForm.submit_field(state, %{time_format: "24h"})

    assert state.prefs_focus == :time_format
    assert state.prefs_draft.time_format == "24h"

    assert attrs == %{
             timezone: "America/Chicago",
             preferences: %{"time_format" => "24h"},
             theme: "gray",
             handle_color: "#FFFFFF"
           }
  end

  test "theme changes are committed on submit only and do not live-preview in list mode" do
    state =
      %{
        State.new(current_user: user())
        | prefs_editing_field: :theme,
          candidate_theme_id: "amber"
      }

    assert {state, [{:account_save_prefs, attrs}]} =
             PrefsForm.submit_field(state, %{theme: "amber"})

    assert state.prefs_focus == :theme
    assert state.prefs_draft.theme == "amber"
    assert state.candidate_theme_id == nil
    assert attrs.theme == "amber"
  end

  test "opening theme modal opts into account-local live preview routing" do
    state = %{State.new(current_user: user()) | prefs_focus: :theme}

    assert {:ok, state, [%Effect{type: :modal, payload: {:open, %Modal{} = modal}}]} =
             PrefsForm.handle_key(%{key: :enter}, state, user())

    assert state.prefs_editing_field == :theme
    assert state.candidate_theme_id == nil
    assert modal.change_target == {:account, :prefs_field}
    assert Form.field_value(modal.message, :theme) == "gray"
  end

  test "theme modal enum cycling previews without mutating user, session, or draft" do
    account_state = %{State.new(current_user: user()) | prefs_editing_field: :theme}
    form = State.build_prefs_field_form(account_state.prefs_draft, :theme)

    app = %App{
      current_screen: :account,
      current_user: user(),
      session_context: %{theme_id: "gray", theme: Theme.resolve(:gray)},
      terminal_size: {80, 24},
      screen_state: %{account: account_state},
      modal: %Modal{
        type: :form,
        title: form.title,
        message: form,
        change_target: {:account, :prefs_field}
      }
    }

    {previewed, []} = App.update({:key, %{key: :down}}, app)
    preview_theme = Form.field_value(previewed.modal.message, :theme)

    assert preview_theme != "gray"
    assert previewed.screen_state.account.candidate_theme_id == preview_theme
    assert previewed.screen_state.account.prefs_draft.theme == "gray"
    assert previewed.current_user.theme == "gray"
    assert previewed.session_context.theme_id == "gray"
    assert previewed.session_context.theme == Theme.resolve(:gray)
    assert Theme.from_state(previewed) == Theme.resolve(String.to_existing_atom(preview_theme))

    {cancelled, []} = App.update({:key, %{key: :escape}}, previewed)

    assert cancelled.modal == nil
    assert cancelled.screen_state.account.candidate_theme_id == nil
    assert cancelled.screen_state.account.prefs_editing_field == nil
    assert cancelled.current_user.theme == "gray"
    assert cancelled.session_context.theme_id == "gray"
  end

  test "non-theme prefs modal changes do not affect candidate_theme_id" do
    account_state = %{State.new(current_user: user()) | prefs_editing_field: :time_format}
    form = State.build_prefs_field_form(account_state.prefs_draft, :time_format)
    {form, nil} = Form.handle_event(%{key: :down}, form)

    assert Form.field_value(form, :time_format) == "24h"

    state = PrefsForm.preview_field_change(%{account_state | candidate_theme_id: "amber"}, form)

    assert state.candidate_theme_id == nil
  end

  test "timezone overlay Enter selects without submitting while Ctrl+S saves selected timezone" do
    state = State.new(current_user: user())
    form = State.build_prefs_field_form(state.prefs_draft, :timezone)

    {edited_form, nil} = Form.handle_event(%{key: :char, char: "P"}, form)
    {edited_form, nil} = Form.handle_event(%{key: :enter}, edited_form)

    assert Form.field_value(edited_form, :timezone) != state.prefs_draft.timezone

    {saved_form, action} = Form.handle_event(%{key: :char, char: "s", ctrl: true}, edited_form)

    assert {:submitted,
            %Effect{
              type: :modal_submit,
              payload: %{
                screen_key: :account,
                kind: :prefs_field,
                payload: %{timezone: timezone}
              }
            }} = action

    assert timezone == Form.field_value(saved_form, :timezone)
    assert saved_form.submit_state == :submitting
  end

  test "timezone overlay footer is accurate for Enter selection and Ctrl+S save at 80 columns" do
    state = State.new(current_user: user())
    form = State.build_prefs_field_form(state.prefs_draft, :timezone)
    flat = form |> Form.render(theme: Theme.default(), width: 80) |> flatten_text()

    assert flat =~ "[Enter] Select"
    assert flat =~ "[Ctrl+S] Save"
    assert flat =~ "[Esc] Cancel"
    refute flat =~ "[Enter/Ctrl+S] Save"
  end

  test "Esc cancels timezone overlay without submitting or mutating prefs draft" do
    state = State.new(current_user: user())
    form = State.build_prefs_field_form(state.prefs_draft, :timezone)

    {edited_form, nil} = Form.handle_event(%{key: :char, char: "P"}, form)
    {edited_form, nil} = Form.handle_event(%{key: :enter}, edited_form)
    {_cancelled_form, action} = Form.handle_event(%{key: :escape}, edited_form)

    assert action == :cancelled

    assert state.prefs_draft == %{
             timezone: "America/Chicago",
             time_format: "12h",
             theme: "gray",
             handle_color: "#FFFFFF"
           }
  end

  test "failed prefs save reopens the selected field overlay with validation errors" do
    state = %{State.new(current_user: user()) | prefs_editing_field: :timezone}

    assert %Effect{type: :modal, payload: {:open, %Modal{} = modal}} =
             PrefsForm.error_modal(state, %{timezone: "Timezone must be a valid IANA name"})

    assert %Form{
             title: "Edit preferences: Timezone",
             fields: [%{name: :timezone}],
             errors: errors
           } =
             modal.message

    assert errors.timezone == "Timezone must be a valid IANA name"
    assert modal.message.submit_state == {:error, "validation"}
  end

  test "prefs display friendly theme labels without mutating the saved theme id" do
    state = %{State.new(current_user: %{user() | theme: "amber"}) | prefs_focus: :theme}

    node = PrefsForm.render(state, Theme.default(), width: 80, height: 12)

    assert inspect(node) =~ "Amber"
    assert state.prefs_draft.theme == "amber"
  end
end
