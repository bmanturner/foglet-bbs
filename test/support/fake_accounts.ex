defmodule Foglet.TUI.FakeAccounts do
  @moduledoc """
  Test double for the `Foglet.Accounts` boundary used by the Phase 29
  Sysop USERS load triad.

  Configurable via the test process dictionary:

  - `:fake_accounts_status_targets_result` — the value returned from
    `list_user_status_admin_targets/1`. Defaults to a populated
    `{:ok, groups}` map.

  Sends a `{:list_user_status_admin_targets, user}` message to the test
  owner so behaviour assertions can verify the call site fired.
  """

  def list_user_status_admin_targets(user) do
    send(test_owner(), {:list_user_status_admin_targets, user})

    Process.get(:fake_accounts_status_targets_result, {:ok, default_groups()})
  end

  defp default_groups do
    %{pending: [], active: [], suspended: [], rejected: []}
  end

  defp test_owner do
    Process.get(:fake_accounts_owner, self())
  end
end
