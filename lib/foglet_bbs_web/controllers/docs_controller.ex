defmodule FogletBbsWeb.DocsController do
  use FogletBbsWeb, :controller

  alias FogletBbsWeb.Docs

  def index(conn, _params) do
    render(conn, :index,
      layout: false,
      groups: Docs.grouped_pages()
    )
  end

  def show(conn, %{"category" => category, "id" => id}) do
    page = Docs.get_page!(category, id)

    render(conn, :show,
      layout: false,
      page: page,
      groups: Docs.grouped_pages()
    )
  end
end
