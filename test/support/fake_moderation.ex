defmodule Foglet.TUI.FakeModeration do
  @moduledoc false

  def workspace_snapshot(user) do
    send(test_owner(), {:workspace_snapshot, user})

    Process.get(:fake_moderation_workspace_result, {:ok, default_snapshot()})
  end

  defp default_snapshot do
    %{
      scopes: [:site],
      queue: [],
      mod_log: [],
      users: [],
      boards: []
    }
  end

  defp test_owner do
    Process.get(:fake_moderation_owner, self())
  end
end
