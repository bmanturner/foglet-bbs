defmodule Foglet.TUI.Screens.BBSMailTest do
  use FogletBbs.DataCase, async: true

  import FogletBbs.AccountsFixtures

  alias Foglet.DMs
  alias Foglet.TUI.Context
  alias Foglet.TUI.Screens.BBSMail
  alias Foglet.TUI.Screens.BBSMail.State

  describe "task results" do
    test "loads inbox conversations from screen task's nested ok result" do
      sender = user_fixture(%{handle: "sender#{System.unique_integer([:positive])}"})
      recipient = user_fixture(%{handle: "recipient#{System.unique_integer([:positive])}"})
      {:ok, _message} = DMs.send_message(sender, recipient, %{body: "durable hello"})

      rows = DMs.list_conversations(recipient, :inbox)

      {state, effects} =
        BBSMail.update(
          {:task_result, :load_mail, {:ok, {:ok, rows}}},
          %State{mode: :inbox, status: :loading},
          Context.new(current_user: recipient, route: :bbs_mail)
        )

      assert effects == []
      assert state.status == :loaded
      assert [%{participant: %{id: sender_id}, unread_count: 1}] = state.conversations
      assert sender_id == sender.id
    end

    test "opens a selected conversation after nested load result populates rows" do
      sender = user_fixture(%{handle: "sender#{System.unique_integer([:positive])}"})
      recipient = user_fixture(%{handle: "recipient#{System.unique_integer([:positive])}"})
      {:ok, _message} = DMs.send_message(sender, recipient, %{body: "open me"})

      rows = DMs.list_conversations(recipient, :inbox)
      context = Context.new(current_user: recipient, route: :bbs_mail)

      {loaded_state, []} =
        BBSMail.update({:task_result, :load_mail, {:ok, {:ok, rows}}}, %State{}, context)

      {opening_state, effects} = BBSMail.update({:key, %{key: :enter}}, loaded_state, context)

      assert opening_state.mode == :conversation
      assert opening_state.participant.id == sender.id
      assert [%Foglet.TUI.Effect{type: :task, payload: %{op: :load_conversation}}] = effects
    end
  end
end
