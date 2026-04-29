defmodule Foglet.TUI.App.ModalTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.App
  alias Foglet.TUI.App.Modal, as: AppModal
  alias Foglet.TUI.App.Routing
  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Modal
  alias Foglet.TUI.Widgets.Modal.Form
  alias Raxol.Core.Runtime.Command

  defmodule SampleScreen do
    defmodule State do
      defstruct keys: [], submits: [], route_entries: 0
    end

    def init(%Context{}), do: %State{}

    def update({:key, key}, %State{} = state, %Context{}) do
      {%{state | keys: [key | state.keys]}, []}
    end

    def update({:modal_submit, kind, payload}, %State{} = state, %Context{}) do
      {%{state | submits: [{kind, payload} | state.submits]}, []}
    end

    def update(:on_route_enter, %State{} = state, %Context{}) do
      {%{state | route_entries: state.route_entries + 1}, []}
    end

    def update(_message, %State{} = state, %Context{}), do: {state, []}
  end

  defp state(attrs) do
    attrs = Map.new(attrs)

    session_context =
      Map.get(attrs, :session_context, %{
        domain: %{screen_modules: %{source: SampleScreen, target: SampleScreen}}
      })

    struct!(
      App,
      Map.merge(
        %{
          current_screen: :source,
          session_context: session_context,
          screen_state: %{source: %SampleScreen.State{}, target: %SampleScreen.State{}},
          terminal_size: {100, 30}
        },
        attrs
      )
    )
  end

  defp form(submit_result) do
    Form.init(
      title: "Test Submit",
      fields: [%{name: :topic, type: :text, label: "Topic"}],
      on_submit: fn payload ->
        case submit_result do
          fun when is_function(fun, 1) -> fun.(payload)
          other -> other
        end
      end,
      on_cancel: fn -> :ok end
    )
  end

  describe "modal key precedence" do
    test "handle_key/2 does not route keys to the active screen reducer while a modal is open" do
      modal = %Modal{type: :info, message: "pause"}
      state = state(modal: modal)

      {new_state, cmds} = AppModal.handle_key(%{key: :char, char: "x"}, state)

      assert cmds == []
      assert new_state.modal == modal
      assert %SampleScreen.State{keys: []} = Routing.screen_state_for(new_state, :source)
    end
  end

  describe "confirm callbacks" do
    test "confirm yes receives cleared state and can return {state, commands}" do
      owner = self()

      modal = %Modal{
        type: :confirm,
        message: "Proceed?",
        on_confirm: fn cleared ->
          send(owner, {:confirm_callback_state, cleared.modal})
          {%{cleared | current_screen: :target}, [Command.quit()]}
        end
      }

      {new_state, cmds} = AppModal.handle_key(%{key: :char, char: "Y"}, state(modal: modal))

      assert_receive {:confirm_callback_state, nil}
      assert new_state.current_screen == :target
      assert new_state.modal == nil
      assert [%Command{type: :quit}] = cmds
    end

    test "confirm no receives cleared state and can return a message to re-dispatch" do
      owner = self()

      modal = %Modal{
        type: :confirm,
        message: "Leave?",
        on_cancel: fn cleared ->
          send(owner, {:confirm_callback_state, cleared.modal})
          {:navigate, :target}
        end
      }

      {new_state, cmds} = AppModal.handle_key(%{key: :escape}, state(modal: modal))

      assert_receive {:confirm_callback_state, nil}
      assert cmds == []
      assert new_state.current_screen == :target
      assert new_state.modal == nil
      assert %SampleScreen.State{route_entries: 1} = Routing.screen_state_for(new_state, :target)
    end
  end

  describe "dismiss keys" do
    test "info/error/warning dismissal clears modal on Enter, Escape, and Space" do
      cases = [
        {:info, %{key: :enter}},
        {:info, %{key: :escape}},
        {:info, %{key: :char, char: " "}},
        {:error, %{key: :enter}},
        {:error, %{key: :escape}},
        {:error, %{key: :char, char: " "}},
        {:warning, %{key: :enter}},
        {:warning, %{key: :escape}},
        {:warning, %{key: :char, char: " "}}
      ]

      for {type, key} <- cases do
        {new_state, cmds} =
          AppModal.handle_key(key, state(modal: %Modal{type: type, message: "dismiss"}))

        assert cmds == []
        assert new_state.modal == nil
      end
    end
  end

  describe "form modal_submit routing" do
    test "form submit with modal_submit effect reaches the target screen reducer" do
      modal = %Modal{
        type: :form,
        message: form(fn payload -> Effect.modal_submit(:target, :confirm, payload) end)
      }

      {new_state, cmds} = AppModal.handle_key(%{key: :enter}, state(modal: modal))

      assert cmds == []

      assert %SampleScreen.State{submits: [confirm: %{topic: ""}]} =
               Routing.screen_state_for(new_state, :target)
    end

    test "form submit with missing target sets generic visible error modal" do
      modal = %Modal{
        type: :form,
        message: form(fn payload -> Effect.modal_submit(:missing, :confirm, payload) end)
      }

      {new_state, cmds} = AppModal.handle_key(%{key: :enter}, state(modal: modal))

      assert cmds == []

      assert %Modal{
               type: :error,
               title: "Form Error",
               message: "Unable to submit form."
             } = new_state.modal
    end

    test "form submit without modal_submit effect sets generic visible error modal" do
      modal = %Modal{type: :form, message: form(:ok)}

      {new_state, cmds} = AppModal.handle_key(%{key: :enter}, state(modal: modal))

      assert cmds == []
      assert %Modal{type: :error, message: "Unable to submit form."} = new_state.modal
    end

    test "cancelled form submission clears modal state" do
      modal = %Modal{type: :form, message: form(:ok)}

      {new_state, cmds} = AppModal.handle_key(%{key: :escape}, state(modal: modal))

      assert cmds == []
      assert new_state.modal == nil
    end
  end
end
