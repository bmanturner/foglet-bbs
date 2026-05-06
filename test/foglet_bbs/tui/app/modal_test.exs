defmodule Foglet.TUI.App.ModalTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.App
  alias Foglet.TUI.App.Modal, as: AppModal
  alias Foglet.TUI.App.Routing
  alias Foglet.TUI.AsciiRenderer
  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Modal
  alias Foglet.TUI.Widgets.Modal.Form
  alias Foglet.TUI.Widgets.Post.ReplyContext
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

  defp timezone_form do
    Form.init(
      title: "Edit preferences: Timezone",
      fields: [
        %{
          name: :timezone,
          type: :select_list,
          label: "Timezone",
          value: "Etc/UTC",
          choices: [
            "Etc/UTC",
            "America/Chicago",
            "America/New_York",
            "America/Los_Angeles",
            "Europe/London",
            "Pacific/Auckland"
          ],
          max_height: 4
        }
      ],
      show_footer: true,
      on_submit: fn payload -> Effect.modal_submit(:account, :prefs_field, payload) end,
      on_cancel: fn -> :ok end
    )
  end

  defp reply_context_modal do
    body =
      Enum.map_join(1..12, "\n", fn row ->
        "Long reply-context body for scroll verification with enough words to wrap inside the modal interior while preserving chrome row #{row}."
      end)

    post = %{
      id: "p1",
      message_number: 1,
      body: body,
      upvote_count: 2,
      user: %{handle: "bob"},
      inserted_at: ~U[2026-04-18 00:00:00Z]
    }

    %Modal{
      type: :reply_context,
      message: ReplyContext.new(post, Foglet.Markdown.render(body), upvote?: true)
    }
  end

  defp row_containing(rendered, needle) do
    rendered
    |> String.split("\n")
    |> Enum.find(&String.contains?(&1, needle))
  end

  defp assert_modal_boundary_survives(rendered, needle) do
    row = row_containing(rendered, needle)

    assert row,
           "expected rendered modal to contain #{inspect(needle)}; got:\n#{rendered}"

    assert String.ends_with?(row, "║"),
           "expected modal right boundary to survive on #{inspect(needle)} row; got #{inspect(row)}"
  end

  defp assert_modal_rows_bounded(rendered) do
    bad_rows =
      rendered
      |> String.split("\n")
      |> Enum.filter(&(String.contains?(&1, "║") and not String.ends_with?(&1, "║")))

    assert bad_rows == [],
           "expected every modal content row to preserve the right border; got:\n#{Enum.join(bad_rows, "\n")}"
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

  describe "modal overlay rendering" do
    test "reply-context scroll keys update the active modal without routing the screen" do
      state = state(modal: reply_context_modal())

      {down_state, down_cmds} = AppModal.handle_key(%{key: :down}, state)
      assert down_cmds == []
      assert %Modal{message: %ReplyContext{scroll_top: 1}} = down_state.modal
      assert %SampleScreen.State{keys: []} = Routing.screen_state_for(down_state, :source)

      {paged_state, page_cmds} = AppModal.handle_key(%{key: :page_down}, down_state)
      assert page_cmds == []
      assert %Modal{message: %ReplyContext{scroll_top: 9}} = paged_state.modal
      assert %SampleScreen.State{keys: []} = Routing.screen_state_for(paged_state, :source)

      {up_state, up_cmds} = AppModal.handle_key(%{key: :up}, paged_state)
      assert up_cmds == []
      assert %Modal{message: %ReplyContext{scroll_top: 8}} = up_state.modal
    end

    test "form select-list body stays inside modal border at cramped width" do
      modal = %Modal{type: :form, message: timezone_form()}

      cramped =
        state(modal: modal, terminal_size: {64, 22})
        |> App.view()
        |> AsciiRenderer.render({64, 22})

      assert_modal_boundary_survives(cramped, "selected Etc/UTC")
      assert_modal_boundary_survives(cramped, "Type to filter")
      assert_modal_boundary_survives(cramped, "America/Chicago")
      assert_modal_boundary_survives(cramped, "Ctrl+S")

      baseline =
        state(modal: modal, terminal_size: {80, 24})
        |> App.view()
        |> AsciiRenderer.render({80, 24})

      assert_modal_boundary_survives(baseline, "selected Etc/UTC")
      assert_modal_boundary_survives(baseline, "[Enter] Select   [Ctrl+S] Save   [Esc] Cancel")
    end

    test "reply-context body, scroll status, and keybar stay inside modal border" do
      for size <- [{64, 22}, {80, 24}] do
        rendered =
          state(modal: reply_context_modal(), terminal_size: size)
          |> App.view()
          |> AsciiRenderer.render(size)

        assert_modal_boundary_survives(rendered, "Long reply-context body")
        assert_modal_boundary_survives(rendered, "Lines 1-8/")
        assert_modal_boundary_survives(rendered, "[↑↓] Scroll")
        assert_modal_rows_bounded(rendered)
      end
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
