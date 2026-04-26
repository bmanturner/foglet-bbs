defmodule Foglet.TUI.LayoutSmoke.AccountHelper do
  @moduledoc """
  Per-tab size-contract registry for the Account screen (Phase 25, D-09/D-11).

  Plan 02 fills in PROFILE/PREFS/SSH KEYS blocks here.

  Plans that add blocks here do NOT modify layout_smoke_test.exs directly,
  keeping wave-2 merge conflict surface at zero.
  """

  # ---------------------------------------------------------------------------
  # Private helpers (outside quote so Credo cyclomatic/complexity checks apply
  # to small, focused functions rather than the macro body as a whole).
  # ---------------------------------------------------------------------------

  @doc false
  def account_smoke_state(width, height, screen_state) do
    %Foglet.TUI.App{
      current_screen: :account,
      current_user: %Foglet.Accounts.User{
        id: "00000000-0000-0000-0000-000000000001",
        handle: "alice",
        role: :user,
        location: "Mist Harbor",
        tagline: "low clouds",
        real_name: "Alice Example",
        timezone: "Etc/UTC",
        preferences: %{"time_format" => "12h"},
        theme: "gray"
      },
      session_context: %{theme: Foglet.TUI.Theme.resolve(:gray), theme_id: "gray"},
      terminal_size: {width, height},
      screen_state: %{account: screen_state}
    }
    |> Map.from_struct()
  end

  @doc false
  def collect_render_text(tree), do: tree |> do_collect([], []) |> Enum.reverse()

  defp do_collect(nil, _path, acc), do: acc

  defp do_collect(list, _path, acc) when is_list(list),
    do: Enum.reduce(list, acc, fn item, a -> do_collect(item, [], a) end)

  defp do_collect(%{children: children} = node, _path, acc) do
    acc = node_content(node, acc)
    do_collect(children, [], acc)
  end

  defp do_collect(%{content: content}, _path, acc) when is_binary(content), do: [content | acc]
  defp do_collect(%{text: text}, _path, acc) when is_binary(text), do: [text | acc]
  defp do_collect(_other, _path, acc), do: acc

  defp node_content(%{content: content}, acc) when is_binary(content), do: [content | acc]
  defp node_content(_node, acc), do: acc

  defmacro register_account_size_contracts do
    quote do
      import Foglet.TUI.LayoutSmokeHelpers, only: [set_active_tab: 2]

      alias Foglet.TUI.LayoutSmoke.AccountHelper
      alias Foglet.TUI.Screens.Account
      alias Foglet.TUI.Screens.Account.SSHKeysState
      alias Foglet.TUI.TextWidth

      describe "account profile tab — size contract" do
        for {width, height} <- [{64, 22}, {80, 24}] do
          @width width
          @height height
          @tag :"account profile size contract"
          test "at #{width}x#{height} primitives render within bounds" do
            width = @width
            height = @height

            user = %Foglet.Accounts.User{
              id: "u1",
              handle: "alice",
              role: :user,
              location: "Mist Harbor",
              tagline: "low clouds",
              real_name: "Alice Example",
              timezone: "Etc/UTC",
              preferences: %{"time_format" => "12h"},
              theme: "gray"
            }

            ss =
              Account.init_screen_state(current_user: user)
              |> set_active_tab("PROFILE")

            state = AccountHelper.account_smoke_state(width, height, ss)
            tree = Account.render(state)
            positioned = apply_at_size(tree, {width, height})
            elements = text_elements(positioned)

            for el <- elements do
              assert el.x + TextWidth.display_width(el.text) <= width,
                     "element #{inspect(el.text)} at x=#{el.x} exceeds width #{width}"

              assert el.y < height,
                     "element #{inspect(el.text)} at y=#{el.y} exceeds height #{height}"
            end

            texts = Enum.map(elements, & &1.text)

            assert Enum.any?(texts, &String.contains?(&1, "[Enter] Submit")),
                   "expected Modal.Form footer sentinel '[Enter] Submit' at #{width}x#{height}"
          end
        end
      end

      describe "account prefs tab — size contract" do
        for {width, height} <- [{64, 22}, {80, 24}] do
          @width width
          @height height
          @tag :"account prefs size contract"
          test "at #{width}x#{height} Modal.Form primitive sentinel renders" do
            width = @width
            height = @height

            user = %Foglet.Accounts.User{
              id: "u1",
              handle: "alice",
              role: :user,
              location: "",
              tagline: "",
              real_name: "",
              timezone: "Etc/UTC",
              preferences: %{"time_format" => "12h"},
              theme: "gray"
            }

            ss =
              Account.init_screen_state(current_user: user)
              |> set_active_tab("PREFS")

            state = AccountHelper.account_smoke_state(width, height, ss)
            texts = Account.render(state) |> AccountHelper.collect_render_text()

            assert Enum.any?(texts, &String.contains?(&1, "[Enter] Submit")),
                   "expected Modal.Form footer '[Enter] Submit' at #{width}x#{height}, got: #{inspect(texts)}"

            assert Enum.any?(texts, &String.contains?(&1, "Theme")),
                   "expected 'Theme' enum field label at #{width}x#{height}"
          end
        end
      end

      describe "account ssh_keys tab — size contract" do
        for {width, height} <- [{64, 22}, {80, 24}] do
          @width width
          @height height
          @tag :"account ssh_keys size contract"
          test "at #{width}x#{height} ConsoleTable header sentinel renders" do
            width = @width
            height = @height

            inserted_at = ~U[2026-04-24 10:00:00.000000Z]

            ssh_keys =
              SSHKeysState.loaded(SSHKeysState.new(), [
                %{
                  id: "k1",
                  label: "laptop",
                  fingerprint: "SHA256:abc123",
                  inserted_at: inserted_at,
                  last_used_at: nil,
                  public_key: "ssh-ed25519 AAAAC3 laptop@test"
                }
              ])

            ss =
              Account.init_screen_state()
              |> Map.put(:active_tab, 2)
              |> Map.put(:ssh_keys, ssh_keys)
              |> set_active_tab("SSH KEYS")

            state = AccountHelper.account_smoke_state(width, height, ss)
            texts = Account.render(state) |> AccountHelper.collect_render_text()

            assert Enum.any?(texts, &String.contains?(&1, "Label")),
                   "expected 'Label' column header sentinel at #{width}x#{height}, got: #{inspect(texts)}"
          end
        end
      end
    end
  end
end
