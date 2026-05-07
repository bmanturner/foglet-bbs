defmodule FogletBbsWeb.Docs.Page do
  @moduledoc """
  A single docs page parsed from `priv/docs/<category>/<id>.md` by NimblePublisher.

  - `id` — filename slug (no extension), e.g. `"hello"`.
  - `category` — parent folder slug, e.g. `"getting-started"`. Used to group pages
    in the sidebar and as the first segment of the URL.
  - `category_title` — humanized category for display (`"Getting Started"`).
  - `weight` — sort order within the category (lowest first). Defaults to `100`.
  """

  @enforce_keys [:id, :category, :category_title, :title, :description, :weight, :body]
  defstruct [:id, :category, :category_title, :title, :description, :weight, :body]

  @docs_root "priv/docs"

  def build(filename, attrs, body) do
    {category, id} = parse_path(filename)

    %__MODULE__{
      id: id,
      category: category,
      category_title: humanize(category),
      title: Map.get(attrs, :title, id),
      description: Map.get(attrs, :description, ""),
      weight: Map.get(attrs, :weight, 100),
      body: body
    }
  end

  # Extracts {category_slug, page_id} from a path like
  # ".../priv/docs/getting-started/hello.md".
  defp parse_path(filename) do
    id = filename |> Path.basename(".md")

    category =
      filename
      |> Path.dirname()
      |> Path.split()
      |> Enum.reverse()
      |> Enum.take_while(&(&1 != Path.basename(@docs_root)))
      |> Enum.reverse()
      |> case do
        [] -> "uncategorized"
        parts -> Enum.join(parts, "/")
      end

    {category, id}
  end

  defp humanize(slug) do
    slug
    |> String.split(["-", "_", "/"])
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end

defmodule FogletBbsWeb.Docs.MarkdownConverter do
  @moduledoc false

  def convert(_extname, body, _attrs, _opts) do
    MDEx.to_html!(body, extension: [table: true])
  end
end

defmodule FogletBbsWeb.Docs.NotFoundError do
  defexception [:message, plug_status: 404]
end
