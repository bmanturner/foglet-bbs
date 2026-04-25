defmodule FogletBbsWeb.ErrorJSONTest do
  use FogletBbsWeb.ConnCase, async: true

  test "renders 404" do
    assert FogletBbsWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end
end
