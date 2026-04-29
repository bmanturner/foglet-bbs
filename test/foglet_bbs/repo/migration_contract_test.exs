defmodule FogletBbs.Repo.MigrationContractTest do
  use ExUnit.Case, async: true

  @migration_path "priv/repo/migrations/20260429143000_add_account_board_contract_baseline.exs"

  test "account and board baseline migration documents forward and rollback paths" do
    Code.compile_file(@migration_path)

    assert function_exported?(
             FogletBbs.Repo.Migrations.AddAccountBoardContractBaseline,
             :up,
             0
           )

    assert function_exported?(
             FogletBbs.Repo.Migrations.AddAccountBoardContractBaseline,
             :down,
             0
           )

    body = File.read!(@migration_path)

    assert body =~ "Forward:"
    assert body =~ "Rollback:"
    assert body =~ "handle_canonical"
    assert body =~ "slug_canonical"
    assert body =~ "remove :role"
  end
end
