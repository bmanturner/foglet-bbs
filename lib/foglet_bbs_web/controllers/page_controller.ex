defmodule FogletBbsWeb.PageController do
  use FogletBbsWeb, :controller

  def home(conn, _params) do
    render(conn, :home, layout: false)
  end

  def ddn(conn, _params) do
    render(conn, :ddn, layout: false)
  end
end
