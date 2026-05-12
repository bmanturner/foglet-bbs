defmodule Foglet.TUI.Screens.Sysop.BoardsViewTest do
  use FogletBbs.DataCase, async: false

  import FogletBbs.BoardsFixtures

  alias Foglet.Accounts.User
  alias Foglet.Boards.Board
  alias Foglet.TUI.Screens.Sysop.BoardsView
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Input.TextInput
  alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm
  alias FogletBbs.Repo

  defp sysop_actor, do: %User{role: :sysop, status: :active, deleted_at: nil}

  describe "enhanced-width board workspace" do
    test "uses a board list plus selected settings inspector at 120 columns" do
      category = category_fixture(%{name: "General"})
      board = board_fixture(category, %{slug: "general", name: "General", postable_by: :members})

      state =
        BoardsView.init(current_user: sysop_actor())
        |> select_board(board.id)

      flat =
        state
        |> BoardsView.render(Theme.default(), width: 116, visible_height: 32)
        |> Foglet.TUI.WidgetHelpers.flatten_text()

      assert flat =~ "Selected board settings"
      assert flat =~ "Slug"
      assert flat =~ "general"
      assert flat =~ "Actions"
    end
  end

  describe "board display_order form payloads" do
    test "new board form defaults display_order to zero and persists submitted value" do
      _category = category_fixture(%{name: "General"})

      state = BoardsView.init(current_user: sysop_actor())
      {state, []} = BoardsView.handle_key(%{key: :char, char: "n"}, state)

      assert %ModalForm{} = state.modal
      assert ModalForm.field_value(state.modal, :display_order) == 0

      form =
        state.modal
        |> put_text_field(:slug, "display-order-new")
        |> put_text_field(:name, "Display Order New")
        |> put_text_field(:display_order, "37")

      {state, []} = BoardsView.handle_key(%{key: :enter}, %{state | modal: form})

      assert state.modal == nil
      assert %Board{display_order: 37} = Repo.get_by!(Board, slug: "display-order-new")
    end

    test "edit board form prefills display_order and persists submitted changes" do
      category = category_fixture(%{name: "General"})
      board = board_fixture(category, %{slug: "display-order-edit", display_order: 2})

      state =
        BoardsView.init(current_user: sysop_actor())
        |> select_board(board.id)

      {state, []} = BoardsView.handle_key(%{key: :char, char: "e"}, state)

      assert %ModalForm{} = state.modal
      assert ModalForm.field_value(state.modal, :display_order) == 2

      form = put_text_field(state.modal, :display_order, "9")
      {state, []} = BoardsView.handle_key(%{key: :enter}, %{state | modal: form})

      assert state.modal == nil
      assert %Board{display_order: 9} = Repo.get!(Board, board.id)
    end

    test "invalid board display_order stays in the form as a field-level error" do
      _category = category_fixture(%{name: "General"})

      state = BoardsView.init(current_user: sysop_actor())
      {state, []} = BoardsView.handle_key(%{key: :char, char: "n"}, state)

      form =
        state.modal
        |> put_text_field(:slug, "display-order-invalid")
        |> put_text_field(:name, "Display Order Invalid")
        |> put_text_field(:display_order, "not-an-int")

      {state, []} = BoardsView.handle_key(%{key: :enter}, %{state | modal: form})

      assert %ModalForm{} = state.modal
      assert state.modal.errors.display_order == "is invalid"
      assert {:error, "validation"} = state.modal.submit_state
      refute Repo.get_by(Board, slug: "display-order-invalid")
    end
  end

  defp select_board(%BoardsView{rows: rows} = state, board_id) do
    idx = Enum.find_index(rows, &match?({:board, %{id: ^board_id}}, &1))
    assert is_integer(idx), "expected board #{inspect(board_id)} in rows #{inspect(rows)}"
    %{state | selection_index: idx}
  end

  defp put_text_field(%ModalForm{} = form, field_name, value) do
    idx = Enum.find_index(form.fields, &(&1.name == field_name))

    assert is_integer(idx),
           "expected field #{inspect(field_name)} in #{inspect(Enum.map(form.fields, & &1.name))}"

    spec = Enum.at(form.fields, idx)
    assert spec.type in [:text, :integer]

    new_state =
      TextInput.init(
        value: value,
        max_length: Map.get(spec, :max_length, 256),
        placeholder: Map.get(spec, :placeholder, "")
      )

    %{form | field_states: List.replace_at(form.field_states, idx, new_state)}
  end
end
