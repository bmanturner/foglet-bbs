defmodule FogletBbsWeb.PageControllerTest do
  use FogletBbsWeb.ConnCase, async: true

  test "home page references landing assets served by the endpoint", %{conn: conn} do
    conn = get(conn, ~p"/")

    assert html_response(conn, 200) =~ ~s(href="/assets/landing.css")
    assert html_response(conn, 200) =~ ~s(src="/assets/landing.js")

    assert get(build_conn(), ~p"/assets/landing.css").status == 200
    assert get(build_conn(), ~p"/assets/landing.js").status == 200
  end
end
