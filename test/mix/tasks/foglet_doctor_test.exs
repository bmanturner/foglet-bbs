defmodule Mix.Tasks.Foglet.DoctorTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Foglet.Doctor

  describe "parse_tool_versions/2" do
    test "reads the pinned version for a tool and ignores comments" do
      content = """
      # managed by asdf/mise
      erlang 28.3.1 # current OTP
      elixir 1.19.5-otp-28
      nodejs 24.0.0
      """

      assert Doctor.parse_tool_versions(content, "elixir") == "1.19.5-otp-28"
      assert Doctor.parse_tool_versions(content, "erlang") == "28.3.1"
    end

    test "returns nil when the tool entry is absent" do
      assert Doctor.parse_tool_versions("elixir 1.19.5-otp-28\n", "erlang") == nil
    end
  end

  describe "database_connection_failure_message/2" do
    test "gives the operator a setup command when the configured database is missing" do
      reason = %Postgrex.Error{postgres: %{code: :invalid_catalog_name}}

      message = Doctor.database_connection_failure_message("foglet_bbs_dev", reason)

      assert message =~ "database foglet_bbs_dev does not exist"
      assert message =~ "rtk mix ecto.create"
      assert message =~ "rtk mix setup"
    end

    test "gives the operator a Postgres startup hint for connection errors" do
      reason = DBConnection.ConnectionError.exception("connection refused")

      message = Doctor.database_connection_failure_message("foglet_bbs_dev", reason)

      assert message =~ "cannot reach Postgres"
      assert message =~ "docker compose up -d postgres"
      assert message =~ "DATABASE_URL"
    end
  end
end
