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

  alias Foglet.Sessions.Preferences
  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Screens.Account.PrefsForm
  alias Foglet.TUI.Screens.Account.ProfileForm
  alias Foglet.TUI.Screens.Account.Render
  alias Foglet.TUI.Screens.Account.SSHKeysActions
  alias Foglet.TUI.Screens.Account.SSHKeysState
  alias Foglet.TUI.Screens.Account.State
  alias Foglet.TUI.Screens.Domain
  alias Foglet.TUI.Screens.Shared.InvitesActions
  alias Foglet.TUI.Screens.ShellVisibility
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

    if shield_tab_shortcut?(event, ss) do
      handle_active_key(event, ss, context)
    else
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
  end

  def update({:task_result, :account_save_profile, result}, local_state, %Context{}) do
    ss = normalize_state(local_state)

    case unwrap_task_result(result) do
      {:ok, user} ->
        new_ss =
          State.seed_from_user(ss, user) |> Map.put(:status_message, "Profile saved.")

        {new_ss, [Effect.session({:set_current_user, user})]}

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
          |> Map.put(:status_message, "Preferences saved.")
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
    context
    |> render_model(local_state)
    |> Render.render()
  end

  def render(local_state, %Context{} = context),
    do: render(normalize_state(local_state, context), context)

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

  defp tab_labels(%State{tabs: %Tabs{raxol_state: raxol_state}}) do
    raxol_state
    |> Map.get(:tabs, [])
    |> Enum.map(&Map.fetch!(&1, :label))
  end

  defp active_label(%State{} = ss), do: Enum.at(tab_labels(ss), ss.active_tab)

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
        new_ss = sync_prefs_focus_from_form(new_ss)
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
        {%{ss | ssh_keys: SSHKeysState.start_confirm_revoke(ss.ssh_keys)}, []}

      {:enter, :confirm_revoke} ->
        revoking = %{ss.ssh_keys | mode: :list, confirm_target: nil}

        {%{ss | ssh_keys: revoking},
         [ssh_keys_effect(:account_revoke_ssh_key, context, revoking)]}

      {:escape, :confirm_revoke} ->
        {%{ss | ssh_keys: SSHKeysState.cancel_confirm_revoke(ss.ssh_keys)}, []}

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
    invites = ss.invites
    mode = Map.get(invites, :mode, :list)

    case {key, mode} do
      {key, :list} when key in ["r", "R"] ->
        {ss, [invites_effect(:account_load_invites, context, invites)]}

      {key, :list} when key in ["g", "G"] ->
        {ss, [invites_effect(:account_generate_invite, context, invites)]}

      {key, :list} when key in ["d", "D"] ->
        {%{ss | invites: Foglet.TUI.Screens.Shared.InvitesState.start_confirm_revoke(invites)},
         []}

      {:enter, :confirm_revoke} ->
        cleared = %{invites | mode: :list, confirm_target: nil}
        {%{ss | invites: cleared}, [invites_effect(:account_revoke_invite, context, cleared)]}

      {:escape, :confirm_revoke} ->
        {%{ss | invites: Foglet.TUI.Screens.Shared.InvitesState.cancel_confirm_revoke(invites)},
         []}

      _ ->
        case InvitesActions.handle_key(key, context.current_user, invites) do
          {:ok, new_invites} -> {%{ss | invites: new_invites}, []}
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

  # FOG-142 / FOG-717: Tabs consumes global tab shortcuts before the
  # active Account tab sees them. Focused text-entry fields must get first
  # refusal for digit shortcuts and cursor-editing keys; otherwise typing
  # digits into a form or pressing Left/Right inside populated text fields
  # silently changes Account tabs instead of editing the field.
  defp shield_tab_shortcut?(event, %State{} = ss) do
    text_entry_event?(event, active_text_entry_field(ss))
  end

  defp text_entry_event?(%{key: :char, char: <<c>>}, {:form, %{type: :select_list}, field_state})
       when c in ?0..?9 do
    select_search_active?(field_state)
  end

  defp text_entry_event?(%{key: :char, char: <<c>>}, {:form, %{type: type}, _field_state})
       when c in ?0..?9 and type in [:text, :textarea, :integer, :password],
       do: true

  defp text_entry_event?(%{key: :char, char: char}, {:form, %{type: :select_list}, _field_state})
       when is_binary(char),
       do: true

  defp text_entry_event?(%{key: key}, {:form, %{type: type}, _field_state})
       when key in [:left, :right, :home, :end, :delete] and
              type in [:text, :textarea, :integer, :password],
       do: true

  defp text_entry_event?(%{key: :backspace}, {:form, %{type: type}, _field_state})
       when type in [:text, :textarea, :integer, :password, :select_list],
       do: true

  defp text_entry_event?(%{key: key}, {:form, %{type: :select_list}, field_state})
       when key in [:left, :right, :home, :end, :delete] do
    select_search_active?(field_state)
  end

  defp text_entry_event?(%{key: :char, char: <<c>>}, :ssh_key_add) when c in ?0..?9, do: true

  defp text_entry_event?(%{key: key}, :ssh_key_add)
       when key in [:left, :right, :home, :end, :delete, :backspace],
       do: true

  defp text_entry_event?(_event, _entry), do: false

  defp active_text_entry_field(%State{} = ss) do
    case active_label(ss) do
      "SSH KEYS" -> if ss.ssh_keys.mode == :add, do: :ssh_key_add
      "PROFILE" -> focused_form_field(ss.profile_form)
      "PREFS" -> focused_form_field(ss.prefs_form)
      _ -> nil
    end
  end

  # FOG-333 / FOG-717: Generalized text-entry shielding for
  # Modal.Form-backed tabs. Free-form fields shield digit and cursor-editing
  # shortcuts. Searchable select-list filters shield letters and cursor keys,
  # while preserving blank numeric tab jumps until the user has begun a search.
  defp focused_form_field(%{fields: fields, field_states: field_states, focus_index: idx}) do
    case Enum.at(fields, idx) do
      %{type: type} = field when type in [:text, :textarea, :integer, :password, :select_list] ->
        {:form, field, Enum.at(field_states, idx)}

      _ ->
        nil
    end
  end

  defp focused_form_field(_), do: nil

  defp select_search_active?(%{select_list: %{search_buffer: search}}) when is_binary(search),
    do: search != ""

  defp select_search_active?(_), do: false

  defp action_key(%{key: :char, char: char}) when is_binary(char), do: char
  defp action_key(%{key: key}), do: key
  defp action_key(event), do: event

  defp domain_module(%Context{} = context, key, default) do
    with nil <- Map.get(context.domain || %{}, key),
         {:error, :not_configured} <- Domain.get(context.session_context || %{}, key) do
      default
    else
      mod when is_atom(mod) and not is_nil(mod) -> mod
      {:ok, mod} -> mod
    end
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
    |> Map.put(:status_message, save_failure_message(section))
    |> apply_form_errors(section, errors)
  end

  defp save_failure_message(:profile), do: "Profile was not saved."
  defp save_failure_message(:prefs), do: "Preferences were not saved."

  @profile_labels %{location: "Location", tagline: "Tagline", real_name: "Real name"}
  @prefs_labels %{timezone: "Timezone", time_format: "Time format", theme: "Theme"}

  defp apply_form_errors(%{profile_form: form} = ss, :profile, errors) when not is_nil(form) do
    alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

    form =
      form
      |> ModalForm.set_errors(prefix_errors(errors, @profile_labels))
      |> ModalForm.set_submit_state({:error, "validation"})

    %{ss | profile_form: form}
  end

  defp apply_form_errors(%{prefs_form: form} = ss, :prefs, errors) when not is_nil(form) do
    alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

    form =
      form
      |> ModalForm.set_errors(prefix_errors(errors, @prefs_labels))
      |> ModalForm.set_submit_state({:error, "validation"})

    %{ss | prefs_form: form}
  end

  defp apply_form_errors(ss, _section, _errors), do: ss

  # Friendly user-facing validation copy (FOG-127). Falls back to a generic
  # "{Label} error: {message}" string for any field/message we have not yet
  # rewritten so we never silently drop validation feedback.
  defp prefix_errors(errors, labels) do
    Map.new(errors, fn {field, message} ->
      {field, friendly_error(field, message, labels)}
    end)
  end

  defp friendly_error(:location, msg, _labels) do
    if String.contains?(msg, "at most") or String.contains?(msg, "character") do
      "Location must be 80 characters or fewer."
    else
      "Location: #{msg}"
    end
  end

  defp friendly_error(:tagline, msg, _labels) do
    if String.contains?(msg, "at most") or String.contains?(msg, "character") do
      "Tagline must be 120 characters or fewer."
    else
      "Tagline: #{msg}"
    end
  end

  defp friendly_error(:real_name, msg, _labels) do
    cond do
      String.contains?(msg, "blank") or String.contains?(msg, "required") ->
        "Real name is required."

      String.contains?(msg, "at most") or String.contains?(msg, "character") ->
        "Real name must be 120 characters or fewer."

      true ->
        "Real name: #{msg}"
    end
  end

  defp friendly_error(:timezone, msg, _labels) do
    cond do
      String.contains?(msg, "blank") or String.contains?(msg, "required") ->
        "Timezone is required."

      String.contains?(msg, "IANA") or String.contains?(msg, "timezone") ->
        "Timezone must be a valid IANA name, like America/Chicago."

      true ->
        "Timezone: #{msg}"
    end
  end

  defp friendly_error(:time_format, _msg, _labels), do: "Time format must be 12h or 24h."

  defp friendly_error(:preferences, msg, _labels) do
    if String.contains?(msg, "time_format") do
      "Time format must be 12h or 24h."
    else
      "Preferences: #{msg}"
    end
  end

  defp friendly_error(:theme, _msg, _labels), do: "Theme is not available."

  defp friendly_error(field, message, labels) do
    label = Map.get(labels, field, to_string(field))
    "#{label} error: #{message}"
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

  @prefs_focus_index %{timezone: 0, time_format: 1, theme: 2}
  @prefs_focus_atom %{0 => :timezone, 1 => :time_format, 2 => :theme}

  # Pre-dispatch: tests/seeders write `prefs_focus` directly on the struct;
  # mirror it onto `prefs_form.focus_index` so Modal.Form dispatches to the
  # field the screen thinks is focused. After PrefsForm runs,
  # `sync_prefs_focus_from_form/1` mirrors any focus advancement (Tab,
  # Shift-Tab, Enter) back into `prefs_focus` so this pre-dispatch step does
  # not stomp Modal.Form's focus on the next keystroke (FOG-139).
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

  # Dialyzer infers `prefs_form` is always set by the time this helper runs
  # (PrefsForm.handle_key only succeeds when the form is built), so a nil
  # fallback would be flagged as unreachable.
  defp sync_prefs_focus_from_form(%State{prefs_form: %{focus_index: idx}} = ss) do
    case Map.get(@prefs_focus_atom, idx) do
      nil -> ss
      atom -> %{ss | prefs_focus: atom}
    end
  end
end
