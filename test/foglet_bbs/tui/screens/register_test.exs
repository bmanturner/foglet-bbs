defmodule Foglet.TUI.Screens.RegisterTest do
  use FogletBbs.DataCase, async: false

  alias Foglet.Accounts.User
  alias Foglet.Config
  alias Foglet.TUI.{Context, Effect, TextWidth}
  alias Foglet.TUI.Screens.Register
  alias Foglet.TUI.Screens.Register.State, as: RegisterState
  alias Foglet.TUI.Widgets.Auth.AuthForm
  alias Foglet.TUI.Widgets.Input.TextInput

  defmodule AccountsRecorder do
    def register_user(attrs), do: {:ok, %{id: "user", handle: attrs.handle, attrs: attrs}}
    def register_pending_user(attrs), do: {:ok, %{id: "pending-user", attrs: attrs}}
    def post_login_screen(_user), do: :main_menu
  end

  import FogletBbs.AccountsFixtures
  import Swoosh.TestAssertions

  defp context(mode \\ "open", extra \\ []) do
    Context.new(
      Keyword.merge(
        [
          current_user: nil,
          session_context: %{registration_mode: mode},
          terminal_size: {80, 24}
        ],
        extra
      )
    )
  end

  defp text_input_at_end(ti) do
    {ti_end, _action} = TextInput.handle_event(%{key: :end}, ti)
    ti_end
  end

  defp combined_state(fields, focused), do: combined_state(fields, focused, "open")

  defp combined_state(fields, focused, mode) do
    %{
      mode: mode,
      step: :combined,
      focused_field: focused,
      invite_code_input: TextInput.init([]),
      handle_input:
        TextInput.init(value: Keyword.get(fields, :handle, ""), max_length: User.handle_max())
        |> text_input_at_end(),
      email_input: TextInput.init(value: Keyword.get(fields, :email, "")) |> text_input_at_end(),
      password_input:
        TextInput.init(value: Keyword.get(fields, :password, ""), mask_char: "*")
        |> text_input_at_end(),
      confirm_input:
        TextInput.init(value: Keyword.get(fields, :confirm, ""), mask_char: "*")
        |> text_input_at_end(),
      save_offered_ssh_key?: Keyword.get(fields, :save_offered_ssh_key?, false),
      collected: Keyword.get(fields, :collected, %{}),
      error: Keyword.get(fields, :error, nil)
    }
  end

  defp invite_state(invite_code \\ "") do
    %{
      RegisterState.for_mode("invite_only")
      | invite_code_input: TextInput.init(value: invite_code) |> text_input_at_end()
    }
  end

  defp task_effect(effects, op) do
    Enum.find(effects, &match?(%Effect{type: :task, payload: %{op: ^op}}, &1))
  end

  defp modal_effect(effects) do
    Enum.find(effects, &match?(%Effect{type: :modal, payload: {:open, _}}, &1))
  end

  defp session_effect(effects) do
    Enum.find(effects, &match?(%Effect{type: :session}, &1))
  end

  defp navigate_effect(effects) do
    Enum.find(effects, &match?(%Effect{type: :navigate}, &1))
  end

  defp run_register_task(%Effect{payload: %{fun: fun}}), do: fun.()

  defp collect_panels(tree), do: tree |> collect_panels([]) |> Enum.reverse()

  defp collect_panels(nil, acc), do: acc
  defp collect_panels(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect_panels/2)

  defp collect_panels(%{type: :panel, children: children} = node, acc),
    do: collect_panels(children, [node | acc])

  defp collect_panels(%{children: children}, acc), do: collect_panels(children, acc)
  defp collect_panels(_other, acc), do: acc

  defp collect_text(tree), do: tree |> collect_text([]) |> Enum.reverse()

  defp collect_text(nil, acc), do: acc
  defp collect_text(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect_text/2)

  defp collect_text(%{type: :text, content: text}, acc) when is_binary(text),
    do: [text | acc]

  defp collect_text(%{children: children}, acc), do: collect_text(children, acc)
  defp collect_text(_other, acc), do: acc

  defp sysop_user_fixture do
    user = user_fixture()
    {:ok, promoted} = user |> Ecto.Changeset.change(role: :sysop) |> FogletBbs.Repo.update()
    promoted
  end

  setup do
    Config.init_cache()
    original_mode = Config.get("registration_mode", "open")
    original_delivery_mode = Config.get("delivery_mode", "no_email")
    original_require_verification = Config.get("require_email_verification", true)

    on_exit(fn ->
      Config.put!("registration_mode", original_mode)
      Config.put!("delivery_mode", original_delivery_mode)
      Config.put!("require_email_verification", original_require_verification)
      Config.invalidate("registration_mode")
      Config.invalidate("delivery_mode")
      Config.invalidate("require_email_verification")
    end)

    :ok
  end

  describe "init/render" do
    test "Register.init/1 builds mode-aware screen-local state" do
      assert Register.init(context("open")).step == :combined
      assert Register.init(context("sysop_approved")).step == :combined
      assert Register.init(context("invite_only")).step == :invite_code
    end

    test "Register.render/2 renders local state without App-shaped input" do
      assert Register.render(Register.init(context("open")), context("open"))
      assert Register.render(Register.init(context("invite_only")), context("invite_only"))

      assert Register.render(
               Register.init(
                 context("open",
                   session_context: %{offered_ssh_public_key: default_ssh_public_key()}
                 )
               ),
               context("open",
                 session_context: %{
                   registration_mode: "open",
                   offered_ssh_public_key: default_ssh_public_key()
                 }
               )
             )
    end

    test "offered SSH key fingerprint line is truncated within the AuthForm panel" do
      ctx =
        context("open",
          session_context: %{
            registration_mode: "open",
            offered_ssh_public_key: default_ssh_public_key()
          }
        )

      tree = Register.render(Register.init(ctx), ctx)
      # Panel width minus side borders (-2) minus the column's padding: 1
      # on each side (-2). Anything wider overwrites the inner right
      # border at 80x24 (FOG-702).
      max_width = AuthForm.default_width() - 4

      fingerprint_line =
        tree
        |> collect_text()
        |> Enum.find(&String.starts_with?(&1, "  Fingerprint: "))

      assert fingerprint_line, "expected a Fingerprint: line in the rendered tree"
      assert TextWidth.display_width(fingerprint_line) <= max_width
      assert String.starts_with?(fingerprint_line, "  Fingerprint: SHA256:")
      assert String.ends_with?(fingerprint_line, "…")
    end

    test "invite and combined steps render in shared auth cards" do
      [invite_panel] = Register.render(invite_state(), context("invite_only")) |> collect_panels()
      assert invite_panel.attrs.title == "Invite required"
      assert invite_panel.attrs.width == 46

      [combined_panel] =
        Register.render(combined_state([], :handle), context("open")) |> collect_panels()

      assert combined_panel.attrs.title == "Create account"
      assert combined_panel.attrs.width == 46
    end
  end

  describe "Register.update/3 invite step" do
    test "escape requests login navigation" do
      {local_state, effects} = Register.update({:key, %{key: :escape}}, invite_state(), context())

      assert local_state.step == :invite_code
      assert %Effect{type: :navigate, payload: %{screen: :login}} = navigate_effect(effects)
    end

    test "typing edits the invite-code input" do
      {local_state, []} =
        Register.update({:key, %{key: :char, char: "X"}}, invite_state(), context("invite_only"))

      assert local_state.invite_code_input.raxol_state.value == "X"
    end

    test "valid invite code advances to combined form without App delegation" do
      invite = invite_fixture()

      {local_state, []} =
        Register.update(
          {:wizard, {:submit_step, :invite_code, invite.code}},
          invite_state(),
          context("invite_only")
        )

      assert local_state.step == :combined
      assert local_state.focused_field == :handle
      assert local_state.collected.invite_code == invite.code
      assert local_state.error == nil
    end

    test "invalid invite code stays on invite step with local error" do
      {local_state, []} =
        Register.update(
          {:wizard, {:submit_step, :invite_code, "short"}},
          invite_state(),
          context("invite_only")
        )

      assert local_state.step == :invite_code
      assert local_state.error == "Invalid or expired invite code."
    end

    test "well-formed but unknown invite code stays on invite step" do
      {local_state, []} =
        Register.update(
          {:wizard, {:submit_step, :invite_code, "Zz9Aa1"}},
          invite_state(),
          context("invite_only")
        )

      assert local_state.step == :invite_code
      assert local_state.error == "Invalid or expired invite code."
    end

    test "revoked invite code stays on invite step instead of advancing" do
      issuer = sysop_user_fixture()
      invite = invite_fixture(issuer)
      {:ok, _} = Foglet.Accounts.Invites.revoke_invite(issuer, invite.code)

      {local_state, []} =
        Register.update(
          {:wizard, {:submit_step, :invite_code, invite.code}},
          invite_state(invite.code),
          context("invite_only")
        )

      assert local_state.step == :invite_code
      assert local_state.error == "Invalid or expired invite code."
    end
  end

  describe "Register.update/3 combined form" do
    test "tab and enter advance focus through local reducer state" do
      {local_state, []} =
        Register.update({:key, %{key: :tab}}, combined_state([], :handle), context())

      assert local_state.focused_field == :email

      {local_state, []} = Register.update({:key, %{key: :enter}}, local_state, context())
      assert local_state.focused_field == :password
    end

    test "shift tab retreats focus through local reducer state" do
      {local_state, []} =
        Register.update(
          {:key, %{key: :tab, shift: true}},
          combined_state([], :password),
          context()
        )

      assert local_state.focused_field == :email

      {local_state, []} =
        Register.update({:key, %{key: :backtab}}, local_state, context())

      assert local_state.focused_field == :handle
    end

    test "plain tab from password still advances to confirm password" do
      {local_state, []} =
        Register.update({:key, %{key: :tab}}, combined_state([], :password), context())

      assert local_state.focused_field == :confirm_password
    end

    test "offered SSH key opt-in joins tab order only when session context carries a key" do
      {local_state, []} =
        Register.update(
          {:key, %{key: :tab}},
          combined_state([], :confirm_password),
          context()
        )

      assert local_state.focused_field == :handle

      {local_state, []} =
        Register.update(
          {:key, %{key: :tab}},
          combined_state([], :confirm_password),
          context("open",
            session_context: %{
              registration_mode: "open",
              offered_ssh_public_key: default_ssh_public_key()
            }
          )
        )

      assert local_state.focused_field == :ssh_key_opt_in

      {local_state, []} =
        Register.update(
          {:key, %{key: :tab, shift: true}},
          local_state,
          context("open",
            session_context: %{
              registration_mode: "open",
              offered_ssh_public_key: default_ssh_public_key()
            }
          )
        )

      assert local_state.focused_field == :confirm_password
    end

    test "space toggles offered SSH key opt-in while enter keeps next-submit semantics" do
      context =
        context("open",
          session_context: %{
            registration_mode: "open",
            offered_ssh_public_key: default_ssh_public_key()
          }
        )

      state = combined_state([password: "sekret01", confirm: "sekret01"], :confirm_password)

      {local_state, []} = Register.update({:key, %{key: :enter}}, state, context)
      assert local_state.focused_field == :ssh_key_opt_in
      refute local_state.save_offered_ssh_key?

      {local_state, effects} = Register.update({:key, %{key: :enter}}, local_state, context)
      refute local_state.save_offered_ssh_key?
      assert %Effect{type: :task, payload: %{op: :register}} = task_effect(effects, :register)

      {local_state, []} = Register.update({:key, %{key: :space}}, local_state, context)
      assert local_state.save_offered_ssh_key?
    end

    test "character input edits only the focused field" do
      {local_state, []} =
        Register.update({:key, %{key: :char, char: "a"}}, combined_state([], :handle), context())

      assert local_state.handle_input.raxol_state.value == "a"
      assert local_state.email_input.raxol_state.value == ""
    end

    test "mismatched passwords remain local validation failure" do
      state = combined_state([password: "sekret01", confirm: "different"], :confirm_password)

      {local_state, []} = Register.update({:key, %{key: :enter}}, state, context())

      assert local_state.error == "Those two passwords don't match."
      assert local_state.focused_field == :confirm_password
    end

    test "matching passwords request a register task effect" do
      state =
        combined_state(
          [
            handle: "taskreg",
            email: "taskreg@example.test",
            password: "sekret01",
            confirm: "sekret01"
          ],
          :confirm_password
        )

      {_local_state, effects} = Register.update({:key, %{key: :enter}}, state, context())

      assert %Effect{type: :task, payload: %{op: :register, screen_key: :register}} =
               task_effect(effects, :register)
    end

    test "offered SSH key is included in open registration payload only when checked" do
      offered_key = default_ssh_public_key()

      context =
        context("open",
          session_context: %{registration_mode: "open", offered_ssh_public_key: offered_key},
          domain: %{accounts: AccountsRecorder}
        )

      unchecked =
        combined_state(
          [
            handle: "nokeyreg",
            email: "nokeyreg@example.test",
            password: "sekret01",
            confirm: "sekret01",
            save_offered_ssh_key?: false
          ],
          :ssh_key_opt_in
        )

      {_submitting, effects} = Register.update({:key, %{key: :enter}}, unchecked, context)
      assert {:ok, user, :main_menu, nil} = run_register_task(task_effect(effects, :register))
      refute Map.has_key?(user.attrs, :offered_ssh_public_key)

      checked = %{
        unchecked
        | save_offered_ssh_key?: true,
          handle_input: TextInput.init(value: "keyreg") |> text_input_at_end()
      }

      {_submitting, effects} = Register.update({:key, %{key: :enter}}, checked, context)
      assert {:ok, user, :main_menu, nil} = run_register_task(task_effect(effects, :register))
      assert user.attrs.offered_ssh_public_key == offered_key
    end

    test "offered SSH key is included in sysop-approved registration payload when checked" do
      offered_key = default_ssh_public_key()

      context =
        context("sysop_approved",
          session_context: %{
            registration_mode: "sysop_approved",
            offered_ssh_public_key: offered_key
          },
          domain: %{accounts: AccountsRecorder}
        )

      state =
        combined_state(
          [
            handle: "pendingkey",
            email: "pendingkey@example.test",
            password: "sekret01",
            confirm: "sekret01",
            save_offered_ssh_key?: true
          ],
          :ssh_key_opt_in,
          "sysop_approved"
        )

      {_submitting, effects} = Register.update({:key, %{key: :enter}}, state, context)
      assert {:ok, :pending_approval, user} = run_register_task(task_effect(effects, :register))
      assert user.attrs.offered_ssh_public_key == offered_key
    end
  end

  describe "registration outcomes" do
    setup :set_swoosh_global

    test "open registration routes to Verify after attempted email delivery" do
      Config.put!("registration_mode", "open")
      Config.put!("delivery_mode", "email")
      Config.put!("require_email_verification", true)

      state =
        combined_state(
          [
            handle: "mailreg",
            email: "mailreg@example.test",
            password: "sekret01",
            confirm: "sekret01"
          ],
          :confirm_password
        )

      {_submitting, effects} = Register.update({:key, %{key: :enter}}, state, context("open"))
      result = run_register_task(task_effect(effects, :register))

      {local_state, effects} =
        Register.update({:task_result, :register, {:ok, result}}, state, context())

      assert local_state == RegisterState.default()
      assert %Effect{type: :session, payload: {:set_current_user, user}} = session_effect(effects)
      assert user.handle == "mailreg"
      assert %Effect{type: :navigate, payload: %{screen: :verify}} = navigate_effect(effects)
      assert_email_sent(subject: "Your Foglet verification code")
    end

    test "no-email verification delivery failure opens honest error modal" do
      Config.put!("registration_mode", "open")
      Config.put!("delivery_mode", "no_email")
      Config.put!("require_email_verification", true)

      state =
        combined_state(
          [
            handle: "nomailreg",
            email: "nomailreg@example.test",
            password: "sekret01",
            confirm: "sekret01"
          ],
          :confirm_password
        )

      {_submitting, effects} = Register.update({:key, %{key: :enter}}, state, context("open"))
      result = run_register_task(task_effect(effects, :register))

      {_local_state, effects} =
        Register.update({:task_result, :register, {:ok, result}}, state, context())

      assert %Effect{type: :modal, payload: {:open, modal}} = modal_effect(effects)
      assert modal.type == :error

      assert modal.message ==
               "This Foglet has email turned off, so we can't send a verification code. Ask the sysop."

      refute_email_sent()
    end

    test "open registration with verification disabled promotes the session" do
      Config.put!("registration_mode", "open")
      Config.put!("delivery_mode", "no_email")
      Config.put!("require_email_verification", false)

      state =
        combined_state(
          [
            handle: "openmain",
            email: "openmain@example.test",
            password: "sekret01",
            confirm: "sekret01"
          ],
          :confirm_password
        )

      {_submitting, effects} = Register.update({:key, %{key: :enter}}, state, context("open"))
      result = run_register_task(task_effect(effects, :register))

      {_local_state, effects} =
        Register.update({:task_result, :register, {:ok, result}}, state, context())

      assert %Effect{type: :session, payload: {:promote_session, user}} =
               session_effect(effects)

      assert user.handle == "openmain"
    end

    test "invite revoked between wizard steps surfaces friendly modal" do
      Config.put!("delivery_mode", "no_email")
      Config.put!("require_email_verification", false)
      Config.put!("registration_mode", "open")

      issuer = sysop_user_fixture()
      invite = invite_fixture(issuer)
      Config.put!("registration_mode", "invite_only")

      state =
        combined_state(
          [
            handle: "racer",
            email: "racer@example.test",
            password: "sekret01",
            confirm: "sekret01",
            collected: %{invite_code: invite.code}
          ],
          :confirm_password,
          "invite_only"
        )

      {_submitting, effects} =
        Register.update({:key, %{key: :enter}}, state, context("invite_only"))

      {:ok, _} = Foglet.Accounts.Invites.revoke_invite(issuer, invite.code)
      result = run_register_task(task_effect(effects, :register))

      {local_state, effects} =
        Register.update({:task_result, :register, {:ok, result}}, state, context("invite_only"))

      assert %Effect{type: :modal, payload: {:open, modal}} = modal_effect(effects)
      assert modal.type == :error

      assert modal.message ==
               "Invite is no longer valid. Please request a new code from the sysop."

      assert local_state.step == :invite_code
      assert local_state.focused_field == :invite_code
      refute local_state.error
    end

    test "invite-only registration submits the collected invite code" do
      Config.put!("delivery_mode", "no_email")
      Config.put!("require_email_verification", false)

      invite = invite_fixture()
      Config.put!("registration_mode", "invite_only")

      state =
        combined_state(
          [
            handle: "invited",
            email: "invited@example.test",
            password: "sekret01",
            confirm: "sekret01",
            collected: %{invite_code: invite.code}
          ],
          :confirm_password,
          "invite_only"
        )

      {_submitting, effects} =
        Register.update({:key, %{key: :enter}}, state, context("invite_only"))

      assert {:ok, user, :main_menu, nil} = run_register_task(task_effect(effects, :register))
      assert user.handle == "invited"
    end

    test "sysop-approved registration requests pending-approval termination (email mode)" do
      Config.put!("registration_mode", "sysop_approved")
      Config.put!("delivery_mode", "email")

      state =
        combined_state(
          [
            handle: "pendingcopy",
            email: "pendingcopy@example.test",
            password: "sekret01",
            confirm: "sekret01"
          ],
          :confirm_password,
          "sysop_approved"
        )

      {_submitting, effects} =
        Register.update({:key, %{key: :enter}}, state, context("sysop_approved"))

      result = run_register_task(task_effect(effects, :register))

      {_local_state, effects} =
        Register.update(
          {:task_result, :register, {:ok, result}},
          state,
          context("sysop_approved")
        )

      assert %Effect{type: :modal, payload: {:open, modal}} = modal_effect(effects)
      assert modal.title == "Account waiting for approval"
      assert modal.message =~ "pending sysop approval"
      assert modal.message =~ "email"

      assert %Effect{
               type: :session,
               payload: {:terminate_after_modal, :pending_approval}
             } = session_effect(effects)
    end

    test "sysop-approved pending-approval modal omits email under no_email delivery" do
      Config.put!("registration_mode", "sysop_approved")
      Config.put!("delivery_mode", "no_email")

      state =
        combined_state(
          [
            handle: "pendingnoemail",
            email: "pendingnoemail@example.test",
            password: "sekret01",
            confirm: "sekret01"
          ],
          :confirm_password,
          "sysop_approved"
        )

      {_submitting, effects} =
        Register.update({:key, %{key: :enter}}, state, context("sysop_approved"))

      result = run_register_task(task_effect(effects, :register))

      {_local_state, effects} =
        Register.update(
          {:task_result, :register, {:ok, result}},
          state,
          context("sysop_approved")
        )

      assert %Effect{type: :modal, payload: {:open, modal}} = modal_effect(effects)
      assert modal.title == "Account waiting for approval"
      assert modal.message =~ "pending sysop approval"
      assert modal.message =~ "contact you"
      refute modal.message =~ ~r/email/i
    end

    test "registration validation failures return to the first field with changeset text" do
      user_fixture(%{email: "taken@example.test"})

      state =
        combined_state(
          [
            handle: "takenmail",
            email: "taken@example.test",
            password: "sekret01",
            confirm: "sekret01"
          ],
          :confirm_password
        )

      {_submitting, effects} = Register.update({:key, %{key: :enter}}, state, context("open"))
      result = run_register_task(task_effect(effects, :register))

      {local_state, []} =
        Register.update({:task_result, :register, {:ok, result}}, state, context())

      assert local_state.focused_field == :handle
      assert local_state.error =~ "email"
    end
  end
end
