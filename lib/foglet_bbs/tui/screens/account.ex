defmodule Foglet.TUI.Screens.Account do
  @moduledoc """
  Account shell screen for Foglet BBS (ACCT-01, D-03, D-04, D-05, D-08, D-09, D-12, D-13).

  Implements `Foglet.TUI.Screen` behaviour with three tabs:
    * PROFILE  — inline private profile draft form
    * PREFS    — inline presentation preference draft form with local theme preview
    * SSH KEYS — self-service SSH public-key management
    * INVITES  — conditional; shown when `ShellVisibility.invites_visible?/2` returns
                 true (D-09). Rendered via the shared `InvitesSurface` primitive (D-06).

  Tab focus is delegated entirely to `Foglet.TUI.Widgets.Input.Tabs` (D-05).
  Screen-local state lives at `state.screen_state[:account]` as a
  `%Foglet.TUI.Screens.Account.State{}` struct (D-04).

  Account PROFILE/PREFS save keys emit command tuples for the app layer to persist
  later in Phase 5. INVITES live actions still delegate to the shared surface.

  Security:
    * T-00-01: No Repo/domain imports; no fake operator actions.
    * T-00-04: INVITES tab body delegates entirely to `InvitesSurface.render/2`.
    * T-05-09: Candidate theme previews only through Account rendering.
  """

  @behaviour Foglet.TUI.Screen

  import Raxol.Core.Renderer.View

  alias Foglet.Sessions.Preferences
  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Presentation
  alias Foglet.TUI.Screens.Account.PrefsForm
  alias Foglet.TUI.Screens.Account.ProfileForm
  alias Foglet.TUI.Screens.Account.SSHKeysActions
  alias Foglet.TUI.Screens.Account.SSHKeysState
  alias Foglet.TUI.Screens.Account.SSHKeysSurface
  alias Foglet.TUI.Screens.Account.State
  alias Foglet.TUI.Screens.Shared.InvitesActions
  alias Foglet.TUI.Screens.Shared.InvitesSurface
  alias Foglet.TUI.Screens.ShellVisibility
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Input.Tabs

  @impl true
  @spec init(Context.t()) :: State.t()
  def init(%Context{} = context) do
    State.new(
      current_user: context.current_user,
      invites_visible?:
        ShellVisibility.invites_visible?(context.current_user, context.session_context)
    )
  end

  @impl true
  @spec init_screen_state(keyword()) :: State.t()
  def init_screen_state(opts \\ []) do
    State.new(translate_opts(opts))
  end

  @impl true
  @spec update(term(), State.t() | nil, Context.t()) :: {State.t(), [Effect.t()]}
  def update({:key, %{key: :char, char: c, ctrl: true}}, local_state, %Context{})
      when c in ["q", "Q"] do
    {normalize_state(local_state), [Effect.navigate(:main_menu, %{})]}
  end

  def update({:key, event}, local_state, %Context{} = context) do
    ss =
      local_state
      |> normalize_state(context)
      |> sync_prefs_focus()

    {new_tabs, action} = Tabs.handle_event(event, ss.tabs)

    if action != nil do
      new_active =
        case action do
          {:tab_changed, idx} -> idx
          _ -> ss.active_tab
        end

      new_ss = %{ss | tabs: new_tabs, active_tab: new_active}
      {loaded_ss, effects} = maybe_request_tab_load(new_ss, context)
      {loaded_ss, effects}
    else
      handle_active_key(event, ss, context)
    end
  end

  def update({:task_result, :account_save_profile, result}, local_state, %Context{}) do
    ss = normalize_state(local_state)

    case unwrap_task_result(result) do
      {:ok, user} ->
        {State.seed_from_user(ss, user) |> Map.put(:status_message, "Account changes saved."), []}

      {:error, %Ecto.Changeset{} = changeset} ->
        {put_account_errors(ss, :profile, changeset_errors(changeset)), []}

      {:error, reason} ->
        {put_account_errors(ss, :profile, %{base: to_string(reason)}), []}
    end
  end

  def update({:task_result, :account_save_prefs, result}, local_state, %Context{}) do
    ss = normalize_state(local_state)

    case unwrap_task_result(result) do
      {:ok, user} ->
        snapshot = Preferences.from_user(user)

        new_ss =
          ss
          |> State.seed_from_user(user)
          |> Map.put(:status_message, "Account changes saved.")
          |> Map.put(:candidate_theme_id, nil)

        effects = [
          Effect.session({:set_current_user, user}),
          Effect.session({:update_preferences, snapshot})
        ]

        {new_ss, effects}

      {:error, %Ecto.Changeset{} = changeset} ->
        {put_account_errors(ss, :prefs, changeset_errors(changeset)), []}

      {:error, reason} ->
        {put_account_errors(ss, :prefs, %{base: to_string(reason)}), []}
    end
  end

  def update({:task_result, op, result}, local_state, %Context{})
      when op in [:account_load_ssh_keys, :account_add_ssh_key, :account_revoke_ssh_key] do
    ss = normalize_state(local_state)

    case unwrap_task_result(result) do
      {:ok, %Foglet.TUI.Screens.Account.SSHKeysState{} = ssh_keys} ->
        {%{ss | ssh_keys: ssh_keys}, []}

      {:error, reason} ->
        {%{ss | ssh_keys: SSHKeysState.with_error(ss.ssh_keys, to_string(reason))}, []}
    end
  end

  def update({:task_result, op, result}, local_state, %Context{})
      when op in [:account_load_invites, :account_generate_invite, :account_revoke_invite] do
    ss = normalize_state(local_state)

    case unwrap_task_result(result) do
      {:ok, %Foglet.TUI.Screens.Shared.InvitesState{} = invites} ->
        {%{ss | invites: invites}, []}

      {:error, reason} ->
        {%{
           ss
           | invites:
               Foglet.TUI.Screens.Shared.InvitesState.with_error(ss.invites, to_string(reason))
         }, []}
    end
  end

  def update(_message, local_state, %Context{} = context),
    do: {normalize_state(local_state, context), []}

  @impl true
  @spec render(State.t(), Context.t()) :: any()
  def render(%State{} = local_state, %Context{} = context) do
    render(render_model(context, local_state))
  end

  def render(local_state, %Context{} = context),
    do: render(normalize_state(local_state, context), context)

  @impl true
  @spec render(map()) :: any()
  def render(state) do
    ss = synced_screen_state(state)
    theme = account_theme(state, ss)
    active_label = active_label(ss) || "PROFILE"
    width = inner_width(state)

    content =
      column style: %{gap: 0} do
        [
          Tabs.render(ss.tabs, theme: theme, width: width),
          divider(char: "─", style: %{fg: theme.border.fg}),
          render_tab_body(active_label, ss, theme)
        ]
      end

    ScreenFrame.render(preview_state(state, theme), account_chrome(), content, key_bar(ss))
  end

  # Phase 29 D-26 (SYSOP-07): the key bar is rendered at request time so the
  # `1-N Jump` hint reflects the actual tab count (3 without INVITES, 4 with).
  # Inserted between `←/→ Tab` and `Tab Field` so the navigation cluster reads
  # left-to-right: arrows / numbers / tab-cycle.
  defp key_bar(ss) do
    [
      {"←/→", "Tab"},
      {jump_hint(length(tab_labels(ss))), "Jump"},
      {"Tab", "Field"},
      {"Enter", "Save"},
      {"Esc", "Cancel"},
      {"Ctrl+Q", "Back"}
    ]
  end

  defp jump_hint(n) when is_integer(n) and n > 0, do: "1-#{n}"

  @impl true
  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  # Ctrl+Q leaves the screen. Bare q/Q would eat input on form fields, and Esc
  # is reserved for in-form cancel (e.g., dropping a theme preview).
  def handle_key(%{key: :char, char: c, ctrl: true}, state) when c in ["q", "Q"] do
    {:update, %{state | current_screen: :main_menu}, []}
  end

  def handle_key(event, state) do
    ss = synced_screen_state(state)
    {new_tabs, action} = Tabs.handle_event(event, ss.tabs)

    new_active =
      case action do
        {:tab_changed, idx} -> idx
        _ -> ss.active_tab
      end

    new_ss = %{ss | tabs: new_tabs, active_tab: new_active}

    cond do
      action != nil ->
        actor = Map.get(state, :current_user)

        new_ss =
          new_ss
          |> maybe_load_ssh_keys(actor)
          |> maybe_load_invites(actor)

        {:update, put_screen_state(state, new_ss), []}

      active_label(ss) == "SSH KEYS" ->
        delegate_ssh_keys_key(event, state, ss)

      active_label(ss) == "INVITES" ->
        delegate_invites_key(event, state, ss)

      active_label(ss) == "PROFILE" ->
        delegate_profile_key(event, state, ss)

      active_label(ss) == "PREFS" ->
        delegate_prefs_key(event, state, ss)

      true ->
        :no_match
    end
  end

  # --- private helpers ---

  # ScreenFrame uses padding: 1 and border: :single, consuming 4 columns total.
  defp inner_width(state) do
    case Map.get(state, :terminal_size) do
      {w, _} when is_integer(w) -> max(w - 4, 0)
      _ -> 76
    end
  end

  defp synced_screen_state(state) do
    state
    |> get_screen_state()
    |> State.ensure_visibility(invites_visible?(state))
  end

  defp normalize_state(nil, %Context{} = context), do: init(context)

  defp normalize_state(%State{} = ss, %Context{} = context) do
    State.ensure_visibility(
      ss,
      ShellVisibility.invites_visible?(context.current_user, context.session_context)
    )
  end

  defp normalize_state(%State{} = ss), do: ss
  defp normalize_state(_other), do: State.new()

  defp render_model(%Context{} = context, %State{} = local_state) do
    %{
      current_user: context.current_user,
      session_context: context.session_context,
      terminal_size: context.terminal_size,
      current_screen: :account,
      route_params: context.route_params,
      screen_state: %{account: local_state}
    }
  end

  defp invites_visible?(state) do
    ShellVisibility.invites_visible?(
      Map.get(state, :current_user),
      Map.get(state, :session_context)
    )
  end

  defp get_screen_state(state) do
    case get_in(state.screen_state, [:account]) do
      nil -> init_screen_state(init_opts_from_state(state))
      ss -> ss
    end
  end

  defp init_opts_from_state(state) do
    [
      invites_visible?:
        ShellVisibility.invites_visible?(
          Map.get(state, :current_user),
          Map.get(state, :session_context)
        ),
      current_user: Map.get(state, :current_user)
    ]
  end

  # Translate :role option to :invites_visible? so that
  # init_screen_state(role: :sysop) works from tests and direct callers.
  defp translate_opts(opts) do
    case Keyword.pop(opts, :role) do
      {nil, opts} ->
        opts

      {role, opts} ->
        visible? = InvitesSurface.visible?(%{role: role}, nil)
        Keyword.put_new(opts, :invites_visible?, visible?)
    end
  end

  defp tab_labels(%State{tabs: %Tabs{raxol_state: raxol_state}}) do
    raxol_state
    |> Map.get(:tabs, [])
    |> Enum.map(&Map.fetch!(&1, :label))
  end

  defp active_label(%State{} = ss), do: Enum.at(tab_labels(ss), ss.active_tab)

  defp maybe_load_invites(%State{} = ss, actor) do
    if active_label(ss) == "INVITES" and not is_list(ss.invites.items) do
      {:ok, invites} = InvitesActions.load(actor, ss.invites)
      %{ss | invites: invites}
    else
      ss
    end
  end

  defp maybe_request_tab_load(%State{} = ss, %Context{} = context) do
    case active_label(ss) do
      "SSH KEYS" when not is_list(ss.ssh_keys.items) ->
        {ss, [ssh_keys_effect(:account_load_ssh_keys, context, ss.ssh_keys)]}

      "INVITES" when not is_list(ss.invites.items) ->
        {ss, [invites_effect(:account_load_invites, context, ss.invites)]}

      _ ->
        {ss, []}
    end
  end

  defp handle_active_key(event, %State{} = ss, %Context{} = context) do
    case active_label(ss) do
      "SSH KEYS" -> handle_ssh_keys_update(event, ss, context)
      "INVITES" -> handle_invites_update(event, ss, context)
      "PROFILE" -> handle_profile_update(event, ss, context)
      "PREFS" -> handle_prefs_update(event, ss, context)
      _ -> {ss, []}
    end
  end

  defp handle_profile_update(event, %State{} = ss, %Context{} = context) do
    case ProfileForm.handle_key(event, ss, context.current_user) do
      {:ok, new_ss, cmds} ->
        {new_ss, account_command_effects(cmds, context, new_ss)}

      :no_match ->
        {ss, []}
    end
  end

  defp handle_prefs_update(event, %State{} = ss, %Context{} = context) do
    case PrefsForm.handle_key(event, ss, context.current_user) do
      {:ok, new_ss, cmds} ->
        {new_ss, account_command_effects(cmds, context, new_ss)}

      :no_match ->
        {ss, []}
    end
  end

  defp handle_ssh_keys_update(event, %State{} = ss, %Context{} = context) do
    key = action_key(event)

    case {key, ss.ssh_keys.mode} do
      {key, :list} when key in ["r", "R"] ->
        {ss, [ssh_keys_effect(:account_load_ssh_keys, context, ss.ssh_keys)]}

      {key, :list} when key in ["d", "D"] ->
        {ss, [ssh_keys_effect(:account_revoke_ssh_key, context, ss.ssh_keys)]}

      {:enter, :add} ->
        {ss, [ssh_keys_effect(:account_add_ssh_key, context, ss.ssh_keys)]}

      _ ->
        case SSHKeysActions.handle_key(key, context.current_user, ss.ssh_keys) do
          {:ok, ssh_keys} -> {%{ss | ssh_keys: ssh_keys}, []}
          :no_match -> {ss, []}
        end
    end
  end

  defp handle_invites_update(event, %State{} = ss, %Context{} = context) do
    key = action_key(event)

    case key do
      key when key in ["r", "R"] ->
        {ss, [invites_effect(:account_load_invites, context, ss.invites)]}

      key when key in ["g", "G"] ->
        {ss, [invites_effect(:account_generate_invite, context, ss.invites)]}

      key when key in ["d", "D"] ->
        {ss, [invites_effect(:account_revoke_invite, context, ss.invites)]}

      _ ->
        case InvitesActions.handle_key(key, context.current_user, ss.invites) do
          {:ok, invites} -> {%{ss | invites: invites}, []}
          :no_match -> {ss, []}
        end
    end
  end

  defp account_command_effects(commands, %Context{} = context, %State{}) do
    Enum.flat_map(commands, fn
      {:account_save_profile, attrs} ->
        [save_profile_effect(context, attrs)]

      {:account_save_prefs, attrs} ->
        [save_prefs_effect(context, attrs)]

      _other ->
        []
    end)
    |> case do
      [] -> []
      effects -> effects
    end
  end

  defp save_profile_effect(%Context{current_user: nil}, _attrs) do
    Effect.task(:account_save_profile, :account, fn -> {:error, :missing_user} end)
  end

  defp save_profile_effect(%Context{} = context, attrs) do
    accounts_mod = domain_module(context, :accounts, Foglet.Accounts)
    attrs = Map.take(attrs, [:location, :tagline, :real_name])

    Effect.task(:account_save_profile, :account, fn ->
      accounts_mod.update_profile(context.current_user, attrs)
    end)
  end

  defp save_prefs_effect(%Context{current_user: nil}, _attrs) do
    Effect.task(:account_save_prefs, :account, fn -> {:error, :missing_user} end)
  end

  defp save_prefs_effect(%Context{} = context, attrs) do
    accounts_mod = domain_module(context, :accounts, Foglet.Accounts)
    attrs = normalize_account_preferences(attrs)

    Effect.task(:account_save_prefs, :account, fn ->
      accounts_mod.update_profile(context.current_user, attrs)
    end)
  end

  defp ssh_keys_effect(op, %Context{} = context, ssh_keys) do
    Effect.task(op, :account, fn ->
      case op do
        :account_load_ssh_keys -> SSHKeysActions.load(context.current_user, ssh_keys)
        :account_add_ssh_key -> SSHKeysActions.add(context.current_user, ssh_keys, ssh_keys.form)
        :account_revoke_ssh_key -> SSHKeysActions.revoke_selected(context.current_user, ssh_keys)
      end
    end)
  end

  defp invites_effect(op, %Context{} = context, invites) do
    Effect.task(op, :account, fn ->
      case op do
        :account_load_invites -> InvitesActions.load(context.current_user, invites)
        :account_generate_invite -> InvitesActions.generate(context.current_user, invites)
        :account_revoke_invite -> InvitesActions.revoke_selected(context.current_user, invites)
      end
    end)
  end

  defp action_key(%{key: :char, char: char}) when is_binary(char), do: char
  defp action_key(%{key: key}), do: key
  defp action_key(event), do: event

  defp domain_module(%Context{} = context, key, default) do
    Map.get(context.domain || %{}, key) ||
      (is_map(context.session_context) &&
         get_in(context.session_context, [:domain, key])) ||
      default
  end

  defp unwrap_task_result({:ok, {:ok, value}}), do: {:ok, value}
  defp unwrap_task_result({:ok, {:error, reason}}), do: {:error, reason}
  defp unwrap_task_result({:ok, value}), do: {:ok, value}
  defp unwrap_task_result({:error, reason}), do: {:error, reason}

  defp normalize_account_preferences(%{preferences: preferences} = attrs)
       when is_map(preferences) do
    time_format = Map.get(preferences, "time_format") || Map.get(preferences, :time_format)
    %{attrs | preferences: %{"time_format" => time_format}}
  end

  defp normalize_account_preferences(attrs), do: attrs

  defp put_account_errors(%State{} = ss, section, errors) do
    ss
    |> Map.put(error_field(section), errors)
    |> Map.put(:status_message, "Account save failed.")
    |> apply_form_errors(section, errors)
  end

  @profile_labels %{location: "Location", tagline: "Tagline", real_name: "Real name"}
  @prefs_labels %{timezone: "Timezone", time_format: "Time format", theme: "Theme"}

  defp apply_form_errors(%{profile_form: form} = ss, :profile, errors) when not is_nil(form) do
    alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm
    %{ss | profile_form: ModalForm.set_errors(form, prefix_errors(errors, @profile_labels))}
  end

  defp apply_form_errors(%{prefs_form: form} = ss, :prefs, errors) when not is_nil(form) do
    alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm
    %{ss | prefs_form: ModalForm.set_errors(form, prefix_errors(errors, @prefs_labels))}
  end

  defp apply_form_errors(ss, _section, _errors), do: ss

  defp prefix_errors(errors, labels) do
    Map.new(errors, fn {field, message} ->
      label = Map.get(labels, field, to_string(field))
      {field, "#{label} error: #{message}"}
    end)
  end

  defp error_field(:profile), do: :profile_errors
  defp error_field(:prefs), do: :prefs_errors

  defp changeset_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.into(%{}, fn {field, messages} -> {field, Enum.join(messages, ", ")} end)
  end

  defp maybe_load_ssh_keys(%State{} = ss, actor) do
    if active_label(ss) == "SSH KEYS" and not is_list(ss.ssh_keys.items) do
      {:ok, ssh_keys} = SSHKeysActions.load(actor, ss.ssh_keys)
      %{ss | ssh_keys: ssh_keys}
    else
      ss
    end
  end

  defp delegate_ssh_keys_key(%{key: :char, char: char}, state, %State{} = ss) do
    case SSHKeysActions.handle_key(char, Map.get(state, :current_user), ss.ssh_keys) do
      {:ok, ssh_keys} -> {:update, put_screen_state(state, %{ss | ssh_keys: ssh_keys}), []}
      :no_match -> :no_match
    end
  end

  defp delegate_ssh_keys_key(%{key: key}, state, %State{} = ss) do
    case SSHKeysActions.handle_key(key, Map.get(state, :current_user), ss.ssh_keys) do
      {:ok, ssh_keys} -> {:update, put_screen_state(state, %{ss | ssh_keys: ssh_keys}), []}
      :no_match -> :no_match
    end
  end

  defp delegate_invites_key(%{key: :char, char: char}, state, %State{} = ss) do
    case InvitesActions.handle_key(char, Map.get(state, :current_user), ss.invites) do
      {:ok, invites} -> {:update, put_screen_state(state, %{ss | invites: invites}), []}
      :no_match -> :no_match
    end
  end

  defp delegate_invites_key(%{key: key}, state, %State{} = ss) do
    case InvitesActions.handle_key(key, Map.get(state, :current_user), ss.invites) do
      {:ok, invites} -> {:update, put_screen_state(state, %{ss | invites: invites}), []}
      :no_match -> :no_match
    end
  end

  defp delegate_profile_key(event, state, %State{} = ss) do
    case ProfileForm.handle_key(event, ss, Map.get(state, :current_user)) do
      {:ok, new_ss, cmds} -> {:update, put_screen_state(state, new_ss), cmds}
      :no_match -> :no_match
    end
  end

  defp delegate_prefs_key(event, state, %State{} = ss) do
    # Sync form focus_index from prefs_focus so tests that set prefs_focus
    # directly (D-19 compatibility) also update the form's active field.
    ss = sync_prefs_focus(ss)

    case PrefsForm.handle_key(event, ss, Map.get(state, :current_user)) do
      {:ok, new_ss, cmds} -> {:update, put_screen_state(state, new_ss), cmds}
      :no_match -> :no_match
    end
  end

  @prefs_focus_index %{timezone: 0, time_format: 1, theme: 2}

  defp sync_prefs_focus(%State{prefs_focus: pf, prefs_form: form} = ss)
       when not is_nil(form) do
    idx = Map.get(@prefs_focus_index, pf, 0)

    if form.focus_index == idx do
      ss
    else
      %{ss | prefs_form: %{form | focus_index: idx}}
    end
  end

  defp sync_prefs_focus(ss), do: ss

  defp put_screen_state(state, %State{} = ss) do
    %{state | screen_state: Map.put(state.screen_state, :account, ss)}
  end

  defp account_theme(state, %State{candidate_theme_id: nil}), do: Theme.from_state(state)

  defp account_theme(state, %State{candidate_theme_id: theme_id}) do
    case resolve_theme_id(theme_id) do
      nil -> Theme.from_state(state)
      id -> Theme.resolve(id)
    end
  end

  defp preview_state(state, theme) do
    sc = Map.get(state, :session_context) || %Foglet.TUI.SessionContext{}
    %{state | session_context: Map.put(sc, :theme, theme)}
  end

  defp account_chrome do
    %{title: "Account", mode: Presentation.mode_for!(:account)}
  end

  defp resolve_theme_id(theme_id) when is_binary(theme_id) do
    Enum.find(Theme.ids(), &(Atom.to_string(&1) == theme_id))
  end

  defp render_tab_body("PROFILE", ss, theme), do: ProfileForm.render(ss, theme)

  defp render_tab_body("PREFS", ss, theme), do: PrefsForm.render(ss, theme)

  defp render_tab_body("SSH KEYS", ss, theme), do: SSHKeysSurface.render(ss.ssh_keys, theme)

  defp render_tab_body("INVITES", ss, theme) do
    InvitesSurface.render(ss.invites, theme)
  end

  defp render_tab_body(_unknown, _ss, theme) do
    column style: %{gap: 0} do
      [text("", fg: theme.dim.fg)]
    end
  end
end
