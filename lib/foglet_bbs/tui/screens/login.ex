defmodule Foglet.TUI.Screens.Login do
  @moduledoc """
  Login-or-register entry screen (SSH-04, D-22).

  Respects runtime config:
    * registration_mode == "disabled" → hides [R] Register (D-06)
    * any other value → shows all three options

  Sub-states (stored in state.screen_state[:login]):
    * :menu          — showing [L]/[R]/[Q] menu
    * :login_form    — collecting handle+password
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

    panel(
      title: "Foglet BBS — Login",
      border: :single,
      children:
        [
          case sub do
            :login_form -> render_login_form(state)
            _ -> render_menu(mode)
          end
        ] ++ [KeyBar.render(keys_for(sub, mode))]
    )
  end

  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  def handle_key(%{key: "q"}, state), do: {:update, state, [{:terminate, :user_quit}]}
  def handle_key(%{key: "Q"}, state), do: {:update, state, [{:terminate, :user_quit}]}

  def handle_key(%{key: "l"}, state), do: enter_login_form(state)
  def handle_key(%{key: "L"}, state), do: enter_login_form(state)

  def handle_key(%{key: "r"}, state), do: maybe_register(state)
  def handle_key(%{key: "R"}, state), do: maybe_register(state)

  def handle_key(%{key: "enter"}, state) do
    case sub_state(state) do
      :login_form -> submit_login(state)
      _ -> :no_match
    end
  end

  def handle_key(_key, _state), do: :no_match

  # --- Private ---

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

  defp keys_for(:login_form, _), do: [{"Enter", "Submit"}, {"Esc", "Cancel"}]
  defp keys_for(_, "disabled"), do: @menu_keys_no_register
  defp keys_for(_, _), do: @menu_keys

  defp render_menu(mode) do
    keys = if mode == "disabled", do: @menu_keys_no_register, else: @menu_keys

    box(
      children:
        [text("Welcome.", color: :green)] ++
          Enum.map(keys, fn {k, label} ->
            text("  [#{k}] #{label}", color: :green)
          end)
    )
  end

  defp render_login_form(state) do
    login_ss = Map.get(state.screen_state || %{}, :login) || %{}

    form =
      Map.get(login_ss, :form) ||
        %{handle: "", password: "", error: nil}

    error_items =
      if form.error do
        [text(""), text(form.error, color: :red)]
      else
        []
      end

    box(
      children:
        [
          text("Handle:   #{form.handle}", color: :green),
          text(
            "Password: #{String.duplicate("*", String.length(form.password))}",
            color: :green
          )
        ] ++ error_items
    )
  end

  defp enter_login_form(state) do
    new_screen_state =
      put_in(state.screen_state, [:login], %{
        sub: :login_form,
        form: %{handle: "", password: "", error: nil}
      })

    {:update, %{state | screen_state: new_screen_state}, []}
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
    login_ss = Map.get(state.screen_state || %{}, :login) || %{}
    form = Map.get(login_ss, :form) || %{handle: "", password: ""}

    case Accounts.authenticate_by_password(form.handle, form.password) do
      {:ok, %{status: :active} = user} ->
        {:update, %{state | current_user: user, current_screen: :main_menu, screen_state: %{}},
         []}

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
        form_with_error = Map.put(form, :error, "Invalid credentials.")
        new_screen_state = put_in(state.screen_state, [:login, :form], form_with_error)
        {:update, %{state | screen_state: new_screen_state}, []}
    end
  end
end
