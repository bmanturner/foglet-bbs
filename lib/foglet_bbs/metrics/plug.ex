defmodule Foglet.Metrics.Plug do
  @moduledoc """
  Dedicated Prometheus text endpoint for Fly custom metrics scraping.

  This plug is mounted on its own Bandit listener by `FogletBbs.Application`.
  It is not part of the end-user Phoenix/BBS surface.
  """

  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: "GET", request_path: path} = conn, _opts) do
    configured_path = metrics_path()

    if path == configured_path do
      conn
      |> put_resp_content_type("text/plain; version=0.0.4")
      |> send_resp(200, Foglet.Metrics.Store.render())
      |> halt()
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(404, "not found\n")
      |> halt()
    end
  end

  def call(conn, _opts) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(405, "method not allowed\n")
    |> halt()
  end

  defp metrics_path do
    :foglet_bbs
    |> Application.get_env(:metrics_server, [])
    |> Keyword.get(:path, "/metrics")
  end
end
