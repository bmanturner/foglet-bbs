defmodule Foglet.Metrics.PlugTest do
  use ExUnit.Case, async: false
  import Plug.Test

  setup do
    Foglet.Metrics.Store.reset()
    :ok
  end

  test "GET /metrics returns Prometheus text without the Phoenix endpoint" do
    :telemetry.execute([:foglet, :auth, :outcome], %{count: 1}, %{
      method: :password,
      outcome: :success
    })

    conn =
      :get
      |> conn("/metrics")
      |> Foglet.Metrics.Plug.call([])

    assert conn.status == 200

    assert Plug.Conn.get_resp_header(conn, "content-type") == [
             "text/plain; version=0.0.4; charset=utf-8"
           ]

    assert conn.resp_body =~ "# HELP foglet_ssh_auth_outcomes_total"
    assert conn.resp_body =~ "# TYPE foglet_ssh_auth_outcomes_total counter"

    assert conn.resp_body =~
             ~s(foglet_ssh_auth_outcomes_total{method="password",outcome="success"} 1)

    assert conn.resp_body =~ ~s(foglet_ssh_sessions_active{kind="guest"})
    assert conn.resp_body =~ "foglet_vm_memory_bytes"
  end

  test "non-metrics paths do not expose metrics" do
    conn =
      :get
      |> conn("/")
      |> Foglet.Metrics.Plug.call([])

    assert conn.status == 404
    assert conn.resp_body == "not found\n"
  end

  test "telemetry summaries render count and sum samples" do
    :telemetry.execute(
      [:foglet, :door, :duration],
      %{duration: System.convert_time_unit(2, :second, :native)},
      %{
        runtime: :native_elixir
      }
    )

    body = Foglet.Metrics.Store.render()

    assert body =~ "# TYPE foglet_door_runtime_seconds summary"
    assert body =~ ~s(foglet_door_runtime_seconds_count{runtime="native_elixir"} 1)
    assert body =~ ~s(foglet_door_runtime_seconds_sum{runtime="native_elixir"} 2.000000000)
  end
end
