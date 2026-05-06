defmodule FogletBbsWeb.DocsHTML do
  use Phoenix.Component

  embed_templates "docs_html/*"

  attr :groups, :list, required: true
  attr :active, :any, default: nil, doc: "either nil or {category_slug, id}"

  def sidebar(assigns) do
    ~H"""
    <aside class="sidebar">
      <a class="brand" href="/">
        foglet
        <small>ssh-first bbs · docs</small>
      </a>

      <div :for={{title, pages} <- @groups} class="group">
        <p class="group-title">§ {title}</p>
        <ul>
          <li :for={page <- pages}>
            <a
              href={"/docs/#{page.category}/#{page.id}"}
              class={if @active == {page.category, page.id}, do: "active", else: ""}
            >
              {page.title}
            </a>
          </li>
        </ul>
      </div>
    </aside>
    """
  end
end
