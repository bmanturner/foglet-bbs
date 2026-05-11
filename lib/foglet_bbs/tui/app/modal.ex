defmodule Foglet.TUI.App.Modal do
  @moduledoc """
  App-shell modal runtime helper.

  This module owns modal overlay rendering, modal key precedence, dismissal,
  confirmation callbacks, and form-submit routing for `%Foglet.TUI.App{}` state.
  It does not own durable domain behavior or screen-specific workflows.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.App
  alias Foglet.TUI.App.Routing
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets
  alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm
  alias Foglet.TUI.Widgets.Post.ReplyContext
  alias Raxol.Core.Runtime.Command

  @doc """
  Renders the modal as the sole visible content, centered in the terminal.
  """
  @spec render_overlay(Foglet.TUI.Modal.t(), App.t()) :: term()
  def render_overlay(modal, %App{} = state) do
    theme = Theme.from_state(state)
    {terminal_width, _terminal_height} = state.terminal_size

    column justify: :center, align: :center do
      [
        box style: %{border: :double, padding: 1, border_fg: theme.border.fg} do
          Widgets.Modal.render(modal, theme, width: overlay_body_width(terminal_width))
        end
      ]
    end
  end

  defp overlay_body_width(width) when is_integer(width),
    do: width |> Kernel.-(4) |> min(76) |> max(28)

  defp overlay_body_width(_width), do: 76

  @doc """
  Handles a key while a modal is active.

  Modal keys take precedence over the active screen reducer. Unknown modal keys
  leave the App state unchanged.
  """
  @spec handle_key(map(), App.t()) :: {App.t(), [Command.t()]}
  def handle_key(key, %App{modal: modal} = state) when not is_nil(modal) do
    modal_type = Map.get(modal, :type, :info)
    handle_modal_key(modal_type, key, state)
  end

  def handle_key(_key, %App{} = state), do: {state, []}

  @doc "Clears the active modal."
  @spec dismiss(App.t()) :: {App.t(), []}
  def dismiss(%App{} = state), do: {%{state | modal: nil}, []}

  @doc """
  Applies a confirm modal answer and invokes the configured callback.

  Callback functions receive the App state after the modal has already been
  cleared. They may return `{state, commands}` or a message to redispatch
  through the App shell.
  """
  @spec confirm(App.t(), :yes | :no) :: {App.t(), [Command.t()]}
  def confirm(%App{} = state, answer) when answer in [:yes, :no] do
    apply_callback(state, callback_key(answer))
  end

  @doc "Replaces the active modal with the generic visible form-submit error."
  @spec submit_error(App.t()) :: {App.t(), []}
  def submit_error(%App{} = state) do
    modal = %Foglet.TUI.Modal{
      type: :error,
      title: "Form Error",
      message: "Unable to submit form."
    }

    {%{state | modal: modal}, []}
  end

  defp handle_modal_key(:confirm, %{key: :char, char: c}, %App{} = state)
       when c in ["y", "Y"] do
    confirm(state, :yes)
  end

  defp handle_modal_key(:confirm, %{key: :char, char: c}, %App{} = state)
       when c in ["n", "N"] do
    confirm(state, :no)
  end

  defp handle_modal_key(:confirm, %{key: :escape}, %App{} = state) do
    confirm(state, :no)
  end

  defp handle_modal_key(
         :reply_context,
         %{key: :down},
         %App{modal: %Foglet.TUI.Modal{message: %ReplyContext{} = context}} = state
       ) do
    scroll_reply_context(state, context, 1)
  end

  defp handle_modal_key(
         :reply_context,
         %{key: :up},
         %App{modal: %Foglet.TUI.Modal{message: %ReplyContext{} = context}} = state
       ) do
    scroll_reply_context(state, context, -1)
  end

  defp handle_modal_key(
         :reply_context,
         %{key: key},
         %App{modal: %Foglet.TUI.Modal{message: %ReplyContext{} = context}} = state
       )
       when key in [:page_down, :page_up] do
    delta = if key == :page_down, do: context.visible_body_rows, else: -context.visible_body_rows
    scroll_reply_context(state, context, delta)
  end

  defp handle_modal_key(
         :reply_context,
         %{key: :char, char: c},
         %App{modal: %Foglet.TUI.Modal{message: %ReplyContext{} = context}} = state
       )
       when c in ["u", "U"] do
    if context.upvote? do
      Routing.route_screen_update(
        state,
        :post_reader,
        {:reply_context_upvote, context.post.id, context.scroll_top}
      )
    else
      {state, []}
    end
  end

  defp handle_modal_key(:reply_context, %{key: :escape}, %App{} = state), do: dismiss(state)
  defp handle_modal_key(:reply_context, %{key: :enter}, %App{} = state), do: dismiss(state)

  defp handle_modal_key(
         :public_profile,
         %{key: :char, char: "!"},
         %App{modal: %Foglet.TUI.Modal{message: %{report_target: target}}} = state
       )
       when is_map(target) do
    route_modal_submit(
      state,
      Effect.modal_submit(
        Map.get(target, :screen_key),
        Map.get(target, :kind),
        Map.get(target, :payload)
      )
    )
  end

  defp handle_modal_key(:public_profile, %{key: :escape}, %App{} = state), do: dismiss(state)
  defp handle_modal_key(:public_profile, %{key: :enter}, %App{} = state), do: dismiss(state)

  defp handle_modal_key(:public_profile, %{key: :char, char: " "}, %App{} = state),
    do: dismiss(state)

  defp handle_modal_key(
         :form,
         key,
         %App{modal: %Foglet.TUI.Modal{message: %ModalForm{} = form}} = state
       ) do
    {new_form, action} = ModalForm.handle_event(key, form)
    state = %{state | modal: %{state.modal | message: new_form}}

    case action do
      {:submitted, %Effect{type: :modal_submit} = effect} ->
        route_modal_submit(state, effect)

      :submitted ->
        submit_error(state)

      {:submitted, _other} ->
        submit_error(state)

      :cancelled ->
        cancel_form_change(state)

      _other ->
        route_form_change(state)
    end
  end

  defp handle_modal_key(type, %{key: :enter}, %App{} = state)
       when type in [:info, :success, :error, :warning] do
    apply_callback(state, :on_confirm)
  end

  defp handle_modal_key(type, %{key: :escape}, %App{} = state)
       when type in [:info, :success, :error, :warning] do
    apply_callback(state, :on_cancel)
  end

  defp handle_modal_key(type, %{key: :char, char: " "}, %App{} = state)
       when type in [:info, :success, :error, :warning] do
    apply_callback(state, :on_confirm)
  end

  defp handle_modal_key(_type, _key, %App{} = state), do: {state, []}

  defp scroll_reply_context(%App{} = state, %ReplyContext{} = context, delta) do
    theme = Theme.from_state(state)
    {terminal_width, _terminal_height} = state.terminal_size

    body_line_count =
      ReplyContext.rendered_body_line_count(context, theme,
        width: overlay_body_width(terminal_width)
      )

    update_reply_context(state, ReplyContext.scroll(context, delta, body_line_count))
  end

  defp update_reply_context(%App{} = state, %ReplyContext{} = context) do
    modal = %{state.modal | message: context}
    {%{state | modal: modal}, []}
  end

  defp route_modal_submit(
         %App{} = state,
         %Effect{
           payload: %{screen_key: screen_key, kind: kind, payload: payload}
         }
       )
       when is_atom(kind) do
    if modal_submit_target?(state, screen_key) do
      Routing.route_screen_update(state, screen_key, {:modal_submit, kind, payload})
    else
      submit_error(state)
    end
  end

  defp route_modal_submit(%App{} = state, %Effect{}), do: submit_error(state)

  defp route_form_change(%App{modal: %{change_target: {screen_key, kind}, message: form}} = state)
       when is_atom(screen_key) and is_atom(kind) do
    Routing.route_screen_update(state, screen_key, {:modal_change, kind, form})
  end

  defp route_form_change(%App{} = state), do: {state, []}

  defp cancel_form_change(%App{modal: %{change_target: {screen_key, kind}}} = state)
       when is_atom(screen_key) and is_atom(kind) do
    {routed_state, cmds} = Routing.route_screen_update(state, screen_key, {:modal_cancel, kind})
    {cleared, dismiss_cmds} = dismiss(routed_state)
    {cleared, cmds ++ dismiss_cmds}
  end

  defp cancel_form_change(%App{} = state), do: dismiss(state)

  defp modal_submit_target?(%App{} = state, screen_key) do
    module = Routing.screen_module_for(state, screen_key)
    Code.ensure_loaded?(module) and function_exported?(module, :update, 3)
  end

  defp callback_key(:yes), do: :on_confirm
  defp callback_key(:no), do: :on_cancel

  defp apply_callback(%App{} = state, callback_key)
       when callback_key in [:on_confirm, :on_cancel] do
    modal = state.modal
    cleared = %{state | modal: nil}
    callback = modal && Map.get(modal, callback_key)

    case callback do
      nil ->
        {cleared, []}

      :dismiss_modal ->
        {cleared, []}

      fun when is_function(fun, 1) ->
        case fun.(cleared) do
          {%App{} = new_state, cmds} when is_list(cmds) ->
            {new_state, wrap_commands(cmds)}

          msg ->
            App.update(msg, cleared)
        end
    end
  end

  defp wrap_commands(commands), do: Enum.map(commands, &wrap_command/1)

  defp wrap_command({:terminate, _reason}), do: Command.quit()
  defp wrap_command(%Command{} = cmd), do: cmd
  defp wrap_command(other), do: other
end
