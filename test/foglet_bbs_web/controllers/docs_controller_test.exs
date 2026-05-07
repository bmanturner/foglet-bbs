defmodule FogletBbsWeb.DocsControllerTest do
  use FogletBbsWeb.ConnCase, async: true

  describe "GET /docs" do
    test "redirects to the start-here overview", %{conn: conn} do
      conn = get(conn, ~p"/docs")
      assert redirected_to(conn) == ~p"/docs/start-here/overview"
    end

    test "/assets/docs.css is served by the endpoint", %{conn: conn} do
      conn = get(conn, ~p"/assets/docs.css")
      assert conn.status == 200
    end
  end

  describe "GET /docs/:category/:id" do
    test "renders the page body as HTML with breadcrumbs", %{conn: conn} do
      conn = get(conn, ~p"/docs/start-here/overview")
      body = html_response(conn, 200)

      assert body =~ "Overview"
      # Breadcrumbs include humanized category title
      assert body =~ "Start Here"
      # Sidebar marks the active page
      assert body =~ ~s(class="active")
    end

    test "raises NotFoundError for unknown category", %{conn: conn} do
      assert_error_sent(404, fn -> get(conn, ~p"/docs/nope/hello") end)
    end

    test "raises NotFoundError for unknown id", %{conn: conn} do
      assert_error_sent(404, fn -> get(conn, ~p"/docs/start-here/missing") end)
    end
  end

  describe "FogletBbsWeb.Docs.MarkdownConverter" do
    test "renders pipe tables as semantic HTML tables" do
      html =
        FogletBbsWeb.Docs.MarkdownConverter.convert(
          ".md",
          "| Setting | Default |\n| --- | --- |\n| site.name | Foglet |\n",
          %{},
          []
        )

      assert html =~ "<table>"
      assert html =~ "<thead>"
      assert html =~ "<tbody>"
      assert html =~ "<th>Setting</th>"
      assert html =~ "<td>site.name</td>"
      refute html =~ "<p>| Setting | Default |"
    end
  end

  describe "FogletBbsWeb.Docs published pages" do
    test "site settings page body includes semantic tables" do
      page = FogletBbsWeb.Docs.get_page!("configuration", "site-settings")

      assert page.body =~ "<table>"
      assert page.body =~ "<th>Setting</th>"
      assert page.body =~ "<th>Stored key</th>"
      refute page.body =~ "<p>| Key |"
    end
  end

  describe "FogletBbsWeb.Docs ordering" do
    test "categories follow the public docs outline order" do
      titles =
        FogletBbsWeb.Docs.grouped_pages()
        |> Enum.map(fn {title, _pages} -> title end)

      assert titles == [
               "Start Here",
               "Installation",
               "Deployment",
               "Configuration",
               "Administration",
               "User Guide",
               "Door Games",
               "Operations",
               "Concepts",
               "Advanced"
             ]
    end

    test "pages within a category are sorted by weight ascending" do
      [{_title, pages} | _] =
        FogletBbsWeb.Docs.grouped_pages()
        |> Enum.filter(fn {title, _} -> title == "Door Games" end)

      ids = Enum.map(pages, & &1.id)

      assert ids == [
               "overview",
               "support-status",
               "operator-setup",
               "demo-doors",
               "manifest-reference",
               "visibility-and-launch-policy",
               "native-elixir-doors",
               "external-pty-doors",
               "classic-dropfile-doors",
               "adapter-contract",
               "security-and-sandboxing",
               "deployment-profiles",
               "runtime-boundary",
               "tui-flow",
               "troubleshooting",
               "qa-and-release-checks"
             ]
    end
  end
end
