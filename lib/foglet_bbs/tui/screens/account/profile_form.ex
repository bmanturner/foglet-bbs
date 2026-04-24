defmodule Foglet.TUI.Screens.Account.ProfileForm do
  @moduledoc """
  Inline PROFILE tab form for Account (D-10, D-13, D-16).

  Draft keys are atoms matching `Foglet.TUI.Screens.Account.State`.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Screens.Account.State
  alias Foglet.TUI.Theme

  @fields [:location, :tagline, :real_name]
  @labels %{location: "Location", tagline: "Tagline", real_name: "Real name"}
  @max_lengths %{location: 80, tagline: 120, real_name: 120}

  @spec render(State.t(), Theme.t()) :: any()
  def render(%State{} = state, %Theme{} = theme) do
    column style: %{gap: 0} do
      [
        form_rows(state, theme),
        error_rows(state.profile_errors, theme),
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
      next_focus?(event) ->
        {:ok, %{state | profile_focus: move_focus(state.profile_focus, 1)}, []}

      previous_focus?(event) ->
        {:ok, %{state | profile_focus: move_focus(state.profile_focus, -1)}, []}

      cancel?(event) ->
        {:ok,
         State.seed_from_user(
           %{state | status_message: "Profile changes discarded."},
           current_user
         ), []}

      save?(event) ->
        save(state)

      text_input?(event) ->
        {:ok, update_text(state, event), []}

      true ->
        :no_match
    end
  end

  defp form_rows(%State{} = state, %Theme{} = theme) do
    Enum.map(@fields, fn field ->
      label = Map.fetch!(@labels, field)
      value = Map.get(state.profile_draft, field) || ""
      marker = if state.profile_focus == field, do: "> ", else: "  "
      fg = if state.profile_focus == field, do: theme.selected.fg, else: theme.primary.fg
      text("#{marker}#{label}: #{value}", fg: fg)
    end)
  end

  defp error_rows(errors, %Theme{} = theme) do
    Enum.map(errors, fn {field, message} ->
      text("#{Map.fetch!(@labels, field)} error: #{message}", fg: theme.error.fg)
    end)
  end

  defp status_row(nil, _theme), do: []
  defp status_row(message, %Theme{} = theme), do: [text(message, fg: theme.warning.fg)]

  defp save(%State{} = state) do
    errors = validate(state.profile_draft)

    if map_size(errors) == 0 do
      attrs = Map.take(state.profile_draft, @fields)

      {:ok, %{state | profile_errors: %{}, status_message: "Profile ready to save."},
       [{:account_save_profile, attrs}]}
    else
      {:ok, %{state | profile_errors: errors, status_message: "Profile has errors."}, []}
    end
  end

  defp validate(draft) do
    Enum.reduce(@max_lengths, %{}, fn {field, max_length}, errors ->
      value = Map.get(draft, field) || ""

      if String.length(value) > max_length do
        Map.put(errors, field, "must be at most #{max_length} characters")
      else
        errors
      end
    end)
  end

  defp update_text(%State{} = state, %{key: :char, char: char}) do
    put_profile_value(
      state,
      state.profile_focus,
      (Map.get(state.profile_draft, state.profile_focus) || "") <> char
    )
  end

  defp update_text(%State{} = state, %{key: :backspace}) do
    value = Map.get(state.profile_draft, state.profile_focus) || ""

    put_profile_value(
      state,
      state.profile_focus,
      String.slice(value, 0, max(String.length(value) - 1, 0))
    )
  end

  defp put_profile_value(%State{} = state, field, value) do
    %{
      state
      | profile_draft: Map.put(state.profile_draft, field, value),
        profile_dirty?: true,
        status_message: nil
    }
  end

  defp move_focus(field, delta) do
    idx = Enum.find_index(@fields, &(&1 == field)) || 0
    Enum.at(@fields, rem(idx + delta + length(@fields), length(@fields)))
  end

  defp next_focus?(%{key: key}) when key in [:tab, :down], do: true
  defp next_focus?(_event), do: false

  defp previous_focus?(%{key: key}) when key in [:shift_tab, :up], do: true
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
