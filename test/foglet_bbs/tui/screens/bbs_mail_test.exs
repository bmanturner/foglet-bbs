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

    test "ctrl-s key event in reply mode sends instead of switching to Sent" do
      sender = user_fixture(%{handle: "sender#{System.unique_integer([:positive])}"})
      recipient = user_fixture(%{handle: "recipient#{System.unique_integer([:positive])}"})
      {:ok, message} = DMs.send_message(sender, recipient, %{body: "please reply"})

      context = Context.new(current_user: recipient, route: :bbs_mail)
      state = %State{mode: :reply, participant: sender, messages: [message], body: "live reply"}

      {sending_state, effects} =
        BBSMail.update({:key, %{key: :char, char: "s", ctrl: true}}, state, context)

      assert sending_state.mode == :reply
      assert sending_state.status == :sending
      assert [%Foglet.TUI.Effect{type: :task, payload: %{op: :send_mail}}] = effects
    end

    test "reply mode captures printable chars before navigation shortcuts" do
      sender = user_fixture(%{handle: "sender#{System.unique_integer([:positive])}"})
      recipient = user_fixture(%{handle: "recipient#{System.unique_integer([:positive])}"})
      context = Context.new(current_user: recipient, route: :bbs_mail)
      state = %State{mode: :reply, participant: sender, body: ""}

      {state, []} = BBSMail.update({:key, %{key: :char, char: "l"}}, state, context)
      {state, []} = BBSMail.update({:key, %{key: :char, char: "i"}}, state, context)
      {state, []} = BBSMail.update({:key, %{key: :char, char: "s"}}, state, context)
      {state, []} = BBSMail.update({:key, %{key: :backspace}}, state, context)

      assert state.mode == :reply
      assert state.body == "li"
    end

    test "send result reload scrolls conversation to show appended reply" do
      sender = user_fixture(%{handle: "sender#{System.unique_integer([:positive])}"})
      recipient = user_fixture(%{handle: "recipient#{System.unique_integer([:positive])}"})

      older =
        for idx <- 1..9 do
          {:ok, message} = DMs.send_message(sender, recipient, %{body: "older #{idx}"})
          message
        end

      {:ok, reply} = DMs.send_message(recipient, sender, %{body: "appended reply"})
      messages = older ++ [reply]
      state = %State{mode: :conversation, participant: sender, info: "Message sent.", scroll: 0}
      context = Context.new(current_user: recipient, route: :bbs_mail)

      {loaded_state, []} =
        BBSMail.update({:task_result, :load_conversation, {:ok, {:ok, messages}}}, state, context)

      assert loaded_state.scroll == 6
      assert List.last(loaded_state.messages).body == "appended reply"
    end

    test "plain s still opens Sent outside ctrl-s submit" do
      sender = user_fixture(%{handle: "sender#{System.unique_integer([:positive])}"})
      recipient = user_fixture(%{handle: "recipient#{System.unique_integer([:positive])}"})
      {:ok, _message} = DMs.send_message(sender, recipient, %{body: "sent toggle"})

      context = Context.new(current_user: recipient, route: :bbs_mail)
      state = %State{mode: :inbox, conversations: DMs.list_conversations(recipient, :inbox)}

      {sent_state, effects} = BBSMail.update({:key, %{key: :char, char: "s"}}, state, context)

      assert sent_state.mode == :sent
      assert sent_state.status == :loading
      assert [%Foglet.TUI.Effect{type: :task, payload: %{op: :load_mail}}] = effects
    end
  end
end
