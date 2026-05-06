defmodule FogletBbsWeb.DocsControllerTest do
  use FogletBbsWeb.ConnCase, async: true

  describe "GET /docs" do
    test "renders categorized index of compiled pages", %{conn: conn} do
      conn = get(conn, ~p"/docs")
      body = html_response(conn, 200)

      # Categories appear as group headings
      assert body =~ "Getting Started"
      assert body =~ "Architecture"

      # Pages link to /docs/<category>/<id>
      assert body =~ ~s(href="/docs/getting-started/hello")
      assert body =~ ~s(href="/docs/getting-started/connect")
      assert body =~ ~s(href="/docs/architecture/overview")

      # Sidebar links to landing page
      assert body =~ ~s(href="/")

      # Loads the docs stylesheet
      assert body =~ ~s(href="/assets/docs.css")
    end

    test "/assets/docs.css is served by the endpoint", %{conn: conn} do
      conn = get(conn, ~p"/assets/docs.css")
      assert conn.status == 200
    end
  end

  describe "GET /docs/:category/:id" do
    test "renders the page body as HTML with breadcrumbs", %{conn: conn} do
      conn = get(conn, ~p"/docs/getting-started/hello")
      body = html_response(conn, 200)

      assert body =~ "Hello, Foglet"
      # Markdown was rendered to HTML
      assert body =~ "<code>"
      # Breadcrumbs include humanized category title
      assert body =~ "Getting Started"
      # Sidebar marks the active page
      assert body =~ ~s(class="active")
    end

    test "raises NotFoundError for unknown category", %{conn: conn} do
      assert_error_sent(404, fn -> get(conn, ~p"/docs/nope/hello") end)
    end

    test "raises NotFoundError for unknown id", %{conn: conn} do
      assert_error_sent(404, fn -> get(conn, ~p"/docs/getting-started/missing") end)
    end
  end

  describe "FogletBbsWeb.Docs ordering" do
    test "pages within a category are sorted by weight ascending" do
      [{_title, pages} | _] =
        FogletBbsWeb.Docs.grouped_pages()
        |> Enum.filter(fn {title, _} -> title == "Getting Started" end)

      ids = Enum.map(pages, & &1.id)
      assert ids == ["hello", "connect"]
    end
  end
end
