defmodule Foglet.TUI.Widgets.List.SelectableFieldListTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.List.SelectableFieldList
  alias Raxol.UI.Layout.Engine

  defp fields do
    [
      %{name: :location, label: "Location", value: "Birmingham"},
      %{name: :tagline, label: "Tagline", value: ""},
      %{
        name: :real_name,
        label: "Real name",
        value: nil,
        description: "For friends and the sysop; blank uses your handle."
      },
      %{name: :theme, label: "Theme", value: "Amber"}
    ]
  end

  test "move/3 clamps deterministic list selection" do
    assert SelectableFieldList.move(0, 4, :up) == 0
    assert SelectableFieldList.move(0, 4, :down) == 1
    assert SelectableFieldList.move(1, 4, "j") == 2
    assert SelectableFieldList.move(2, 4, "k") == 1
    assert SelectableFieldList.move(2, 4, :home) == 0
    assert SelectableFieldList.move(0, 4, :end) == 3
    assert SelectableFieldList.move(3, 4, :down) == 3
  end

  test "render marks selected row, uses empty placeholder, and includes descriptions" do
    texts = render_texts(fields(), 2, width: 64, height: 8)
    rendered = Enum.map_join(texts, "\n", & &1.text)

    assert rendered =~ "▸ Real name"
    assert rendered =~ "—"
    assert rendered =~ "For friends and the sysop"

    selected = Enum.find(texts, &String.starts_with?(&1.text, "▸ Real name"))
    assert selected.style.reverse
    assert selected.style.bold
  end

  test "render windows cramped lists so the selected primary row remains visible" do
    texts = render_texts(fields(), 3, width: 64, height: 2)
    rendered = Enum.map_join(texts, "\n", & &1.text)

    assert rendered =~ "▸ Theme"
    refute rendered =~ "Location"
  end

  defp render_texts(fields, selected, opts) do
    width = Keyword.fetch!(opts, :width)
    height = Keyword.fetch!(opts, :height)

    fields
    |> SelectableFieldList.render(selected, theme: Theme.default(), width: width, height: height)
    |> Engine.apply_layout(%{width: width, height: height})
    |> List.flatten()
    |> Enum.filter(&(&1.type == :text))
    |> Enum.sort_by(&{&1.y, &1.x})
  end
end
