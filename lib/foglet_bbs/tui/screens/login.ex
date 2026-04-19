defmodule Foglet.TUI.Screens.Login do
  @moduledoc """
  Login-or-register entry screen (SSH-04, D-22).

  Respects runtime config:
    * registration_mode == "disabled" → hides [R] Register (D-06)
    * any other value → shows all three options

  Sub-states (stored in state.screen_state[:login]):
    * :menu          — showing [L]/[R]/[Q] menu
    * :login_form    — collecting handle+password

  Login form state shape:
    %{
      sub: :login_form,
      form: %{handle: "", password: "", error: nil},
      focused_field: :handle | :password
    }
  """

  alias Foglet.{Accounts, Config}
  alias Foglet.TUI.Widgets.KeyBar

  import Raxol.Core.Renderer.View

  @menu_keys [{"L", "Login"}, {"R", "Register"}, {"Q", "Quit"}]
  @menu_keys_no_register [{"L", "Login"}, {"Q", "Quit"}]

  @spec render(map()) :: any()
  def render(state) do
    mode = registration_mode(state)
    sub = sub_state(state)

    box style: %{border: :single, padding: 1} do
      column style: %{gap: 0} do
        [
          text(" Foglet BBS — Login ", style: [:bold]),
          divider(),
          case sub do
            :login_form -> render_login_form(state)
            _ -> render_menu(mode)
          end,
          KeyBar.render(keys_for(sub, mode))
        ]
      end
    end
  end

  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  # Route all keys through sub-state so form input gets every character.
  def handle_key(key, state) do
    case sub_state(state) do
      :login_form -> handle_form_key(key, state)
      _ -> handle_menu_key(key, state)
    end
  end

  defp handle_menu_key(%{key: "q"}, state), do: {:update, state, [{:terminate, :user_quit}]}
  defp handle_menu_key(%{key: "Q"}, state), do: {:update, state, [{:terminate, :user_quit}]}
  defp handle_menu_key(%{key: "l"}, state), do: enter_login_form(state)
  defp handle_menu_key(%{key: "L"}, state), do: enter_login_form(state)
  defp handle_menu_key(%{key: "r"}, state), do: maybe_register(state)
  defp handle_menu_key(%{key: "R"}, state), do: maybe_register(state)
  defp handle_menu_key(_key, _state), do: :no_match

  # --- Private ---

  # Form key handlers — only reached when sub == :login_form

  # Tab cycles focus between :handle and :password
  defp handle_form_key(%{key: "tab"}, state) do
    login_ss = get_login_ss(state)
    focused = Map.get(login_ss, :focused_field, :handle)
    new_focused = if focused == :handle, do: :password, else: :handle
    new_login_ss = Map.put(login_ss, :focused_field, new_focused)
    {:update, put_login_ss(state, new_login_ss), []}
  end

  # Enter: submit if focused on password; advance focus if on handle
  defp handle_form_key(%{key: "enter"}, state) do
    login_ss = get_login_ss(state)
    focused = Map.get(login_ss, :focused_field, :handle)

    if focused == :password do
      submit_login(state)
    else
      new_login_ss = Map.put(login_ss, :focused_field, :password)
      {:update, put_login_ss(state, new_login_ss), []}
    end
  end

  # Backspace: delete last grapheme from focused field
  defp handle_form_key(%{key: "backspace"}, state) do
    login_ss = get_login_ss(state)
    focused = Map.get(login_ss, :focused_field, :handle)
    form = Map.get(login_ss, :form) || %{handle: "", password: "", error: nil}

    current_val = Map.get(form, focused, "")
    new_val = drop_last_grapheme(current_val)

    new_form = Map.put(form, focused, new_val)
    new_login_ss = Map.put(login_ss, :form, new_form)
    {:update, put_login_ss(state, new_login_ss), []}
  end

  # Escape: return to menu sub, clear form state
  defp handle_form_key(%{key: "escape"}, state) do
    new_login_ss = %{sub: :menu, form: %{handle: "", password: "", error: nil}}
    {:update, put_login_ss(state, new_login_ss), []}
  end

  # Binary-key catch-all: handles space + single-character input.
  #
  # Note: the multi-char named keys (tab, enter, backspace, escape) are matched
  # by the clauses above, so by the time we get here we have either:
  #   * "space" (spacebar, converted to a literal " " by the normalization layer)
  #   * a single grapheme character (letter, digit, punctuation, unicode)
  #   * some other multi-char name we don't care about (→ :no_match)
  #
  # String.length/1 is NOT guard-safe, so we move the length check into the body.
  # Using String.length (grapheme count) rather than byte_size/1 ensures multibyte
  # unicode characters are accepted correctly (avoids the composer bug from task #13).
  #
  # FUTURE (task #16): the "space" special-case can be removed once the
  # key normalization layer converts spacebar events to a literal " ".
  defp handle_form_key(%{key: key}, state) when is_binary(key) do
    cond do
      key == "space" -> append_to_focused(state, " ")
      String.length(key) == 1 -> append_to_focused(state, key)
      true -> :no_match
    end
  end

  defp handle_form_key(_key, _state), do: :no_match

  defp append_to_focused(state, char) do
    login_ss = get_login_ss(state)
    focused = Map.get(login_ss, :focused_field, :handle)
    form = Map.get(login_ss, :form) || %{handle: "", password: "", error: nil}

    current_val = Map.get(form, focused, "")
    new_form = Map.put(form, focused, current_val <> char)
    new_login_ss = Map.put(login_ss, :form, new_form)
    {:update, put_login_ss(state, new_login_ss), []}
  end

  defp drop_last_grapheme(""), do: ""

  defp drop_last_grapheme(str) do
    graphemes = String.graphemes(str)
    graphemes |> Enum.take(length(graphemes) - 1) |> Enum.join()
  end

  defp registration_mode(state) do
    ctx = Map.get(state, :session_context) || %{}

    case Map.get(ctx, :registration_mode) do
      nil -> safe_config_get("registration_mode", "open")
      mode -> mode
    end
  end

  defp safe_config_get(key, default) do
    Config.get!(key)
  rescue
    _ -> default
  end

  defp sub_state(state) do
    login_ss = Map.get(state.screen_state || %{}, :login) || %{}
    Map.get(login_ss, :sub) || :menu
  end

  defp get_login_ss(state) do
    Map.get(state.screen_state || %{}, :login) || %{}
  end

  defp put_login_ss(state, login_ss) do
    new_screen_state = Map.put(state.screen_state || %{}, :login, login_ss)
    %{state | screen_state: new_screen_state}
  end

  defp keys_for(:login_form, _),
    do: [{"Tab", "Switch field"}, {"Enter", "Submit/Next"}, {"Esc", "Cancel"}]

  defp keys_for(_, "disabled"), do: @menu_keys_no_register
  defp keys_for(_, _), do: @menu_keys

  defp render_menu(mode) do
    keys = if mode == "disabled", do: @menu_keys_no_register, else: @menu_keys

    column style: %{gap: 0} do
      [text("Welcome.", fg: :green)] ++
        Enum.map(keys, fn {k, label} ->
          text("  [#{k}] #{label}", fg: :green)
        end)
    end
  end

  defp render_login_form(state) do
    login_ss = get_login_ss(state)

    form =
      Map.get(login_ss, :form) ||
        %{handle: "", password: "", error: nil}

    focused = Map.get(login_ss, :focused_field, :handle)

    error_items =
      if form.error do
        [text(""), text(form.error, fg: :red)]
      else
        []
      end

    column style: %{gap: 0} do
      [
        text("Handle:", fg: :green),
        text_input(
          value: form.handle,
          placeholder: "handle",
          style: focus_style(focused == :handle)
        ),
        text("Password:", fg: :green),
        text_input(
          value: mask(form.password),
          placeholder: "password",
          style: focus_style(focused == :password)
        )
      ] ++ error_items
    end
  end

  # Returns a bold style list when focused, empty list otherwise.
  defp focus_style(true), do: [:bold]
  defp focus_style(false), do: []

  # Masks password characters with asterisks for display.
  defp mask(pw) when is_binary(pw), do: String.duplicate("*", String.length(pw))
  defp mask(_), do: ""

  defp enter_login_form(state) do
    new_login_ss = %{
      sub: :login_form,
      form: %{handle: "", password: "", error: nil},
      focused_field: :handle
    }

    {:update, put_login_ss(state, new_login_ss), []}
  end

  defp maybe_register(state) do
    case registration_mode(state) do
      "disabled" ->
        :no_match

      mode ->
        new_state = %{
          state
          | current_screen: :register,
            register_wizard: %{mode: mode, step: :start}
        }

        {:update, new_state, []}
    end
  end

  defp submit_login(state) do
    login_ss = get_login_ss(state)
    form = Map.get(login_ss, :form) || %{handle: "", password: ""}

    case Accounts.authenticate_by_password(form.handle, form.password) do
      {:ok, %{status: :active} = user} ->
        # Clear screen state and promote the session via the App's handler.
        {:update, %{state | screen_state: %{}}, [{:promote_session, user}]}

      {:ok, %{status: :pending}} ->
        modal = %{
          type: :error,
          message:
            "Your account is pending sysop approval. Please wait for an approval notification."
        }

        {:update, %{state | modal: modal}, []}

      {:ok, %{status: :suspended}} ->
        modal = %{type: :error, message: "Your account is suspended. Contact the sysop."}
        {:update, %{state | modal: modal}, []}

      {:error, :invalid_credentials} ->
        # Clear the password field but keep the handle for retry.
        form_with_error =
          form
          |> Map.put(:error, "Invalid credentials.")
          |> Map.put(:password, "")

        new_login_ss = Map.put(login_ss, :form, form_with_error)
        {:update, put_login_ss(state, new_login_ss), []}
    end
  end
end
