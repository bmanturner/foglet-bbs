defmodule Foglet.PrivacySafePubSubFailureLoggingTest do
  @moduledoc """
  FOG-675/FOG-1008: privacy-safe `Logger.warning` on `Phoenix.PubSub.broadcast/3`
  failure at PubSub broadcast sites that previously suppressed the
  result with `_ = ...`:

    * `Foglet.BoardChat.Permanent.broadcast_new_message/2` (board chat insert)
    * `Foglet.BoardChat.Ephemeral.Room.broadcast/2` (in-memory board chat post)
    * `Foglet.TUI.App.Effects.apply_effect/2` for `%Effect{type: :publish}`

  Both must:

    * emit a `Logger.warning` carrying the broadcast `topic` and a
      low-cardinality message-kind atom on `{:error, _}`,
    * never log the message body, author, recipient, or subscriber list,
    * preserve their existing return shape on success or failure.

  We swap `:foglet_bbs, :pubsub_module` to a stub that returns
  `{:error, :stub_failure}` from `broadcast/3` so the warning branch is
  exercised without disturbing the live `Phoenix.PubSub`. This is the
  "stubbed broadcast result" path called out in the FOG-675 acceptance
  criteria.
  """

  use FogletBbs.DataCase, async: false

  import ExUnit.CaptureLog

  import FogletBbs.BoardsFixtures, only: [category_fixture: 0, user_fixture: 0]

  alias Foglet.BoardChat.{Ephemeral, Message, Permanent}
  alias Foglet.Boards.Board
  alias Foglet.TUI.App
  alias Foglet.TUI.App.Effects
  alias Foglet.TUI.Effect

  defmodule FailingPubSub do
    @moduledoc false
    def broadcast(_name, _topic, _message), do: {:error, :stub_failure}
  end

  setup do
    previous = Application.get_env(:foglet_bbs, :pubsub_module)
    Application.put_env(:foglet_bbs, :pubsub_module, FailingPubSub)

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:foglet_bbs, :pubsub_module)
        value -> Application.put_env(:foglet_bbs, :pubsub_module, value)
      end
    end)

    :ok
  end

  describe "Foglet.BoardChat.Permanent.insert/3 broadcast failure" do
    setup do
      category = category_fixture()
      user = user_fixture()

      board =
        %Board{}
        |> Board.changeset(%{
          slug: "fog675-#{System.unique_integer([:positive])}",
          name: "FOG-675 board",
          description: "FOG-675 fixture",
          category_id: category.id,
          chat_enabled: true,
          chat_storage_mode: :permanent,
          chat_message_ttl_seconds: 7_200
        })
        |> Repo.insert!()

      %{board: board, user: user}
    end

    test "logs topic and message_type, omits message body and author handle",
         %{board: board, user: user} do
      body = "secret-payload-#{System.unique_integer([:positive])}"

      log =
        capture_log(fn ->
          assert {:ok, %Message{}} = Permanent.insert(board, user, body)
        end)

      assert log =~ "BoardChat.Permanent broadcast failed"
      assert log =~ "message_type=:board_chat_new_message"
      assert log =~ "reason=:stub_failure"
      assert log =~ Foglet.PubSub.board_chat_topic(board.id)
      refute log =~ body
      refute log =~ user.handle
    end
  end

  describe "Foglet.BoardChat.Ephemeral.post/4 broadcast failure" do
    test "logs topic and message_type, omits ephemeral message body" do
      board = %Board{
        id: Ecto.UUID.generate(),
        slug: "fog1008-ephemeral",
        name: "FOG-1008 ephemeral board",
        chat_enabled: true,
        chat_storage_mode: :ephemeral,
        chat_message_ttl_seconds: 60
      }

      user_id = Ecto.UUID.generate()
      body = "ephemeral-secret-#{System.unique_integer([:positive])}"

      log =
        capture_log(fn ->
          assert {:ok, %{body: ^body}} = Ephemeral.post(board, user_id, body)
        end)

      assert log =~ "BoardChat.Ephemeral.Room broadcast failed"
      assert log =~ "message_type=:board_chat_new_message"
      assert log =~ "reason=:stub_failure"
      assert log =~ Foglet.PubSub.board_chat_topic(board.id)
      refute log =~ body
      refute log =~ user_id

      Ephemeral.stop(board)
    end
  end

  describe "Foglet.TUI.App.Effects :publish broadcast failure" do
    test "logs topic and message_kind from a tuple payload, never the body" do
      topic = "fog-675-effects-#{System.unique_integer([:positive])}"
      body = "do-not-log-me-#{System.unique_integer([:positive])}"
      message = {:board_chat, :new_message, %{body: body}}

      effect = %Effect{type: :publish, payload: %{topic: topic, message: message}}

      log =
        capture_log(fn ->
          assert {%App{}, []} = Effects.apply_effect(%App{}, effect)
        end)

      assert log =~ "TUI.App.Effects publish broadcast failed"
      assert log =~ "topic=" <> inspect(topic)
      assert log =~ "message_kind=:board_chat"
      assert log =~ "reason=:stub_failure"
      refute log =~ body
    end

    test "non-tuple payloads collapse to :unknown without leaking the payload" do
      topic = "fog-675-effects-bare-#{System.unique_integer([:positive])}"
      payload = "raw-string-payload-#{System.unique_integer([:positive])}"

      effect = %Effect{type: :publish, payload: %{topic: topic, message: payload}}

      log =
        capture_log(fn ->
          assert {%App{}, []} = Effects.apply_effect(%App{}, effect)
        end)

      assert log =~ "TUI.App.Effects publish broadcast failed"
      assert log =~ "message_kind=:unknown"
      refute log =~ payload
    end

    test "atom payloads surface as the kind atom directly" do
      topic = "fog-675-effects-atom-#{System.unique_integer([:positive])}"

      effect = %Effect{
        type: :publish,
        payload: %{topic: topic, message: :session_tick}
      }

      log =
        capture_log(fn ->
          assert {%App{}, []} = Effects.apply_effect(%App{}, effect)
        end)

      assert log =~ "message_kind=:session_tick"
    end
  end
end
