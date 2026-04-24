defmodule Foglet.TUI.FakeOneliners do
  @moduledoc false

  def list_recent_visible(limit) do
    send(test_owner(), {:list_recent_visible, limit})
    Process.get(:fake_oneliners_entries, [])
  end

  def create_entry(user, attrs) do
    send(test_owner(), {:create_entry, user, attrs})

    Process.get(
      :fake_oneliners_create_result,
      {:ok, %{id: "ol-new", body: attrs.body, user: user}}
    )
  end

  def hide_entry(actor, target, reason) do
    send(test_owner(), {:hide_entry, actor, target, reason})

    Process.get(
      :fake_oneliners_hide_result,
      {:ok, %{id: target, hidden?: true, hidden_reason: reason}}
    )
  end

  defp test_owner do
    Process.get(:fake_oneliners_owner, self())
  end
end
