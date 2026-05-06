%{
  title: "Hello, Foglet",
  description: "Smoke-test page for the /docs surface.",
  weight: 1
}
---
# Hello, Foglet

This page exists so the `/docs` route has something to render.

NimblePublisher compiles every `priv/docs/**/*.md` file at build time. The
frontmatter above (the `%{...}` map) becomes the page's `attrs`. Everything
below the `---` separator is rendered to HTML through `MDEx`.

## What lives here

Project documentation that benefits from a browser surface lives under
`priv/docs/`. The `docs/` tree at the repo root is the canonical source for
contributors and is not served here.

Pages are grouped by **subfolder** — each folder under `priv/docs/` becomes a
sidebar category, and within a category, pages sort by their `weight`
frontmatter (lowest first), then by title.

```elixir
def hello do
  :world
end
```

- Lists work
- Inline `code` works
- [Links](/docs) work
