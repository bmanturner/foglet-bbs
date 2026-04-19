defmodule Foglet.TUI.Widgets.ModalTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Widgets.Modal

  # Recursively collects all text content strings from the view tree.
  defp collect_text_content(element, acc \\ [])

  defp collect_text_content(element, acc) when is_map(element) do
    # Text elements have :content field
    acc =
      case Map.get(element, :content) do
        content when is_binary(content) -> [content | acc]
        _ -> acc
      end

    children = Map.get(element, :children, [])
    collect_text_content(children, acc)
  end

  defp collect_text_content(list, acc) when is_list(list) do
    Enum.reduce(list, acc, fn el, acc -> collect_text_content(el, acc) end)
  end

  defp collect_text_content(_other, acc), do: acc

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

  describe "word-wrap (Gap 3a)" do
    test "Test A: 120-char message is wrapped so no single text line exceeds 50 chars" do
      # Build a 120-char message with spaces so word_wrap can break it
      msg = "This is a very long pending approval message that definitely exceeds fifty characters in total length yes."

      tree = Modal.render(%{type: :error, message: msg})
      all_text = collect_text_content(tree)

      # Filter out the title (" Error "), key hint ("[Enter] OK"), and empty strings
      message_lines =
        all_text
        |> Enum.reject(fn s ->
          s == "" or
            String.trim(s) in ["Error", "Info", "Warning", "Confirm", "[Enter] OK", "[Y] Yes   [N] No"] or
            String.starts_with?(String.trim(s), " ") and String.ends_with?(String.trim(s), " ")
        end)
        |> Enum.reject(&(&1 == "[Enter] OK"))

      assert message_lines != [], "Expected wrapped message lines in tree, found none. All text: #{inspect(all_text)}"

      for line <- message_lines do
        assert String.length(line) <= 50,
               "Line exceeds 50 chars (#{String.length(line)}): #{inspect(line)}"
      end
    end
  end

  describe "key hint (Gap 3c)" do
    test "Test B: :info modal ends with '[Enter] OK' (no Esc)" do
      tree = Modal.render(%{type: :info, message: "short"})
      all_text = collect_text_content(tree)

      assert "[Enter] OK" in all_text,
             "Expected '[Enter] OK' in text elements, found: #{inspect(all_text)}"

      refute Enum.any?(all_text, &String.contains?(&1, "Esc")),
             "Expected no 'Esc' in key hint, found: #{inspect(all_text)}"
    end

    test "Test C: :confirm modal still shows '[Y] Yes   [N] No'" do
      tree = Modal.render(%{type: :confirm, message: "yn"})
      all_text = collect_text_content(tree)

      assert "[Y] Yes   [N] No" in all_text,
             "Expected '[Y] Yes   [N] No' in text elements, found: #{inspect(all_text)}"
    end
  end
end
