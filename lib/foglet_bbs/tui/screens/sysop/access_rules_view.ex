defmodule Foglet.TUI.Screens.Sysop.AccessRulesView do
  @moduledoc """
  ACCESS tab submodule for sysop SSH IP access policy management.
  """

  alias Foglet.Config
  alias Foglet.SSH
  alias Foglet.TUI.Effect
  alias Foglet.TUI.ScrollKeys
  alias Foglet.TUI.Widgets.Display.ConsoleTable

  import Raxol.Core.Renderer.View

  @columns [
    %{key: :mode, label: "Mode", width: 6, priority: 20, demand: :content},
    %{key: :enabled, label: "On", width: 4, priority: 20, demand: :content},
    %{key: :address, label: "Address/CIDR", width: 28, grow: 1, priority: 100, demand: :content},
    %{key: :reason, label: "Reason", width: 18, grow: 1, priority: 60, demand: :content}
  ]

  @type form_mode :: nil | :create_deny | :create_allow
  @type t :: %__MODULE__{
          current_user: Foglet.Accounts.User.t() | nil,
          rules: [struct()],
          selection_index: non_neg_integer(),
          message: String.t() | nil,
          allowlist_enabled?: boolean(),
          pending_action: {:toggle | :remove, pos_integer()} | nil,
          form_mode: form_mode(),
          form_field: :address | :reason | :comment,
          draft: map()
        }

  defstruct current_user: nil,
            rules: [],
            selection_index: 0,
            message: nil,
            allowlist_enabled?: false,
            pending_action: nil,
            form_mode: nil,
            form_field: :address,
            draft: %{"address" => "", "reason" => "", "comment" => ""}

  @spec from_rules([struct()], Foglet.Accounts.User.t() | nil) :: t()
  def from_rules(rules, current_user, allowlist_enabled? \\ Config.ssh_ip_allowlist_enabled?())

  def from_rules(rules, current_user, allowlist_enabled?) when is_list(rules) do
    %__MODULE__{current_user: current_user, rules: rules, allowlist_enabled?: allowlist_enabled?}
  end

  @spec handle_key(map(), t()) :: {t(), [Effect.t()]}
  def handle_key(event, %__MODULE__{form_mode: mode} = state) when not is_nil(mode),
    do: handle_form_key(event, state)

  def handle_key(%{key: key} = event, state) when key in [:up, :down],
    do: {move(state, ScrollKeys.vertical_delta(event)), []}

  def handle_key(%{key: :char, char: char} = event, state) when char in ["j", "k"],
    do: {move(state, ScrollKeys.vertical_delta(event)), []}

  def handle_key(%{key: :char, char: c}, state) when c in ["r", "R"],
    do: {state, [load_effect(state.current_user)]}

  def handle_key(%{key: :char, char: c}, state) when c in ["d", "D"],
    do: {start_form(state, :create_deny), []}

  def handle_key(%{key: :char, char: c}, state) when c in ["a", "A"],
    do: {start_form(state, :create_allow), []}

  def handle_key(%{key: :char, char: c}, state) when c in ["e", "E"],
    do: confirm_or_update_selected(state, :toggle)

  def handle_key(%{key: :char, char: c}, state) when c in ["x", "X"],
    do: confirm_or_update_selected(state, :remove)

  def handle_key(_event, state), do: {state, []}

  @spec render(t(), map()) :: any()
  def render(%__MODULE__{} = state, theme) do
    rows = Enum.map(state.rules, &row_map/1)

    table =
      ConsoleTable.init(
        columns: @columns,
        rows: rows,
        width: 60,
        selectable: true,
        empty_state: "No IP access rules configured."
      )

    column style: %{gap: 0} do
      [text("SSH IP access policies", fg: theme.title.fg, style: [:bold]), text("")] ++
        policy_lines(state, theme) ++
        message_lines(state, theme) ++
        [render_body(state, table, theme), text(""), text(footer(state), fg: theme.dim.fg)]
    end
  end

  def keybar_groups(%__MODULE__{form_mode: nil}) do
    [
      %{
        label: "Access",
        commands: [
          %{key: "A", label: "Allow", priority: 5},
          %{key: "D", label: "Deny", priority: 5},
          %{key: "E", label: "Enable/disable", priority: 10},
          %{key: "X", label: "Remove", priority: 10},
          %{key: "R", label: "Reload", priority: 20}
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
      case SSH.list_access_rules(actor) do
        {:ok, rules} -> {:ok, from_rules(rules, actor, Config.ssh_ip_allowlist_enabled?())}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp render_body(%__MODULE__{form_mode: nil} = state, %ConsoleTable{} = table, theme) do
    table = put_in(table.table.raxol_state[:selected_row], state.selection_index)
    rendered = ConsoleTable.render(table, theme: theme)

    column style: %{gap: 0} do
      [rendered]
    end
  end

  defp render_body(%__MODULE__{} = state, _table, theme) do
    column style: %{gap: 0} do
      [
        text(form_title(state.form_mode), fg: theme.accent.fg, style: [:bold]),
        text(field_line(state, :address), fg: field_color(state, :address, theme)),
        text(field_line(state, :reason), fg: field_color(state, :reason, theme)),
        text(field_line(state, :comment), fg: field_color(state, :comment, theme)),
        text(""),
        text("Allowlist mode: #{allowlist_label(state.allowlist_enabled?)}",
          fg: allowlist_color(state, theme)
        ),
        text(
          "CIDR and exact IPv4/IPv6 entries are accepted. Save only after checking lockout risk.",
          fg: theme.warning.fg
        )
      ]
    end
  end

  defp handle_form_key(%{key: :escape}, state), do: {%{state | form_mode: nil}, []}
  defp handle_form_key(%{key: :tab}, state), do: {next_field(state), []}
  defp handle_form_key(%{key: :enter}, state), do: submit_form(state)
  defp handle_form_key(%{key: :char, char: "s", ctrl: true}, state), do: submit_form(state)
  defp handle_form_key(%{key: :char, char: <<127>>}, state), do: {backspace(state), []}
  defp handle_form_key(%{key: :backspace}, state), do: {backspace(state), []}

  defp handle_form_key(%{key: :char, char: c}, state) when is_binary(c),
    do: {append_char(state, c), []}

  defp handle_form_key(_event, state), do: {state, []}

  defp submit_form(%__MODULE__{} = state) do
    attrs = %{
      mode: if(state.form_mode == :create_allow, do: :allow, else: :deny),
      address: String.trim(state.draft["address"] || ""),
      reason: String.trim(state.draft["reason"] || ""),
      comment: String.trim(state.draft["comment"] || "")
    }

    {state,
     [
       Effect.task(:sysop_load_access_rules, :sysop, fn ->
         with {:ok, _rule} <- SSH.create_access_rule(state.current_user, attrs),
              {:ok, rules} <- SSH.list_access_rules(state.current_user) do
           {:ok, from_rules(rules, state.current_user, Config.ssh_ip_allowlist_enabled?())}
         end
       end)
     ]}
  end

  defp update_selected(%__MODULE__{rules: []} = state, _op), do: {state, []}

  defp update_selected(%__MODULE__{} = state, op) do
    rule = Enum.at(state.rules, state.selection_index)

    {state,
     [
       Effect.task(:sysop_load_access_rules, :sysop, fn ->
         result =
           case op do
             :toggle ->
               if(rule.enabled,
                 do: SSH.disable_access_rule(state.current_user, rule.id),
                 else: SSH.enable_access_rule(state.current_user, rule.id)
               )

             :remove ->
               SSH.remove_access_rule(state.current_user, rule.id)
           end

         with {:ok, _} <- result,
              {:ok, rules} <- SSH.list_access_rules(state.current_user) do
           {:ok, from_rules(rules, state.current_user, Config.ssh_ip_allowlist_enabled?())}
         end
       end)
     ]}
  end

  defp confirm_or_update_selected(%__MODULE__{rules: []} = state, _op), do: {state, []}

  defp confirm_or_update_selected(%__MODULE__{} = state, op) do
    rule = Enum.at(state.rules, state.selection_index)
    pending = {op, rule.id}

    if state.pending_action == pending do
      update_selected(%{state | pending_action: nil, message: nil}, op)
    else
      {%{
         state
         | pending_action: pending,
           message: confirmation_message(op, rule, state.allowlist_enabled?)
       }, []}
    end
  end

  defp start_form(state, mode),
    do: %{
      state
      | form_mode: mode,
        form_field: :address,
        pending_action: nil,
        message: nil,
        draft: %{"address" => "", "reason" => "", "comment" => ""}
    }

  defp move(%__MODULE__{rules: rules} = state, delta),
    do: %{state | selection_index: clamp(state.selection_index + delta, rules)}

  defp clamp(_idx, []), do: 0
  defp clamp(idx, rows), do: idx |> max(0) |> min(length(rows) - 1)
  defp next_field(%{form_field: :address} = state), do: %{state | form_field: :reason}
  defp next_field(%{form_field: :reason} = state), do: %{state | form_field: :comment}
  defp next_field(state), do: %{state | form_field: :address}
  defp append_char(state, c), do: update_draft(state, &String.slice(&1 <> c, 0, 160))

  defp backspace(state),
    do: update_draft(state, &String.slice(&1, 0, max(String.length(&1) - 1, 0)))

  defp update_draft(state, fun),
    do: %{state | draft: Map.update!(state.draft, Atom.to_string(state.form_field), fun)}

  defp row_map(rule),
    do: %{
      mode: String.upcase(to_string(rule.mode)),
      enabled: if(rule.enabled, do: "yes", else: "no"),
      address: rule.address,
      reason: rule.reason || "—"
    }

  defp message_lines(%{message: nil}, _theme), do: []
  defp message_lines(%{message: msg}, theme), do: [text(msg, fg: theme.warning.fg), text("")]

  defp policy_lines(%{allowlist_enabled?: true}, theme) do
    [
      text("Allowlist mode: ON — only enabled ALLOW rules may connect.", fg: theme.warning.fg),
      text("Toggle/remove can lock out operators; press the action key twice to confirm."),
      text("")
    ]
  end

  defp policy_lines(_state, theme) do
    [
      text("Allowlist mode: OFF — DENY rules block matching sources.", fg: theme.dim.fg),
      text("Toggle/remove requires a second keypress to confirm lockout-prone changes."),
      text("")
    ]
  end

  defp footer(%{form_mode: nil}),
    do: "[↑/↓] Move  [A] Allow  [D] Deny  [E] Enable/disable*  [X] Remove*  [R] Reload"

  defp footer(_), do: "[Tab] Fields  [Enter/Ctrl+S] Save  [Esc] Cancel"
  defp form_title(:create_allow), do: "New allow rule"
  defp form_title(:create_deny), do: "New deny rule"

  defp field_line(state, field),
    do:
      marker(state, field) <>
        String.capitalize(Atom.to_string(field)) <>
        ": " <> (state.draft[Atom.to_string(field)] || "")

  defp marker(%{form_field: field}, field), do: "> "
  defp marker(_, _), do: "  "
  defp field_color(%{form_field: field}, field, theme), do: theme.accent.fg
  defp field_color(_, _, theme), do: theme.primary.fg

  defp allowlist_label(true), do: "ON — only enabled ALLOW rules may connect"
  defp allowlist_label(false), do: "OFF — DENY rules block matching sources"
  defp allowlist_color(%{allowlist_enabled?: true}, theme), do: theme.warning.fg
  defp allowlist_color(_state, theme), do: theme.dim.fg

  defp confirmation_message(:remove, rule, true),
    do: "Press X again to remove #{rule.address}; removing allow rules may lock out operators."

  defp confirmation_message(:remove, rule, false),
    do: "Press X again to remove #{rule.address}."

  defp confirmation_message(:toggle, rule, true),
    do: "Press E again to toggle #{rule.address}; disabling allow rules may lock out operators."

  defp confirmation_message(:toggle, rule, false),
    do: "Press E again to toggle #{rule.address}."
end
