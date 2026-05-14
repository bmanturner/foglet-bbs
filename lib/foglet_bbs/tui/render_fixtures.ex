defmodule Foglet.TUI.RenderFixtures do
  @moduledoc """
  Synthetic, in-memory state builders for `Foglet.TUI.AsciiRenderer` and
  `mix foglet.tui.render`.

  Each `state_for/2` clause returns a `%Foglet.TUI.App{}` struct populated
  with just enough data for the requested screen to render meaningful
  content — no Repo, no SSH, no PubSub. The resulting state can be passed
  directly to `Foglet.TUI.App.view/1`, which routes through `SizeGate` and
  the chrome to produce a full-screen view tree.

  This is **not** a test fixture for end-to-end behaviour — it produces a
  stable visual snapshot of each screen for inspection. Don't lean on the
  shapes here for assertions about real screen behaviour; use the actual
  domain types from a `DataCase` test for that.
  """

  alias Foglet.Accounts.User
  alias Foglet.AppName
  alias Foglet.TUI.App
  alias Foglet.TUI.Modal
  alias Foglet.TUI.SessionContext
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Input.TextInput
  alias Foglet.TUI.Widgets.List.BoardTree

  alias Foglet.TUI.Screens.{
    Account,
    BBSMail,
    BoardConfig,
    BoardList,
    BoardNews,
    BoardScreen,
    DoorList,
    Login,
    MainMenu,
    Moderation,
    NewThread,
    Notifications,
    OnlineNow,
    PostComposer,
    PostReader,
    Register,
    Sysop,
    ThreadList,
    Verify
  }

  alias Foglet.Threads.ThreadEntry

  @screens ~w(
    login register verify main_menu notifications bbs_mail online_now board_list thread_list board_screen
    post_reader post_composer new_thread door_list account moderation sysop
  )a

  @substates %{
    login: ~w(login_form reset_recovery reset_request reset_consume suspended rejected pending)a,
    register: ~w(invite_only)a,
    verify: ~w(resend_cooldown unverified)a,
    main_menu: ~w(suspended rejected pending unverified)a,
    thread_list: ~w(archived)a,
    board_screen:
      ~w(threads_chat_news operator_config config_add config_ttl news_empty news_error news_detail)a,
    post_reader: ~w(archived)a
  }

  @seed_presets ~w(suspended rejected pending unverified invite_only resend_cooldown)a

  @typedoc "Screen identifier accepted by `state_for/2`."
  @type screen ::
          :login
          | :register
          | :verify
          | :main_menu
          | :notifications
          | :bbs_mail
          | :online_now
          | :board_list
          | :thread_list
          | :post_reader
          | :post_composer
          | :new_thread
          | :door_list
          | :account
          | :moderation
          | :sysop

  @type seed_preset ::
          :suspended | :rejected | :pending | :unverified | :invite_only | :resend_cooldown

  @doc "All screens that can be rendered."
  @spec screens() :: [screen()]
  @dialyzer {:nowarn_function, screens: 0}
  def screens, do: @screens

  @doc """
  Build an `%App{}` state for `screen` at `terminal_size`.

  Unknown screens raise `ArgumentError`.
  """
  @spec state_for(screen() | atom(), {pos_integer(), pos_integer()}) :: App.t()
  def state_for(screen, terminal_size), do: state_for(screen, terminal_size, [])

  @doc """
  Build an `%App{}` state with optional render-only state hydration.

  Options:

    * `:substate` — named sub-state supported by the target screen.
    * `:seed_state` — named preset or an inline JSON-decoded map overlay.

  This stays deliberately in-memory: no Repo, no SSH, no PubSub.
  """
  @spec state_for(screen() | atom(), {pos_integer(), pos_integer()}, keyword()) :: App.t()
  def state_for(screen, terminal_size, opts) when screen in @screens do
    base = base_state(screen, terminal_size)

    screen
    |> populate(base, terminal_size)
    |> apply_seed_state(Keyword.get(opts, :seed_state))
    |> apply_substate(screen, Keyword.get(opts, :substate))
  end

  def state_for(screen, _size, _opts) do
    raise ArgumentError,
          "unknown screen: #{inspect(screen)}. Known: #{inspect(@screens)}"
  end

  @doc "Sub-states supported by `state_for/3` for a given screen."
  @spec substates_for(screen() | atom()) :: [atom()]
  def substates_for(screen), do: Map.get(@substates, screen, [])

  @doc "Named `:seed_state` presets supported by `state_for/3`."
  @spec seed_state_presets() :: nonempty_list(seed_preset())
  def seed_state_presets, do: @seed_presets

  # --- base -----------------------------------------------------------------

  defp base_state(screen, terminal_size) do
    user = if screen in [:login, :register, :verify], do: nil, else: synthetic_user()

    %App{
      current_screen: screen,
      current_user: user,
      session_context: synthetic_session_context(user),
      terminal_size: terminal_size,
      screen_state: %{}
    }
  end

  defp synthetic_user do
    %User{
      id: "00000000-0000-0000-0000-000000000001",
      handle: "alice",
      email: "alice@example.com",
      role: :sysop,
      status: :active,
      timezone: "America/Chicago",
      theme: "gray",
      preferences: %{"time_format" => "24h"},
      post_count: 42,
      tagline: "Just here for the dot art.",
      location: "Chicago, IL",
      confirmed_at: ~U[2026-01-01 00:00:00.000000Z],
      inserted_at: ~U[2026-01-01 00:00:00.000000Z],
      updated_at: ~U[2026-04-01 00:00:00.000000Z]
    }
  end

  defp synthetic_user(attrs) when is_map(attrs) do
    attrs
    |> Enum.reduce(synthetic_user(), fn {key, value}, user ->
      normalized_key = normalize_key(key)

      if Map.has_key?(user, normalized_key) do
        Map.put(user, normalized_key, coerce_user_value(normalized_key, value))
      else
        user
      end
    end)
  end

  defp synthetic_session_context(user) do
    %SessionContext{
      user: user,
      user_id: user && user.id,
      session_pid: nil,
      pubkey_authenticated: not is_nil(user),
      registration_mode: "open",
      max_post_length: 65_535,
      timezone: (user && user.timezone) || "Etc/UTC",
      time_format: "24h",
      theme_id: "gray",
      theme: Theme.default()
    }
  end

  # --- seed overlays --------------------------------------------------------

  defp apply_seed_state(state, nil), do: state
  defp apply_seed_state(state, ""), do: state

  defp apply_seed_state(state, seed) when is_binary(seed) do
    case existing_atom(String.trim(seed)) do
      {:ok, preset} ->
        apply_seed_state(state, preset)

      :error ->
        raise ArgumentError,
              "unknown seed_state preset: #{inspect(seed)}. Known: #{inspect(@seed_presets)}"
    end
  end

  defp apply_seed_state(_state, seed) when is_atom(seed) and seed not in @seed_presets do
    raise ArgumentError,
          "unknown seed_state preset: #{inspect(seed)}. Known: #{inspect(@seed_presets)}"
  end

  defp apply_seed_state(state, seed) when seed in @seed_presets do
    case seed do
      :suspended -> seed_account_gate(state, :suspended)
      :rejected -> seed_account_gate(state, :rejected)
      :pending -> seed_account_gate(state, :pending)
      :unverified -> seed_unverified(state)
      :invite_only -> seed_registration_mode(state, "invite_only")
      :resend_cooldown -> seed_verify_resend_cooldown(state)
    end
  end

  defp apply_seed_state(state, %{} = overlay) do
    Enum.reduce(overlay, state, fn {key, value}, acc ->
      apply_overlay_field(acc, normalize_key(key), value)
    end)
  end

  defp apply_seed_state(_state, seed) do
    raise ArgumentError,
          "seed_state must be a named preset or JSON object, got: #{inspect(seed)}"
  end

  defp apply_substate(state, _screen, nil), do: state
  defp apply_substate(state, _screen, ""), do: state

  defp apply_substate(state, screen, substate) when is_binary(substate) do
    case existing_atom(substate) do
      {:ok, atom} ->
        apply_substate(state, screen, atom)

      :error ->
        raise ArgumentError,
              "unknown substate #{inspect(substate)} for #{inspect(screen)}. " <>
                "Known: #{inspect(substates_for(screen))}"
    end
  end

  defp apply_substate(state, screen, substate) do
    unless substate in substates_for(screen) do
      raise ArgumentError,
            "unknown substate #{inspect(substate)} for #{inspect(screen)}. " <>
              "Known: #{inspect(substates_for(screen))}"
    end

    seed_substate(state, screen, substate)
  end

  defp apply_overlay_field(state, :current_screen, value) when is_binary(value) do
    %{state | current_screen: String.to_existing_atom(value)}
  end

  defp apply_overlay_field(state, :current_user, nil) do
    %{state | current_user: nil, session_context: synthetic_session_context(nil)}
  end

  defp apply_overlay_field(state, :current_user, %{} = attrs) do
    user = synthetic_user(attrs)
    %{state | current_user: user, session_context: sync_session_user(state.session_context, user)}
  end

  defp apply_overlay_field(state, :session_context, %{} = attrs) do
    session_context =
      Enum.reduce(attrs, state.session_context, fn {key, value}, context ->
        update_session_context(context, normalize_key(key), value)
      end)

    %{state | session_context: session_context}
  end

  defp apply_overlay_field(state, :screen_state, %{} = screen_states) do
    Enum.reduce(screen_states, state, fn {screen, local_overlay}, acc ->
      screen_key = normalize_key(screen)
      existing = App.screen_state_for(acc, screen_key) || %{}
      base = overlay_base(screen_key, existing, local_overlay)
      App.put_screen_state(acc, screen_key, merge_local_state(base, local_overlay))
    end)
  end

  defp apply_overlay_field(state, :modal, nil), do: %{state | modal: nil}

  defp apply_overlay_field(state, :modal, %{} = attrs) do
    modal =
      %Modal{}
      |> Map.merge(atomize_keys(attrs))
      |> Map.update(:type, :info, &coerce_atom/1)

    %{state | modal: modal}
  end

  defp apply_overlay_field(state, :route_params, %{} = route_params) do
    %{state | route_params: atomize_keys(route_params)}
  end

  defp apply_overlay_field(state, _key, _value), do: state

  # --- named sub-states -----------------------------------------------------

  defp seed_substate(state, :login, :login_form) do
    ss =
      Login.State.login_form()
      |> put_text_input(:handle_input, "alice")

    App.put_screen_state(state, :login, ss)
  end

  defp seed_substate(state, :login, :reset_request) do
    ss =
      Login.State.reset_request()
      |> put_text_input(:identifier_input, "alice@example.com")
      |> Map.put(:message, "If the account exists, reset instructions have been sent.")
      |> Map.put(:message_category, :info)

    App.put_screen_state(state, :login, ss)
  end

  defp seed_substate(state, :login, :reset_recovery) do
    ss =
      Login.State.reset_recovery(:request)
      |> put_text_input(:identifier_input, "alice@example.com")
      |> put_text_input(:token_input, "RESET-TOKEN")

    App.put_screen_state(state, :login, ss)
  end

  defp seed_substate(state, :login, :reset_consume) do
    ss =
      Login.State.reset_consume()
      |> put_text_input(:token_input, "RESET-TOKEN")

    App.put_screen_state(state, :login, ss)
  end

  defp seed_substate(state, :login, substate)
       when substate in [:suspended, :rejected, :pending] do
    seed_account_gate(%{state | current_screen: :login}, substate)
  end

  defp seed_substate(state, :register, :invite_only) do
    state
    |> seed_registration_mode("invite_only")
    |> App.put_screen_state(:register, Register.State.for_mode("invite_only"))
  end

  defp seed_substate(state, :verify, :resend_cooldown) do
    seed_verify_resend_cooldown(state)
  end

  defp seed_substate(state, :verify, :unverified) do
    seed_unverified(%{state | current_screen: :verify})
  end

  defp seed_substate(state, :main_menu, substate)
       when substate in [:suspended, :rejected, :pending, :unverified] do
    apply_seed_state(state, substate)
  end

  defp seed_substate(state, :thread_list, :archived) do
    ss = App.screen_state_for(state, :thread_list)
    board = Map.merge(ss.board, %{archived: true})
    ss = %{ss | board: board}

    %{state | route_params: %{state.route_params | board: board}}
    |> App.put_screen_state(:thread_list, ss)
  end

  defp seed_substate(state, :board_screen, :threads_chat_news),
    do: seed_board_screen(state, :news)

  defp seed_substate(state, :board_screen, :operator_config),
    do: seed_board_screen(state, :config)

  defp seed_substate(state, :board_screen, :config_add),
    do: seed_board_screen(state, {:config, :add})

  defp seed_substate(state, :board_screen, :config_ttl),
    do: seed_board_screen(state, {:config, :ttl})

  defp seed_substate(state, :board_screen, :news_empty), do: seed_board_screen(state, :news_empty)
  defp seed_substate(state, :board_screen, :news_error), do: seed_board_screen(state, :news_error)

  defp seed_substate(state, :board_screen, :news_detail),
    do: seed_board_screen(state, :news_detail)

  defp seed_substate(state, :post_reader, :archived) do
    ss = App.screen_state_for(state, :post_reader)
    board = Map.merge(ss.board, %{archived: true})
    ss = %{ss | board: board}

    %{state | route_params: %{state.route_params | board: board}}
    |> App.put_screen_state(:post_reader, ss)
  end

  defp seed_account_gate(state, status) when status in [:suspended, :rejected, :pending] do
    user = synthetic_user(%{status: status, confirmed_at: ~U[2026-01-01 00:00:00Z]})
    message = account_gate_message(status)

    %{state | current_user: user, session_context: sync_session_user(state.session_context, user)}
    |> put_login_modal(message)
  end

  defp seed_unverified(state) do
    user = synthetic_user(%{status: :active, confirmed_at: nil})

    state
    |> seed_config_value("require_email_verification", true)
    |> Map.merge(%{current_screen: :verify, current_user: user})
    |> then(fn seeded ->
      %{seeded | session_context: sync_session_user(seeded.session_context, user)}
    end)
    |> App.put_screen_state(:verify, Verify.State.default())
  end

  defp seed_verify_resend_cooldown(state) do
    user = state.current_user || synthetic_user(%{confirmed_at: nil})

    state
    |> Map.merge(%{current_screen: :verify, current_user: user})
    |> then(fn seeded ->
      %{seeded | session_context: sync_session_user(seeded.session_context, user)}
    end)
    |> App.put_screen_state(
      :verify,
      %{
        Verify.State.default()
        | resend_cooldown_until: DateTime.add(DateTime.utc_now(), 60, :second)
      }
    )
    |> Map.put(:modal, %Modal{type: :error, message: "Please wait to resend. Wait 60s."})
  end

  defp seed_registration_mode(state, mode) do
    state
    |> Map.update!(:session_context, fn context ->
      update_session_context(context, :registration_mode, mode)
    end)
    |> seed_config_value("registration_mode", mode)
  end

  defp seed_config_value(key, value) do
    :ets.insert(:foglet_config, {key, value})
  rescue
    ArgumentError -> :ok
  end

  defp seed_config_value(state, key, value) do
    seed_config_value(key, value)
    state
  end

  defp put_login_modal(state, message) do
    %{
      state
      | current_screen: :login,
        screen_state: Map.put(state.screen_state || %{}, :login, Login.State.default()),
        modal: %Modal{type: :error, message: message}
    }
  end

  defp account_gate_message(:pending), do: "Your account is pending sysop approval."
  defp account_gate_message(:rejected), do: "Your registration was rejected. Contact the sysop."
  defp account_gate_message(:suspended), do: "Your account is suspended. Contact the sysop."

  defp sync_session_user(%SessionContext{} = context, user) do
    %{
      context
      | user: user,
        user_id: user && user.id,
        pubkey_authenticated: not is_nil(user),
        timezone: (user && user.timezone) || context.timezone,
        theme_id: (user && user.theme) || context.theme_id
    }
  end

  defp sync_session_user(context, user) when is_map(context) do
    context
    |> Map.put(:user, user)
    |> Map.put(:user_id, user && user.id)
    |> Map.put(:pubkey_authenticated, not is_nil(user))
  end

  defp update_session_context(%SessionContext{} = context, key, value) do
    if Map.has_key?(context, key) do
      Map.put(context, key, coerce_session_value(key, value))
    else
      context
    end
  end

  defp update_session_context(context, key, value) when is_map(context) do
    Map.put(context, key, value)
  end

  defp merge_local_state(existing, overlay) when is_map(existing) and is_map(overlay) do
    Map.merge(existing, atomize_keys(overlay), fn _key, old, new ->
      merge_local_state(old, new)
    end)
  end

  defp merge_local_state(%TextInput{} = input, value) when is_binary(value) do
    %{input | raxol_state: %{input.raxol_state | value: value, cursor_pos: String.length(value)}}
  end

  defp merge_local_state(existing, value) when is_atom(existing) and is_binary(value),
    do: coerce_atom(value)

  defp merge_local_state(_existing, new), do: normalize_value(new)

  defp overlay_base(:login, existing, %{} = overlay) do
    case atom_overlay_value(overlay, "sub") || atom_overlay_value(overlay, :sub) do
      :login_form -> Login.State.login_form()
      :reset_request -> Login.State.reset_request()
      :reset_consume -> Login.State.reset_consume()
      _other -> existing
    end
  end

  defp overlay_base(:register, existing, %{} = overlay) do
    mode = Map.get(overlay, "mode") || Map.get(overlay, :mode)
    step = atom_overlay_value(overlay, "step") || atom_overlay_value(overlay, :step)

    cond do
      is_binary(mode) ->
        Register.State.for_mode(mode)

      step == :invite_code ->
        Register.State.for_mode("invite_only")

      true ->
        existing
    end
  end

  defp overlay_base(_screen, existing, _overlay), do: existing

  defp atom_overlay_value(overlay, key) do
    case Map.get(overlay, key) do
      value when is_atom(value) ->
        value

      value when is_binary(value) ->
        case existing_atom(value) do
          {:ok, atom} -> atom
          :error -> nil
        end

      _other ->
        nil
    end
  end

  defp put_text_input(state, key, value) do
    Map.update!(state, key, fn %TextInput{} = input -> merge_local_state(input, value) end)
  end

  defp atomize_keys(map) do
    Map.new(map, fn {key, value} -> {normalize_key(key), normalize_value(value)} end)
  end

  defp normalize_value(value) when is_map(value), do: atomize_keys(value)
  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_value(value), do: value

  defp normalize_key(key) when is_atom(key), do: key
  defp normalize_key(key) when is_binary(key), do: String.to_existing_atom(key)

  defp coerce_user_value(key, value) when key in [:role, :status] and is_binary(value),
    do: String.to_existing_atom(value)

  defp coerce_user_value(key, value) when key in [:inserted_at, :updated_at, :confirmed_at],
    do: coerce_datetime(value)

  defp coerce_user_value(_key, value), do: value

  defp coerce_session_value(:theme, value), do: value
  defp coerce_session_value(_key, value), do: value

  defp coerce_atom(value) when is_atom(value), do: value
  defp coerce_atom(value) when is_binary(value), do: String.to_existing_atom(value)

  defp coerce_datetime(nil), do: nil
  defp coerce_datetime(%DateTime{} = value), do: value

  defp coerce_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> value
    end
  end

  defp existing_atom(value) when is_binary(value) do
    {:ok, String.to_existing_atom(value)}
  rescue
    ArgumentError -> :error
  end

  defp synthetic_oneliners do
    [
      %{
        id: "ol-1",
        body: "Welcome to #{AppName.name()}.",
        author_handle: "sysop",
        inserted_at: ~U[2026-04-27 12:00:00Z]
      },
      %{
        id: "ol-2",
        body: "New thread in /general — say hi!",
        author_handle: "alice",
        inserted_at: ~U[2026-04-27 12:30:00Z]
      }
    ]
  end

  defp synthetic_online_now_rows do
    [
      online_now_row(%{id: "u-alice", handle: "alice", role: :sysop}, "Online"),
      online_now_row(%{id: "u-mod", handle: "mod", role: :mod}, "Chatting in general"),
      online_now_row(%{id: "u-foglet", handle: "foglet", role: :user}, "Browsing boards")
    ]
  end

  defp synthetic_notifications do
    [
      %{
        id: "notif-1",
        kind: :mention,
        read_at: nil,
        inserted_at: ~U[2026-05-11 21:30:00Z],
        actor: %{id: "u-alice", handle: "alice", role: :sysop},
        payload: %{
          "snippet" => "Check the new welcome thread.",
          "thread_id" => "t1",
          "board_id" => "b1",
          "post_id" => "p1"
        }
      },
      %{
        id: "notif-2",
        kind: :dm,
        read_at: ~U[2026-05-11 21:31:00Z],
        inserted_at: ~U[2026-05-11 21:31:00Z],
        actor: %{id: "u-mod", handle: "mod", role: :mod},
        payload: %{"preview" => "See the moderator notes.", "message_id" => "m1"}
      }
    ]
  end

  defp online_now_row(user, presence_label) do
    %{
      user_id: user.id,
      handle: user.handle,
      role: user.role,
      presence_label: presence_label,
      presence: %Foglet.Sessions.PresenceSummary{label: presence_label, online?: true},
      user: user
    }
  end

  # --- per-screen population -----------------------------------------------

  defp synthetic_mail_conversations do
    bob = synthetic_user(%{id: "00000000-0000-0000-0000-000000000002", handle: "bob"})

    [
      %{
        participant: bob,
        last_at: ~U[2025-12-31 19:00:00.000000Z],
        preview: "**Markdown** meetup notes and a `code` sample",
        unread_count: 3,
        sent?: false
      }
    ]
  end

  defp synthetic_mail_messages do
    alice = synthetic_user()
    bob = synthetic_user(%{id: "00000000-0000-0000-0000-000000000002", handle: "bob"})

    [
      %Foglet.DMs.Message{
        id: "10000000-0000-0000-0000-000000000001",
        sender_id: bob.id,
        recipient_id: alice.id,
        sender: bob,
        recipient: alice,
        body: "# Hello\nThis **BBS Mail** thread uses Markdown.",
        inserted_at: ~U[2025-12-31 21:00:00.000000Z]
      },
      %Foglet.DMs.Message{
        id: "10000000-0000-0000-0000-000000000002",
        sender_id: alice.id,
        recipient_id: bob.id,
        sender: alice,
        recipient: bob,
        body: "Thanks -- `rendered` and wrapped like posts.",
        inserted_at: ~U[2025-12-31 21:10:00.000000Z]
      },
      %Foglet.DMs.Message{
        id: "10000000-0000-0000-0000-000000000003",
        sender_id: bob.id,
        recipient_id: alice.id,
        sender: bob,
        recipient: alice,
        body:
          "Unread reply with enough text to prove wrapping at supported terminal sizes without hiding the notice.",
        inserted_at: ~U[2025-12-31 21:00:00.000000Z]
      }
    ]
  end

  defp populate(:login, state, _size) do
    App.put_screen_state(state, :login, init_screen(Login, state))
  end

  defp populate(:register, state, _size) do
    App.put_screen_state(state, :register, init_screen(Register, state))
  end

  defp populate(:verify, state, _size) do
    App.put_screen_state(state, :verify, init_screen(Verify, state))
  end

  defp populate(:main_menu, state, _size) do
    local_state =
      state
      |> App.build_context()
      |> MainMenu.init()
      |> MainMenu.State.from_entries(synthetic_oneliners())
      |> Map.put(:unread_notifications_count, 3)

    App.put_screen_state(state, :main_menu, local_state)
  end

  defp populate(:notifications, state, _size) do
    local_state =
      state
      |> App.build_context()
      |> Notifications.init()
      |> Notifications.State.from_rows(synthetic_notifications())

    App.put_screen_state(state, :notifications, local_state)
  end

  defp populate(:bbs_mail, state, _size) do
    local_state = %BBSMail.State{
      mode: :conversation,
      status: :loaded,
      participant: synthetic_user(%{id: "00000000-0000-0000-0000-000000000002", handle: "bob"}),
      conversations: synthetic_mail_conversations(),
      messages: synthetic_mail_messages(),
      info: "3 unread"
    }

    App.put_screen_state(state, :bbs_mail, local_state)
  end

  defp populate(:online_now, state, _size) do
    local_state =
      state
      |> App.build_context()
      |> OnlineNow.init()
      |> OnlineNow.State.from_rows(synthetic_online_now_rows())

    App.put_screen_state(state, :online_now, local_state)
  end

  defp populate(:board_list, state, _size) do
    directory = synthetic_directory()
    board_tree = BoardTree.init(directory: directory, id: "board-directory")

    App.put_screen_state(
      state,
      :board_list,
      BoardList.State.new(
        directory: directory,
        board_tree: board_tree,
        status: :loaded,
        feedback: nil
      )
    )
  end

  defp populate(:thread_list, state, _size) do
    board = hd(synthetic_boards())
    threads = synthetic_threads(board)

    %{state | route_params: %{board: board, board_id: board.id}}
    |> App.put_screen_state(
      :thread_list,
      ThreadList.State.new(
        board: board,
        board_id: board.id,
        threads: threads,
        selected_index: 0,
        status: :loaded
      )
    )
  end

  defp populate(:board_screen, state, _size), do: seed_board_screen(state, :news)

  defp populate(:post_reader, state, _size) do
    board = hd(synthetic_boards())
    threads = synthetic_threads(board)
    thread = hd(threads)
    posts = synthetic_posts(thread)

    post_reader_state =
      PostReader.State.new(
        board: board,
        board_id: board.id,
        thread: thread,
        thread_id: thread.id,
        posts: posts,
        status: :loaded,
        selected_post_index: 0
      )

    populated =
      %{
        state
        | route_params: %{board: board, board_id: board.id, thread: thread, thread_id: thread.id}
      }
      |> App.put_screen_state(:post_reader, post_reader_state)

    # Warm the render cache + viewport for the selected post so the snapshot
    # exercises the cache-hit branch (mirrors the production :load task_result
    # path). Without this, render_post_content/5 emits a Logger.warning on
    # every fixture render and the timestamp leaks into the deterministic
    # snapshot file. (WR-01.)
    warmed_ss = PostReader.prepare_after_load(populated, posts, 0)
    App.put_screen_state(populated, :post_reader, warmed_ss)
  end

  defp populate(:post_composer, state, {w, _h}) do
    board = hd(synthetic_boards())
    [thread | _] = synthetic_threads(board)
    [reply_to | _] = synthetic_posts(thread)

    post_composer_state =
      PostComposer.State.new(
        board: board,
        board_id: board.id,
        thread: thread,
        thread_id: thread.id,
        reply_to: reply_to,
        origin: :post_reader,
        width: max(w - 4, 20),
        height: 10
      )

    %{
      state
      | route_params: %{board: board, board_id: board.id, thread: thread, thread_id: thread.id}
    }
    |> App.put_screen_state(:post_composer, post_composer_state)
  end

  defp populate(:new_thread, state, {w, _h}) do
    [board | _] = synthetic_boards()

    ss =
      NewThread.State.new(
        step: :compose,
        board: board,
        boards: [board],
        load_status: :loaded,
        origin: :thread_list,
        width: w
      )

    %{state | route_params: %{board: board, board_id: board.id}}
    |> App.put_screen_state(:new_thread, ss)
  end

  defp populate(:door_list, state, _size) do
    App.put_screen_state(state, :door_list, init_screen(DoorList, state))
  end

  defp populate(:account, state, _size) do
    App.put_screen_state(state, :account, init_screen(Account, state))
  end

  defp populate(:moderation, state, _size) do
    App.put_screen_state(state, :moderation, init_screen(Moderation, state))
  end

  defp populate(:sysop, state, _size) do
    App.put_screen_state(state, :sysop, init_screen(Sysop, state))
  end

  defp seed_board_screen(state, variant) do
    board = hd(synthetic_boards()) |> Map.put(:chat_enabled, true)
    threads = synthetic_threads(board)
    feeds = synthetic_feeds(variant)
    items = synthetic_feed_items(variant)

    thread_state =
      ThreadList.State.new(
        board: board,
        board_id: board.id,
        threads: threads,
        selected_index: 0,
        status: :loaded
      )

    news_state = %BoardNews.State{
      status: :loaded,
      feeds: feeds,
      items: items,
      selected_index: 0,
      view: if(variant == :news_detail, do: :detail, else: :list)
    }

    config_state = %BoardConfig.State{
      status: :loaded,
      feeds: feeds,
      mode: config_mode(variant),
      input: if(variant == {:config, :add}, do: "https://example.com/feed.xml", else: ""),
      ttl_input: "3600",
      message: config_message(variant)
    }

    screen_state = %BoardScreen.State{
      thread_list: thread_state,
      chat_room: nil,
      news: news_state,
      config: config_state,
      tabs: [:threads, :chat, :news, :config],
      current_tab: current_board_tab(variant),
      presence_count: 2,
      board: board,
      board_id: board.id,
      user_id: state.current_user && state.current_user.id
    }

    %{
      state
      | current_screen: :thread_list,
        route_params: %{board: board, board_id: board.id, news_enabled: true}
    }
    |> App.put_screen_state(:thread_list, screen_state)
  end

  defp init_screen(screen_mod, %App{} = state) do
    state
    |> App.build_context()
    |> screen_mod.init()
  end

  # --- synthetic data shapes -----------------------------------------------

  # Directory shape used by `Foglet.Boards.board_directory_for/1` and
  # consumed by the BoardList screen / BoardTree widget.
  defp synthetic_directory do
    boards = synthetic_boards()
    category = %{id: "c-1", name: "main", display_order: 1}

    [
      %{
        category: category,
        boards:
          Enum.map(boards, fn board ->
            %{
              board: board,
              subscribed?: true,
              required_subscription?: false,
              unread_count: board.unread_count,
              last_post_at: ~U[2026-04-27 12:30:00Z]
            }
          end)
      }
    ]
  end

  defp synthetic_boards do
    [
      %{
        id: "b-1",
        name: "general",
        description: "Anything goes",
        display_order: 1,
        readable_by: :public,
        postable_by: :members,
        archived: false,
        thread_count: 12,
        unread_count: 3
      },
      %{
        id: "b-2",
        name: "tech",
        description: "Computers, code, and curiosities",
        display_order: 2,
        readable_by: :public,
        postable_by: :members,
        archived: false,
        thread_count: 7,
        unread_count: 0
      },
      %{
        id: "b-3",
        name: "lounge",
        description: "Off-topic chat",
        display_order: 3,
        readable_by: :public,
        postable_by: :members,
        archived: false,
        thread_count: 4,
        unread_count: 1
      }
    ]
  end

  defp current_board_tab({:config, _}), do: :config
  defp current_board_tab(:config), do: :config
  defp current_board_tab(_), do: :news

  defp config_mode({:config, mode}), do: mode
  defp config_mode(_), do: :list

  defp config_message({:config, :add}),
    do: "Enter RSS/Atom URL, Enter to validate/save, Esc to cancel."

  defp config_message({:config, :ttl}), do: "Enter TTL seconds."
  defp config_message(_), do: nil

  defp synthetic_feeds(:news_empty), do: []

  defp synthetic_feeds(:news_error) do
    [
      %{
        id: "feed-1",
        title: "Foglet Dispatch",
        url: "https://example.com/rss.xml",
        cache_ttl_seconds: 3600,
        last_error: "timeout",
        last_fetched_at: ~U[2026-05-13 09:00:00Z],
        last_success_at: ~U[2026-05-12 09:00:00Z]
      }
    ]
  end

  defp synthetic_feeds(_variant) do
    [
      %{
        id: "feed-1",
        title: "Foglet Dispatch",
        url: "https://example.com/rss.xml",
        cache_ttl_seconds: 3600,
        last_error: nil,
        last_fetched_at: ~U[2026-05-13 09:00:00Z],
        last_success_at: ~U[2026-05-13 09:00:00Z]
      }
    ]
  end

  defp synthetic_feed_items(variant) when variant in [:news_empty], do: []

  defp synthetic_feed_items(variant) do
    feed = hd(synthetic_feeds(variant))

    [
      %{
        id: "item-1",
        feed: feed,
        title: "Small terminal networks are back",
        summary:
          "Cached RSS text is sanitized, bounded, and rendered without a browser dependency.",
        url: "https://example.com/posts/terminal-networks",
        published_at: ~U[2026-05-13 08:30:00Z]
      },
      %{
        id: "item-2",
        feed: feed,
        title: "Atom feed fixtures cover wide layouts",
        summary: "The board renderer can now show NEWS and CONFIG substates directly.",
        url: "https://example.com/posts/atom-fixtures",
        published_at: ~U[2026-05-13 07:45:00Z]
      }
    ]
  end

  defp synthetic_threads(board) do
    [
      %ThreadEntry{
        id: "t-1",
        title: "Welcome — read me first",
        board_id: board.id,
        sticky: true,
        locked: false,
        post_count: 3,
        last_post_at: ~U[2026-04-27 11:00:00Z],
        inserted_at: ~U[2026-04-01 09:00:00Z],
        created_by_id: "u-sysop",
        has_unread: false,
        created_by: %{handle: "sysop"}
      },
      %ThreadEntry{
        id: "t-2",
        title: "What is everyone working on?",
        board_id: board.id,
        sticky: false,
        locked: false,
        post_count: 8,
        last_post_at: ~U[2026-04-27 12:30:00Z],
        inserted_at: ~U[2026-04-20 10:00:00Z],
        created_by_id: "u-alice",
        has_unread: true,
        created_by: %{handle: "alice"}
      },
      %ThreadEntry{
        id: "t-3",
        title: "Thread renderer ASCII tool",
        board_id: board.id,
        sticky: false,
        locked: false,
        post_count: 2,
        last_post_at: ~U[2026-04-27 13:00:00Z],
        inserted_at: ~U[2026-04-27 12:45:00Z],
        created_by_id: "u-alice",
        has_unread: true,
        created_by: %{handle: "alice"}
      }
    ]
  end

  defp synthetic_posts(thread) do
    [
      %{
        id: "p-1",
        thread_id: thread.id,
        message_number: 1,
        body: "Welcome — please read the rules in /general.",
        body_rendered: nil,
        upvote_count: 4,
        edit_count: 0,
        deleted_at: nil,
        inserted_at: ~U[2026-04-01 09:00:00Z],
        user: %{handle: "sysop"}
      },
      %{
        id: "p-2",
        thread_id: thread.id,
        message_number: 2,
        body: "Glad to be here. Foglet looks great so far.",
        body_rendered: nil,
        upvote_count: 1,
        edit_count: 0,
        deleted_at: nil,
        inserted_at: ~U[2026-04-02 10:00:00Z],
        user: %{handle: "alice"}
      }
    ]
  end
end
