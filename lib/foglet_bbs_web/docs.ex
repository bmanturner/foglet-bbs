defmodule FogletBbsWeb.Docs do
  @moduledoc """
  Compile-time index of pages under `priv/docs/**/*.md`, served at `/docs`.

  Each markdown file becomes a `FogletBbsWeb.Docs.Page` keyed by the pair
  `{category, id}`. Pages are grouped in the sidebar by their parent folder
  (the category slug), and within a category they sort by `weight`, then by
  title.

  See `docs/ARCHITECTURE.md` §12 for why this surface is intentional.
  """

  alias FogletBbsWeb.Docs.{NotFoundError, Page}

  use NimblePublisher,
    build: Page,
    from: Application.app_dir(:foglet_bbs, "priv/docs/**/*.md"),
    as: :pages,
    html_converter: FogletBbsWeb.Docs.MarkdownConverter

  @pages Enum.sort_by(@pages, &{&1.category, &1.weight, &1.title})
  @categories @pages |> Enum.map(&{&1.category, &1.category_title}) |> Enum.uniq()

  @doc "All pages, sorted by category → weight → title."
  def all_pages, do: @pages

  @doc """
  Pages grouped by category for sidebar rendering.

  Returns a list of `{category_title, pages}` tuples in stable order. Within
  each group pages are already sorted by weight then title.
  """
  def grouped_pages do
    Enum.map(@categories, fn {slug, title} ->
      {title, Enum.filter(@pages, &(&1.category == slug))}
    end)
  end

  @doc "Look up a page by `{category, id}`. Raises `NotFoundError` if missing."
  def get_page!(category, id) do
    Enum.find(@pages, &(&1.category == category and &1.id == id)) ||
      raise NotFoundError, "page not found: #{category}/#{id}"
  end
end
