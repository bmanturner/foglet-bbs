defmodule Foglet.TUI.Screens.AccountHandleColorTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.RenderHelpers

  alias Foglet.TUI.Screens.Account.PrefsForm
  alias Foglet.TUI.Screens.Account.State
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

  defp text_nodes(tree) do
    tree
    |> flatten_nodes()
    |> Enum.filter(&(Map.get(&1, :type) == :text))
  end

  defp flatten_nodes(node), do: do_flatten_nodes(node, [])

  defp do_flatten_nodes(nodes, acc) when is_list(nodes),
    do: Enum.flat_map(nodes, &do_flatten_nodes(&1, acc))

  defp do_flatten_nodes(%{} = node, _acc) do
    [node | do_flatten_nodes(Map.get(node, :children, []), [])]
  end

  defp do_flatten_nodes(_other, _acc), do: []

  test "PREFS includes handle color with saved value and a colored swatch" do
    state =
      State.new(
        current_user: %{
          timezone: "Etc/UTC",
          theme: "gray",
          preferences: %{},
          handle_color: "#66ccff"
        }
      )

    view =
      PrefsForm.render(%{state | prefs_focus: :handle_color}, Theme.default(),
        width: 80,
        height: 12
      )

    assert Enum.any?(collect_text_values(view), &String.contains?(&1, "Handle color"))
    assert Enum.any?(collect_text_values(view), &String.contains?(&1, "#66ccff"))

    assert Enum.any?(text_nodes(view), fn node ->
             Map.get(node, :content) =~ "██" and Map.get(node, :fg) == "#66ccff"
           end)
  end

  test "handle color edit modal previews draft color and uses copy handoff" do
    form =
      State.build_prefs_field_form(
        %{timezone: "Etc/UTC", time_format: "12h", theme: "gray", handle_color: "#ff8800"},
        :handle_color
      )

    view = ModalForm.render(form, theme: Theme.default(), width: 76)

    assert Enum.any?(
             collect_text_values(view),
             &String.contains?(&1, "Edit preferences: Handle color")
           )

    assert Enum.any?(
             collect_text_values(view),
             &String.contains?(&1, "Type a six-digit hex color")
           )

    assert Enum.any?(text_nodes(view), fn node ->
             Map.get(node, :content) =~ "@you" and Map.get(node, :fg) == "#ff8800"
           end)
  end

  test "submit includes handle_color and cancel clears only preview state" do
    state = %State{
      prefs_draft: %{
        timezone: "Etc/UTC",
        time_format: "12h",
        theme: "gray",
        handle_color: "#ff8800"
      },
      prefs_focus: :handle_color,
      prefs_editing_field: :handle_color,
      candidate_theme_id: nil,
      status_message: "editing"
    }

    {updated, effects} = PrefsForm.submit_field(state, %{handle_color: "#66ccff"})

    assert updated.prefs_draft.handle_color == "#66ccff"
    assert [{:account_save_prefs, %{handle_color: "#66ccff"}}] = effects

    previewed =
      PrefsForm.preview_field_change(
        state,
        State.build_prefs_field_form(state.prefs_draft, :handle_color)
      )

    cancelled = PrefsForm.cancel_field(previewed)

    assert cancelled.prefs_draft.handle_color == "#ff8800"
    assert cancelled.prefs_editing_field == nil
  end
end
