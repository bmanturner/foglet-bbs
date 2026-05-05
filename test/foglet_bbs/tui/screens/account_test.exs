defmodule Foglet.TUI.Screens.AccountTest do
  use FogletBbs.DataCase, async: false

  import Foglet.TUI.RenderHelpers

  alias Foglet.Accounts
  alias Foglet.Accounts.Invites
  alias Foglet.Config
  alias Foglet.Sessions.Session
  alias Foglet.TUI.App
  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Presentation
  alias Foglet.TUI.Screens.Account
  alias Foglet.TUI.Screens.Account.SSHKeysState
  alias Foglet.TUI.Screens.Account.State, as: AccountState
  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias FogletBbs.AccountsFixtures
  alias Raxol.UI.Layout.Engine

  @alternate_ssh_public_key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBp8Yt7rf3YpZ8eR+3KEBLQnUlsMHfK4VwCaZJmjs4Cq other@example"

  defp build_state(user, session_context) do
    %Foglet.TUI.App{
      current_screen: :account,
      current_user: user,
      session_context: session_context,
      terminal_size: {80, 24},
      screen_state: %{}
    }
    |> Map.from_struct()
  end

  defp user(role) do
    %Foglet.Accounts.User{
      id: "00000000-0000-0000-0000-000000000001",
      handle: "alice",
      role: role
    }
  end

  defp build_state_for_role(role, session_context \\ %{}) do
    build_state(user(role), session_context)
  end

  defp account_context(state) do
    app = struct!(App, Map.take(state, Map.keys(%App{})))
    App.build_context(app)
  end

  defp render_account(state) do
    context = account_context(state)
    local_state = get_in(state, [:screen_state, :account]) || Account.init(context)

    Account.render(local_state, context)
  end

  defp ssh_key_table_row(positioned, sentinel) do
    positioned
    |> Enum.filter(fn element ->
      element.type == :text and is_binary(Map.get(element, :text)) and
        element.text != "" and not String.starts_with?(element.text, "A Add key") and
        not (Map.get(element, :attrs, %{}) |> Map.get(:chrome_frame?, false))
    end)
    |> Enum.group_by(& &1.y)
    |> Enum.find_value([], fn {_y, elements} ->
      ordered = Enum.sort_by(elements, & &1.x)

      if Enum.any?(ordered, &String.contains?(&1.text, sentinel)) do
        ordered
      end
    end)
  end

  defp selected_markers(%SSHKeysState{table: %{rows: rows}}) do
    Enum.map(rows, fn row -> row |> Map.fetch!(:selected) |> String.trim() end)
  end

  # FOG-333 / FOG-717: PROFILE shields digit shortcuts AND cursor/edit keys
  # while a text field is focused so editing keys reach the form before tab
  # navigation. Many tests assume the legacy behavior of digit chars or
  # arrow keys switching tabs directly from the seeded initial state. This
  # helper steps out of the PROFILE form by directly setting active_tab to
  # PREFS (whose default Timezone select-list does not shield tab
  # shortcuts), so subsequent digit/arrow presses reach the Tabs widget.
  defp leave_profile_form(state) do
    state = ensure_account_seeded(state)

    update_in(state.screen_state.account, fn account ->
      Foglet.TUI.LayoutSmokeHelpers.set_active_tab(account, "PREFS")
    end)
  end

  # FOG-717: peek at the underlying TextInput state for the Location field
  # so cursor-position assertions can prove arrow keys edit text instead of
  # being swallowed by tab navigation.
  defp location_field_state(%{fields: fields, field_states: states}) do
    idx = Enum.find_index(fields, &(&1.name == :location))
    Enum.at(states, idx)
  end

  defp ensure_account_seeded(state) do
    case get_in(state, [:screen_state, :account]) do
      nil ->
        context = account_context(state)
        put_in(state, [:screen_state, :account], Account.init(context))

      _ ->
        state
    end
  end

  defp handle_account_key(event, state) do
    context = account_context(state)
    local_state = get_in(state, [:screen_state, :account]) || Account.init(context)
    {new_local_state, effects} = Account.update({:key, event}, local_state, context)
    state = put_in(state, [:screen_state, :account], new_local_state)

    if new_local_state == local_state and effects == [] do
      :no_match
    else
      apply_account_effects(state, effects)
    end
  end

  defp apply_account_effects(state, effects) do
    Enum.reduce(effects, {:update, state, []}, fn
      %Effect{type: :navigate, payload: %{screen: screen, params: params}},
      {:update, state, cmds} ->
        {:update, %{state | current_screen: screen, route_params: params || %{}}, cmds}

      %Effect{type: :session, payload: {:set_current_user, user}}, {:update, state, cmds} ->
        {:update, %{state | current_user: user}, cmds}

      %Effect{type: :session, payload: {:update_preferences, _snapshot}}, acc ->
        acc

      %Effect{type: :task, payload: %{op: op, fun: fun}}, {:update, state, cmds} ->
        result = fun.()
        local_state = get_in(state, [:screen_state, :account])

        {new_local_state, followup} =
          Account.update({:task_result, op, {:ok, result}}, local_state, account_context(state))

        state
        |> put_in([:screen_state, :account], new_local_state)
        |> apply_account_effects(followup)
        |> append_cmds(cmds)

      _effect, acc ->
        acc
    end)
  end

  defp append_cmds({:update, state, new_cmds}, cmds), do: {:update, state, cmds ++ new_cmds}

  setup do
    %{state: build_state_for_role(:user)}
  end

  describe "Account.State.new/1" do
    test "returns a struct with active_tab: 0 and a Tabs wrapper state" do
      ss = AccountState.new()
      assert ss.active_tab == 0
      assert %Foglet.TUI.Widgets.Input.Tabs{} = ss.tabs
    end

    test "seeds profile and prefs drafts from current_user without mutating session context" do
      user = %Foglet.Accounts.User{
        id: "u1",
        handle: "alice",
        role: :user,
        location: "Mist Harbor",
        tagline: "low clouds, loud modems",
        real_name: "Alice Example",
        timezone: "America/Chicago",
        preferences: %{"time_format" => "24h"},
        theme: "amber"
      }

      ss = AccountState.new(current_user: user)

      assert ss.profile_draft == %{
               location: "Mist Harbor",
               tagline: "low clouds, loud modems",
               real_name: "Alice Example"
             }

      assert ss.prefs_draft == %{
               timezone: "America/Chicago",
               time_format: "24h",
               theme: "amber"
             }

      assert ss.profile_focus == :location
      assert ss.prefs_focus == :timezone
      assert ss.profile_errors == %{}
      assert ss.prefs_errors == %{}
      refute ss.profile_dirty?
      refute ss.prefs_dirty?
      assert ss.candidate_theme_id == nil
    end
  end

  describe "new screen contract" do
    test "Account.Render is the sibling render entry point" do
      assert Code.ensure_loaded?(Account.Render)
      assert function_exported?(Account.Render, :render, 1)

      source = File.read!("lib/foglet_bbs/tui/screens/account.ex")

      assert String.contains?(source, "Render.render()")
    end

    test "Account.init/1 seeds local state from Context" do
      user = build_user_with_profile(location: "Mist Harbor")

      state =
        Account.init(
          Context.new(
            current_user: user,
            session_context: %{
              registration_mode: "invite_only",
              invite_code_generators: "any_user"
            },
            route: :account
          )
        )

      assert %AccountState{} = state
      assert state.profile_draft.location == "Mist Harbor"
      assert "INVITES" in AccountState.tab_labels(true)
    end

    test "Account INVITES tab is hidden for normal users and sysops under open registration" do
      open_any_user = %{registration_mode: "open", invite_code_generators: "any_user"}

      user_state =
        Account.init(Context.new(current_user: user(:user), session_context: open_any_user))

      sysop_state =
        Account.init(Context.new(current_user: user(:sysop), session_context: open_any_user))

      assert user_state.tab_labels == AccountState.tab_labels(false)
      assert sysop_state.tab_labels == AccountState.tab_labels(false)
    end

    test "Account INVITES tab follows role policy when registration is invite-only" do
      invite_sysop_only = %{
        registration_mode: "invite_only",
        invite_code_generators: "sysop_only"
      }

      invite_any_user = %{registration_mode: "invite_only", invite_code_generators: "any_user"}

      user_hidden =
        Account.init(Context.new(current_user: user(:user), session_context: invite_sysop_only))

      sysop_visible =
        Account.init(Context.new(current_user: user(:sysop), session_context: invite_sysop_only))

      user_visible =
        Account.init(Context.new(current_user: user(:user), session_context: invite_any_user))

      assert user_hidden.tab_labels == AccountState.tab_labels(false)
      assert sysop_visible.tab_labels == AccountState.tab_labels(true)
      assert user_visible.tab_labels == AccountState.tab_labels(true)
    end

    test "Account render clamps away from stale INVITES tab when registration mode changes to open" do
      sysop = user(:sysop)

      stale_invites_state =
        AccountState.new(current_user: sysop, invites_visible?: true, active: 3)

      context =
        Context.new(
          current_user: sysop,
          session_context: %{registration_mode: "open", invite_code_generators: "sysop_only"},
          route: :account,
          terminal_size: {80, 24}
        )

      synced = Account.update(:noop, stale_invites_state, context) |> elem(0)

      assert synced.tab_labels == AccountState.tab_labels(false)
      assert synced.active_tab == 2
      assert _node = Account.render(stale_invites_state, context)
    end

    test "Account.render/2 renders from local state and Context without App-shaped input" do
      user = build_user_with_profile()
      context = Context.new(current_user: user, route: :account, terminal_size: {80, 24})
      state = Account.init(context)

      assert _node = Account.render(state, context)
    end

    test "profile task result reseeds Account local state and refreshes App user" do
      user = build_user_with_profile()
      context = Context.new(current_user: user, route: :account)
      state = Account.init(context)
      updated = %{user | location: "New Cove"}

      {state, effects} =
        Account.update(
          {:task_result, :account_save_profile, {:ok, {:ok, updated}}},
          state,
          context
        )

      assert %AccountState{} = state
      assert state.profile_draft.location == "New Cove"
      assert state.status_message == "Profile saved."
      assert [%Effect{type: :session, payload: {:set_current_user, ^updated}}] = effects
    end

    test "prefs task result reseeds state and emits session refresh effects" do
      user = build_user_with_profile(theme: "amber")
      context = Context.new(current_user: user, route: :account)

      state =
        Account.init(context)
        |> Map.put(:candidate_theme_id, "gray")

      {state, effects} =
        Account.update({:task_result, :account_save_prefs, {:ok, {:ok, user}}}, state, context)

      assert state.candidate_theme_id == nil
      assert state.status_message == "Preferences saved."

      assert [
               %Effect{type: :session, payload: {:set_current_user, ^user}},
               %Effect{type: :session, payload: {:update_preferences, snapshot}}
             ] = effects

      assert snapshot.theme_id == "amber"
    end

    test "profile task failure moves Modal.Form out of submitting" do
      alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

      user = build_user_with_profile()
      context = Context.new(current_user: user, route: :account)

      state =
        Account.init(context)
        |> Map.update!(:profile_form, &%{&1 | submit_state: :submitting})

      changeset = Accounts.User.profile_changeset(user, %{location: String.duplicate("x", 200)})

      {state, []} =
        Account.update(
          {:task_result, :account_save_profile, {:ok, {:error, changeset}}},
          state,
          context
        )

      assert %ModalForm{submit_state: {:error, _}} = state.profile_form
      assert %{location: message} = state.profile_form.errors
      assert String.contains?(message, "Location must be 80 characters or fewer.")
    end

    test "prefs task failure moves Modal.Form out of submitting" do
      alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

      user = build_user_with_profile()
      context = Context.new(current_user: user, route: :account)

      state =
        Account.init(context)
        |> Map.put(:active_tab, 1)
        |> Map.update!(:prefs_form, &%{&1 | submit_state: :submitting})

      changeset = Accounts.User.profile_changeset(user, %{timezone: "Not/AZone"})

      {state, []} =
        Account.update(
          {:task_result, :account_save_prefs, {:ok, {:error, changeset}}},
          state,
          context
        )

      assert %ModalForm{submit_state: {:error, _}} = state.prefs_form
      assert %{timezone: message} = state.prefs_form.errors
      assert String.contains?(message, "Timezone must be a valid IANA name")
    end

    test "SSH key and invite tabs request task-backed loads" do
      user = build_user_with_profile()

      context =
        Context.new(
          current_user: user,
          route: :account,
          session_context: %{registration_mode: "invite_only", invite_code_generators: "any_user"}
        )

      # FOG-333 / FOG-717: PROFILE shields digit/cursor/edit keys while a
      # text field is focused. Step out of the form by parking on PREFS
      # directly; from PREFS (Timezone is :select_list) digits are not
      # shielded so the digit shortcut still reaches the Tabs widget.
      initial =
        context
        |> Account.init()
        |> Foglet.TUI.LayoutSmokeHelpers.set_active_tab("PREFS")

      {ssh_state, ssh_effects} =
        Account.update({:key, %{key: :char, char: "3"}}, initial, context)

      assert ssh_state.active_tab == 2
      assert [%Effect{payload: %{op: :account_load_ssh_keys}}] = ssh_effects

      {invite_state, invite_effects} =
        Account.update({:key, %{key: :char, char: "4"}}, ssh_state, context)

      assert invite_state.active_tab == 3
      assert [%Effect{payload: %{op: :account_load_invites}}] = invite_effects
    end
  end

  describe "render/1 (Account.render/1 traceability)" do
    test "declares operator mode through Presentation", %{state: state} do
      state = put_in(state, [:screen_state, :account], AccountState.new())

      assert _ = render_account(state)
      assert Presentation.mode_for!(:account) == :operator

      assert File.read!("lib/foglet_bbs/tui/screens/account/render.ex") =~
               "Presentation.mode_for!(:account)"
    end

    test "KEYS-01 defines PROFILE, PREFS, and SSH KEYS tab labels by default" do
      assert AccountState.tab_labels(false) == ["PROFILE", "PREFS", "SSH KEYS"]
    end

    test "KEYS-01 SSH KEYS tab renders an empty key-list state", %{state: state} do
      account_state =
        AccountState.new()
        |> Map.put(:active_tab, 2)
        |> Map.put(:ssh_keys, SSHKeysState.loaded(SSHKeysState.new(), []))

      state = put_in(state, [:screen_state, :account], account_state)
      flat = render_account(state) |> collect_text_values()

      assert Enum.any?(
               flat,
               &String.contains?(&1, "No SSH keys yet. Add one to sign in without a password.")
             )
    end

    test "omits INVITES when InvitesSurface.visible?/3 returns false" do
      # role: :user with sysop_only policy in invite-only mode => not visible
      state =
        :user
        |> build_state_for_role(%{
          registration_mode: "invite_only",
          invite_code_generators: "sysop_only"
        })
        |> put_in([:screen_state, :account], AccountState.new())

      flat = render_account(state) |> collect_text_values()
      refute Enum.any?(flat, &String.contains?(&1, "INVITES"))
    end

    test "includes INVITES when InvitesSurface.visible?/3 returns true" do
      # role: :sysop with invite-only registration => operator invite management visible
      state =
        build_state_for_role(:sysop, %{
          registration_mode: "invite_only",
          invite_code_generators: "sysop_only"
        })

      state = put_in(state, [:screen_state, :account], AccountState.new(role: :sysop))
      flat = render_account(state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "INVITES"))
    end

    test "any_user policy shows INVITES for a regular user in invite-only mode" do
      state =
        :user
        |> build_state_for_role(%{
          registration_mode: "invite_only",
          invite_code_generators: "any_user"
        })
        |> put_in([:screen_state, :account], AccountState.new())

      flat = render_account(state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "INVITES"))
    end

    test "mods and sysop_only policies hide INVITES for a regular user" do
      for policy <- ["mods", "sysop_only"] do
        state =
          :user
          |> build_state_for_role(%{
            registration_mode: "invite_only",
            invite_code_generators: policy
          })
          |> put_in([:screen_state, :account], AccountState.new())

        flat = render_account(state) |> collect_text_values()
        refute Enum.any?(flat, &String.contains?(&1, "INVITES"))
      end
    end

    test "nil user does not see INVITES under any_user policy" do
      state =
        build_state(nil, %{registration_mode: "invite_only", invite_code_generators: "any_user"})

      flat = render_account(state) |> collect_text_values()
      refute Enum.any?(flat, &String.contains?(&1, "INVITES"))
    end

    test "visibility changes in session_context rebuild tab list on render" do
      state =
        :user
        |> build_state_for_role(%{
          registration_mode: "invite_only",
          invite_code_generators: "sysop_only"
        })
        |> put_in([:screen_state, :account], AccountState.new())

      hidden_flat = render_account(state) |> collect_text_values()
      refute Enum.any?(hidden_flat, &String.contains?(&1, "INVITES"))

      visible_state = %{
        state
        | session_context: %{registration_mode: "invite_only", invite_code_generators: "any_user"}
      }

      visible_flat = render_account(visible_state) |> collect_text_values()
      assert Enum.any?(visible_flat, &String.contains?(&1, "INVITES"))
    end

    test "renders no fake invite or approval buttons", %{state: state} do
      state = put_in(state, [:screen_state, :account], AccountState.new())
      flat = render_account(state) |> collect_text_values()
      forbidden = ["Generate", "Revoke", "Approve"]

      for word <- forbidden do
        refute Enum.any?(flat, &String.contains?(&1, word)),
               "Expected #{inspect(word)} not to appear in Account render output"
      end
    end

    test "PROFILE and PREFS define editable field labels", %{state: state} do
      ss = AccountState.new(current_user: state.current_user)

      assert Enum.map(ss.profile_form.fields, & &1.label) == ["Location", "Tagline", "Real name"]
      assert Enum.map(ss.prefs_form.fields, & &1.label) == ["Timezone", "Time format", "Theme"]
    end

    test "unsaved theme preview changes Account render and cancel keeps session theme unchanged" do
      user = %Foglet.Accounts.User{
        id: "u1",
        handle: "alice",
        role: :user,
        timezone: "Etc/UTC",
        preferences: %{"time_format" => "12h"},
        theme: "gray"
      }

      state =
        user
        |> build_state(%{theme: Theme.resolve(:gray), theme_id: "gray"})
        |> put_in([:screen_state, :account], AccountState.new(current_user: user))

      state = leave_profile_form(state)
      {:update, state, []} = handle_account_key(%{key: :char, char: "2"}, state)
      before_preview = inspect(render_account(state))

      account_state = %{state.screen_state.account | prefs_focus: :theme}
      state = put_in(state, [:screen_state, :account], account_state)

      {:update, preview_state, []} = handle_account_key(%{key: :down}, state)

      assert preview_state.screen_state.account.candidate_theme_id != nil
      assert preview_state.session_context.theme == Theme.resolve(:gray)
      assert inspect(render_account(preview_state)) != before_preview

      {:update, cancelled_state, []} = handle_account_key(%{key: :escape}, preview_state)

      assert cancelled_state.screen_state.account.candidate_theme_id == nil
      assert cancelled_state.screen_state.account.prefs_draft.theme == "gray"
      assert cancelled_state.session_context.theme == Theme.resolve(:gray)
    end
  end

  describe "handle_key/2 (handle_account_key/2 traceability)" do
    setup %{state: state} do
      state = put_in(state, [:screen_state, :account], AccountState.new())
      %{state: state}
    end

    test "Right arrow advances active_tab via Tabs.handle_event/2 when no text field is focused",
         %{state: state} do
      # FOG-717: PROFILE Location is a text field — :right is now routed to
      # the form for cursor movement. Park on PREFS (Timezone select-list
      # is not text-shielded) before exercising tab nav.
      state = leave_profile_form(state)
      {:update, new_state, _cmds} = handle_account_key(%{key: :right}, state)
      assert new_state.screen_state.account.active_tab == 2
    end

    test "visibility changes in session_context rebuild tab list on handle-key", %{state: state} do
      state = %{
        state
        | session_context: %{registration_mode: "invite_only", invite_code_generators: "any_user"}
      }

      # FOG-717: PROFILE shields cursor/edit keys; step out of the text
      # form via the helper so the digit shortcut reaches the Tabs widget.
      state = leave_profile_form(state)

      {:update, new_state, _cmds} = handle_account_key(%{key: :char, char: "4"}, state)

      assert new_state.screen_state.account.active_tab == 3
      flat = render_account(new_state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "INVITES"))
    end

    test "digit '2' jumps to second tab (index 1) when no text field is focused", %{state: state} do
      # FOG-333: PROFILE Location field is text-typed and shields digits.
      # Move focus to PREFS (Timezone is :select_list, not shielded) before
      # exercising the shortcut.
      state = leave_profile_form(state)
      {:update, new_state, _cmds} = handle_account_key(%{key: :char, char: "2"}, state)
      assert new_state.screen_state.account.active_tab == 1
    end

    test "FOG-741: Esc from Profile exposes tab jumps without mutating text", %{state: state} do
      state = ensure_account_seeded(state)

      state =
        update_in(state.screen_state.account, fn account ->
          %{account | profile_form: %{account.profile_form | focus_index: 0}}
        end)

      before_location =
        Foglet.TUI.Widgets.Modal.Form.field_value(
          state.screen_state.account.profile_form,
          :location
        )

      {:update, state, []} = handle_account_key(%{key: :escape}, state)
      assert state.screen_state.account.active_tab == 0
      assert state.screen_state.account.tab_navigation?

      {:update, state, []} = handle_account_key(%{key: :char, char: "2"}, state)
      assert state.screen_state.account.active_tab == 1
      refute state.screen_state.account.tab_navigation?

      assert Foglet.TUI.Widgets.Modal.Form.field_value(
               state.screen_state.account.profile_form,
               :location
             ) == before_location
    end

    test "FOG-741: Account form keybar advertises Esc before tab arrows", %{state: state} do
      flat = render_account(state) |> collect_text_values() |> Enum.join(" ")

      assert flat =~ "Esc,←/→"
      refute flat =~ "Jump"
      refute flat =~ "1-3"

      {:update, state, []} = handle_account_key(%{key: :escape}, state)
      flat = render_account(state) |> collect_text_values() |> Enum.join(" ")

      assert flat =~ "←/→"
      refute flat =~ "Esc,←/→"
      refute flat =~ "Jump"
    end

    test "KEYS-01 digit '3' selects SSH KEYS when invites are hidden", %{state: state} do
      # FOG-333: leave PROFILE first so the digit shortcut isn't shielded.
      state = leave_profile_form(state)

      {:update, new_state, _cmds} = handle_account_key(%{key: :char, char: "3"}, state)
      assert new_state.screen_state.account.active_tab == 2

      flat = render_account(new_state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "SSH KEYS"))
    end

    test "FOG-717: left/right cursor keys edit Location, never advance Account tabs" do
      alias Foglet.TUI.Widgets.Input.TextInput
      alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

      user = %Foglet.Accounts.User{
        id: "00000000-0000-0000-0000-000000000010",
        handle: "alice",
        role: :user,
        location: "Bend"
      }

      state =
        build_state(user, %{})
        |> put_in([:screen_state, :account], AccountState.new(current_user: user))

      account = state.screen_state.account
      assert account.active_tab == 0
      assert Enum.at(account.profile_form.fields, 0).name == :location

      # Cursor starts placed at end of "Bend" (length 4).
      %TextInput{raxol_state: %{cursor_pos: start_pos}} =
        location_field_state(account.profile_form)

      assert start_pos == 4

      # Two :left presses must move the cursor inside Location, NOT switch
      # tabs. The legacy bug routed :left through Tabs first, switching tab.
      {:update, state, []} = handle_account_key(%{key: :left}, state)
      {:update, state, []} = handle_account_key(%{key: :left}, state)
      assert state.screen_state.account.active_tab == 0

      %TextInput{raxol_state: %{cursor_pos: pos_after_left}} =
        location_field_state(state.screen_state.account.profile_form)

      assert pos_after_left == start_pos - 2,
             "expected :left to move TextInput cursor while Location is focused"

      # Typing 'Y' between cursor positions must insert into the focused
      # field instead of being swallowed.
      {:update, state, []} = handle_account_key(%{key: :char, char: "Y"}, state)
      assert state.screen_state.account.active_tab == 0

      assert ModalForm.field_value(state.screen_state.account.profile_form, :location) ==
               "BeYnd"

      # :right must continue to move the cursor forward, NOT advance tab.
      {:update, state, []} = handle_account_key(%{key: :right}, state)
      assert state.screen_state.account.active_tab == 0

      # :home/:end remain text-cursor keys when Location is focused.
      {:update, state, []} = handle_account_key(%{key: :home}, state)
      assert state.screen_state.account.active_tab == 0

      %TextInput{raxol_state: %{cursor_pos: pos_after_home}} =
        location_field_state(state.screen_state.account.profile_form)

      assert pos_after_home == 0

      {:update, state, []} = handle_account_key(%{key: :end}, state)
      assert state.screen_state.account.active_tab == 0

      # Backspace and delete also stay in the focused field.
      {:update, state, []} = handle_account_key(%{key: :backspace}, state)
      assert state.screen_state.account.active_tab == 0
      assert ModalForm.field_value(state.screen_state.account.profile_form, :location) == "BeYn"
    end

    test "FOG-717: cursor keys still advance tabs when no text field is focused" do
      # PROFILE Location is text-shielded. Park on PREFS where Timezone is
      # a select-list (not text-shielded) so :right advances to SSH KEYS.
      user = AccountsFixtures.user_fixture()

      state =
        build_state(user, %{})
        |> put_in([:screen_state, :account], AccountState.new(current_user: user))
        |> leave_profile_form()

      assert state.screen_state.account.active_tab == 1

      {:update, state, []} = handle_account_key(%{key: :right}, state)
      assert state.screen_state.account.active_tab == 2

      {:update, state, []} = handle_account_key(%{key: :left}, state)
      assert state.screen_state.account.active_tab == 1
    end

    test "FOG-717: cursor/edit keys do not switch tabs when PREFS Timezone is filtering" do
      # PREFS Timezone is :select_list — a list/filter mode. Backspace and
      # char keys should drive the search filter (or stay no-op when empty)
      # without ever switching to PROFILE/SSH KEYS, even when the search
      # buffer is empty.
      user = AccountsFixtures.user_fixture()

      state =
        build_state(user, %{})
        |> put_in([:screen_state, :account], AccountState.new(current_user: user))
        |> leave_profile_form()

      assert state.screen_state.account.active_tab == 1

      # With an empty search, :left/:right fall through to Tabs (browse-mode
      # tab nav). Char keys begin filtering and stay inside the form.
      {:update, state, []} = handle_account_key(%{key: :char, char: "C"}, state)
      assert state.screen_state.account.active_tab == 1

      {:update, state, []} = handle_account_key(%{key: :backspace}, state)
      assert state.screen_state.account.active_tab == 1

      # Once the filter is active, cursor keys must stay in the form so the
      # user is not yanked out of PREFS while editing the Timezone search.
      {:update, state, []} = handle_account_key(%{key: :char, char: "E"}, state)
      {:update, state, []} = handle_account_key(%{key: :char, char: "u"}, state)
      assert state.screen_state.account.active_tab == 1

      context = account_context(state)
      account = state.screen_state.account
      {after_left, _} = Account.update({:key, %{key: :left}}, account, context)
      assert after_left.active_tab == 1

      {after_right, _} = Account.update({:key, %{key: :right}}, account, context)
      assert after_right.active_tab == 1
    end

    test "Ctrl+Q returns to :main_menu", %{state: state} do
      {:update, new_state, _cmds} =
        handle_account_key(%{key: :char, char: "Q", ctrl: true}, state)

      assert new_state.current_screen == :main_menu
    end

    test "'q' is delegated to the active form", %{state: state} do
      {:update, new_state, _cmds} = handle_account_key(%{key: :char, char: "q"}, state)
      assert new_state.current_screen == :account
      assert new_state.screen_state.account.profile_dirty?
    end

    test "non-text unknown key returns :no_match", %{state: state} do
      assert :no_match = handle_account_key(%{key: :f12}, state)
    end

    # FOG-139: regression test for PREFS Tab key advancing focus through
    # all-enum fields (Timezone -> Time format -> Theme). The previous
    # bug was a one-way pre-dispatch sync from prefs_focus to
    # form.focus_index that stomped Modal.Form's focus advancement on the
    # next keystroke; Tab visually no-op'd and Down kept mutating Timezone.
    test "FOG-139: Tab in PREFS advances focus through enum fields and back-syncs prefs_focus" do
      user = %Foglet.Accounts.User{
        id: "u1",
        handle: "alice",
        role: :user,
        timezone: "America/Chicago",
        preferences: %{"time_format" => "12h"},
        theme: "gray"
      }

      state =
        user
        |> build_state(%{theme: Theme.resolve(:gray), theme_id: "gray"})
        |> put_in([:screen_state, :account], AccountState.new(current_user: user))

      state = leave_profile_form(state)
      {:update, state, []} = handle_account_key(%{key: :char, char: "2"}, state)

      account = state.screen_state.account
      assert account.prefs_focus == :timezone
      assert account.prefs_form.focus_index == 0

      {:update, state, []} = handle_account_key(%{key: :tab}, state)
      account = state.screen_state.account
      assert account.prefs_form.focus_index == 1
      assert account.prefs_focus == :time_format

      {:update, state, []} = handle_account_key(%{key: :tab}, state)
      account = state.screen_state.account
      assert account.prefs_form.focus_index == 2
      assert account.prefs_focus == :theme

      {:update, state, []} = handle_account_key(%{key: :tab}, state)
      account = state.screen_state.account
      assert account.prefs_form.focus_index == 0
      assert account.prefs_focus == :timezone
    end

    test "PREFS timezone uses searchable select-list and preserves non-curated saved values" do
      alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

      user = %Foglet.Accounts.User{
        id: "u1",
        handle: "alice",
        role: :user,
        timezone: "Antarctica/Troll",
        preferences: %{"time_format" => "12h"},
        theme: "gray"
      }

      state =
        user
        |> build_state(%{theme: Theme.resolve(:gray), theme_id: "gray"})
        |> put_in([:screen_state, :account], AccountState.new(current_user: user))

      state = leave_profile_form(state)
      {:update, state, []} = handle_account_key(%{key: :char, char: "2"}, state)
      form = state.screen_state.account.prefs_form

      assert %{type: :select_list, name: :timezone} = hd(form.fields)
      assert ModalForm.field_value(form, :timezone) == "Antarctica/Troll"

      flat = render_account(state) |> collect_text_values() |> Enum.join("")
      assert flat =~ "Type to filter"
      assert flat =~ "Antarctica/Troll"
    end

    test "PREFS timezone can search America/Chicago without full cycling" do
      alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

      user = %Foglet.Accounts.User{
        id: "u1",
        handle: "alice",
        role: :user,
        timezone: "Etc/UTC",
        preferences: %{"time_format" => "12h"},
        theme: "gray"
      }

      state =
        user
        |> build_state(%{theme: Theme.resolve(:gray), theme_id: "gray"})
        |> put_in([:screen_state, :account], AccountState.new(current_user: user))

      state = leave_profile_form(state)
      {:update, state, []} = handle_account_key(%{key: :char, char: "2"}, state)
      assert ModalForm.field_value(state.screen_state.account.prefs_form, :timezone) == "Etc/UTC"

      {:update, state, []} = handle_account_key(%{key: :char, char: "C"}, state)
      {:update, state, []} = handle_account_key(%{key: :char, char: "h"}, state)
      {:update, state, []} = handle_account_key(%{key: :enter}, state)

      assert ModalForm.field_value(state.screen_state.account.prefs_form, :timezone) ==
               "America/Chicago"

      assert state.screen_state.account.prefs_form.focus_index == 1
    end

    test "FOG-139: Down after Tab cycles the next enum field, not Timezone" do
      alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

      user = %Foglet.Accounts.User{
        id: "u1",
        handle: "alice",
        role: :user,
        timezone: "America/Chicago",
        preferences: %{"time_format" => "12h"},
        theme: "gray"
      }

      state =
        user
        |> build_state(%{theme: Theme.resolve(:gray), theme_id: "gray"})
        |> put_in([:screen_state, :account], AccountState.new(current_user: user))

      state = leave_profile_form(state)
      {:update, state, []} = handle_account_key(%{key: :char, char: "2"}, state)

      original_tz = state.screen_state.account.prefs_form |> ModalForm.field_value(:timezone)
      original_tf = state.screen_state.account.prefs_form |> ModalForm.field_value(:time_format)

      {:update, state, []} = handle_account_key(%{key: :tab}, state)
      {:update, state, []} = handle_account_key(%{key: :down}, state)

      account = state.screen_state.account
      new_tz = account.prefs_form |> ModalForm.field_value(:timezone)
      new_tf = account.prefs_form |> ModalForm.field_value(:time_format)

      assert new_tz == original_tz, "Timezone must not change after Tab + Down"
      assert new_tf != original_tf, "Time format must cycle on Down after Tab"
    end

    test "FOG-139: Shift-Tab in PREFS retreats focus and back-syncs prefs_focus" do
      user = %Foglet.Accounts.User{
        id: "u1",
        handle: "alice",
        role: :user,
        timezone: "America/Chicago",
        preferences: %{"time_format" => "12h"},
        theme: "gray"
      }

      state =
        user
        |> build_state(%{theme: Theme.resolve(:gray), theme_id: "gray"})
        |> put_in([:screen_state, :account], AccountState.new(current_user: user))

      state = leave_profile_form(state)
      {:update, state, []} = handle_account_key(%{key: :char, char: "2"}, state)

      {:update, state, []} = handle_account_key(%{key: :shift_tab}, state)
      account = state.screen_state.account
      assert account.prefs_form.focus_index == 2
      assert account.prefs_focus == :theme
    end

    test "Account screen does NOT dispatch any fake operator commands (Save/Generate/Revoke)", %{
      state: state
    } do
      forbidden_commands = [:save_profile, :generate_invite, :revoke_invite, :approve_user]

      keys = [
        %{key: :right},
        %{key: :left},
        %{key: :char, char: "1"},
        %{key: :char, char: "2"}
      ]

      for key <- keys do
        case handle_account_key(key, state) do
          {:update, _new_state, cmds} ->
            for cmd <- cmds do
              if is_tuple(cmd) do
                refute elem(cmd, 0) in forbidden_commands,
                       "Unexpected command #{inspect(cmd)} from key #{inspect(key)}"
              end
            end

          :no_match ->
            :ok
        end
      end
    end
  end

  describe "App Account reducer result handling" do
    test "successful save results refresh local state, current user, and active session snapshots" do
      user = AccountsFixtures.user_fixture()

      {:ok, session_pid} =
        start_supervised(
          {Session, [user_id: user.id, handle: user.handle, role: user.role]},
          id: :account_save_success_session
        )

      state = %App{
        current_screen: :account,
        current_user: user,
        session_context: %{
          session_pid: session_pid,
          timezone: "Etc/UTC",
          time_format: "12h",
          theme_id: "gray",
          theme: Theme.resolve(:gray)
        },
        session_pid: session_pid,
        terminal_size: {80, 24},
        screen_state: %{
          account:
            AccountState.new(current_user: user)
            |> Map.put(:profile_dirty?, true)
            |> Map.put(:prefs_dirty?, true)
            |> Map.put(:candidate_theme_id, "amber")
        }
      }

      {:ok, updated_profile} =
        Accounts.update_profile(user, %{
          location: "Mist Harbor",
          tagline: "low clouds",
          real_name: "Alice Example"
        })

      {state, []} =
        App.update(
          {:screen_task_result, :account, :account_save_profile, {:ok, {:ok, updated_profile}}},
          state
        )

      {:ok, updated_prefs} =
        Accounts.update_profile(updated_profile, %{
          timezone: "America/Chicago",
          preferences: %{"time_format" => "24h"},
          theme: "amber"
        })

      {state, []} =
        App.update(
          {:screen_task_result, :account, :account_save_prefs, {:ok, {:ok, updated_prefs}}},
          state
        )

      persisted = Accounts.get_user!(user.id)

      assert persisted.location == "Mist Harbor"
      assert persisted.tagline == "low clouds"
      assert persisted.real_name == "Alice Example"
      assert persisted.timezone == "America/Chicago"
      assert persisted.preferences["time_format"] == "24h"
      assert persisted.theme == "amber"

      assert state.current_user.id == user.id
      assert state.current_user.location == "Mist Harbor"
      assert state.current_user.timezone == "America/Chicago"
      assert state.current_user.preferences["time_format"] == "24h"
      assert state.current_user.theme == "amber"

      assert state.session_context.timezone == "America/Chicago"
      assert state.session_context.time_format == "24h"
      assert state.session_context.theme_id == "amber"
      assert state.session_context.theme == Theme.resolve(:amber)

      account_state = state.screen_state.account
      refute account_state.profile_dirty?
      refute account_state.prefs_dirty?
      assert account_state.candidate_theme_id == nil
      assert account_state.profile_errors == %{}
      assert account_state.prefs_errors == %{}

      _ = :sys.get_state(session_pid)
      session_state = Session.get_state(session_pid)
      assert session_state.timezone == "America/Chicago"
      assert session_state.time_format == "24h"
      assert session_state.theme_id == "amber"
      assert session_state.theme == Theme.resolve(:amber)
    end

    test "failed save result renders errors and leaves active snapshots unchanged" do
      user =
        AccountsFixtures.user_fixture(%{
          location: "Original Cove",
          timezone: "Etc/UTC",
          preferences: %{"time_format" => "12h"},
          theme: "gray"
        })

      {:ok, session_pid} =
        start_supervised(
          {Session, [user_id: user.id, handle: user.handle, role: user.role]},
          id: :account_save_failure_session
        )

      state = %App{
        current_screen: :account,
        current_user: user,
        session_context: %{
          session_pid: session_pid,
          timezone: "Etc/UTC",
          time_format: "12h",
          theme_id: "gray",
          theme: Theme.resolve(:gray)
        },
        session_pid: session_pid,
        terminal_size: {80, 24},
        screen_state: %{
          account:
            AccountState.new(current_user: user)
            |> Map.put(:active_tab, 1)
            |> Map.put(:prefs_dirty?, true)
        }
      }

      original_user = state.current_user
      original_context = state.session_context
      original_session = Session.get_state(session_pid)

      {:error, changeset} =
        Accounts.update_profile(user, %{
          timezone: "Not/AZone",
          preferences: %{"time_format" => "24h"},
          theme: "amber"
        })

      {new_state, []} =
        App.update(
          {:screen_task_result, :account, :account_save_prefs, {:ok, {:error, changeset}}},
          state
        )

      assert new_state.current_user == original_user
      assert new_state.session_context == original_context

      _ = :sys.get_state(session_pid)
      assert Session.get_state(session_pid).timezone == original_session.timezone
      assert Session.get_state(session_pid).time_format == original_session.time_format
      assert Session.get_state(session_pid).theme_id == original_session.theme_id

      assert %{timezone: message} = new_state.screen_state.account.prefs_errors
      assert String.contains?(message, "valid IANA")
      assert match?({:error, _}, new_state.screen_state.account.prefs_form.submit_state)

      flat = render_account(Map.from_struct(new_state)) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "Timezone must be a valid IANA name"))
    end
  end

  describe "live INVITES actions" do
    setup :restore_invite_config

    test "persists exactly one invite and displays last_generated_code under any_user" do
      # FOG-389: scope assertions by code. `Invites.list_invites/1` performs
      # a global Repo.all scan, so async-true tests sharing the connection
      # can leak invite rows into this list. Filter to the code we just
      # generated instead of pattern-matching on absolute list shape.
      user = AccountsFixtures.user_fixture()

      state =
        build_state(user, %{registration_mode: "invite_only", invite_code_generators: "any_user"})

      {:ok, before} = Invites.list_invites(user)

      state = leave_profile_form(state)
      {:update, state, []} = handle_account_key(%{key: :char, char: "4"}, state)
      {:update, state, []} = handle_account_key(%{key: :char, char: "g"}, state)

      generated_code = state.screen_state.account.invites.last_generated_code
      assert is_binary(generated_code)
      refute Enum.find(before, &(&1.code == generated_code))

      assert {:ok, after_invites} = Invites.list_invites(user)
      assert Enum.find(after_invites, &(&1.code == generated_code))

      assert Enum.find(
               state.screen_state.account.invites.items,
               &(&1.code == generated_code and &1.status == :available)
             )

      flat = render_account(state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "Invite code ready: #{generated_code}"))
    end

    test "refresh, select, and revoke delegate through shared Account INVITES actions" do
      # FOG-389: `Invites.list_invites/1` scans every invite row globally,
      # so async-true tests sharing this connection can interleave their
      # invite rows. Scope every assertion to the two fixture codes and
      # drive selection by index-of-known-code instead of trusting absolute
      # ordering.
      user = AccountsFixtures.user_fixture()

      state =
        build_state(user, %{registration_mode: "invite_only", invite_code_generators: "any_user"})

      {:ok, first} = Invites.create_invite(user)
      {:ok, second} = Invites.create_invite(user)
      fixture_codes = [first.code, second.code]

      state = leave_profile_form(state)
      {:update, state, []} = handle_account_key(%{key: :char, char: "4"}, state)
      items = state.screen_state.account.invites.items
      assert Enum.find(items, &(&1.code == first.code))
      assert Enum.find(items, &(&1.code == second.code))

      # Pick a target invite (the second fixture) and drive selection to it
      # by index rather than via blind `:down` presses, since the items list
      # may also contain leaked rows from concurrent async-true tests.
      target_code = second.code
      target_index = Enum.find_index(items, &(&1.code == target_code))
      assert is_integer(target_index)

      state =
        update_in(state.screen_state.account.invites, fn invites ->
          %{invites | selected_index: target_index}
        end)

      # FOG-130 Item 3: D opens the revoke confirm sub-mode; Enter actually
      # calls revoke. The shared invites action then surfaces the forbidden
      # error to the user.
      {:update, state, []} = handle_account_key(%{key: :char, char: "d"}, state)
      assert state.screen_state.account.invites.mode == :confirm_revoke
      assert state.screen_state.account.invites.confirm_target.code == target_code

      {:update, state, []} = handle_account_key(%{key: :enter}, state)
      assert state.screen_state.account.invites.mode == :list
      assert state.screen_state.account.invites.error == "Your account cannot manage invites."

      for code <- fixture_codes do
        assert {:ok, %{status: :available}} = Invites.get_invite_status(code)
      end

      {:update, state, []} = handle_account_key(%{key: :char, char: "r"}, state)
      refreshed = state.screen_state.account.invites.items
      assert Enum.find(refreshed, &(&1.code == first.code))
      assert Enum.find(refreshed, &(&1.code == second.code))
      assert state.screen_state.account.invites.error == nil
    end

    test "hidden INVITES tab leaves generate unavailable for disallowed Account policy" do
      user = AccountsFixtures.user_fixture()

      state =
        build_state(user, %{
          registration_mode: "invite_only",
          invite_code_generators: "sysop_only"
        })

      {:ok, before} = Invites.list_invites(user)
      assert {:update, _state, []} = handle_account_key(%{key: :char, char: "g"}, state)
      assert {:ok, ^before} = Invites.list_invites(user)
    end
  end

  describe "live SSH KEYS actions" do
    test "KEYS-03 entering SSH KEYS and refreshing load only the current user's keys" do
      user = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()
      own_key = AccountsFixtures.ssh_key_fixture(user, %{label: "laptop"})

      _other_key =
        AccountsFixtures.ssh_key_fixture(other_user, %{public_key: @alternate_ssh_public_key})

      state = build_state(user, %{}) |> leave_profile_form()

      {:update, state, []} = handle_account_key(%{key: :char, char: "3"}, state)

      assert [%{id: key_id, label: "laptop"}] = state.screen_state.account.ssh_keys.items
      assert key_id == own_key.id

      {:update, state, []} = handle_account_key(%{key: :char, char: "r"}, state)
      assert [%{id: ^key_id}] = state.screen_state.account.ssh_keys.items

      flat = render_account(state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "Refresh"))
      assert Enum.any?(flat, &String.contains?(&1, "Revoke"))
    end

    test "KEYS-02 add flow stores a valid key, refreshes list, and shows status" do
      user = AccountsFixtures.user_fixture()
      state = build_state(user, %{}) |> leave_profile_form()

      {:update, state, []} = handle_account_key(%{key: :char, char: "3"}, state)
      {:update, state, []} = handle_account_key(%{key: :char, char: "a"}, state)

      account_state =
        put_ssh_key_form(state.screen_state.account, %{
          label: "workstation",
          public_key: @alternate_ssh_public_key
        })

      state = put_in(state, [:screen_state, :account], account_state)

      {:update, state, []} = handle_account_key(%{key: :enter}, state)

      assert [%{label: "workstation", fingerprint: "SHA256:" <> _}] = Accounts.list_ssh_keys(user)
      assert state.screen_state.account.ssh_keys.status_message == "SSH key added."
      assert [%{label: "workstation"}] = state.screen_state.account.ssh_keys.items
    end

    test "KEYS-02 add flow shows terminal-visible validation errors" do
      user = AccountsFixtures.user_fixture()
      _existing = AccountsFixtures.ssh_key_fixture(user, %{label: "laptop"})
      state = build_state(user, %{}) |> leave_profile_form()

      {:update, state, []} = handle_account_key(%{key: :char, char: "3"}, state)
      {:update, state, []} = handle_account_key(%{key: :char, char: "a"}, state)
      {:update, blank_state, []} = handle_account_key(%{key: :enter}, state)

      blank_flat = render_account(blank_state) |> collect_text_values()
      assert Enum.any?(blank_flat, &String.contains?(&1, "Label is required."))
      assert Enum.any?(blank_flat, &String.contains?(&1, "Public key is required."))

      account_state =
        put_ssh_key_form(blank_state.screen_state.account, %{
          label: "bad",
          public_key: "invalid OpenSSH material"
        })

      invalid_state = put_in(blank_state, [:screen_state, :account], account_state)

      {:update, invalid_state, []} = handle_account_key(%{key: :enter}, invalid_state)
      invalid_flat = render_account(invalid_state) |> collect_text_values()
      assert Enum.any?(invalid_flat, &String.contains?(&1, "valid OpenSSH public key"))

      account_state =
        put_ssh_key_form(invalid_state.screen_state.account, %{
          label: "other",
          public_key: AccountsFixtures.default_ssh_public_key()
        })

      duplicate_fingerprint_state =
        put_in(invalid_state, [:screen_state, :account], account_state)

      {:update, duplicate_fingerprint_state, []} =
        handle_account_key(%{key: :enter}, duplicate_fingerprint_state)

      duplicate_fingerprint_flat =
        duplicate_fingerprint_state |> render_account() |> collect_text_values()

      assert Enum.any?(
               duplicate_fingerprint_flat,
               &String.contains?(&1, "That public key is already on this account.")
             )

      account_state =
        put_ssh_key_form(duplicate_fingerprint_state.screen_state.account, %{
          label: "laptop",
          public_key: @alternate_ssh_public_key
        })

      duplicate_label_state =
        put_in(duplicate_fingerprint_state, [:screen_state, :account], account_state)

      {:update, duplicate_label_state, []} =
        handle_account_key(%{key: :enter}, duplicate_label_state)

      duplicate_label_flat = duplicate_label_state |> render_account() |> collect_text_values()

      assert Enum.any?(
               duplicate_label_flat,
               &String.contains?(&1, "You already have an SSH key with that label.")
             )
    end

    test "KEYS-04 revoke selected key refreshes list and reports missing selections" do
      user = AccountsFixtures.user_fixture()
      first = AccountsFixtures.ssh_key_fixture(user, %{label: "first"})

      second =
        AccountsFixtures.ssh_key_fixture(user, %{
          label: "second",
          public_key: @alternate_ssh_public_key
        })

      state = build_state(user, %{}) |> leave_profile_form()

      {:update, state, []} = handle_account_key(%{key: :char, char: "3"}, state)
      {:update, state, []} = handle_account_key(%{key: :down}, state)
      assert state.screen_state.account.ssh_keys.selected_index == 1

      # FOG-130 Item 2: D opens the revoke confirmation; Enter actually
      # performs the destructive action.
      {:update, state, []} = handle_account_key(%{key: :char, char: "d"}, state)
      assert state.screen_state.account.ssh_keys.mode == :confirm_revoke
      assert state.screen_state.account.ssh_keys.confirm_target.label == "second"

      {:update, state, []} = handle_account_key(%{key: :enter}, state)

      assert state.screen_state.account.ssh_keys.mode == :list
      assert state.screen_state.account.ssh_keys.status_message == "SSH key revoked."
      assert [%{id: remaining_id}] = state.screen_state.account.ssh_keys.items
      assert remaining_id == first.id
      assert [%{id: ^remaining_id}] = Accounts.list_ssh_keys(user)
      refute Enum.any?(Accounts.list_ssh_keys(user), &(&1.id == second.id))

      account_state = %{
        state.screen_state.account
        | ssh_keys: SSHKeysState.loaded(state.screen_state.account.ssh_keys, [])
      }

      empty_state = put_in(state, [:screen_state, :account], account_state)

      # On an empty list D refuses to open the confirm sub-mode and surfaces
      # the friendly selection error directly.
      {:update, empty_state, []} = handle_account_key(%{key: :char, char: "d"}, empty_state)
      assert empty_state.screen_state.account.ssh_keys.mode == :list

      assert empty_state.screen_state.account.ssh_keys.errors.general ==
               "Select an SSH key first."
    end

    test "KEYS-04 revoke handles not found without crashing" do
      user = AccountsFixtures.user_fixture()
      key = AccountsFixtures.ssh_key_fixture(user)
      state = build_state(user, %{}) |> leave_profile_form()

      {:update, state, []} = handle_account_key(%{key: :char, char: "3"}, state)
      {:ok, _revoked} = Accounts.revoke_ssh_key(user, key.id)

      {:update, state, []} = handle_account_key(%{key: :char, char: "d"}, state)
      assert state.screen_state.account.ssh_keys.mode == :confirm_revoke

      {:update, state, []} = handle_account_key(%{key: :enter}, state)

      assert state.screen_state.account.ssh_keys.errors.general ==
               "That SSH key is no longer here. Refresh the list."
    end

    test "FOG-142: digit chars typed in SSH KEYS add mode insert into focused field, not tab nav" do
      user = AccountsFixtures.user_fixture()
      state = build_state(user, %{})

      # FOG-717: navigate to SSH KEYS without using the digit shortcut.
      # PROFILE shields digit/cursor keys while a text field is focused.
      # Park on PREFS first (no text shield) then arrow into SSH KEYS.
      state = leave_profile_form(state)
      {:update, state, []} = handle_account_key(%{key: :right}, state)
      assert state.screen_state.account.active_tab == 2
      {:update, state, []} = handle_account_key(%{key: :char, char: "a"}, state)
      assert state.screen_state.account.ssh_keys.mode == :add
      assert state.screen_state.account.ssh_keys.focus == :label

      # Digits in label field must NOT switch tabs.
      state =
        Enum.reduce(~w(1 2 3 4 5 6 7 8 9 0), state, fn digit, acc ->
          {:update, acc, []} = handle_account_key(%{key: :char, char: digit}, acc)

          assert acc.screen_state.account.active_tab == 2,
                 "digit #{digit} in label field switched tabs"

          acc
        end)

      assert state.screen_state.account.ssh_keys.form.label == "1234567890"

      # Tab to public key field; digits there must also be inserted, not consumed.
      {:update, state, []} = handle_account_key(%{key: :tab}, state)
      assert state.screen_state.account.ssh_keys.focus == :public_key

      pk_chars = ~w(s s h - e d 2 5 5 1 9)

      state =
        Enum.reduce(pk_chars, state, fn ch, acc ->
          {:update, acc, []} = handle_account_key(%{key: :char, char: ch}, acc)

          assert acc.screen_state.account.active_tab == 2,
                 "char #{ch} in public_key field switched tabs"

          acc
        end)

      assert state.screen_state.account.ssh_keys.form.public_key == "ssh-ed25519"
    end

    test "FOG-142: digit chars are still tab shortcuts in SSH KEYS list mode" do
      user = AccountsFixtures.user_fixture()
      state = build_state(user, %{})

      # FOG-717: PROFILE shields digit/cursor keys while a text field is
      # focused. Park on PREFS first then arrow into SSH KEYS list mode.
      state = leave_profile_form(state)
      {:update, state, []} = handle_account_key(%{key: :right}, state)
      assert state.screen_state.account.active_tab == 2
      assert state.screen_state.account.ssh_keys.mode == :list

      # No add form active and no text-form focus — digits remain tab
      # shortcuts (jump to PROFILE).
      {:update, state, []} = handle_account_key(%{key: :char, char: "1"}, state)
      assert state.screen_state.account.active_tab == 0
    end

    test "FOG-333: digit chars typed in PROFILE text fields insert into the focused field, not tab nav" do
      alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

      user = AccountsFixtures.user_fixture()

      state =
        build_state(user, %{})
        |> put_in([:screen_state, :account], AccountState.new(current_user: user))

      account = state.screen_state.account
      assert account.active_tab == 0
      assert Enum.at(account.profile_form.fields, 0).name == :location

      original_location = ModalForm.field_value(account.profile_form, :location)

      # Location (index 0): every digit must insert and not switch tabs.
      state =
        Enum.reduce(~w(2 3 4 5 6 7 8 9 0 1), state, fn digit, acc ->
          {:update, acc, []} = handle_account_key(%{key: :char, char: digit}, acc)

          assert acc.screen_state.account.active_tab == 0,
                 "digit #{digit} in Location switched tabs"

          acc
        end)

      location_after = ModalForm.field_value(state.screen_state.account.profile_form, :location)
      assert location_after =~ "2345678901"
      refute location_after == original_location

      # Tagline (index 1)
      {:update, state, []} = handle_account_key(%{key: :tab}, state)
      assert state.screen_state.account.profile_form.focus_index == 1
      {:update, state, []} = handle_account_key(%{key: :char, char: "2"}, state)
      assert state.screen_state.account.active_tab == 0
      assert ModalForm.field_value(state.screen_state.account.profile_form, :tagline) =~ "2"

      # Real name (index 2)
      {:update, state, []} = handle_account_key(%{key: :tab}, state)
      assert state.screen_state.account.profile_form.focus_index == 2
      {:update, state, []} = handle_account_key(%{key: :char, char: "3"}, state)
      assert state.screen_state.account.active_tab == 0
      assert ModalForm.field_value(state.screen_state.account.profile_form, :real_name) =~ "3"
    end

    test "FOG-333/FOG-350: digit chars on PREFS still switch tabs (focused field is select-list)" do
      user = AccountsFixtures.user_fixture()

      state =
        build_state(user, %{})
        |> put_in([:screen_state, :account], AccountState.new(current_user: user))

      # FOG-717: PROFILE shields cursor/edit keys when a text field is
      # focused, so step out of the form via the helper. From PREFS, the
      # blank timezone select-list keeps digit tab shortcuts available so
      # users can still jump tabs.
      state = leave_profile_form(state)
      assert state.screen_state.account.active_tab == 1

      focused_field =
        Enum.at(
          state.screen_state.account.prefs_form.fields,
          state.screen_state.account.prefs_form.focus_index
        )

      assert focused_field.type == :select_list

      {:update, state, _} = handle_account_key(%{key: :char, char: "3"}, state)
      assert state.screen_state.account.active_tab == 2
    end
  end

  # ---------------------------------------------------------------------------
  # Phase 25 Plan 05 — Per-tab theme hygiene (D-12)
  # ---------------------------------------------------------------------------

  describe "Phase 25 theme hygiene (D-12)" do
    import Foglet.TUI.WidgetHelpers
    import Foglet.TUI.LayoutSmokeHelpers

    for tab <- ["PROFILE", "PREFS", "SSH KEYS"] do
      @tab tab
      test "converted Account #{tab} tab leaks no color atoms" do
        ss =
          AccountState.new()
          |> set_active_tab(@tab)

        state =
          build_state_for_role(:user)
          |> put_in([:screen_state, :account], ss)

        serialized = state |> render_account() |> inspect(limit: :infinity)

        for color <- color_names() do
          refute color_atom_leaked?(serialized, color),
                 "leaked :#{color} in converted Account #{@tab} tab"
        end
      end
    end
  end

  defp restore_invite_config(_context) do
    Config.init_cache()
    current_generators = Config.get("invite_code_generators", "sysops")
    current_registration_mode = Config.get("registration_mode", "open")
    current_limit = Config.get("invite_generation_per_user_limit", 0)

    on_exit(fn ->
      Config.put!("invite_code_generators", current_generators)
      Config.put!("registration_mode", current_registration_mode)
      Config.put!("invite_generation_per_user_limit", current_limit)
      Config.invalidate("invite_code_generators")
      Config.invalidate("registration_mode")
      Config.invalidate("invite_generation_per_user_limit")
    end)

    Config.put!("registration_mode", "invite_only")
    Config.put!("invite_code_generators", "any_user")
    Config.put!("invite_generation_per_user_limit", 0)
    :ok
  end

  defp put_ssh_key_form(account_state, form) do
    %{account_state | ssh_keys: %{account_state.ssh_keys | form: form}}
  end

  defp build_user_with_profile(opts \\ []) do
    %Foglet.Accounts.User{
      id: "u-honest-esc",
      handle: "alice",
      role: :user,
      location: Keyword.get(opts, :location, "Berlin"),
      tagline: Keyword.get(opts, :tagline, "hi"),
      real_name: Keyword.get(opts, :real_name, "Brendan"),
      timezone: Keyword.get(opts, :timezone, "Etc/UTC"),
      preferences: Keyword.get(opts, :preferences, %{"time_format" => "12h"}),
      theme: Keyword.get(opts, :theme, "gray")
    }
  end

  # ---------------------------------------------------------------------------
  # Phase 28 Plan 03 — FORM-06 honest Esc (D-10, D-11)
  # ---------------------------------------------------------------------------

  describe "FORM-06 honest Esc on Account Profile (Phase 28 D-10, D-11)" do
    alias Foglet.TUI.Screens.Account.ProfileForm
    alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

    test "Esc reseeds profile_draft to saved-user values, clears dirty + status_message" do
      user = build_user_with_profile()
      ss = AccountState.new(current_user: user)

      # Mutate the live form by typing a char into the focused field
      # (focus starts at :location — first field).
      {form_after_type, nil} =
        ModalForm.handle_event(%{key: :char, char: "X"}, ss.profile_form)

      # Sanity: the typing event mutated :location away from "Berlin" (we don't
      # care about cursor position — only that the live form differs from the
      # saved-user value, which is what Esc must reseed away).
      assert ModalForm.field_value(form_after_type, :location) != "Berlin"
      assert ModalForm.field_value(form_after_type, :location) =~ "X"

      ss_dirty = %{ss | profile_form: form_after_type, profile_dirty?: true}

      {:ok, after_esc, cmds} = ProfileForm.handle_key(%{key: :escape}, ss_dirty, user)

      assert after_esc.profile_draft == %{
               location: "Berlin",
               tagline: "hi",
               real_name: "Brendan"
             }

      assert after_esc.profile_dirty? == false
      assert after_esc.status_message == nil
      assert cmds == []

      # And the rendered form's first-field value reverted on the next render.
      assert ModalForm.field_value(after_esc.profile_form, :location) == "Berlin"
    end

    test "Esc on Account Profile does not produce any 'discarded' status copy" do
      user = build_user_with_profile()
      ss = AccountState.new(current_user: user)

      {form_after_type, nil} =
        ModalForm.handle_event(%{key: :char, char: "X"}, ss.profile_form)

      ss_dirty = %{ss | profile_form: form_after_type, profile_dirty?: true}

      {:ok, after_esc, []} = ProfileForm.handle_key(%{key: :escape}, ss_dirty, user)

      # No status_message, and no "discarded" text anywhere in the state map.
      assert after_esc.status_message == nil

      serialized = inspect(after_esc, limit: :infinity)
      refute serialized =~ "Profile changes discarded"
      refute serialized =~ "discarded"
    end
  end

  describe "FORM-06 honest Esc on Account Preferences (Phase 28 D-10, D-11)" do
    alias Foglet.TUI.Screens.Account.PrefsForm
    alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

    test "Esc reseeds prefs_draft to saved-user values, clears dirty + status_message" do
      user = build_user_with_profile()
      ss = AccountState.new(current_user: user)

      # Mutate the live prefs form by searching/selecting the focused timezone select-list
      # (focus starts at :timezone — first field).
      {form_after_search, nil} = ModalForm.handle_event(%{key: :char, char: "C"}, ss.prefs_form)

      {form_after_search, nil} =
        ModalForm.handle_event(%{key: :char, char: "h"}, form_after_search)

      {form_after_pick, nil} = ModalForm.handle_event(%{key: :enter}, form_after_search)

      # Sanity: selection moved :timezone off the seeded "Etc/UTC".
      assert ModalForm.field_value(form_after_pick, :timezone) == "America/Chicago"

      ss_dirty = %{
        ss
        | prefs_form: form_after_pick,
          prefs_dirty?: true,
          candidate_theme_id: "amber"
      }

      {:ok, after_esc, cmds} = PrefsForm.handle_key(%{key: :escape}, ss_dirty, user)

      assert after_esc.prefs_draft == %{
               timezone: "Etc/UTC",
               time_format: "12h",
               theme: "gray"
             }

      assert after_esc.prefs_dirty? == false
      assert after_esc.status_message == nil
      assert after_esc.candidate_theme_id == nil
      assert cmds == []

      assert ModalForm.field_value(after_esc.prefs_form, :timezone) == "Etc/UTC"
    end

    test "Esc on Account Preferences does not produce any 'discarded' status copy" do
      user = build_user_with_profile()
      ss = AccountState.new(current_user: user)

      {form_after_pick, nil} =
        ModalForm.handle_event(%{key: :down}, ss.prefs_form)

      ss_dirty = %{ss | prefs_form: form_after_pick, prefs_dirty?: true}

      {:ok, after_esc, []} = PrefsForm.handle_key(%{key: :escape}, ss_dirty, user)

      assert after_esc.status_message == nil

      serialized = inspect(after_esc, limit: :infinity)
      refute serialized =~ "Preference changes discarded"
      refute serialized =~ "discarded"
    end
  end

  describe "PROFILE Modal.Form contract" do
    test "suppresses redundant Modal.Form title and footer (FORM-03 default-off)" do
      # Phase 28 FORM-03 / D-06 plus FOG-710 account polish: Account tab-body
      # forms do NOT render Modal.Form title/footer chrome; the selected tab
      # and global command bar are the single screen-level labels/advertisers.
      state =
        build_state_for_role(:user)
        |> put_in([:screen_state, :account], AccountState.new())

      flat = render_account(state) |> collect_text_values()

      refute Enum.any?(flat, &(&1 == "Profile")),
             "Modal.Form title must NOT duplicate the selected Account tab label"

      refute Enum.any?(flat, &String.contains?(&1, "[Enter] Submit")),
             "Modal.Form footer must NOT appear in Account tab body (Phase 28 D-06)"
    end

    test "builds labeled field rows for each profile field" do
      ss = AccountState.new()

      assert Enum.map(ss.profile_form.fields, & &1.label) == ["Location", "Tagline", "Real name"]
    end

    test "real_name is optional (FOG-130 Item 6 reconciliation with domain validation)" do
      ss = AccountState.new()

      # Real name is NOT required at the form level because
      # User.profile_changeset/2 does not require it. Domain truth wins.
      assert [] = Enum.filter(ss.profile_form.fields, &Map.get(&1, :required, false))

      assert Enum.find(ss.profile_form.fields, &(&1.name == :real_name)) ==
               %{
                 name: :real_name,
                 type: :text,
                 label: "Real name",
                 description: "For friends and the sysop; blank uses your handle.",
                 value: ""
               }
    end

    test "renders inline error text when set_errors is applied" do
      ss = AccountState.new()

      alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

      ss_with_error = %{
        ss
        | profile_form: ModalForm.set_errors(ss.profile_form, %{location: "is too short"})
      }

      state =
        build_state_for_role(:user)
        |> put_in([:screen_state, :account], ss_with_error)

      flat = render_account(state) |> collect_text_values()

      assert Enum.any?(flat, &String.contains?(&1, "is too short")),
             "expected inline error 'is too short' in profile tab render"
    end
  end

  describe "PREFS Modal.Form contract" do
    setup %{state: state} do
      # FOG-333: PROFILE shields digit shortcuts while a text field is
      # focused. Move out of the form before using the digit shortcut.
      state = leave_profile_form(state)
      {:update, prefs_state, []} = handle_account_key(%{key: :char, char: "2"}, state)
      %{state: prefs_state}
    end

    test "suppresses Modal.Form footer in prefs tab (FORM-03 default-off)", %{state: state} do
      # Phase 28 FORM-03 / D-06: Account tab-body forms do NOT render the
      # Modal.Form footer; the global command bar advertises [Enter]/[Esc].
      flat = render_account(state) |> collect_text_values()

      refute Enum.any?(flat, &String.contains?(&1, "[Enter] Submit")),
             "Modal.Form footer must NOT appear in Prefs tab body (Phase 28 D-06)"
    end

    test "defines enum field for theme selection", %{state: state} do
      form = state.screen_state.account.prefs_form

      assert Enum.any?(form.fields, &match?(%{name: :theme, type: :enum}, &1)),
             "expected theme enum field in prefs form spec"
    end

    test "FOG-131/FOG-350: timezone is a searchable select-list, not a raw text field", %{
      state: state
    } do
      form = state.screen_state.account.prefs_form
      tz = Enum.find(form.fields, &(&1.name == :timezone))

      assert tz.type == :select_list, "expected :timezone field to be a searchable select-list"
      assert is_list(tz.choices) and length(tz.choices) > 1
      assert "Etc/UTC" in tz.choices
      assert "America/Chicago" in tz.choices
    end

    test "FOG-350: searching timezone select-list changes the picker value without saving" do
      alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

      user = build_user_with_profile(timezone: "Etc/UTC")
      ss = AccountState.new(current_user: user)

      {form1, nil} = ModalForm.handle_event(%{key: :char, char: "C"}, ss.prefs_form)
      {form1, nil} = ModalForm.handle_event(%{key: :char, char: "h"}, form1)
      {form2, action} = ModalForm.handle_event(%{key: :enter}, form1)

      assert action == nil, "selecting must not emit a submit action (save-only-on-save)"
      assert ModalForm.field_value(form2, :timezone) == "America/Chicago"

      assert ModalForm.field_value(form2, :timezone) in Foglet.TUI.Screens.Account.Timezones.curated()
    end

    test "FOG-131: a non-curated saved timezone is preserved in picker choices" do
      user = build_user_with_profile(timezone: "Pacific/Tarawa")
      ss = AccountState.new(current_user: user)

      tz = Enum.find(ss.prefs_form.fields, &(&1.name == :timezone))

      assert "Pacific/Tarawa" in tz.choices,
             "user's saved timezone must remain selectable even if not curated"

      assert Foglet.TUI.Widgets.Modal.Form.field_value(ss.prefs_form, :timezone) ==
               "Pacific/Tarawa"
    end

    test "FOG-350/FOG-498: timezone select-list is height-bounded", %{state: state} do
      tz = Enum.find(state.screen_state.account.prefs_form.fields, &(&1.name == :timezone))

      assert Map.get(tz, :max_height) == 6
    end

    test "FOG-350/FOG-498: PREFS render contains a searchable bounded timezone picker",
         %{state: state} do
      flat = render_account(state) |> collect_text_values()

      curated = Foglet.TUI.Screens.Account.Timezones.curated()

      visible_timezone_rows =
        Enum.filter(flat, fn line ->
          is_binary(line) and Enum.any?(curated, &String.contains?(line, &1))
        end)

      assert Enum.any?(flat, &(is_binary(&1) and String.contains?(&1, "Type to filter")))
      assert length(visible_timezone_rows) <= 6
      assert Enum.any?(visible_timezone_rows, &String.contains?(&1, "Etc/UTC"))

      # Time format and Theme labels must remain visible alongside the
      # bounded picker — overlap was the original symptom.
      assert Enum.any?(flat, &(is_binary(&1) and String.contains?(&1, "Time format"))),
             "Time format label must still render after the bounded timezone picker (FOG-132)"

      assert Enum.any?(flat, &(is_binary(&1) and String.contains?(&1, "Theme"))),
             "Theme label must still render after the bounded timezone picker (FOG-132)"
    end

    test "cycling down on focused theme enum field updates candidate_theme_id" do
      user = %Foglet.Accounts.User{
        id: "u1",
        handle: "alice",
        role: :user,
        timezone: "Etc/UTC",
        preferences: %{"time_format" => "12h"},
        theme: "gray"
      }

      state =
        user
        |> build_state(%{theme: Theme.resolve(:gray), theme_id: "gray"})
        |> put_in([:screen_state, :account], AccountState.new(current_user: user))

      state = leave_profile_form(state)
      {:update, state, []} = handle_account_key(%{key: :char, char: "2"}, state)

      account_state = %{state.screen_state.account | prefs_focus: :theme}
      state = put_in(state, [:screen_state, :account], account_state)

      {:update, preview_state, []} = handle_account_key(%{key: :down}, state)

      assert preview_state.screen_state.account.candidate_theme_id != nil,
             "expected candidate_theme_id to be set after cycling theme enum field down"
    end
  end

  describe "SSH_KEYS table contract" do
    setup %{state: state} do
      inserted_at = ~U[2026-04-24 10:11:12.123456Z]

      account_state =
        AccountState.new()
        |> Map.put(:active_tab, 2)
        |> Map.put(
          :ssh_keys,
          Foglet.TUI.Screens.Account.SSHKeysState.loaded(
            Foglet.TUI.Screens.Account.SSHKeysState.new(),
            [
              %{
                id: "k1",
                label: "qa generated",
                fingerprint: "SHA256:HSP2xRpOjIsJVABCDE1234567890realisticfingerprint",
                inserted_at: inserted_at,
                last_used_at: nil,
                public_key: "ssh-ed25519 AAAAC3 laptop@test"
              }
            ]
          )
        )

      state = put_in(state, [:screen_state, :account], account_state)
      %{state: state}
    end

    test "builds ConsoleTable columns for SSH key rows", %{state: state} do
      table = state.screen_state.account.ssh_keys.table

      assert Enum.map(table.columns, & &1.label) == [
               "",
               "Label",
               "Fingerprint",
               "Added",
               "Last used"
             ]
    end

    test "renders empty state copy with empty list" do
      state =
        build_state_for_role(:user)
        |> put_in(
          [:screen_state, :account],
          AccountState.new()
          |> Map.put(:active_tab, 2)
          |> Map.put(:ssh_keys, SSHKeysState.loaded(SSHKeysState.new(), []))
        )

      flat = render_account(state) |> collect_text_values()

      assert Enum.any?(
               flat,
               &String.contains?(&1, "No SSH keys yet. Add one to sign in without a password.")
             ),
             "expected empty state copy in SSH KEYS tab"
    end

    test "renders SSH key table with width-aware columns at 80x24 and 64x22", %{state: state} do
      for {terminal_width, terminal_height} <- [
            {80, 24},
            {64, 22}
          ] do
        positioned =
          state
          |> Map.put(:terminal_size, {terminal_width, terminal_height})
          |> render_account()
          |> Engine.apply_layout(%{width: terminal_width, height: terminal_height})
          |> List.flatten()

        header = ssh_key_table_row(positioned, "Label")
        row = ssh_key_table_row(positioned, "qa generated")

        assert [header_marker, label, fingerprint, added, last_used] = header
        assert String.trim(header_marker.text) == ""
        assert header_marker.x == 2
        assert label.x > header_marker.x
        assert fingerprint.x > label.x
        assert added.x > fingerprint.x
        assert last_used.x > added.x
        assert TextWidth.display_width(label.text) > TextWidth.display_width("Label")

        assert [row_marker, row_label, row_fingerprint, row_added, row_last_used] = row
        assert row_marker.x == header_marker.x
        assert String.trim(row_marker.text) == "▶"
        assert row_label.x == label.x
        assert row_fingerprint.x == fingerprint.x
        assert row_added.x == added.x
        assert row_last_used.x == last_used.x

        assert TextWidth.display_width(row_fingerprint.text) <=
                 TextWidth.display_width(fingerprint.text)

        assert TextWidth.display_width(row_added.text) <= TextWidth.display_width(added.text)

        assert TextWidth.display_width(row_last_used.text) <=
                 TextWidth.display_width(last_used.text)
      end
    end

    test "selected marker moves between multiple SSH keys and survives cramped render" do
      keys =
        SSHKeysState.new()
        |> SSHKeysState.loaded([
          %{
            id: "k1",
            label: "personal laptop with a very long label",
            fingerprint: "SHA256:first-key-fingerprint-that-will-truncate-in-the-table",
            inserted_at: ~U[2026-04-24 10:11:12Z],
            last_used_at: nil
          },
          %{
            id: "k2",
            label: "workstation revoked-ish long label",
            fingerprint: "SHA256:second-key-fingerprint-that-will-truncate-in-the-table",
            inserted_at: ~U[2026-04-25 10:11:12Z],
            last_used_at: ~U[2026-04-26 10:11:12Z]
          }
        ])

      assert selected_markers(keys) == ["▶", ""]

      after_down = SSHKeysState.select_next(keys)
      assert after_down.selected_index == 1
      assert selected_markers(after_down) == ["", "▶"]

      # Clamp at the bottom instead of losing focus.
      after_second_down = SSHKeysState.select_next(after_down)
      assert after_second_down.selected_index == 1
      assert selected_markers(after_second_down) == ["", "▶"]

      after_up = SSHKeysState.select_prev(after_second_down)
      assert after_up.selected_index == 0
      assert selected_markers(after_up) == ["▶", ""]

      account_state =
        AccountState.new()
        |> Map.put(:active_tab, 2)
        |> Map.put(:ssh_keys, after_down)

      for {terminal_width, terminal_height, selected_label} <- [
            {80, 24, "workstation"},
            {58, 18, "workstation"}
          ] do
        positioned =
          build_state_for_role(:user)
          |> Map.put(:terminal_size, {terminal_width, terminal_height})
          |> put_in([:screen_state, :account], account_state)
          |> render_account()
          |> Engine.apply_layout(%{width: terminal_width, height: terminal_height})
          |> List.flatten()

        row = ssh_key_table_row(positioned, selected_label)
        assert [%{text: marker} | _] = row
        assert String.trim(marker) == "▶"
      end
    end

    test "pressing down on non-empty list advances cursor without crash", %{state: state} do
      result = handle_account_key(%{key: :down}, state)
      assert match?({:update, _, _}, result) or result == :no_match
    end

    test "pressing up, down, enter on empty list does not crash" do
      state =
        build_state_for_role(:user)
        |> put_in(
          [:screen_state, :account],
          AccountState.new()
          |> Map.put(:active_tab, 2)
          |> Map.put(:ssh_keys, SSHKeysState.loaded(SSHKeysState.new(), []))
        )

      for key <- [%{key: :up}, %{key: :down}, %{key: :enter}] do
        result = handle_account_key(key, state)

        assert match?({:update, _, _}, result) or result == :no_match,
               "expected no crash for key #{inspect(key)} on empty SSH KEYS list"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Phase 28 Plan 05 — WR-01 :backtab on Account ProfileForm / PrefsForm
  # ---------------------------------------------------------------------------

  describe "FORM-02 :backtab on Account ProfileForm / PrefsForm (Phase 28 WR-01)" do
    alias Foglet.TUI.Screens.Account.PrefsForm
    alias Foglet.TUI.Screens.Account.ProfileForm
    alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

    test "FORM-02 :backtab on ProfileForm retreats focus by one" do
      user = build_user_with_profile()
      ss = AccountState.new(current_user: user)

      # Advance focus 0 → 1 via Tab so :backtab has somewhere to retreat to.
      {:ok, ss, []} = ProfileForm.handle_key(%{key: :tab}, ss, user)
      assert ss.profile_form.focus_index == 1

      {:ok, after_backtab, []} = ProfileForm.handle_key(%{key: :backtab}, ss, user)

      assert after_backtab.profile_form.focus_index == 0,
             "WR-01: :backtab on ProfileForm should retreat focus to 0; " <>
               "got focus_index = #{inspect(after_backtab.profile_form.focus_index)}"
    end

    test "FORM-02 :backtab on PrefsForm retreats focus by one" do
      user = build_user_with_profile()
      ss = AccountState.new(current_user: user)

      # Advance focus 0 → 1 (timezone → time_format enum).
      {:ok, ss, []} = PrefsForm.handle_key(%{key: :tab}, ss, user)
      assert ss.prefs_form.focus_index == 1

      {:ok, after_backtab, []} = PrefsForm.handle_key(%{key: :backtab}, ss, user)

      assert after_backtab.prefs_form.focus_index == 0,
             "WR-01: :backtab on PrefsForm should retreat focus to 0; " <>
               "got focus_index = #{inspect(after_backtab.prefs_form.focus_index)}"
    end

    test "WR-01 sanity: :backtab on PrefsForm preserves focused field via Modal.Form path" do
      # Equivalence check: Modal.Form treats :backtab ≡ :shift_tab. After WR-01
      # lands, ProfileForm/PrefsForm route :backtab into that path instead of
      # dropping it on the floor with :no_match.
      user = build_user_with_profile()
      ss = AccountState.new(current_user: user)

      {:ok, ss, []} = PrefsForm.handle_key(%{key: :tab}, ss, user)
      {:ok, ss, []} = PrefsForm.handle_key(%{key: :tab}, ss, user)
      assert ss.prefs_form.focus_index == 2

      {:ok, after_backtab, []} = PrefsForm.handle_key(%{key: :backtab}, ss, user)
      assert after_backtab.prefs_form.focus_index == 1

      # Verify the form's enum value was not silently mutated by routing
      # :backtab through an unintended clause.
      assert ModalForm.field_value(after_backtab.prefs_form, :time_format) ==
               ModalForm.field_value(ss.prefs_form, :time_format)
    end
  end

  # ---------------------------------------------------------------------------
  # Phase 28 Plan 05 — BL-01 :form modal lock release on async failure
  # ---------------------------------------------------------------------------

  describe "BL-01 :form modal lock release (Phase 28 FORM-05)" do
    alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

    setup do
      Process.put(:fake_oneliners_owner, self())

      user = %Foglet.Accounts.User{
        id: "u-bl01",
        handle: "alice",
        role: :mod,
        confirmed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
      }

      {:ok, state} =
        App.init(%{
          session_context: %{
            user: user,
            user_id: user.id,
            domain: %{oneliners: Foglet.TUI.FakeOneliners}
          }
        })

      %{state: state, user: user}
    end

    defp open_oneliner_composer(state) do
      App.update({:key, %{key: :char, char: "O"}}, state)
    end

    defp open_hide_oneliner_modal(state) do
      {with_oneliner, []} =
        App.update(
          {:screen_task_result, :main_menu, :load_oneliners,
           {:ok, [%{id: "ol-bl01", body: "hello", user: %{handle: "bob"}}]}},
          state
        )

      App.update({:key, %{key: :char, char: "H"}}, with_oneliner)
    end

    test "doomed oneliner submit leaves form in {:error, _} (not :submitting)",
         %{state: state} do
      {with_modal, []} = open_oneliner_composer(state)

      # Drive the form to :submitting via the natural Enter-on-last-field path.
      {submitting, cmds} =
        App.update({:key, %{key: :enter}}, with_modal)

      assert %Foglet.TUI.Modal{type: :form, message: %ModalForm{} = form} = submitting.modal
      assert form.submit_state == :submitting
      assert [%Raxol.Core.Runtime.Command{type: :task}] = cmds

      {after_error, []} =
        App.update(
          {:screen_task_result, :main_menu, :submit_oneliner,
           {:ok, {:error, :same_user_latest_visible}}},
          submitting
        )

      assert %Foglet.TUI.Modal{type: :form, message: %ModalForm{} = form} =
               after_error.modal

      assert match?({:error, _}, form.submit_state)
    end

    test "doomed hide-oneliner submit leaves form in {:error, _} (not :submitting)",
         %{state: state} do
      {with_modal, []} = open_hide_oneliner_modal(state)

      # Type a valid reason then Enter to drive :submitting.
      {with_text, _} =
        App.update({:key, %{key: :char, char: "x"}}, with_modal)

      {submitting, cmds} =
        App.update({:key, %{key: :enter}}, with_text)

      assert %Foglet.TUI.Modal{type: :form, message: %ModalForm{} = form} = submitting.modal
      assert form.submit_state == :submitting
      assert [%Raxol.Core.Runtime.Command{type: :task}] = cmds

      {after_error, []} =
        App.update(
          {:screen_task_result, :main_menu, :submit_hide_oneliner, {:ok, {:error, :forbidden}}},
          submitting
        )

      assert %Foglet.TUI.Modal{type: :form, message: %ModalForm{} = form} =
               after_error.modal

      assert match?({:error, _}, form.submit_state)
    end

    test "after doomed oneliner error, %{key: :escape} dismisses the modal", %{state: state} do
      {with_modal, []} = open_oneliner_composer(state)
      {submitting, _cmds} = App.update({:key, %{key: :enter}}, with_modal)

      {after_error, []} =
        App.update(
          {:screen_task_result, :main_menu, :submit_oneliner,
           {:ok, {:error, :same_user_latest_visible}}},
          submitting
        )

      # Today the form is still locked at :submitting and the lock-guard
      # swallows :escape. After the BL-01 fix, set_submit_state has run, the
      # auto-reset preamble collapses {:error, _} → :idle, and the Esc cancel
      # clause fires → modal dismisses.
      {after_esc, _cmds} = App.update({:key, %{key: :escape}}, after_error)

      assert after_esc.modal == nil,
             "BL-01: Esc must dismiss modal after a doomed submit; modal still open: " <>
               inspect(after_esc.modal)
    end

    test "after doomed hide-oneliner error, %{key: :escape} dismisses the modal",
         %{state: state} do
      {with_modal, []} = open_hide_oneliner_modal(state)
      {with_text, _} = App.update({:key, %{key: :char, char: "x"}}, with_modal)
      {submitting, _cmds} = App.update({:key, %{key: :enter}}, with_text)

      {after_error, []} =
        App.update(
          {:screen_task_result, :main_menu, :submit_hide_oneliner, {:ok, {:error, :forbidden}}},
          submitting
        )

      {after_esc, _cmds} = App.update({:key, %{key: :escape}}, after_error)

      assert after_esc.modal == nil,
             "BL-01: Esc must dismiss hide-modal after a doomed submit; modal still open: " <>
               inspect(after_esc.modal)
    end
  end

  # ---------------------------------------------------------------------------
  # FOG-130 — context-aware key bar, revoke confirms, PREFS enum hint
  # ---------------------------------------------------------------------------

  describe "FOG-130 Item 1: tab-context-aware key bar" do
    # Account chrome at 80×24 is tight enough that the priority-truncating key
    # bar drops the Actions group on some tabs. We render at a wider terminal
    # so every advertised command shows up in `collect_text_values/1`.
    defp wide_terminal(state), do: %{state | terminal_size: {140, 30}}

    test "PROFILE shows form-tab cluster (Tab Next, Enter Save, Esc Cancel)" do
      state =
        build_state_for_role(:user)
        |> wide_terminal()
        |> put_in([:screen_state, :account], AccountState.new())

      joined = render_account(state) |> collect_text_values() |> Enum.join("|")

      assert String.contains?(joined, "Next"), "expected 'Next' key bar label on PROFILE"
      assert String.contains?(joined, "Save")
      assert String.contains?(joined, "Cancel")
      refute String.contains?(joined, "Add key")
      # "Generate invite" must not advertise on the PROFILE tab key bar.
      refute String.contains?(joined, "Generate invite")
    end

    test "SSH KEYS list mode advertises A Add key / R Refresh / D Revoke key, no Save/Cancel" do
      account_state =
        AccountState.new()
        |> Map.put(:active_tab, 2)
        |> Map.put(:ssh_keys, SSHKeysState.loaded(SSHKeysState.new(), []))

      state =
        build_state_for_role(:user)
        |> wide_terminal()
        |> put_in([:screen_state, :account], account_state)

      joined = render_account(state) |> collect_text_values() |> Enum.join("|")

      assert String.contains?(joined, "Add key")
      assert String.contains?(joined, "Refresh")
      assert String.contains?(joined, "Revoke key")
      # The key bar must not still advertise Save on the SSH KEYS list mode.
      assert not Enum.any?(
               render_account(state) |> collect_text_values(),
               &(&1 == "Save")
             )
    end

    test "SSH KEYS confirm-revoke mode advertises Enter Revoke key / Esc Keep key" do
      keys = SSHKeysState.new()
      keys = SSHKeysState.loaded(keys, [%{id: "k1", label: "laptop", fingerprint: "SHA256:abc"}])
      keys = SSHKeysState.start_confirm_revoke(keys)

      account_state =
        AccountState.new()
        |> Map.put(:active_tab, 2)
        |> Map.put(:ssh_keys, keys)

      state =
        build_state_for_role(:user)
        |> wide_terminal()
        |> put_in([:screen_state, :account], account_state)

      joined = render_account(state) |> collect_text_values() |> Enum.join("|")

      assert String.contains?(joined, "Revoke key")
      assert String.contains?(joined, "Keep key")
      # In confirm-revoke mode, Add key must not be advertised on the key bar.
      refute String.contains?(joined, "Add key")
    end

    test "INVITES list mode advertises G Generate invite / D Revoke invite" do
      state =
        :sysop
        |> build_state_for_role(%{
          registration_mode: "invite_only",
          invite_code_generators: "sysop_only"
        })
        |> wide_terminal()
        |> put_in(
          [:screen_state, :account],
          AccountState.new(invites_visible?: true, active: 3)
          |> Map.update!(:invites, &Foglet.TUI.Screens.Shared.InvitesState.loaded(&1, []))
        )

      joined = render_account(state) |> collect_text_values() |> Enum.join("|")

      assert String.contains?(joined, "Generate invite")
      assert String.contains?(joined, "Revoke invite")
    end

    test "PREFS adds ↑/↓ Change hint when an enum field is focused (Item 4)" do
      ss =
        AccountState.new()
        |> Map.put(:active_tab, 1)
        |> Map.put(:prefs_focus, :theme)

      state =
        build_state_for_role(:user)
        |> put_in([:screen_state, :account], ss)

      joined = render_account(state) |> collect_text_values() |> Enum.join("|")

      assert String.contains?(joined, "Change"),
             "expected ↑/↓ Change hint when Theme enum is focused"
    end

    test "PREFS does not add Change hint when a text field is focused" do
      ss =
        AccountState.new()
        |> Map.put(:active_tab, 1)
        |> Map.put(:prefs_focus, :timezone)

      state =
        build_state_for_role(:user)
        |> put_in([:screen_state, :account], ss)

      flat = render_account(state) |> collect_text_values()

      # The "Change" key-bar label only renders for enum fields. Some surface
      # copy may contain "Change", so anchor on the exact key-bar element.
      refute Enum.any?(flat, &(&1 == "Change")),
             "↑/↓ Change must not advertise when a text field is focused"
    end
  end

  # ---------------------------------------------------------------------------
  # FOG-689 — Modal.Form Save/Cancel must outrank Field/Tabs at 80x24
  # ---------------------------------------------------------------------------
  #
  # Regression: at 80x24 the priority-truncating CommandBar previously dropped
  # the Actions group (Enter/Ctrl+S Save, Esc Cancel) on PROFILE/PREFS because
  # they were tagged at priority 30 while Field Tab/Shift+Tab and Tabs nav
  # were at priority 10. Lower priority numbers are higher retention in the
  # CommandBar, so Save must outrank Field/Tabs to survive compaction.
  describe "FOG-689 Modal.Form Save/Cancel keybar priority at 80x24" do
    test "PROFILE keybar at 80x24 keeps Enter Save (and Esc Cancel) visible" do
      state =
        build_state_for_role(:user)
        |> Map.put(:terminal_size, {80, 24})
        |> put_in([:screen_state, :account], AccountState.new())

      joined = render_account(state) |> collect_text_values() |> Enum.join("|")

      assert String.contains?(joined, "Save"),
             "PROFILE 80x24 keybar must retain the Save action (FOG-689). " <>
               "Got: #{joined}"

      assert String.contains?(joined, "Cancel"),
             "PROFILE 80x24 keybar must retain the Cancel action (FOG-689)."
    end

    test "PREFS keybar at 80x24 keeps Enter Save (and Esc Cancel) visible" do
      ss =
        AccountState.new()
        |> Map.put(:active_tab, 1)

      state =
        build_state_for_role(:user)
        |> Map.put(:terminal_size, {80, 24})
        |> put_in([:screen_state, :account], ss)

      joined = render_account(state) |> collect_text_values() |> Enum.join("|")

      assert String.contains?(joined, "Save"),
             "PREFS 80x24 keybar must retain the Save action (FOG-689). " <>
               "Got: #{joined}"

      assert String.contains?(joined, "Cancel"),
             "PREFS 80x24 keybar must retain the Cancel action (FOG-689)."
    end
  end

  describe "FOG-130 Item 2: SSH KEYS revoke confirmation flow" do
    test "D opens confirm sub-mode without performing the revoke" do
      user = AccountsFixtures.user_fixture()
      key = AccountsFixtures.ssh_key_fixture(user, %{label: "laptop"})
      state = build_state(user, %{}) |> leave_profile_form()

      {:update, state, []} = handle_account_key(%{key: :char, char: "3"}, state)
      {:update, state, []} = handle_account_key(%{key: :char, char: "d"}, state)

      assert state.screen_state.account.ssh_keys.mode == :confirm_revoke
      assert state.screen_state.account.ssh_keys.confirm_target.label == "laptop"
      assert [%{id: still_there}] = Accounts.list_ssh_keys(user)
      assert still_there == key.id
    end

    test "Esc cancels the confirm and leaves the list unchanged" do
      user = AccountsFixtures.user_fixture()
      _ = AccountsFixtures.ssh_key_fixture(user, %{label: "laptop"})
      state = build_state(user, %{}) |> leave_profile_form()

      {:update, state, []} = handle_account_key(%{key: :char, char: "3"}, state)
      {:update, state, []} = handle_account_key(%{key: :char, char: "d"}, state)
      assert state.screen_state.account.ssh_keys.mode == :confirm_revoke

      {:update, state, []} = handle_account_key(%{key: :escape}, state)

      assert state.screen_state.account.ssh_keys.mode == :list
      assert state.screen_state.account.ssh_keys.confirm_target == nil
      assert [_] = Accounts.list_ssh_keys(user)
    end

    test "confirm body shows label + fingerprint and never the raw public key" do
      raw_key = "ssh-ed25519 SECRET-MATERIAL-DO-NOT-LEAK alice@example"

      keys =
        SSHKeysState.loaded(SSHKeysState.new(), [
          %{id: "k1", label: "laptop", fingerprint: "SHA256:abc", public_key: raw_key}
        ])

      keys = SSHKeysState.start_confirm_revoke(keys)

      account_state =
        AccountState.new()
        |> Map.put(:active_tab, 2)
        |> Map.put(:ssh_keys, keys)

      state =
        build_state_for_role(:user)
        |> wide_terminal()
        |> put_in([:screen_state, :account], account_state)

      flat = render_account(state) |> collect_text_values()
      joined = Enum.join(flat, "\n")

      assert Enum.any?(flat, &String.contains?(&1, "Revoke SSH key?"))
      assert String.contains?(joined, "This removes laptop from your account.")
      refute String.contains?(joined, "SECRET-MATERIAL")
    end
  end

  describe "FOG-130 Item 3: INVITES revoke confirmation flow" do
    alias Foglet.TUI.Screens.Shared.InvitesState

    test "D opens confirm sub-mode and Esc cancels back to the list" do
      invites =
        InvitesState.loaded(InvitesState.new(), [
          %{code: "ABC123", status: :available, issuer_id: 1, inserted_at: nil}
        ])

      account_state =
        AccountState.new(invites_visible?: true, active: 3)
        |> Map.put(:invites, invites)

      state =
        build_state_for_role(:sysop, %{
          registration_mode: "invite_only",
          invite_code_generators: "sysop_only"
        })
        |> put_in([:screen_state, :account], account_state)

      {:update, state, []} = handle_account_key(%{key: :char, char: "d"}, state)
      assert state.screen_state.account.invites.mode == :confirm_revoke
      assert state.screen_state.account.invites.confirm_target.code == "ABC123"

      {:update, state, []} = handle_account_key(%{key: :escape}, state)
      assert state.screen_state.account.invites.mode == :list
      assert state.screen_state.account.invites.confirm_target == nil
    end

    test "confirm body advertises Revoke invite / Keep invite copy" do
      invites =
        InvitesState.start_confirm_revoke(
          InvitesState.loaded(InvitesState.new(), [
            %{code: "XYZ987", status: :available, issuer_id: 1, inserted_at: nil}
          ])
        )

      account_state =
        AccountState.new(invites_visible?: true, active: 3)
        |> Map.put(:invites, invites)

      state =
        build_state_for_role(:sysop, %{
          registration_mode: "invite_only",
          invite_code_generators: "sysop_only"
        })
        |> put_in([:screen_state, :account], account_state)

      flat = render_account(state) |> collect_text_values()
      joined = Enum.join(flat, "\n")

      assert Enum.any?(flat, &String.contains?(&1, "Revoke invite XYZ987?"))
      assert String.contains?(joined, "Code XYZ987 will stop working.")
      assert String.contains?(joined, "Existing accounts stay intact.")
      assert Enum.any?(flat, &String.contains?(&1, "Enter Revoke invite"))
      assert Enum.any?(flat, &String.contains?(&1, "Esc Keep invite"))
    end
  end

  describe "FOG-130 Item 5/6: copy + Real name optional reconciliation" do
    test "PROFILE save success uses 'Profile saved.' (not generic Account changes saved)" do
      user = build_user_with_profile()
      context = Context.new(current_user: user, route: :account)

      {state, _} =
        Account.update(
          {:task_result, :account_save_profile, {:ok, {:ok, user}}},
          Account.init(context),
          context
        )

      assert state.status_message == "Profile saved."
    end

    test "PREFS save success uses 'Preferences saved.'" do
      user = build_user_with_profile()
      context = Context.new(current_user: user, route: :account)

      {state, _} =
        Account.update(
          {:task_result, :account_save_prefs, {:ok, {:ok, user}}},
          Account.init(context),
          context
        )

      assert state.status_message == "Preferences saved."
    end

    test "PROFILE save failure uses 'Profile was not saved.'" do
      user = build_user_with_profile()
      context = Context.new(current_user: user, route: :account)

      changeset = Accounts.User.profile_changeset(user, %{location: String.duplicate("x", 200)})

      {state, _} =
        Account.update(
          {:task_result, :account_save_profile, {:ok, {:error, changeset}}},
          Account.init(context),
          context
        )

      assert state.status_message == "Profile was not saved."
    end

    test "Submitting a Profile draft from the first field saves without moving to the last field" do
      alias Foglet.TUI.Screens.Account.ProfileForm
      alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

      user = build_user_with_profile()
      ss = AccountState.new(current_user: user)

      assert ss.profile_form.focus_index == 0
      assert ModalForm.field_value(ss.profile_form, :location) == user.location

      {:ok, after_submit, cmds} = ProfileForm.handle_key(%{key: :enter}, ss, user)

      assert after_submit.profile_form.focus_index == 0
      assert [{:account_save_profile, attrs}] = cmds
      assert attrs.location == user.location
      refute after_submit.status_message == "Profile ready to save."
    end

    test "Submitting Preferences from a non-last focused field saves without moving focus" do
      alias Foglet.TUI.Screens.Account.PrefsForm

      user = build_user_with_profile()
      ss = AccountState.new(current_user: user)

      {:ok, ss, []} = PrefsForm.handle_key(%{key: :tab}, ss, user)
      assert ss.prefs_form.focus_index == 1

      {:ok, after_submit, cmds} = PrefsForm.handle_key(%{key: :enter}, ss, user)

      assert after_submit.prefs_form.focus_index == 1
      assert [{:account_save_prefs, attrs}] = cmds
      assert attrs.timezone == user.timezone
      assert attrs.preferences == %{"time_format" => "12h"}
      assert attrs.theme == user.theme
    end

    test "Submitting a Profile draft no longer flashes 'Profile ready to save.'" do
      alias Foglet.TUI.Screens.Account.ProfileForm
      alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

      user = build_user_with_profile()
      ss = AccountState.new(current_user: user)

      # Drive ProfileForm to submit from the last field as a compatibility path.
      {:ok, ss, []} = ProfileForm.handle_key(%{key: :tab}, ss, user)
      {:ok, ss, []} = ProfileForm.handle_key(%{key: :tab}, ss, user)
      assert ss.profile_form.focus_index == 2
      assert ModalForm.field_value(ss.profile_form, :real_name) == user.real_name

      {:ok, after_submit, cmds} = ProfileForm.handle_key(%{key: :enter}, ss, user)

      assert [{:account_save_profile, _}] = cmds
      refute after_submit.status_message == "Profile ready to save."
    end

    test "FOG-144: PROFILE save tolerates struct session_context (no Access crash)" do
      user = build_user_with_profile()

      session_context = %Foglet.TUI.SessionContext{
        user: user,
        user_id: user.id,
        pubkey_authenticated: false,
        registration_mode: "open",
        max_post_length: 4_000,
        timezone: "Etc/UTC",
        time_format: "iso",
        theme_id: "gray",
        theme: Theme.default()
      }

      context =
        Context.new(
          current_user: user,
          session_context: session_context,
          route: :account
        )

      ss =
        Account.init(context)
        |> Map.put(:active_tab, 0)

      # Land focus on the last PROFILE field, then submit with Enter.
      {ss, []} = Account.update({:key, %{key: :tab}}, ss, context)
      {ss, []} = Account.update({:key, %{key: :tab}}, ss, context)

      {_after, effects} = Account.update({:key, %{key: :enter}}, ss, context)

      assert [%Effect{type: :task, payload: %{op: :account_save_profile}}] = effects
    end

    test "real_name field carries optional helper description" do
      ss = AccountState.new()

      real_name_field = Enum.find(ss.profile_form.fields, &(&1.name == :real_name))

      refute Map.get(real_name_field, :required, false)

      assert real_name_field.description ==
               "For friends and the sysop; blank uses your handle."
    end

    test "Timezone and Theme fields carry helper descriptions per FOG-127" do
      ss = AccountState.new()

      timezone = Enum.find(ss.prefs_form.fields, &(&1.name == :timezone))
      theme = Enum.find(ss.prefs_form.fields, &(&1.name == :theme))

      assert timezone.description == "Search by city or IANA name; save to keep it."
      assert theme.description == "Preview changes here; save to keep them."
    end
  end
end
