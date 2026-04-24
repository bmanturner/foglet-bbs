defmodule Foglet.TUI.Screens.Account.PrefsForm do
  @moduledoc """
  Inline PREFS tab form and Account-local theme preview behavior (D-10, D-15, D-16).

  Draft keys are atoms matching `Foglet.TUI.Screens.Account.State`.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Screens.Account.State
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Input.RadioGroup

  @fields [:timezone, :time_format, :theme]
  @labels %{timezone: "Timezone", time_format: "Time format", theme: "Theme"}
  @time_formats ["12h", "24h"]

  @spec render(State.t(), Theme.t()) :: any()
  def render(%State{} = state, %Theme{} = theme) do
    column style: %{gap: 0} do
      [
        text_row(state, theme, :timezone),
        text("  Time format:", fg: label_color(state, theme, :time_format)),
        RadioGroup.render(
          @time_formats,
          selected_index(@time_formats, state.prefs_draft.time_format), theme: theme),
        text("  Theme:", fg: label_color(state, theme, :theme)),
        RadioGroup.render(theme_labels(), selected_index(theme_ids(), preview_theme_id(state)),
          theme: theme
        ),
        error_rows(state.prefs_errors, theme),
        status_row(state.status_message, theme),
        text("Tab/Up/Down: field  Enter/S: save  Esc/C: cancel", fg: theme.dim.fg)
      ]
      |> List.flatten()
    end
  end

  @spec handle_key(map(), State.t(), map() | struct() | nil) ::
          {:ok, State.t(), list()} | :no_match
  def handle_key(event, %State{} = state, current_user) do
    cond do
      cancel?(event) ->
        {:ok,
         State.seed_from_user(
           %{state | candidate_theme_id: nil, status_message: "Preference changes discarded."},
           current_user
         ), []}

      save?(event) ->
        save(state)

      selection_next?(event) and state.prefs_focus == :theme ->
        {:ok, cycle_theme(state, 1), []}

      selection_previous?(event) and state.prefs_focus == :theme ->
        {:ok, cycle_theme(state, -1), []}

      selection_next?(event) and state.prefs_focus == :time_format ->
        {:ok, cycle_time_format(state, 1), []}

      selection_previous?(event) and state.prefs_focus == :time_format ->
        {:ok, cycle_time_format(state, -1), []}

      next_focus?(event) ->
        {:ok, %{state | prefs_focus: move_focus(state.prefs_focus, 1)}, []}

      previous_focus?(event) ->
        {:ok, %{state | prefs_focus: move_focus(state.prefs_focus, -1)}, []}

      text_input?(event) and state.prefs_focus == :timezone ->
        {:ok, update_timezone(state, event), []}

      true ->
        :no_match
    end
  end

  defp text_row(%State{} = state, %Theme{} = theme, field) do
    marker = if state.prefs_focus == field, do: "> ", else: "  "
    value = Map.get(state.prefs_draft, field) || ""
    text("#{marker}#{Map.fetch!(@labels, field)}: #{value}", fg: label_color(state, theme, field))
  end

  defp label_color(%State{prefs_focus: field}, %Theme{} = theme, field), do: theme.selected.fg
  defp label_color(_state, %Theme{} = theme, _field), do: theme.primary.fg

  defp error_rows(errors, %Theme{} = theme) do
    Enum.map(errors, fn {field, message} ->
      text("#{Map.fetch!(@labels, field)} error: #{message}", fg: theme.error.fg)
    end)
  end

  defp status_row(nil, _theme), do: []
  defp status_row(message, %Theme{} = theme), do: [text(message, fg: theme.warning.fg)]

  defp save(%State{} = state) do
    errors = validate(state.prefs_draft)

    if map_size(errors) == 0 do
      attrs = %{
        timezone: state.prefs_draft.timezone,
        preferences: %{"time_format" => state.prefs_draft.time_format},
        theme: preview_theme_id(state)
      }

      {:ok, %{state | prefs_errors: %{}, status_message: "Preferences ready to save."},
       [{:account_save_prefs, attrs}]}
    else
      {:ok, %{state | prefs_errors: errors, status_message: "Preferences have errors."}, []}
    end
  end

  defp validate(draft) do
    %{}
    |> maybe_put_error(:timezone, blank?(draft.timezone), "can't be blank")
    |> maybe_put_error(:time_format, draft.time_format not in @time_formats, "must be 12h or 24h")
    |> maybe_put_error(:theme, draft.theme not in theme_ids(), "must be a registered theme")
  end

  defp maybe_put_error(errors, field, true, message), do: Map.put(errors, field, message)
  defp maybe_put_error(errors, _field, false, _message), do: errors

  defp update_timezone(%State{} = state, %{key: :char, char: char}) do
    value = (state.prefs_draft.timezone || "") <> char
    put_prefs_value(state, :timezone, value)
  end

  defp update_timezone(%State{} = state, %{key: :backspace}) do
    value = state.prefs_draft.timezone || ""
    put_prefs_value(state, :timezone, String.slice(value, 0, max(String.length(value) - 1, 0)))
  end

  defp cycle_time_format(%State{} = state, delta) do
    value = cycle(@time_formats, state.prefs_draft.time_format, delta)
    put_prefs_value(state, :time_format, value)
  end

  defp cycle_theme(%State{} = state, delta) do
    value = cycle(theme_ids(), preview_theme_id(state), delta)

    state
    |> put_prefs_value(:theme, value)
    |> Map.put(:candidate_theme_id, value)
  end

  defp put_prefs_value(%State{} = state, field, value) do
    %{
      state
      | prefs_draft: Map.put(state.prefs_draft, field, value),
        prefs_dirty?: true,
        status_message: nil
    }
  end

  defp move_focus(field, delta) do
    idx = Enum.find_index(@fields, &(&1 == field)) || 0
    Enum.at(@fields, rem(idx + delta + length(@fields), length(@fields)))
  end

  defp cycle(values, current, delta) do
    idx = Enum.find_index(values, &(&1 == current)) || 0
    Enum.at(values, rem(idx + delta + length(values), length(values)))
  end

  defp selected_index(values, current), do: Enum.find_index(values, &(&1 == current)) || 0
  defp preview_theme_id(%State{} = state), do: state.candidate_theme_id || state.prefs_draft.theme
  defp theme_ids, do: Enum.map(Theme.ids(), &Atom.to_string/1)
  defp theme_labels, do: theme_ids()
  defp blank?(value), do: value in [nil, ""]

  defp selection_next?(%{key: :down}), do: true
  defp selection_next?(%{key: :char, char: char}) when char in ["n", "N", " "], do: true
  defp selection_next?(_event), do: false

  defp selection_previous?(%{key: :up}), do: true
  defp selection_previous?(%{key: :char, char: char}) when char in ["p", "P"], do: true
  defp selection_previous?(_event), do: false

  defp next_focus?(%{key: :tab}), do: true
  defp next_focus?(_event), do: false

  defp previous_focus?(%{key: :shift_tab}), do: true
  defp previous_focus?(_event), do: false

  defp cancel?(%{key: :escape}), do: true
  defp cancel?(%{key: :char, char: char}) when char in ["c", "C"], do: true
  defp cancel?(_event), do: false

  defp save?(%{key: :enter}), do: true
  defp save?(%{key: :char, char: char}) when char in ["s", "S"], do: true
  defp save?(_event), do: false

  defp text_input?(%{key: :char, char: char}), do: String.length(char) == 1
  defp text_input?(%{key: :backspace}), do: true
  defp text_input?(_event), do: false
end
