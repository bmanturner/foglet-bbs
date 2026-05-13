defmodule Foglet.TUI.Screens.Sysop.AccessRulesView do
  @moduledoc """
  ACCESS tab submodule for sysop network/IP and identity policy management.
  """

  alias Foglet.Accounts
  alias Foglet.Accounts.IdentityPolicy
  alias Foglet.Config
  alias Foglet.SSH
  alias Foglet.TUI.Effect
  alias Foglet.TUI.ScrollKeys
  alias Foglet.TUI.Widgets.Display.ConsoleTable

  import Raxol.Core.Renderer.View

  @network_columns [
    %{key: :mode, label: "Mode", width: 6, priority: 20, demand: :content},
    %{key: :enabled, label: "On", width: 4, priority: 20, demand: :content},
    %{key: :address, label: "Address/CIDR", width: 28, grow: 1, priority: 100, demand: :content},
    %{key: :reason, label: "Reason", width: 18, grow: 1, priority: 60, demand: :content}
  ]

  @identity_columns [
    %{key: :kind, label: "Kind", width: 17, priority: 40, demand: :content},
    %{key: :enabled, label: "On", width: 4, priority: 20, demand: :content},
    %{key: :value, label: "Value", width: 20, grow: 1, priority: 100, demand: :content},
    %{key: :conflicts, label: "Conflicts", width: 10, priority: 90, demand: :content},
    %{key: :reason, label: "Reason", width: 16, grow: 1, priority: 60, demand: :content}
  ]

  @identity_kinds [:reserved_handle, :banned_handle, :banned_email, :banned_email_domain]

  @type form_mode :: nil | :create_deny | :create_allow
  @type identity_form_mode ::
          nil | :reserved_handle | :banned_handle | :banned_email | :banned_email_domain
  @type section :: :network | :identity
  @type t :: %__MODULE__{
          current_user: Foglet.Accounts.User.t() | nil,
          section: section(),
          rules: [struct()],
          identity_rules: [struct()],
          selection_index: non_neg_integer(),
          identity_selection_index: non_neg_integer(),
          message: String.t() | nil,
          allowlist_enabled?: boolean(),
          pending_action: tuple() | nil,
          form_mode: form_mode(),
          identity_form_mode: identity_form_mode(),
          form_field: :address | :reason | :comment,
          identity_form_field: :kind | :value | :reason | :comment,
          draft: map(),
          identity_draft: map()
        }

  defstruct current_user: nil,
            section: :network,
            rules: [],
            identity_rules: [],
            selection_index: 0,
            identity_selection_index: 0,
            message: nil,
            allowlist_enabled?: false,
            pending_action: nil,
            form_mode: nil,
            identity_form_mode: nil,
            form_field: :address,
            identity_form_field: :value,
            draft: %{"address" => "", "reason" => "", "comment" => ""},
            identity_draft: %{"value" => "", "reason" => "", "comment" => ""}

  @spec from_rules([struct()], Foglet.Accounts.User.t() | nil, boolean()) :: t()
  def from_rules(rules, current_user, allowlist_enabled? \\ Config.ssh_ip_allowlist_enabled?())

  def from_rules(rules, current_user, allowlist_enabled?) when is_list(rules) do
    from_rules(rules, IdentityPolicy.list_rules(), current_user, allowlist_enabled?)
  end

  @spec from_rules([struct()], [struct()], Foglet.Accounts.User.t() | nil, boolean()) :: t()
  def from_rules(rules, identity_rules, current_user, allowlist_enabled?)
      when is_list(rules) and is_list(identity_rules) do
    %__MODULE__{
      current_user: current_user,
      rules: rules,
      identity_rules: identity_rules,
      allowlist_enabled?: allowlist_enabled?
    }
  end

  @spec handle_key(map(), t()) :: {t(), [Effect.t()]}
  def handle_key(event, %__MODULE__{form_mode: mode} = state) when not is_nil(mode),
    do: handle_network_form_key(event, state)

  def handle_key(event, %__MODULE__{identity_form_mode: mode} = state) when not is_nil(mode),
    do: handle_identity_form_key(event, state)

  def handle_key(%{key: key}, state) when key in [:tab, :left, :right],
    do: {switch_section(state), []}

  def handle_key(%{key: key} = event, state) when key in [:up, :down],
    do: {move(state, ScrollKeys.vertical_delta(event)), []}

  def handle_key(%{key: :char, char: char} = event, state) when char in ["j", "k"],
    do: {move(state, ScrollKeys.vertical_delta(event)), []}

  def handle_key(%{key: :char, char: c}, state) when c in ["r", "R"],
    do: {state, [load_effect(state.current_user)]}

  def handle_key(%{key: :char, char: c}, %__MODULE__{section: :network} = state)
      when c in ["d", "D"],
      do: {start_network_form(state, :create_deny), []}

  def handle_key(%{key: :char, char: c}, %__MODULE__{section: :network} = state)
      when c in ["a", "A"],
      do: {start_network_form(state, :create_allow), []}

  def handle_key(%{key: :char, char: c}, %__MODULE__{section: :identity} = state)
      when c in ["a", "A"],
      do: {start_identity_form(state, :reserved_handle), []}

  def handle_key(%{key: :char, char: c}, state) when c in ["e", "E"],
    do: confirm_or_update_selected(state, :toggle)

  def handle_key(%{key: :char, char: c}, state) when c in ["x", "X"],
    do: confirm_or_update_selected(state, :remove)

  def handle_key(_event, state), do: {state, []}

  @spec render(t(), map(), keyword()) :: any()
  def render(%__MODULE__{} = state, theme, opts \\ []) do
    width = Keyword.get(opts, :width, 76)
    visible_height = Keyword.get(opts, :visible_height, Keyword.get(opts, :height, 20))

    column style: %{gap: 0} do
      [text("ACCESS policies", fg: theme.title.fg, style: [:bold]), text("")] ++
        section_lines(state, theme) ++
        policy_lines(state, theme, width, visible_height) ++
        message_lines(state, theme) ++
        [
          render_body(state, theme, width, visible_height),
          text(""),
          text(footer(state), fg: theme.dim.fg)
        ]
    end
  end

  def keybar_groups(%__MODULE__{form_mode: nil, identity_form_mode: nil, section: :network}) do
    [
      %{
        label: "Access: Network/IP",
        commands: [
          %{key: "←/→", label: "Identity", priority: 20},
          %{key: "Tab", label: "Identity", priority: 25},
          %{key: "A", label: "Allow", priority: 5},
          %{key: "D", label: "Deny", priority: 5},
          %{key: "E", label: "Enable/disable", priority: 5},
          %{key: "X", label: "Remove", priority: 5},
          %{key: "R", label: "Reload", priority: 15}
        ]
      }
    ]
  end

  def keybar_groups(%__MODULE__{form_mode: nil, identity_form_mode: nil, section: :identity}) do
    [
      %{
        label: "Access: Identity",
        commands: [
          %{key: "←/→", label: "Network/IP", priority: 20},
          %{key: "Tab", label: "Network/IP", priority: 25},
          %{key: "A", label: "Add", priority: 5},
          %{key: "E", label: "Enable/disable", priority: 5},
          %{key: "X", label: "Remove", priority: 5},
          %{key: "R", label: "Reload", priority: 15}
        ]
      }
    ]
  end

  def keybar_groups(%__MODULE__{}) do
    [
      %{
        label: "Rule form",
        commands: [
          %{key: "Enter/Ctrl+S", label: "Save", priority: 0},
          %{key: "Esc", label: "Cancel", priority: 0},
          %{key: "Tab", label: "Next", priority: 5}
        ]
      }
    ]
  end

  def load_effect(actor) do
    Effect.task(:sysop_load_access_rules, :sysop, fn ->
      with {:ok, rules} <- SSH.list_access_rules(actor),
           {:ok, identity_rules} <- Accounts.list_identity_rules(actor) do
        {:ok, from_rules(rules, identity_rules, actor, Config.ssh_ip_allowlist_enabled?())}
      end
    end)
  end

  defp render_body(
         %__MODULE__{form_mode: nil, identity_form_mode: nil, section: :network} = state,
         theme,
         width,
         _visible_height
       ) do
    table =
      ConsoleTable.init(
        columns: @network_columns,
        rows: Enum.map(state.rules, &network_row_map/1),
        width: table_width(width),
        selectable: true,
        empty_state: "No IP access rules configured."
      )
      |> put_in(
        [Access.key(:table), Access.key(:raxol_state), :selected_row],
        state.selection_index
      )

    ConsoleTable.render(table, theme: theme)
  end

  defp render_body(
         %__MODULE__{form_mode: nil, identity_form_mode: nil, section: :identity} = state,
         theme,
         width,
         visible_height
       ) do
    table =
      ConsoleTable.init(
        columns: @identity_columns,
        rows: Enum.map(state.identity_rules, &identity_row_map/1),
        width: table_width(width),
        selectable: true,
        empty_state: "No identity policy rules configured."
      )
      |> put_in(
        [Access.key(:table), Access.key(:raxol_state), :selected_row],
        state.identity_selection_index
      )

    column style: %{gap: 0} do
      [ConsoleTable.render(table, theme: theme)] ++
        conflict_guidance(theme, width, visible_height)
    end
  end

  defp render_body(%__MODULE__{form_mode: mode} = state, theme, width, visible_height)
       when not is_nil(mode) do
    column style: %{gap: 0} do
      [
        text(network_form_title(state.form_mode), fg: theme.accent.fg, style: [:bold]),
        text(field_line(state, :address), fg: field_color(state, :address, theme)),
        text(field_line(state, :reason), fg: field_color(state, :reason, theme)),
        text(field_line(state, :comment), fg: field_color(state, :comment, theme)),
        text(""),
        text("Allowlist mode: #{allowlist_label(state.allowlist_enabled?)}",
          fg: allowlist_color(state, theme)
        )
      ] ++ network_form_guidance(theme, width, visible_height)
    end
  end

  defp render_body(%__MODULE__{identity_form_mode: mode} = state, theme, width, visible_height)
       when not is_nil(mode) do
    column style: %{gap: 0} do
      [
        text("New identity rule", fg: theme.accent.fg, style: [:bold]),
        text(identity_kind_line(state), fg: identity_field_color(state, :kind, theme)),
        text(identity_field_line(state, :value), fg: identity_field_color(state, :value, theme)),
        text(identity_field_line(state, :reason),
          fg: identity_field_color(state, :reason, theme)
        ),
        text(identity_field_line(state, :comment),
          fg: identity_field_color(state, :comment, theme)
        ),
        text("")
      ] ++ identity_form_guidance(theme, width, visible_height)
    end
  end

  defp handle_network_form_key(%{key: :escape}, state), do: {%{state | form_mode: nil}, []}
  defp handle_network_form_key(%{key: :tab}, state), do: {next_network_field(state), []}
  defp handle_network_form_key(%{key: :enter}, state), do: submit_network_form(state)

  defp handle_network_form_key(%{key: :char, char: "s", ctrl: true}, state),
    do: submit_network_form(state)

  defp handle_network_form_key(%{key: :char, char: <<127>>}, state),
    do: {network_backspace(state), []}

  defp handle_network_form_key(%{key: :backspace}, state), do: {network_backspace(state), []}

  defp handle_network_form_key(%{key: :char, char: c}, state) when is_binary(c),
    do: {network_append_char(state, c), []}

  defp handle_network_form_key(_event, state), do: {state, []}

  defp handle_identity_form_key(%{key: :escape}, state),
    do: {%{state | identity_form_mode: nil}, []}

  defp handle_identity_form_key(%{key: :tab}, state), do: {next_identity_field(state), []}
  defp handle_identity_form_key(%{key: :enter}, state), do: submit_identity_form(state)

  defp handle_identity_form_key(%{key: :char, char: "s", ctrl: true}, state),
    do: submit_identity_form(state)

  defp handle_identity_form_key(%{key: :char, char: <<127>>}, state),
    do: {identity_backspace(state), []}

  defp handle_identity_form_key(%{key: :backspace}, state), do: {identity_backspace(state), []}

  defp handle_identity_form_key(%{key: :left}, state), do: {cycle_identity_kind(state, -1), []}
  defp handle_identity_form_key(%{key: :right}, state), do: {cycle_identity_kind(state, 1), []}

  defp handle_identity_form_key(%{key: :char, char: c}, %{identity_form_field: :kind} = state)
       when c in [" ", "j", "J", "k", "K"],
       do: {cycle_identity_kind(state, 1), []}

  defp handle_identity_form_key(%{key: :char, char: c}, state) when is_binary(c),
    do: {identity_append_char(state, c), []}

  defp handle_identity_form_key(_event, state), do: {state, []}

  defp submit_network_form(%__MODULE__{} = state) do
    attrs = %{
      mode: if(state.form_mode == :create_allow, do: :allow, else: :deny),
      address: String.trim(state.draft["address"] || ""),
      reason: String.trim(state.draft["reason"] || ""),
      comment: String.trim(state.draft["comment"] || "")
    }

    {state, [network_task(state, fn -> SSH.create_access_rule(state.current_user, attrs) end)]}
  end

  defp submit_identity_form(%__MODULE__{} = state) do
    attrs = %{
      kind: state.identity_form_mode,
      value: String.trim(state.identity_draft["value"] || ""),
      reason: String.trim(state.identity_draft["reason"] || ""),
      comment: String.trim(state.identity_draft["comment"] || "")
    }

    {state,
     [identity_task(state, fn -> Accounts.create_identity_rule(state.current_user, attrs) end)]}
  end

  defp confirm_or_update_selected(%__MODULE__{section: :network, rules: []} = state, _op),
    do: {state, []}

  defp confirm_or_update_selected(
         %__MODULE__{section: :identity, identity_rules: []} = state,
         _op
       ),
       do: {state, []}

  defp confirm_or_update_selected(%__MODULE__{section: :network} = state, op) do
    rule = Enum.at(state.rules, state.selection_index)
    pending = {:network, op, rule.id}

    if state.pending_action == pending do
      update_network_selected(%{state | pending_action: nil, message: nil}, op)
    else
      {%{
         state
         | pending_action: pending,
           message: network_confirmation_message(op, rule, state.allowlist_enabled?)
       }, []}
    end
  end

  defp confirm_or_update_selected(%__MODULE__{section: :identity} = state, op) do
    rule = Enum.at(state.identity_rules, state.identity_selection_index)
    pending = {:identity, op, rule.id}

    if state.pending_action == pending do
      update_identity_selected(%{state | pending_action: nil, message: nil}, op)
    else
      {%{state | pending_action: pending, message: identity_confirmation_message(op, rule)}, []}
    end
  end

  defp update_network_selected(%__MODULE__{} = state, op) do
    rule = Enum.at(state.rules, state.selection_index)

    {state,
     [
       network_task(state, fn ->
         case op do
           :toggle ->
             if(rule.enabled,
               do: SSH.disable_access_rule(state.current_user, rule.id),
               else: SSH.enable_access_rule(state.current_user, rule.id)
             )

           :remove ->
             SSH.remove_access_rule(state.current_user, rule.id)
         end
       end)
     ]}
  end

  defp update_identity_selected(%__MODULE__{} = state, op) do
    rule = Enum.at(state.identity_rules, state.identity_selection_index)

    {state,
     [
       identity_task(state, fn ->
         case op do
           :toggle ->
             if(rule.enabled,
               do: Accounts.disable_identity_rule(state.current_user, rule.id),
               else: Accounts.enable_identity_rule(state.current_user, rule.id)
             )

           :remove ->
             Accounts.remove_identity_rule(state.current_user, rule.id)
         end
       end)
     ]}
  end

  defp network_task(state, action_fun) do
    Effect.task(:sysop_load_access_rules, :sysop, fn ->
      with {:ok, _} <- action_fun.(),
           {:ok, rules} <- SSH.list_access_rules(state.current_user),
           {:ok, identity_rules} <- Accounts.list_identity_rules(state.current_user) do
        {:ok,
         from_rules(
           rules,
           identity_rules,
           state.current_user,
           Config.ssh_ip_allowlist_enabled?()
         )}
      end
    end)
  end

  defp identity_task(state, action_fun) do
    Effect.task(:sysop_load_access_rules, :sysop, fn ->
      with {:ok, rule} <- normalize_identity_result(action_fun.()),
           {:ok, rules} <- SSH.list_access_rules(state.current_user),
           {:ok, identity_rules} <- Accounts.list_identity_rules(state.current_user) do
        message = identity_success_message(rule)

        {:ok,
         from_rules(
           rules,
           identity_rules,
           state.current_user,
           Config.ssh_ip_allowlist_enabled?()
         )
         |> Map.put(:section, :identity)
         |> Map.put(:message, message)}
      end
    end)
  end

  defp normalize_identity_result({:ok, rule, _conflicts}), do: {:ok, rule}
  defp normalize_identity_result(result), do: result

  defp identity_success_message(rule) do
    conflicts = IdentityPolicy.conflicts_for_rule(rule)

    case length(conflicts) do
      0 -> "Identity rule saved."
      1 -> "Identity rule saved; 1 existing user matches for sysop review."
      count -> "Identity rule saved; #{count} existing users match for sysop review."
    end
  rescue
    _ -> "Identity rule saved."
  end

  defp start_network_form(state, mode),
    do: %{
      state
      | section: :network,
        form_mode: mode,
        identity_form_mode: nil,
        form_field: :address,
        pending_action: nil,
        message: nil,
        draft: %{"address" => "", "reason" => "", "comment" => ""}
    }

  defp start_identity_form(state, kind),
    do: %{
      state
      | section: :identity,
        identity_form_mode: kind,
        form_mode: nil,
        identity_form_field: :kind,
        pending_action: nil,
        message: nil,
        identity_draft: %{"value" => "", "reason" => "", "comment" => ""}
    }

  defp switch_section(%{section: :network} = state),
    do: %{state | section: :identity, pending_action: nil, message: nil}

  defp switch_section(state), do: %{state | section: :network, pending_action: nil, message: nil}

  defp move(%__MODULE__{section: :network, rules: rules} = state, delta),
    do: %{
      state
      | selection_index: clamp(state.selection_index + delta, rules),
        pending_action: nil
    }

  defp move(%__MODULE__{section: :identity, identity_rules: rules} = state, delta),
    do: %{
      state
      | identity_selection_index: clamp(state.identity_selection_index + delta, rules),
        pending_action: nil
    }

  defp clamp(_idx, []), do: 0
  defp clamp(idx, rows), do: idx |> max(0) |> min(length(rows) - 1)

  defp next_network_field(%{form_field: :address} = state), do: %{state | form_field: :reason}
  defp next_network_field(%{form_field: :reason} = state), do: %{state | form_field: :comment}
  defp next_network_field(state), do: %{state | form_field: :address}

  defp next_identity_field(%{identity_form_field: :kind} = state),
    do: %{state | identity_form_field: :value}

  defp next_identity_field(%{identity_form_field: :value} = state),
    do: %{state | identity_form_field: :reason}

  defp next_identity_field(%{identity_form_field: :reason} = state),
    do: %{state | identity_form_field: :comment}

  defp next_identity_field(state), do: %{state | identity_form_field: :kind}

  defp network_append_char(state, c),
    do: network_update_draft(state, &String.slice(&1 <> c, 0, 160))

  defp identity_append_char(%{identity_form_field: :kind} = state, _c), do: state

  defp identity_append_char(state, c),
    do: identity_update_draft(state, &String.slice(&1 <> c, 0, 160))

  defp network_backspace(state),
    do: network_update_draft(state, &String.slice(&1, 0, max(String.length(&1) - 1, 0)))

  defp identity_backspace(%{identity_form_field: :kind} = state), do: state

  defp identity_backspace(state),
    do: identity_update_draft(state, &String.slice(&1, 0, max(String.length(&1) - 1, 0)))

  defp network_update_draft(state, fun),
    do: %{state | draft: Map.update!(state.draft, Atom.to_string(state.form_field), fun)}

  defp identity_update_draft(state, fun),
    do: %{
      state
      | identity_draft:
          Map.update!(state.identity_draft, Atom.to_string(state.identity_form_field), fun)
    }

  defp cycle_identity_kind(state, delta) do
    index = Enum.find_index(@identity_kinds, &(&1 == state.identity_form_mode)) || 0
    next = rem(index + delta + length(@identity_kinds), length(@identity_kinds))
    %{state | identity_form_mode: Enum.at(@identity_kinds, next)}
  end

  defp table_width(width), do: width |> max(48) |> min(96)

  defp conflict_guidance(_theme, width, visible_height) when width < 72 or visible_height < 22,
    do: []

  defp conflict_guidance(theme, _width, _visible_height) do
    [
      text(""),
      text("Conflict counts are sysop-only review warnings; denials stay terse.",
        fg: theme.dim.fg
      )
    ]
  end

  defp network_form_guidance(_theme, _width, visible_height) when visible_height < 22, do: []

  defp network_form_guidance(theme, width, _visible_height) do
    [
      text(
        if(width < 72,
          do: "Check lockout risk before save.",
          else:
            "CIDR and exact IPv4/IPv6 entries are accepted. Save only after checking lockout risk."
        ),
        fg: theme.warning.fg
      )
    ]
  end

  defp identity_form_guidance(_theme, _width, visible_height) when visible_height < 22, do: []

  defp identity_form_guidance(theme, width, _visible_height) do
    kinds =
      if width < 72,
        do: "Kinds: handle, email, domain",
        else: "Kinds: reserved_handle, banned_handle, banned_email, banned_email_domain"

    [
      text(kinds, fg: theme.dim.fg),
      text("Conflicts are reported for review; users are not mutated.", fg: theme.warning.fg)
    ]
  end

  defp network_row_map(rule),
    do: %{
      mode: String.upcase(to_string(rule.mode)),
      enabled: if(rule.enabled, do: "yes", else: "no"),
      address: rule.address,
      reason: rule.reason || "—"
    }

  defp identity_row_map(rule),
    do: %{
      kind: kind_label(rule.kind),
      enabled: if(rule.enabled, do: "yes", else: "no"),
      value: display_identity_value(rule),
      conflicts: conflict_status(rule),
      reason: rule.reason || "—"
    }

  defp display_identity_value(%{kind: :banned_email, value: value}), do: mask_email(value)
  defp display_identity_value(%{value: value}), do: value

  defp mask_email(value) when is_binary(value) do
    case String.split(value, "@", parts: 2) do
      [local, domain] when local != "" and domain != "" ->
        first = String.first(local) || "*"
        "#{first}***@#{domain}"

      _ ->
        "***"
    end
  end

  defp mask_email(_), do: "***"

  defp conflict_status(rule) do
    case IdentityPolicy.conflicts_for_rule(rule) do
      [] -> "0"
      conflicts when is_list(conflicts) -> "#{length(conflicts)} review"
      _ -> "check failed"
    end
  rescue
    _ -> "check failed"
  end

  defp message_lines(%{message: nil}, _theme), do: []
  defp message_lines(%{message: msg}, theme), do: [text(msg, fg: theme.warning.fg), text("")]

  defp section_lines(state, theme) do
    network_marker = if(state.section == :network, do: ">", else: " ")
    identity_marker = if(state.section == :identity, do: ">", else: " ")

    [
      text("#{network_marker} Network/IP rules    #{identity_marker} Identity rules",
        fg: theme.accent.fg
      ),
      text("Use Left/Right or Tab to move between ACCESS policy sections."),
      text("")
    ]
  end

  defp policy_lines(_state, _theme, width, visible_height) when width < 72 or visible_height < 22,
    do: []

  defp policy_lines(%{section: :identity}, theme, _width, _visible_height) do
    [
      text("Identity rules cover reserved/banned handles and banned email/domain values.",
        fg: theme.dim.fg
      ),
      text("Existing-user conflicts are warnings for review only; users are not mutated."),
      text("")
    ]
  end

  defp policy_lines(%{allowlist_enabled?: true}, theme, _width, _visible_height) do
    [
      text("Allowlist mode: ON — only enabled ALLOW rules may connect.", fg: theme.warning.fg),
      text("Toggle/remove can lock out operators; press the action key twice to confirm."),
      text("")
    ]
  end

  defp policy_lines(_state, theme, _width, _visible_height) do
    [
      text("Allowlist mode: OFF — DENY rules block matching sources.", fg: theme.dim.fg),
      text("Toggle/remove requires a second keypress to confirm lockout-prone changes."),
      text("")
    ]
  end

  defp footer(%{form_mode: nil, identity_form_mode: nil, section: :network}),
    do:
      "[A] Allow  [D] Deny  [E] Enable/disable*  [X] Remove*  [R] Reload  [←/→] Identity  [↑/↓] Move"

  defp footer(%{form_mode: nil, identity_form_mode: nil, section: :identity}),
    do: "[A] Add rule  [E] Enable/disable*  [X] Remove*  [R] Reload  [←/→] Network/IP  [↑/↓] Move"

  defp footer(_), do: "[Tab] Fields  [Enter/Ctrl+S] Save  [Esc] Cancel"

  defp network_form_title(:create_allow), do: "New allow rule"
  defp network_form_title(:create_deny), do: "New deny rule"

  defp field_line(state, field),
    do:
      marker(state.form_field, field) <>
        String.capitalize(Atom.to_string(field)) <>
        ": " <> (state.draft[Atom.to_string(field)] || "")

  defp identity_kind_line(state),
    do:
      marker(state.identity_form_field, :kind) <>
        "Kind: " <> kind_label(state.identity_form_mode) <> "  (Left/Right or Space)"

  defp identity_field_line(state, field),
    do:
      marker(state.identity_form_field, field) <>
        String.capitalize(Atom.to_string(field)) <>
        ": " <> (state.identity_draft[Atom.to_string(field)] || "")

  defp marker(field, field), do: "> "
  defp marker(_, _), do: "  "
  defp field_color(%{form_field: field}, field, theme), do: theme.accent.fg
  defp field_color(_, _, theme), do: theme.primary.fg
  defp identity_field_color(%{identity_form_field: field}, field, theme), do: theme.accent.fg
  defp identity_field_color(_, _, theme), do: theme.primary.fg

  defp allowlist_label(true), do: "ON — only enabled ALLOW rules may connect"
  defp allowlist_label(false), do: "OFF — DENY rules block matching sources"
  defp allowlist_color(%{allowlist_enabled?: true}, theme), do: theme.warning.fg
  defp allowlist_color(_state, theme), do: theme.dim.fg

  defp network_confirmation_message(:remove, rule, true),
    do: "Press X again to remove #{rule.address}; removing allow rules may lock out operators."

  defp network_confirmation_message(:remove, rule, false),
    do: "Press X again to remove #{rule.address}."

  defp network_confirmation_message(:toggle, rule, true),
    do: "Press E again to toggle #{rule.address}; disabling allow rules may lock out operators."

  defp network_confirmation_message(:toggle, rule, false),
    do: "Press E again to toggle #{rule.address}."

  defp identity_confirmation_message(:remove, rule),
    do: "Press X again to remove #{kind_label(rule.kind)} #{rule.value}."

  defp identity_confirmation_message(:toggle, rule),
    do: "Press E again to toggle #{kind_label(rule.kind)} #{rule.value}."

  defp kind_label(kind), do: kind |> to_string() |> String.replace("_", " ")
end
