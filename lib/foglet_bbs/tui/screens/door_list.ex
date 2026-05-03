defmodule Foglet.TUI.Screens.DoorList do
  @moduledoc """
  Door Games selector and launch confirmation screen.

  The screen keeps selection/confirmation in TUI state and emits the explicit
  `Foglet.TUI.Effect.launch_door/2` runtime effect. It does not spawn door
  processes directly.
  """

  @behaviour Foglet.TUI.Screen

  import Raxol.Core.Renderer.View

  alias Foglet.Doors.Manifest
  alias Foglet.TUI.{Context, Effect, Modal, TextWidth, Theme}
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame

  defmodule State do
    @moduledoc false
    defstruct selected_index: 0, doors: [], status_message: nil
  end

  @impl true
  def init(%Context{} = context), do: %State{doors: visible_doors(context)}

  @impl true
  def update(:on_route_enter, local_state, %Context{} = context) do
    state = normalize_state(local_state, context)
    {%{state | doors: visible_doors(context)}, []}
  end

  def update({:key, %{key: :up}}, local_state, %Context{} = context) do
    state = normalize_state(local_state, context)
    {%{state | selected_index: clamp(state.selected_index - 1, state.doors)}, []}
  end

  def update({:key, %{key: :down}}, local_state, %Context{} = context) do
    state = normalize_state(local_state, context)
    {%{state | selected_index: clamp(state.selected_index + 1, state.doors)}, []}
  end

  def update({:key, %{key: :enter}}, local_state, %Context{} = context) do
    state = normalize_state(local_state, context)

    case selected_door(state) do
      %Manifest{} = manifest ->
        {state, [Effect.open_modal(confirm_modal(manifest))]}

      nil ->
        {%{state | status_message: "No door games are available for this account."}, []}
    end
  end

  def update({:key, %{key: :char, char: c}}, local_state, %Context{} = context)
      when c in ["q", "Q"] do
    {normalize_state(local_state, context), [Effect.navigate(:main_menu, %{})]}
  end

  def update(
        {:modal_submit, :launch_door, %{door_id: door_id}},
        local_state,
        %Context{} = context
      ) do
    state = normalize_state(local_state, context)

    case doors_module(context).get_visible(context.current_user, door_id) do
      {:ok, %Manifest{} = manifest} ->
        message = "Launched #{manifest.display_name}. You are back in Foglet."

        {%{state | status_message: message},
         [Effect.launch_door(manifest), Effect.open_modal(return_modal(message))]}

      {:error, :not_found} ->
        {%{state | status_message: "That door is no longer available."},
         [Effect.open_modal(%Modal{type: :error, message: "That door is no longer available."})]}
    end
  end

  def update(_message, local_state, %Context{} = context),
    do: {normalize_state(local_state, context), []}

  @impl true
  def render(%State{} = state, %Context{} = context) do
    frame_state = frame_state(context, state)
    theme = Theme.from_state(frame_state)

    body =
      column style: %{gap: 1} do
        [
          text("Choose a door game. Doors may take over the terminal, then return here.",
            fg: theme.primary.fg
          ),
          door_rows(state, theme),
          status_line(state, theme)
        ]
      end

    ScreenFrame.render(frame_state, %{breadcrumb_parts: ["Foglet", "Door Games"]}, body, [
      %{label: "Actions", commands: [%{key: "Enter", label: "Launch", priority: 5}]},
      %{
        label: "Nav",
        commands: [
          %{key: "↑/↓", label: "Select", priority: 10},
          %{key: "Q", label: "Back", priority: 0}
        ]
      }
    ])
  end

  defp door_rows(%State{doors: []}, theme) do
    column style: %{gap: 0} do
      [text("No visible door games are configured.", fg: theme.warning.fg)]
    end
  end

  defp door_rows(%State{} = state, theme) do
    column style: %{gap: 0} do
      state.doors
      |> Enum.with_index()
      |> Enum.map(fn {%Manifest{} = manifest, index} ->
        marker = if index == state.selected_index, do: ">", else: " "
        runtime = manifest.runtime |> Atom.to_string() |> String.replace("_", " ")
        label = TextWidth.slice_to_width("#{marker} #{manifest.display_name} — #{runtime}", 62)
        text(label, fg: theme.primary.fg)
      end)
    end
  end

  defp status_line(%State{status_message: nil}, theme),
    do: text("Enter Launch  Q Back", fg: theme.dim.fg)

  defp status_line(%State{status_message: message}, theme),
    do: text(message, fg: theme.success.fg)

  defp selected_door(%State{doors: doors, selected_index: index}), do: Enum.at(doors, index)

  defp confirm_modal(%Manifest{} = manifest) do
    %Modal{
      type: :confirm,
      message:
        "Launch #{manifest.display_name}? It may take over the full terminal until it exits.",
      on_confirm: fn app_state ->
        Foglet.TUI.App.Effects.apply_effect(
          app_state,
          Effect.modal_submit(:door_list, :launch_door, %{door_id: manifest.id})
        )
      end,
      on_cancel: :dismiss_modal
    }
  end

  defp return_modal(message), do: %Modal{type: :info, message: message}

  defp normalize_state(%State{} = state, %Context{} = context) do
    doors = if state.doors == [], do: visible_doors(context), else: state.doors
    %{state | doors: doors, selected_index: clamp(state.selected_index, doors)}
  end

  defp normalize_state(_state, %Context{} = context), do: init(context)

  defp visible_doors(%Context{} = context),
    do: doors_module(context).list_visible(context.current_user)

  defp doors_module(%Context{domain: domain}) when is_map(domain) do
    case Map.get(domain, :doors) do
      module when is_atom(module) and not is_nil(module) -> module
      _other -> Foglet.Doors
    end
  end

  defp clamp(_index, []), do: 0
  defp clamp(index, doors), do: index |> max(0) |> min(length(doors) - 1)

  defp frame_state(%Context{} = context, %State{} = state) do
    %{
      current_screen: :door_list,
      current_user: context.current_user,
      session_context: context.session_context,
      session_pid: context.session_pid,
      terminal_size: context.terminal_size || {80, 24},
      route_params: context.route_params || %{},
      screen_state: %{door_list: state}
    }
  end
end
