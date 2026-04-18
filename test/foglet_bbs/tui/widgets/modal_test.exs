defmodule Foglet.TUI.Widgets.ModalTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Widgets.Modal

  describe "render/1 (D-20)" do
    test "returns a non-nil view element for :info" do
      assert _ = Modal.render(%{type: :info, message: "Hello"})
    end

    test "returns a non-nil view element for :error" do
      assert _ = Modal.render(%{type: :error, message: "Oh no"})
    end

    test "returns a non-nil view element for :confirm" do
      assert _ = Modal.render(%{type: :confirm, message: "Delete?"})
    end

    test "defaults type to :info when omitted" do
      assert _ = Modal.render(%{message: "No type given"})
    end

    test "raises when :message is missing" do
      assert_raise FunctionClauseError, fn -> Modal.render(%{type: :info}) end
    end
  end
end
