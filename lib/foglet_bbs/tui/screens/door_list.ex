defmodule Foglet.TUI.Screens.DoorList do
  @moduledoc """
  Door Games selector and launch confirmation screen.

  The screen keeps selection/confirmation in TUI state and emits the explicit
  `Foglet.TUI.Effect.launch_door/2` runtime effect. It does not spawn door
  processes directly.
  """

  @behaviour Foglet.TUI.Screen

  import Raxol.Core.Renderer.View

  alias Foglet.AppName
  alias Foglet.Doors.Manifest
  alias Foglet.TUI.{Context, Effect, Layout, Modal, ScrollKeys, TextWidth, Theme}
  alias Foglet.TUI.Guest
  alias Foglet.TUI.Text, as: StyledText
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame

  @wide_layout_min_width 100
  @wide_list_width 44
  @wide_detail_width 48
  @row_width 72

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

  def update({:key, %{key: key} = event}, local_state, %Context{} = context)
      when key in [:up, :down] do
    state = normalize_state(local_state, context)

    {%{
       state
       | selected_index:
           clamp(state.selected_index + ScrollKeys.vertical_delta(event), state.doors)
     }, []}
  end

  def update({:key, %{key: :char, char: c} = event}, local_state, %Context{} = context)
      when c in ["j", "k"] do
    state = normalize_state(local_state, context)

    {%{
       state
       | selected_index:
           clamp(state.selected_index + ScrollKeys.vertical_delta(event), state.doors)
     }, []}
  end

  def update({:key, %{key: :enter}}, local_state, %Context{} = context) do
    state = normalize_state(local_state, context)

    case selected_door(state) do
      %Manifest{} = manifest ->
        if Guest.guest?(context) do
          {state, [Effect.open_modal(Guest.denial_modal(:door))]}
        else
          {state, [Effect.open_modal(confirm_modal(manifest))]}
        end

      nil ->
        {state, []}
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

    if Guest.guest?(context) do
      {state, [Effect.open_modal(Guest.denial_modal(:door))]}
    else
      case doors_module(context).get_visible(context.current_user, door_id) do
        {:ok, %Manifest{} = manifest} ->
          message =
            "Launching #{manifest.display_name}. The door has the terminal until it exits."

          {%{state | status_message: message}, [Effect.launch_door(manifest)]}

        {:error, :not_found} ->
          {%{state | status_message: "That door is no longer available."},
           [Effect.open_modal(%Modal{type: :error, message: "That door is no longer available."})]}
      end
    end
  end

  def update(
        {:door_exited, door_id, {:error, _reason}, _status},
        local_state,
        %Context{} = context
      ) do
    state = normalize_state(local_state, context)

    {%{
       state
       | status_message: "#{door_name(state, door_id)} did not start. Back in #{AppName.name()}."
     }, []}
  end

  def update({:door_launch_failed, door_id, _reason}, local_state, %Context{} = context) do
    state = normalize_state(local_state, context)

    {%{
       state
       | status_message: "#{door_name(state, door_id)} did not start. Back in #{AppName.name()}."
     }, []}
  end

  def update({:door_exited, door_id, _reason, _status}, local_state, %Context{} = context) do
    state = normalize_state(local_state, context)

    {%{state | status_message: "#{door_name(state, door_id)} closed. Back in #{AppName.name()}."},
     []}
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
          intro_block(theme),
          doors_region(state, theme, context),
          status_line(state, theme)
        ]
      end

    ScreenFrame.render(
      frame_state,
      %{breadcrumb_parts: Foglet.AppName.breadcrumb(["Door Games"])},
      body,
      commands_for(state)
    )
  end

  defp intro_block(theme) do
    column style: %{gap: 0} do
      [
        StyledText.Span.new("Choose a door game.", fg: :primary)
        |> StyledText.to_raxol(theme),
        StyledText.Span.new("Doors may take over the terminal, then return here.", fg: :primary)
        |> StyledText.to_raxol(theme)
      ]
    end
  end

  defp doors_region(%State{doors: []} = state, theme, _context), do: door_rows(state, theme)

  defp doors_region(%State{} = state, theme, %Context{terminal_size: {width, _height}})
       when width >= @wide_layout_min_width do
    {list_width, detail_width} = wide_panel_widths(width)

    row style: %{gap: 2} do
      [
        box style: %{border: :single, padding: 1, width: list_width} do
          door_rows(state, theme, list_width - 4)
        end,
        box style: %{border: :single, padding: 1, width: detail_width} do
          detail_panel(selected_door(state), theme, detail_width - 4)
        end
      ]
    end
  end

  defp doors_region(%State{} = state, theme, _context), do: door_rows(state, theme)

  defp wide_panel_widths(terminal_width) do
    [list, _gap, detail] =
      Layout.horizontal(
        %{x: 0, y: 0, width: terminal_width, height: 1},
        [{:length, @wide_list_width}, {:length, 2}, {:max, detail_width(terminal_width)}]
      )

    {list.width, detail.width}
  end

  defp detail_width(terminal_width) do
    terminal_width
    |> Kernel.-(@wide_list_width)
    |> Kernel.-(8)
    |> max(@wide_detail_width)
  end

  defp door_rows(%State{doors: []}, theme) do
    box style: %{border: :single, padding: 1} do
      column style: %{gap: 0} do
        [
          text("No door games are available right now.", fg: theme.warning.fg),
          text("Check back later.", fg: theme.dim.fg)
        ]
      end
    end
  end

  defp door_rows(%State{} = state, theme), do: door_rows(state, theme, @row_width)

  defp door_rows(%State{} = state, theme, width) do
    column style: %{gap: 0} do
      state.doors
      |> Enum.with_index()
      |> Enum.map(fn {%Manifest{} = manifest, index} ->
        text(door_row_label(manifest, index == state.selected_index, width), fg: theme.primary.fg)
      end)
    end
  end

  defp door_row_label(%Manifest{} = manifest, selected?, width) do
    marker = if selected?, do: ">", else: " "
    label = friendly_door_label(manifest)

    TextWidth.slice_to_width("#{marker} #{manifest.display_name} — #{label}", width)
  end

  defp detail_panel(nil, theme, _width) do
    text("No selection", fg: theme.dim.fg)
  end

  defp detail_panel(%Manifest{} = manifest, theme, width) do
    description_rows =
      "About: #{friendly_description(manifest)}"
      |> TextWidth.wrap(width)
      |> Enum.take(2)
      |> Enum.map(&text(&1, fg: theme.dim.fg))

    column style: %{gap: 0} do
      [
        text(TextWidth.slice_to_width(manifest.display_name, width), fg: theme.title.fg),
        text("Kind: #{friendly_door_label(manifest)}", fg: theme.primary.fg),
        text("Status: Ready to launch", fg: theme.primary.fg)
      ] ++
        description_rows ++
        [text("Enter Launch", fg: theme.accent.fg)]
    end
  end

  defp friendly_door_label(%Manifest{id: "usurper-reborn"}), do: "Game"
  defp friendly_door_label(%Manifest{runtime: :classic_dropfile}), do: "Classic BBS door"
  defp friendly_door_label(%Manifest{}), do: "Door"

  defp door_name(%State{} = state, door_id) do
    state.doors
    |> Enum.find(&(&1.id == door_id))
    |> case do
      %Manifest{display_name: display_name} -> display_name
      nil -> humanize_door_id(door_id)
    end
  end

  defp humanize_door_id(door_id) when is_binary(door_id) do
    door_id
    |> String.replace(["-", "_"], " ")
    |> String.split(" ", trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp friendly_description(%Manifest{id: "usurper-reborn"}) do
    "A shared-world fantasy BBS game. Your #{AppName.name()} handle is used when you play."
  end

  defp friendly_description(%Manifest{id: "classic-dropfile-demo"}) do
    "A small classic BBS door demo for checking launch and return behavior."
  end

  defp friendly_description(%Manifest{} = manifest), do: manifest.description

  defp status_line(%State{doors: [], status_message: nil}, theme),
    do: text("Q Back", fg: theme.dim.fg)

  defp status_line(%State{status_message: nil}, theme),
    do: text("Enter Launch  Q Back", fg: theme.dim.fg)

  defp status_line(%State{status_message: message}, theme),
    do: text(message, fg: theme.success.fg)

  defp commands_for(%State{doors: []}) do
    [
      %{
        label: "Nav",
        commands: [
          %{key: "Q", label: "Back", priority: 0}
        ]
      }
    ]
  end

  defp commands_for(%State{}) do
    [
      %{label: "Actions", commands: [%{key: "Enter", label: "Launch", priority: 5}]},
      %{
        label: "Nav",
        commands: [
          %{key: ScrollKeys.commandbar_key(), label: "Select", priority: 10},
          %{key: "Q", label: "Back", priority: 0}
        ]
      }
    ]
  end

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

  defp normalize_state(%State{} = state, %Context{} = context) do
    doors = if state.doors == [], do: visible_doors(context), else: state.doors
    %{state | doors: doors, selected_index: clamp(state.selected_index, doors)}
  end

  defp normalize_state(_state, %Context{} = context), do: init(context)

  defp visible_doors(%Context{} = context),
    do: doors_module(context).list_browsable(context.current_user)

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
      unread_count: context.unread_count,
      session_context: context.session_context,
      session_pid: context.session_pid,
      terminal_size: context.terminal_size || {80, 24},
      route_params: context.route_params || %{},
      screen_state: %{door_list: state}
    }
  end
end
