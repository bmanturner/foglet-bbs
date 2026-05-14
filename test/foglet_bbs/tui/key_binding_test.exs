defmodule Foglet.TUI.KeyBindingTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.KeyBinding

  test "scroll bindings preserve arrow plus j/k movement convention" do
    assert KeyBinding.scroll_up?(%{key: :up})
    assert KeyBinding.scroll_up?(%{key: :char, char: "k"})
    assert KeyBinding.vertical_delta(%{key: :up}) == -1
    assert KeyBinding.vertical_delta(%{key: :char, char: "k"}) == -1

    assert KeyBinding.scroll_down?(%{key: :down})
    assert KeyBinding.scroll_down?(%{key: :char, char: "j"})
    assert KeyBinding.vertical_delta(%{key: :down}) == 1
    assert KeyBinding.vertical_delta(%{key: :char, char: "j"}) == 1
  end

  test "control-modified character keys do not count as plain movement" do
    refute KeyBinding.scroll_down?(%{key: :char, char: "j", ctrl: true})
    refute KeyBinding.scroll_up?(%{key: :char, char: "k", ctrl: true})
    assert KeyBinding.vertical_delta(%{key: :char, char: "j", ctrl: true}) == nil
    assert KeyBinding.vertical_delta(%{key: :char, char: "k", alt: true}) == nil
  end

  test "page home and end bindings accept known key shapes without modifiers" do
    assert KeyBinding.page_up?(%{key: :page_up})
    assert KeyBinding.page_up?(%{key: :pageup})
    assert KeyBinding.page_down?(%{key: :page_down})
    assert KeyBinding.page_down?(%{key: :pagedown})
    assert KeyBinding.home?(%{key: :home})
    assert KeyBinding.end?(%{key: :end})

    refute KeyBinding.page_down?(%{key: :page_down, shift: true})
    refute KeyBinding.home?(%{key: :home, alt: true})
  end

  test "submit requires unmodified enter" do
    assert KeyBinding.submit?(%{key: :enter})
    refute KeyBinding.submit?(%{key: :enter, ctrl: true})
    refute KeyBinding.submit?(%{key: :enter, shift: true})
  end

  test "cancel supports escape and composer-only ctrl+c fallback" do
    assert KeyBinding.cancel?(%{key: :escape})
    refute KeyBinding.cancel?(%{key: :escape, alt: true})

    refute KeyBinding.cancel?(%{key: :char, char: "c", ctrl: true})
    assert KeyBinding.cancel?(%{key: :char, char: "c", ctrl: true}, composer?: true)
    refute KeyBinding.cancel?(%{key: :char, char: "c", ctrl: true, alt: true}, composer?: true)
  end

  test "help supports question mark and stable function key shapes" do
    assert KeyBinding.help?(%{key: :char, char: "?"})
    assert KeyBinding.help?(%{key: :f1})
    assert KeyBinding.help?(%{key: :help})

    refute KeyBinding.help?(%{key: :char, char: "?", ctrl: true})
    refute KeyBinding.help?(%{key: :char, char: "/"})
  end
end
