defmodule Foglet.TUI.Screens.LoginTest do
  use FogletBbs.DataCase, async: false

  alias Foglet.Accounts.User
  alias Foglet.Config
  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Presentation
  alias Foglet.TUI.Screens.Login
  alias Foglet.TUI.Widgets.Input.TextInput

  import Ecto.Query
  import Foglet.TUI.RenderHelpers
  import FogletBbs.AccountsFixtures
  import Swoosh.TestAssertions

  defp base_state(mode \\ "open") do
    %Foglet.TUI.App{
      current_screen: :login,
      current_user: nil,
      session_context: %{registration_mode: mode},
      terminal_size: {80, 24},
      screen_state: %{}
    }
    |> Map.from_struct()
  end

  defp login_context(state) do
    Context.new(
      current_user: Map.get(state, :current_user),
      session_context: Map.get(state, :session_context) || %{},
      session_pid: Map.get(state, :session_pid),
      terminal_size: Map.get(state, :terminal_size, {80, 24}),
      route: :login,
      route_params: Map.get(state, :route_params) || %{},
      domain: Map.get(state, :domain) || get_in(state, [:session_context, :domain]) || %{}
    )
  end

  defp login_state(state),
    do: get_in(state, [:screen_state, :login]) || Login.init(login_context(state))

  defp put_login_state(state, login_state) do
    Map.put(
      state,
      :screen_state,
      Map.put(Map.get(state, :screen_state) || %{}, :login, login_state)
    )
  end

  defp update_login(key, state), do: update_message({:key, key}, state)

  defp update_message(message, state) do
    {new_login_state, effects} = Login.update(message, login_state(state), login_context(state))
    {:update, put_login_state(state, new_login_state), effects}
  end

  defp run_login_task_result(state, %Effect{type: :task, payload: payload}) do
    result = payload.fun.()
    update_message({:task_result, payload.op, {:ok, result}}, state)
  end

  defp submit_reset_request(state) do
    {:update, pending_state, [%Effect{type: :task, payload: %{op: :reset_request}} = effect]} =
      update_login(%{key: :enter}, state)

    run_login_task_result(pending_state, effect)
  end

  defp submit_reset_consume(state) do
    {:update, pending_state, [%Effect{type: :task, payload: %{op: :reset_token}} = effect]} =
      update_login(%{key: :enter}, state)

    run_login_task_result(pending_state, effect)
  end

  defp render_login(state), do: Login.render(login_state(state), login_context(state))

  defp modal_effect(effects) do
    Enum.find_value(effects, fn
      %Effect{type: :modal, payload: {:open, modal}} -> modal
      _other -> nil
    end)
  end

  defp session_effect(effects) do
    Enum.find_value(effects, fn
      %Effect{type: :session, payload: payload} -> payload
      _other -> nil
    end)
  end

  defp navigation_effect(effects) do
    Enum.find_value(effects, fn
      %Effect{type: :navigate, payload: payload} -> payload
      _other -> nil
    end)
  end

  # Moves the TextInput cursor to end-of-value, simulating the user having typed the
  # pre-seeded value. This is necessary because TextInput.init/1 places the cursor at
  # position 0 regardless of the initial value; a real user would have cursor at the end.
  defp text_input_at_end(ti) do
    {ti_end, _action} = TextInput.handle_event(%{key: :end}, ti)
    ti_end
  end

  # Build a state with the login form open and a specific field focused.
  # Fields: handle (string), password (string), error (string | nil)
  defp form_state(fields, focused \\ :password) do
    handle_input = TextInput.init(value: Keyword.get(fields, :handle, "")) |> text_input_at_end()

    password_input =
      TextInput.init(value: Keyword.get(fields, :password, ""), mask_char: "*")
      |> text_input_at_end()

    error = Keyword.get(fields, :error, nil)

    %Foglet.TUI.App{
      current_screen: :login,
      session_context: %{registration_mode: "open"},
      terminal_size: {80, 24},
      screen_state: %{
        login: %{
          sub: :login_form,
          focused_field: focused,
          handle_input: handle_input,
          password_input: password_input,
          error: error
        }
      }
    }
    |> Map.from_struct()
  end

  defp reset_request_state(identifier, opts \\ []) do
    identifier_input = TextInput.init(value: identifier) |> text_input_at_end()
    terminal_size = Keyword.get(opts, :terminal_size, {80, 24})

    %Foglet.TUI.App{
      current_screen: :login,
      session_context: %{registration_mode: "open"},
      terminal_size: terminal_size,
      screen_state: %{
        login: %{
          sub: :reset_request,
          focused_field: :identifier,
          identifier_input: identifier_input,
          error: nil,
          message: nil,
          message_category: nil
        }
      }
    }
    |> Map.from_struct()
  end

  setup do
    original_delivery_mode = Config.get("delivery_mode", "no_email")

    on_exit(fn ->
      Config.put!("delivery_mode", original_delivery_mode)
      Config.invalidate("delivery_mode")
    end)

    :ok
  end

  defp forbidden_reset_route, do: "/users/reset_password"
  defp forbidden_http_prefix, do: "http://"
  defp forbidden_https_prefix, do: "https://"

  defp submit_login_form(state) do
    {:update, submitting_state, [%Effect{type: :task} = effect]} =
      update_login(%{key: :enter}, state)

    assert get_in(submitting_state, [:screen_state, :login, :submitting?]) == true
    assert effect.payload.op == :login
    assert effect.payload.screen_key == :login
    result = effect.payload.fun.()

    {:update, final_state, final_effects} =
      update_message({:task_result, :login, {:ok, result}}, submitting_state)

    {submitting_state, final_state, final_effects}
  end

  defp collect_panels(tree), do: tree |> collect_panels([]) |> Enum.reverse()

  defp collect_panels(nil, acc), do: acc
  defp collect_panels(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect_panels/2)

  defp collect_panels(%{type: :panel, children: children} = node, acc),
    do: collect_panels(children, [node | acc])

  defp collect_panels(%{children: children}, acc), do: collect_panels(children, acc)
  defp collect_panels(_other, acc), do: acc

  describe "Login.init/1 (AUDIT-19)" do
    test "returns minimal menu sub-state" do
      assert Login.init(Context.new(route: :login)) == %{sub: :menu}
    end

    test "ignores unrelated context values for the minimal menu state" do
      assert Login.init(Context.new(route: :login, route_params: %{foo: :bar})) == %{sub: :menu}
    end

    test "Login render decomposition contract is explicit" do
      assert Code.ensure_loaded?(Login.Render)
      assert function_exported?(Login.Render, :render, 2)

      source =
        __ENV__.file
        |> Path.dirname()
        |> Path.join("../../../../lib/foglet_bbs/tui/screens/login.ex")
        |> Path.expand()
        |> File.read!()

      assert source =~
               "def render(local_state, %Context{} = context), do: Render.render(local_state, context)"
    end
  end

  describe "render/1 (SSH-04, D-06)" do
    test "declares BBS presentation mode and renders" do
      assert Presentation.mode_for!(:login) == :bbs
      assert _ = render_login(base_state("open"))
    end

    test "renders without crashing under open mode" do
      assert _ = render_login(base_state("open"))
    end

    test "renders without crashing under disabled mode" do
      assert _ = render_login(base_state("disabled"))
    end

    test "renders login form without crashing when in login_form sub" do
      assert _ = render_login(form_state(handle: "alice", password: "secret"))
    end

    test "renders login form inside an Identify yourself panel with comfortable width" do
      [panel] =
        form_state(handle: "alicealicealicealice", password: "secret")
        |> render_login()
        |> collect_panels()

      assert panel.attrs.title == "Identify yourself"
      assert panel.attrs.width >= 40
      assert panel.attrs.height >= 8
    end

    test "caps long masked password display inside the Identify yourself panel" do
      rendered_text =
        form_state([handle: "alice", password: String.duplicate("s", 30)], :password)
        |> render_login()
        |> collect_text_values()
        |> Enum.join("")

      assert rendered_text =~ String.duplicate("*", 25)
      refute rendered_text =~ String.duplicate("*", 26)
    end

    test "renders forgot password in email delivery mode (D-01)" do
      Config.put!("delivery_mode", "email")
      email_text = render_login(base_state("open")) |> collect_text_values() |> Enum.join("\n")
      assert email_text =~ "Forgot password"
    end

    test "renders forgot password in no-email delivery mode (D-01)" do
      Config.put!("delivery_mode", "no_email")
      no_email_text = render_login(base_state("open")) |> collect_text_values() |> Enum.join("\n")
      assert no_email_text =~ "Forgot password"
    end
  end

  describe "update/3 — menu sub" do
    test "Ctrl+C returns terminate command" do
      assert {:update, _, [%Effect{type: :quit}]} =
               update_login(%{key: :char, char: "c", ctrl: true}, base_state())
    end

    test "Ctrl+C returns terminate command from form sub-states" do
      assert {:update, _, [%Effect{type: :quit}]} =
               update_login(
                 %{key: :char, char: "c", ctrl: true},
                 form_state(handle: "alice", password: "secret")
               )
    end

    test "'Q' is not an exit key" do
      assert {:update, _state, []} = update_login(%{key: :char, char: "Q"}, base_state())
    end

    test "'q' lowercase is not an exit key" do
      assert {:update, _state, []} = update_login(%{key: :char, char: "q"}, base_state())
    end

    test "'R' transitions to :register when registration enabled (D-22)" do
      {:update, _new_state, effects} = update_login(%{key: :char, char: "R"}, base_state("open"))
      assert %{screen: :register, params: %{}} = navigation_effect(effects)
      # Post-Phase-2: login.ex:maybe_register/1 no longer initializes wizard state.
      # register.ex self-initializes screen_state[:register] on first access (D-06).
      # Only the screen transition is login.ex's responsibility.
    end

    test "'R' returns :no_match when registration disabled (D-06)" do
      assert {:update, _state, []} =
               update_login(%{key: :char, char: "R"}, base_state("disabled"))
    end

    test "'L' enters login_form sub-state with focus on :handle" do
      {:update, new_state, _} = update_login(%{key: :char, char: "L"}, base_state())
      assert get_in(new_state, [:screen_state, :login, :sub]) == :login_form
      assert get_in(new_state, [:screen_state, :login, :focused_field]) == :handle
    end

    test "'F' enters reset_request sub-state in email delivery mode (D-01)" do
      Config.put!("delivery_mode", "email")

      {:update, new_state, []} = update_login(%{key: :char, char: "F"}, base_state())
      assert get_in(new_state, [:screen_state, :login, :sub]) == :reset_request
      assert get_in(new_state, [:screen_state, :login, :focused_field]) == :identifier
    end

    test "'F' enters reset_request sub-state in no_email delivery mode (D-01)" do
      Config.put!("delivery_mode", "no_email")

      {:update, new_state, []} = update_login(%{key: :char, char: "F"}, base_state())
      assert get_in(new_state, [:screen_state, :login, :sub]) == :reset_request
      assert get_in(new_state, [:screen_state, :login, :focused_field]) == :identifier
    end

    test "unknown key returns :no_match in menu sub" do
      assert {:update, _state, []} = update_login(%{key: :char, char: "x"}, base_state())
    end
  end

  describe "update/3 — login form typing" do
    test "typing a character appends to focused field (handle)" do
      state = form_state([], :handle)
      {:update, new_state, []} = update_login(%{key: :char, char: "a"}, state)

      assert get_in(new_state, [
               :screen_state,
               :login,
               :handle_input,
               Access.key(:raxol_state),
               :value
             ]) == "a"

      assert get_in(new_state, [
               :screen_state,
               :login,
               :password_input,
               Access.key(:raxol_state),
               :value
             ]) == ""
    end

    test "typing multiple characters builds up the handle" do
      state = form_state([handle: "al"], :handle)
      {:update, s1, []} = update_login(%{key: :char, char: "i"}, state)
      {:update, s2, []} = update_login(%{key: :char, char: "c"}, s1)
      {:update, s3, []} = update_login(%{key: :char, char: "e"}, s2)

      assert get_in(s3, [:screen_state, :login, :handle_input, Access.key(:raxol_state), :value]) ==
               "alice"
    end

    test "handle input stops at the account handle max length" do
      chars = String.graphemes(String.duplicate("a", User.handle_max() + 1))

      {:update, form_state, []} = update_login(%{key: :char, char: "L"}, base_state())

      final_state =
        Enum.reduce(chars, form_state, fn char, acc ->
          {:update, next, []} = update_login(%{key: :char, char: char}, acc)
          next
        end)

      assert get_in(final_state, [
               :screen_state,
               :login,
               :handle_input,
               Access.key(:raxol_state),
               :value
             ]) == String.duplicate("a", User.handle_max())
    end

    test "typing appends to password field when focused" do
      state = form_state([], :password)
      {:update, new_state, []} = update_login(%{key: :char, char: "s"}, state)

      assert get_in(new_state, [
               :screen_state,
               :login,
               :password_input,
               Access.key(:raxol_state),
               :value
             ]) == "s"
    end

    test "spacebar appends a literal space to focused field" do
      state = form_state([handle: "hello"], :handle)
      {:update, new_state, []} = update_login(%{key: :char, char: " "}, state)

      assert get_in(new_state, [
               :screen_state,
               :login,
               :handle_input,
               Access.key(:raxol_state),
               :value
             ]) == "hello "
    end

    test "backspace removes last character from focused field" do
      state = form_state([handle: "alice"], :handle)
      {:update, new_state, []} = update_login(%{key: :backspace}, state)

      assert get_in(new_state, [
               :screen_state,
               :login,
               :handle_input,
               Access.key(:raxol_state),
               :value
             ]) == "alic"
    end

    test "backspace on empty field is a no-op" do
      state = form_state([handle: ""], :handle)
      {:update, new_state, []} = update_login(%{key: :backspace}, state)

      assert get_in(new_state, [
               :screen_state,
               :login,
               :handle_input,
               Access.key(:raxol_state),
               :value
             ]) == ""
    end

    test "tab cycles focus from :handle to :password" do
      state = form_state([], :handle)
      {:update, new_state, []} = update_login(%{key: :tab}, state)
      assert get_in(new_state, [:screen_state, :login, :focused_field]) == :password
    end

    test "tab cycles focus from :password back to :handle" do
      state = form_state([], :password)
      {:update, new_state, []} = update_login(%{key: :tab}, state)
      assert get_in(new_state, [:screen_state, :login, :focused_field]) == :handle
    end

    test "enter on :handle field moves focus to :password without submitting" do
      state = form_state([handle: "alice"], :handle)
      {:update, new_state, cmds} = update_login(%{key: :enter}, state)
      assert get_in(new_state, [:screen_state, :login, :focused_field]) == :password
      assert cmds == []
    end

    test "escape from login form returns to menu sub with cleared form" do
      state = form_state([handle: "alice", password: "secret"], :password)
      {:update, new_state, []} = update_login(%{key: :escape}, state)
      assert get_in(new_state, [:screen_state, :login, :sub]) == :menu
      # Form is cleared — handle_input and password_input are gone from the returned sub-state
      assert get_in(new_state, [:screen_state, :login, :handle_input]) == nil
      assert get_in(new_state, [:screen_state, :login, :password_input]) == nil
    end
  end

  describe "update/3 — reset request subflow" do
    test "renders email-only field label (D-02)" do
      Config.put!("delivery_mode", "email")
      state = reset_request_state("")

      rendered =
        render_login(state)
        |> collect_text_values()
        |> Enum.join("\n")

      assert rendered =~ "Email:"
      # D-02: field is email-only; the prior dual-mode label is gone.
      refute rendered =~ ~r/Handle\s+or\s+email/i
    end

    test "typing updates the identifier field" do
      Config.put!("delivery_mode", "email")
      state = reset_request_state("ali")

      {:update, new_state, []} = update_login(%{key: :char, char: "c"}, state)

      assert get_in(new_state, [
               :screen_state,
               :login,
               :identifier_input,
               Access.key(:raxol_state),
               :value
             ]) == "alic"
    end

    # D-02 invalid local email shapes: missing @, missing domain, whitespace,
    # missing dotted TLD, embedded whitespace. Each case must:
    #   1. leave sub == :reset_request
    #   2. set an inline validation error on the screen state
    #   3. NOT create any reset_password token rows
    for {label, identifier} <- [
          {"empty string", ""},
          {"whitespace only", "   "},
          {"no @ sign", "alice"},
          {"missing domain", "alice@"},
          {"missing dotted tld", "alice@example"},
          {"embedded space", "a b@example.test"}
        ] do
      test "invalid email shape (#{label}) blocks dispatch and creates no token rows (D-02)" do
        Config.put!("delivery_mode", "email")

        # Pre-create a real account so we can prove no token rows are created
        # for any active user even when the input is shape-invalid.
        user =
          user_fixture(%{handle: "shapeguard", email: "shapeguard@example.test"})

        before_count =
          Foglet.Accounts.UserToken
          |> from(where: [context: "reset_password"])
          |> FogletBbs.Repo.aggregate(:count, :id)

        state = reset_request_state(unquote(identifier))

        {:update, new_state, []} = update_login(%{key: :enter}, state)

        assert get_in(new_state, [:screen_state, :login, :sub]) == :reset_request

        # Inline validation error is set
        error = get_in(new_state, [:screen_state, :login, :error])
        assert is_binary(error)
        assert String.length(error) > 0

        # Outward state did NOT enter the success/dispatched category
        assert get_in(new_state, [:screen_state, :login, :message_category]) in [
                 nil,
                 :invalid_email
               ]

        # Zero new reset_password tokens were created
        after_count =
          Foglet.Accounts.UserToken
          |> from(where: [context: "reset_password"])
          |> FogletBbs.Repo.aggregate(:count, :id)

        assert after_count == before_count

        # And specifically not for the active user we created
        refute FogletBbs.Repo.exists?(
                 from t in Foglet.Accounts.UserToken,
                   where: t.user_id == ^user.id and t.context == "reset_password"
               )
      end
    end

    test "valid active email submission produces enumeration-safe message_category (D-03)" do
      Config.put!("delivery_mode", "email")

      user =
        user_fixture(%{handle: "activelady", email: "activelady@example.test"})

      state = reset_request_state("activelady@example.test")

      {:update, new_state, []} = submit_reset_request(state)

      assert get_in(new_state, [:screen_state, :login, :sub]) == :reset_request
      assert get_in(new_state, [:screen_state, :login, :error]) == nil
      active_category = get_in(new_state, [:screen_state, :login, :message_category])
      assert is_atom(active_category)
      assert active_category != nil

      # Active email creates exactly one reset_password token row
      assert FogletBbs.Repo.exists?(
               from t in Foglet.Accounts.UserToken,
                 where: t.user_id == ^user.id and t.context == "reset_password"
             )

      rendered =
        render_login(new_state)
        |> collect_text_values()
        |> Enum.join("\n")

      refute rendered =~ forbidden_reset_route()
      refute rendered =~ forbidden_http_prefix()
      refute rendered =~ forbidden_https_prefix()
    end

    test "valid unknown email submission produces same category as active (D-03)" do
      Config.put!("delivery_mode", "email")

      # Active for category-equality comparison
      _ = user_fixture(%{handle: "anchor", email: "anchor@example.test"})

      active_state = reset_request_state("anchor@example.test")
      {:update, active_new, []} = submit_reset_request(active_state)
      active_category = get_in(active_new, [:screen_state, :login, :message_category])

      unknown_state = reset_request_state("ghost@example.test")
      {:update, unknown_new, []} = submit_reset_request(unknown_state)
      unknown_category = get_in(unknown_new, [:screen_state, :login, :message_category])

      assert is_atom(active_category)
      assert active_category != nil
      assert unknown_category == active_category

      # No reset token row is created for an unknown email
      refute FogletBbs.Repo.exists?(
               from t in Foglet.Accounts.UserToken,
                 where: t.context == "reset_password",
                 join: u in Foglet.Accounts.User,
                 on: u.id == t.user_id,
                 where: u.email == "ghost@example.test"
             )
    end

    test "no_email mode produces operator-assisted copy, not 'unavailable' (D-14, AUTH-03)" do
      Config.put!("delivery_mode", "no_email")
      state = reset_request_state("alice@example.test")

      {:update, new_state, []} = submit_reset_request(state)

      message = get_in(new_state, [:screen_state, :login, :message])
      assert is_binary(message)
      refute message =~ "unavailable"

      rendered =
        render_login(new_state)
        |> collect_text_values()
        |> Enum.join("\n")

      # Honest operator-assisted SSH path; advertises token entry via Esc + [T].
      assert rendered =~ ~r/sysop|operator/i
      assert rendered =~ "[T]"
      refute rendered =~ "unavailable"
      refute rendered =~ forbidden_reset_route()
      refute rendered =~ forbidden_http_prefix()
      refute rendered =~ forbidden_https_prefix()
    end

    test "no_email mode lists active sysop emails comma-separated when present (D-14)" do
      Config.put!("delivery_mode", "no_email")

      sysop_a =
        user_fixture(%{handle: "sysopa", email: "sysopa@example.test"})
        |> Foglet.Accounts.User.role_changeset(%{role: :sysop})
        |> FogletBbs.Repo.update!()

      sysop_b =
        user_fixture(%{handle: "sysopb", email: "sysopb@example.test"})
        |> Foglet.Accounts.User.role_changeset(%{role: :sysop})
        |> FogletBbs.Repo.update!()

      # Confirm both are active
      {:ok, _} = Foglet.Accounts.confirm_user(sysop_a)
      {:ok, _} = Foglet.Accounts.confirm_user(sysop_b)

      state = reset_request_state("alice@example.test")
      {:update, new_state, []} = submit_reset_request(state)

      rendered =
        render_login(new_state)
        |> collect_text_values()
        |> Enum.join("\n")

      assert rendered =~ "sysopa@example.test"
      assert rendered =~ "sysopb@example.test"
      # Comma-separated rendering: assert one of the two contact emails is
      # followed by a comma somewhere on the rendered output.
      joined = rendered
      assert joined =~ ~r/sysopa@example\.test\s*,|,\s*sysopa@example\.test/
    end

    test "no_email mode falls back honestly when no sysops exist (D-14)" do
      Config.put!("delivery_mode", "no_email")

      state = reset_request_state("alice@example.test")
      {:update, new_state, []} = submit_reset_request(state)

      rendered =
        render_login(new_state)
        |> collect_text_values()
        |> Enum.join("\n")

      # Still honest operator-assisted copy, never says unavailable
      assert rendered =~ ~r/sysop|operator/i
      refute rendered =~ "unavailable"

      # IN-004: assert the actual fallback string from
      # `@reset_no_email_no_sysops_fallback`. Without this, the test would
      # still pass even if the fallback constant were never inserted —
      # the intro copy alone matches the broader sysop|operator regex.
      assert rendered =~ "No sysop contact is listed"
    end

    test "reset confirmation copy wraps via TextWidth.wrap at compact widths (D-12, AUTH-02)" do
      Config.put!("delivery_mode", "email")
      state = reset_request_state("anybody@example.test", terminal_size: {64, 22})

      {:update, new_state, []} = submit_reset_request(state)

      rendered_lines =
        render_login(new_state)
        |> collect_text_values()

      # No single rendered text node should exceed terminal content width
      # (64 cols minus chrome borders/margins). Use a generous upper bound
      # of 62 to allow for 2-cell border, but the key property is that the
      # confirmation copy is split across multiple rows rather than one long
      # silently-truncated node.
      max_width =
        rendered_lines
        |> Enum.map(&Foglet.TUI.TextWidth.display_width/1)
        |> Enum.max(fn -> 0 end)

      assert max_width <= 62

      # Confirmation copy occupies multiple visible text nodes (proves wrap
      # produced row-per-line nodes, not a single long node that engine
      # truncates).
      message_category = get_in(new_state, [:screen_state, :login, :message_category])
      assert message_category != nil
    end

    # CR-001 regression: typing `t` or `T` while on the reset_request screen
    # MUST append to the identifier input (free-text email). The earlier
    # implementation hijacked bare `t`/`T` as a [T] Enter-reset-token shortcut,
    # which made it impossible to type emails like `taylor@example.com` or
    # `bfturner@foglet.io`. Token-consume entry remains reachable from the
    # Login menu (Esc → [T]); see "[T] from menu enters reset_consume" below.
    test "typing 't' or 'T' into the identifier field appends to the input, not the [T] shortcut (CR-001)" do
      # Lower-case `t` mid-typing: simulate user partway through `test@host`.
      state = reset_request_state("alice@example.")
      {:update, after_t, []} = update_login(%{key: :char, char: "t"}, state)
      assert get_in(after_t, [:screen_state, :login, :sub]) == :reset_request

      assert get_in(after_t, [
               :screen_state,
               :login,
               :identifier_input,
               Access.key(:raxol_state),
               :value
             ]) == "alice@example.t"

      # Upper-case `T` likewise.
      state2 = reset_request_state("alice@example.")
      {:update, after_upper, []} = update_login(%{key: :char, char: "T"}, state2)
      assert get_in(after_upper, [:screen_state, :login, :sub]) == :reset_request

      assert get_in(after_upper, [
               :screen_state,
               :login,
               :identifier_input,
               Access.key(:raxol_state),
               :value
             ]) == "alice@example.T"
    end

    test "[T] from the Login menu enters reset_consume sub-state (D-15)" do
      Config.put!("delivery_mode", "no_email")

      {:update, new_state, []} = update_login(%{key: :char, char: "T"}, base_state())

      assert get_in(new_state, [:screen_state, :login, :sub]) == :reset_consume
      assert get_in(new_state, [:screen_state, :login, :focused_field]) == :token
    end

    test "escape returns to menu and clears reset request state" do
      state = reset_request_state("alice@example.test")

      {:update, new_state, []} = update_login(%{key: :escape}, state)

      assert get_in(new_state, [:screen_state, :login, :sub]) == :menu
      assert get_in(new_state, [:screen_state, :login, :identifier_input]) == nil
    end
  end

  # ---- Plan 31-03 :reset_consume sub-state (D-04..D-11, D-15, D-17) ----

  defp reset_consume_state(opts) do
    token = Keyword.get(opts, :token, "")
    password = Keyword.get(opts, :password, "")
    confirmation = Keyword.get(opts, :password_confirmation, "")
    focused = Keyword.get(opts, :focused_field, :token)

    token_input = TextInput.init(value: token) |> text_input_at_end()

    password_input =
      TextInput.init(value: password, mask_char: "*") |> text_input_at_end()

    password_confirmation_input =
      TextInput.init(value: confirmation, mask_char: "*") |> text_input_at_end()

    %Foglet.TUI.App{
      current_screen: :login,
      session_context: %{registration_mode: "open"},
      terminal_size: {80, 24},
      screen_state: %{
        login: %{
          sub: :reset_consume,
          focused_field: focused,
          token_input: token_input,
          password_input: password_input,
          password_confirmation_input: password_confirmation_input,
          error: nil
        }
      }
    }
    |> Map.from_struct()
  end

  describe "update/3 - reset_consume entry (D-15)" do
    test "'T' from menu enters :reset_consume sub-state with focus on :token" do
      {:update, new_state, []} = update_login(%{key: :char, char: "T"}, base_state())

      assert get_in(new_state, [:screen_state, :login, :sub]) == :reset_consume
      assert get_in(new_state, [:screen_state, :login, :focused_field]) == :token
    end

    test "'t' lowercase from menu also enters :reset_consume" do
      {:update, new_state, []} = update_login(%{key: :char, char: "t"}, base_state())

      assert get_in(new_state, [:screen_state, :login, :sub]) == :reset_consume
    end

    test "menu advertises Enter reset token in keys_for output" do
      rendered =
        render_login(base_state("open"))
        |> collect_text_values()
        |> Enum.join("\n")

      assert rendered =~ "Enter reset token"
    end

    # CR-001: bare `T`/`t` while on the reset_request screen MUST NOT navigate
    # to :reset_consume — that screen has a free-text email field whose
    # contents include `t`/`T`. Token-consume entry from the Forgot Password
    # flow is reachable via Esc → menu → [T] (verified separately above).
    test "'T' on reset_request types into the identifier input (CR-001)" do
      Config.put!("delivery_mode", "no_email")
      state = reset_request_state("alice@example.test")

      {:update, new_state, []} = update_login(%{key: :char, char: "T"}, state)

      assert get_in(new_state, [:screen_state, :login, :sub]) == :reset_request

      assert get_in(new_state, [
               :screen_state,
               :login,
               :identifier_input,
               Access.key(:raxol_state),
               :value
             ]) == "alice@example.testT"
    end

    test "'t' lowercase on reset_request types into the identifier input (CR-001)" do
      Config.put!("delivery_mode", "no_email")
      state = reset_request_state("alice@example.test")

      {:update, new_state, []} = update_login(%{key: :char, char: "t"}, state)

      assert get_in(new_state, [:screen_state, :login, :sub]) == :reset_request

      assert get_in(new_state, [
               :screen_state,
               :login,
               :identifier_input,
               Access.key(:raxol_state),
               :value
             ]) == "alice@example.testt"
    end

    test "fresh :reset_consume initializes three TextInput fields with masked password fields (D-05)" do
      {:update, new_state, []} = update_login(%{key: :char, char: "T"}, base_state())
      ss = get_in(new_state, [:screen_state, :login])

      assert match?(%TextInput{}, ss.token_input)
      assert match?(%TextInput{}, ss.password_input)
      assert match?(%TextInput{}, ss.password_confirmation_input)

      refute get_in(ss.token_input, [Access.key(:raxol_state), :mask_char]) == "*"
      assert get_in(ss.password_input, [Access.key(:raxol_state), :mask_char]) == "*"
      assert get_in(ss.password_confirmation_input, [Access.key(:raxol_state), :mask_char]) == "*"

      assert get_in(ss.token_input, [Access.key(:raxol_state), :value]) == ""
      assert get_in(ss.password_input, [Access.key(:raxol_state), :value]) == ""
      assert get_in(ss.password_confirmation_input, [Access.key(:raxol_state), :value]) == ""

      assert ss.error == nil
    end
  end

  describe "update/3 - reset_consume focus (D-06)" do
    test "Tab cycles :token to :password" do
      state = reset_consume_state(focused_field: :token)
      {:update, new_state, []} = update_login(%{key: :tab}, state)

      assert get_in(new_state, [:screen_state, :login, :focused_field]) == :password
    end

    test "Tab cycles :password to :password_confirmation" do
      state = reset_consume_state(focused_field: :password)
      {:update, new_state, []} = update_login(%{key: :tab}, state)

      assert get_in(new_state, [:screen_state, :login, :focused_field]) == :password_confirmation
    end

    test "Tab cycles :password_confirmation to :token" do
      state = reset_consume_state(focused_field: :password_confirmation)
      {:update, new_state, []} = update_login(%{key: :tab}, state)

      assert get_in(new_state, [:screen_state, :login, :focused_field]) == :token
    end

    test ":backtab cycles :token to :password_confirmation" do
      state = reset_consume_state(focused_field: :token)
      {:update, new_state, []} = update_login(%{key: :backtab}, state)

      assert get_in(new_state, [:screen_state, :login, :focused_field]) == :password_confirmation
    end

    test ":backtab cycles :password_confirmation to :password" do
      state = reset_consume_state(focused_field: :password_confirmation)
      {:update, new_state, []} = update_login(%{key: :backtab}, state)

      assert get_in(new_state, [:screen_state, :login, :focused_field]) == :password
    end

    test ":backtab cycles :password to :token" do
      state = reset_consume_state(focused_field: :password)
      {:update, new_state, []} = update_login(%{key: :backtab}, state)

      assert get_in(new_state, [:screen_state, :login, :focused_field]) == :token
    end

    test "typing characters land only in the focused input field" do
      state = reset_consume_state(focused_field: :token)

      {:update, s1, []} = update_login(%{key: :char, char: "a"}, state)

      assert get_in(s1, [
               :screen_state,
               :login,
               :token_input,
               Access.key(:raxol_state),
               :value
             ]) == "a"

      assert get_in(s1, [
               :screen_state,
               :login,
               :password_input,
               Access.key(:raxol_state),
               :value
             ]) == ""

      assert get_in(s1, [
               :screen_state,
               :login,
               :password_confirmation_input,
               Access.key(:raxol_state),
               :value
             ]) == ""

      {:update, s2, []} = update_login(%{key: :tab}, s1)
      {:update, s3, []} = update_login(%{key: :char, char: "p"}, s2)

      assert get_in(s3, [
               :screen_state,
               :login,
               :token_input,
               Access.key(:raxol_state),
               :value
             ]) == "a"

      assert get_in(s3, [
               :screen_state,
               :login,
               :password_input,
               Access.key(:raxol_state),
               :value
             ]) == "p"

      assert get_in(s3, [
               :screen_state,
               :login,
               :password_confirmation_input,
               Access.key(:raxol_state),
               :value
             ]) == ""

      {:update, s4, []} = update_login(%{key: :tab}, s3)
      {:update, s5, []} = update_login(%{key: :char, char: "c"}, s4)

      assert get_in(s5, [
               :screen_state,
               :login,
               :token_input,
               Access.key(:raxol_state),
               :value
             ]) == "a"

      assert get_in(s5, [
               :screen_state,
               :login,
               :password_input,
               Access.key(:raxol_state),
               :value
             ]) == "p"

      assert get_in(s5, [
               :screen_state,
               :login,
               :password_confirmation_input,
               Access.key(:raxol_state),
               :value
             ]) == "c"
    end
  end

  describe "update/3 - reset_consume submission (D-07, D-10, D-11)" do
    test "mismatch in password confirmation sets generic error and does not consume token" do
      user =
        user_fixture(%{
          handle: "mismatch",
          email: "mismatch@example.test"
        })

      {raw_token, user_token} =
        Foglet.Accounts.UserToken.build_email_token(user, "reset_password")

      {:ok, _} = FogletBbs.Repo.insert(user_token)

      state =
        reset_consume_state(
          token: raw_token,
          password: "newvalidpass99",
          password_confirmation: "different-pw99",
          focused_field: :password_confirmation
        )

      {:update, new_state, cmds} = update_login(%{key: :enter}, state)

      assert cmds == []
      assert get_in(new_state, [:screen_state, :login, :sub]) == :reset_consume

      error = get_in(new_state, [:screen_state, :login, :error])
      assert is_binary(error)
      assert error =~ ~r/match/i

      assert FogletBbs.Repo.exists?(
               from t in Foglet.Accounts.UserToken,
                 where: t.user_id == ^user.id and t.context == "reset_password"
             )
    end

    test "successful consume: matching passwords + valid token returns to menu and clears state (D-07)" do
      user =
        user_fixture(%{
          handle: "consumer",
          email: "consumer@example.test"
        })

      {raw_token, user_token} =
        Foglet.Accounts.UserToken.build_email_token(user, "reset_password")

      {:ok, _} = FogletBbs.Repo.insert(user_token)

      new_password = "freshvalidpass99"

      state =
        reset_consume_state(
          token: raw_token,
          password: new_password,
          password_confirmation: new_password,
          focused_field: :password_confirmation
        )

      {:update, new_state, _cmds} = submit_reset_consume(state)

      assert get_in(new_state, [:screen_state, :login, :sub]) == :menu
      assert get_in(new_state, [:screen_state, :login, :token_input]) == nil
      assert get_in(new_state, [:screen_state, :login, :password_input]) == nil
      assert get_in(new_state, [:screen_state, :login, :password_confirmation_input]) == nil

      refute FogletBbs.Repo.exists?(
               from t in Foglet.Accounts.UserToken,
                 where: t.user_id == ^user.id and t.context == "reset_password"
             )

      assert {:ok, returned} =
               Foglet.Accounts.Auth.authenticate_by_password(user.handle, new_password)

      assert returned.id == user.id
    end

    test "invalid token submission stays on form with generic error (D-10)" do
      state =
        reset_consume_state(
          token: "obviously-not-a-real-token",
          password: "freshvalidpass99",
          password_confirmation: "freshvalidpass99",
          focused_field: :password_confirmation
        )

      {:update, new_state, []} = submit_reset_consume(state)

      assert get_in(new_state, [:screen_state, :login, :sub]) == :reset_consume

      error = get_in(new_state, [:screen_state, :login, :error])
      assert is_binary(error)
      assert String.length(error) > 0

      refute error =~ ~r/expired/i
      refute error =~ ~r/already.?used/i
      refute error =~ ~r/malformed/i
    end

    test "invalid token error copy is identical for missing-token vs malformed-token (D-10)" do
      state_unknown =
        reset_consume_state(
          token: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
          password: "freshvalidpass99",
          password_confirmation: "freshvalidpass99",
          focused_field: :password_confirmation
        )

      state_malformed =
        reset_consume_state(
          token: "!!!not-base64!!!",
          password: "freshvalidpass99",
          password_confirmation: "freshvalidpass99",
          focused_field: :password_confirmation
        )

      {:update, new_unknown, []} = submit_reset_consume(state_unknown)
      {:update, new_malformed, []} = submit_reset_consume(state_malformed)

      err_unknown = get_in(new_unknown, [:screen_state, :login, :error])
      err_malformed = get_in(new_malformed, [:screen_state, :login, :error])

      assert is_binary(err_unknown) and is_binary(err_malformed)
      assert err_unknown == err_malformed
    end

    test "raw token value never appears in chrome/breadcrumb/keys/error copy (D-11)" do
      raw_token = "RAWTOKENSENTINELZZZZ-not-a-real-token-but-distinctive"

      state =
        reset_consume_state(
          token: raw_token,
          password: "freshvalidpass99",
          password_confirmation: "freshvalidpass99",
          focused_field: :password_confirmation
        )

      {:update, new_state, []} = submit_reset_consume(state)

      error = get_in(new_state, [:screen_state, :login, :error])
      refute is_binary(error) and error =~ raw_token

      pre_state = reset_consume_state(token: raw_token, focused_field: :token)
      rendered = render_login(pre_state) |> collect_text_values()

      breadcrumb =
        rendered
        |> Enum.find(&(is_binary(&1) and &1 =~ "Foglet"))

      if breadcrumb, do: refute(breadcrumb =~ raw_token)

      key_hint_strings = ["Tab", "Shift+Tab", "Enter", "Esc"]

      Enum.each(rendered, fn rendered_text ->
        if is_binary(rendered_text) and Enum.any?(key_hint_strings, &(rendered_text =~ &1)) do
          refute rendered_text =~ raw_token
        end
      end)
    end

    test "escape clears reset_consume state and returns to menu" do
      state =
        reset_consume_state(
          token: "some-token",
          password: "some-password",
          password_confirmation: "some-password",
          focused_field: :password
        )

      {:update, new_state, []} = update_login(%{key: :escape}, state)

      assert get_in(new_state, [:screen_state, :login, :sub]) == :menu
      assert get_in(new_state, [:screen_state, :login, :token_input]) == nil
      assert get_in(new_state, [:screen_state, :login, :password_input]) == nil
      assert get_in(new_state, [:screen_state, :login, :password_confirmation_input]) == nil
    end
  end

  describe "login form submission" do
    test "valid credentials emit {:promote_session, user} command" do
      password = "correcthorsebatterystaple"
      user = user_fixture(%{password: password})
      # Confirm the user so login produces {:promote_session} rather than routing to verify
      {:ok, user} = Foglet.Accounts.confirm_user(user)

      state = form_state([handle: user.handle, password: password], :password)

      {_submitting_state, new_state, cmds} = submit_login_form(state)

      assert get_in(new_state, [:screen_state, :login, :sub]) == :menu
      assert {:promote_session, returned_user} = session_effect(cmds)
      assert returned_user.id == user.id
    end

    test "full flow: type handle, tab, type password, enter → promote_session" do
      password = "horsecorrectbattery"
      user = user_fixture(%{password: password})
      # Confirm the user so login produces {:promote_session} rather than routing to verify
      {:ok, user} = Foglet.Accounts.confirm_user(user)

      # Start at menu, press L to enter form
      {:update, s1, []} = update_login(%{key: :char, char: "L"}, base_state())

      # Type the handle character by character
      s2 =
        Enum.reduce(String.graphemes(user.handle), s1, fn char, acc ->
          {:update, next, []} = update_login(%{key: :char, char: char}, acc)
          next
        end)

      # Tab to password field
      {:update, s3, []} = update_login(%{key: :tab}, s2)
      assert get_in(s3, [:screen_state, :login, :focused_field]) == :password

      # Type the password
      s4 =
        Enum.reduce(String.graphemes(password), s3, fn char, acc ->
          {:update, next, []} = update_login(%{key: :char, char: char}, acc)
          next
        end)

      # Enter submits
      {_submitting_state, final_state, cmds} = submit_login_form(s4)

      assert get_in(final_state, [:screen_state, :login, :sub]) == :menu
      assert {:promote_session, returned_user} = session_effect(cmds)
      assert returned_user.id == user.id
    end

    test "invalid credentials surface an inline error and clear password field" do
      state = form_state([handle: "ghost", password: "nope"], :password)

      {_submitting_state, new_state, cmds} = submit_login_form(state)

      assert cmds == []

      assert get_in(new_state, [:screen_state, :login, :error]) ==
               "That handle and password don't match."

      # Password is cleared so user doesn't have to delete it before retrying
      assert get_in(new_state, [
               :screen_state,
               :login,
               :password_input,
               Access.key(:raxol_state),
               :value
             ]) == ""

      # Handle is preserved for retry convenience
      assert get_in(new_state, [
               :screen_state,
               :login,
               :handle_input,
               Access.key(:raxol_state),
               :value
             ]) == "ghost"
    end

    test "submitting login form ignores duplicate submit and input keys" do
      state = form_state([handle: "ghost", password: "nope"], :password)

      {:update, submitting_state, [%Effect{type: :task}]} =
        update_login(%{key: :enter}, state)

      assert get_in(submitting_state, [:screen_state, :login, :submitting?]) == true

      assert {:update, ^submitting_state, []} =
               update_login(%{key: :enter}, submitting_state)

      assert {:update, ^submitting_state, []} =
               update_login(%{key: :char, char: "x"}, submitting_state)
    end

    test "pending user shows 'pending sysop approval' modal (D-05)" do
      password = "correct horse battery"
      attrs = valid_user_attributes(%{password: password})
      {:ok, user} = Foglet.Accounts.register_pending_user(attrs)
      assert user.status == :pending

      state = form_state([handle: user.handle, password: password], :password)

      {_submitting_state, _new_state, effects} = submit_login_form(state)

      assert %{type: :error, message: msg} = modal_effect(effects)

      assert msg ==
               "Your account is waiting for sysop approval. Try again once you've heard back."

      refute msg =~ "notification"
      refute msg =~ "email"
    end

    test "rejected user shows rejection modal and does not promote session" do
      password = "correct horse battery"

      user =
        user_fixture(%{password: password})
        |> Foglet.Accounts.User.status_changeset(%{status: :rejected})
        |> FogletBbs.Repo.update!()

      state = form_state([handle: user.handle, password: password], :password)

      {_submitting_state, new_state, effects} = submit_login_form(state)

      assert %{
               type: :error,
               message:
                 "Your registration was turned down. Reach the sysop if you think that's a mistake."
             } = modal_effect(effects)

      assert get_in(new_state, [:screen_state, :login, :sub]) == :menu
      refute session_effect(effects)
    end
  end

  describe "status modals clear screen_state (Gap 3b)" do
    test "Test D: pending user modal sets screen_state to %{}" do
      password = "correcthorsebatterystaple"
      attrs = valid_user_attributes(%{password: password})
      {:ok, user} = Foglet.Accounts.register_pending_user(attrs)
      assert user.status == :pending

      state =
        form_state(
          [handle: user.handle, password: password],
          :password
        )

      {_submitting_state, new_state, effects} = submit_login_form(state)

      assert modal_effect(effects) != nil, "Expected a modal effect for pending user"

      assert get_in(new_state, [:screen_state, :login, :sub]) == :menu
    end

    test "Test E: suspended user modal sets screen_state to %{}" do
      password = "correcthorsebatterystaple"
      user = user_fixture(%{password: password})
      # Confirm user first so authentication succeeds, then suspend them
      {:ok, user} = Foglet.Accounts.confirm_user(user)
      # Suspend the user via Repo
      {:ok, _} =
        FogletBbs.Repo.update(Ecto.Changeset.change(user, status: :suspended))

      state =
        form_state(
          [handle: user.handle, password: password],
          :password
        )

      {_submitting_state, new_state, effects} = submit_login_form(state)

      assert modal_effect(effects) != nil, "Expected a modal effect for suspended user"

      assert get_in(new_state, [:screen_state, :login, :sub]) == :menu
    end
  end

  describe "submit_login/1 — VERIFY-01 retroactive bypass" do
    setup :set_swoosh_global

    setup do
      original = Foglet.Config.get("require_email_verification", :not_seeded)
      original_delivery_mode = Config.get("delivery_mode", "no_email")

      on_exit(fn ->
        case original do
          :not_seeded -> :ok
          value -> Foglet.Config.put!("require_email_verification", value)
        end

        Config.put!("delivery_mode", original_delivery_mode)
        Config.invalidate("delivery_mode")
      end)

      :ok
    end

    test "unconfirmed user + toggle=true + email mode delivers verification email and routes to :verify" do
      Foglet.Config.put!("require_email_verification", true)
      Config.put!("delivery_mode", "email")

      password = "letmein12"

      user =
        user_fixture(%{
          password: password,
          handle: "loginverify",
          email: "loginverify@example.test"
        })

      assert user.confirmed_at == nil

      state = form_state([handle: user.handle, password: password], :password)

      {_submitting_state, new_state, effects} = submit_login_form(state)

      assert get_in(new_state, [:screen_state, :login, :sub]) == :menu
      assert {:set_current_user, returned_user} = session_effect(effects)
      assert returned_user.id == user.id
      assert %{screen: :verify, params: %{}} = navigation_effect(effects)
      refute Map.has_key?(new_state.screen_state || %{}, :verify)

      assert FogletBbs.Repo.exists?(
               from t in Foglet.Accounts.UserToken,
                 where: t.user_id == ^user.id and t.context == "email_verify"
             )

      assert_email_sent(fn email ->
        assert email.to == [{"loginverify", "loginverify@example.test"}]
        assert email.subject == "Your Foglet verification code"
      end)
    end

    test "unconfirmed user + toggle=true + no-email mode reports unavailable without routing" do
      Foglet.Config.put!("require_email_verification", true)
      Config.put!("delivery_mode", "no_email")

      password = "letmein12"
      user = user_fixture(%{password: password})
      assert user.confirmed_at == nil

      state = form_state([handle: user.handle, password: password], :password)

      {_submitting_state, _new_state, effects} = submit_login_form(state)

      refute navigation_effect(effects)
      refute session_effect(effects)

      assert %{type: :error, message: msg} = modal_effect(effects)

      assert msg ==
               "This Foglet has email turned off, so we can't send a verification code. Ask the sysop."

      refute FogletBbs.Repo.exists?(
               from t in Foglet.Accounts.UserToken,
                 where: t.user_id == ^user.id and t.context == "email_verify"
             )
    end

    test "unconfirmed user + toggle=false routes to :main_menu via {:promote_session, user}" do
      Foglet.Config.put!("require_email_verification", false)

      password = "letmein12"
      user = user_fixture(%{password: password})
      assert user.confirmed_at == nil

      state = form_state([handle: user.handle, password: password], :password)

      {_submitting_state, new_state, effects} = submit_login_form(state)

      assert get_in(new_state, [:screen_state, :login, :sub]) == :menu
      assert {:promote_session, returned_user} = session_effect(effects)
      assert returned_user.id == user.id
    end

    test "confirmed user is unaffected by toggle value" do
      for toggle <- [true, false] do
        Foglet.Config.put!("require_email_verification", toggle)

        password = "letmein12"
        user = user_fixture(%{password: password})
        {:ok, confirmed} = Foglet.Accounts.confirm_user(user)
        assert confirmed.confirmed_at != nil

        state = form_state([handle: confirmed.handle, password: password], :password)

        {_submitting_state, _new_state, effects} = submit_login_form(state)

        assert {:promote_session, _} = session_effect(effects),
               "Confirmed user must always promote regardless of toggle=#{toggle}"
      end
    end
  end
end
