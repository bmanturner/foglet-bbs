defmodule Foglet.Markdown do
  @moduledoc """
  Renders CommonMark Markdown to ANSI-escaped plain text for terminal display.

  ## ANSI Mapping (D-02)

  | Markdown element   | ANSI output                              |
  |--------------------|------------------------------------------|
  | `**bold**`         | `\\e[1mbold\\e[0m`                       |
  | `*italic*`         | `\\e[3mitalic\\e[0m`                     |
  | `# Heading`        | `\\e[4mHEADING\\e[0m` (uppercased)      |
  | `` `code` ``       | `\\e[2mcode\\e[0m`                       |
  | ` ```block``` `    | 2-space indent + `\\e[2m...\\e[0m`      |
  | `[text](url)`      | `text (url)`                             |
  | `![alt](url)`      | alt text only                            |

  ## Security

  Raw ANSI escape sequences in user input are stripped before rendering.
  All styled output originates from the parsed Markdown AST — user text
  cannot inject terminal color codes through post bodies (T-2-03).
  """

  @ansi_reset "\e[0m"
  @ansi_bold "\e[1m"
  @ansi_italic "\e[3m"
  @ansi_dim "\e[2m"
  @ansi_underline "\e[4m"

  @doc """
  Render a Markdown string to ANSI-escaped plain text.

  Accepts CommonMark + GFM Markdown via MDEx. Returns a string suitable for
  terminal output. Raw ANSI escape sequences in the input are stripped.

  ## Examples

      iex> Foglet.Markdown.render("**hello**")
      "\\e[1mhello\\e[0m"

      iex> Foglet.Markdown.render("[click](https://example.com)")
      "click (https://example.com)"

  """
  @spec render(String.t()) :: String.t()
  def render(markdown) when is_binary(markdown) do
    # Strip raw ANSI escape sequences from user input (T-2-03)
    sanitized = strip_ansi(markdown)

    # Parse to HTML via MDEx (CommonMark + GFM with syntax highlighting)
    html = MDEx.to_html!(sanitized)

    # Transform HTML tags to ANSI sequences
    html
    |> transform_html()
    |> String.trim_trailing()
  end

  # ---------- Private helpers ----------

  # Strip raw ESC characters from user-supplied text before passing to MDEx.
  # Prevents injection of terminal escape sequences through post bodies.
  @spec strip_ansi(String.t()) :: String.t()
  defp strip_ansi(text) do
    # Remove ESC character (\x1b) and any following CSI sequence (optional).
    String.replace(text, ~r/\x1b(\[[0-9;]*[A-Za-z~])?/, "")
  end

  # Walk the HTML output from MDEx and replace known tags with ANSI sequences.
  # Code blocks are handled first to prevent inner tag expansion.
  @spec transform_html(String.t()) :: String.t()
  defp transform_html(html) do
    html
    # Code blocks first — MDEx wraps fenced code in <pre>...</pre> with syntax
    # highlighting spans. Extract plain text then apply dim + 2-space indent.
    |> replace_code_blocks()
    # Headings → uppercase + underline (all h1-h6 treated uniformly per D-02)
    |> replace_heading_tags()
    # Bold
    |> String.replace(~r/<strong>(.*?)<\/strong>/s, "#{@ansi_bold}\\1#{@ansi_reset}")
    # Italic
    |> String.replace(~r/<em>(.*?)<\/em>/s, "#{@ansi_italic}\\1#{@ansi_reset}")
    # Inline code
    |> String.replace(~r/<code[^>]*>(.*?)<\/code>/s, "#{@ansi_dim}\\1#{@ansi_reset}")
    # Images → alt text only (strip src)
    |> String.replace(~r/<img[^>]*alt="([^"]*)"[^>]*\/?>/s, "\\1")
    |> String.replace(~r/<img[^>]*\/?>/s, "")
    # Links → text (url)
    |> String.replace(~r/<a[^>]*href="([^"]*)"[^>]*>(.*?)<\/a>/s, "\\2 (\\1)")
    # Paragraphs → text + newline
    |> String.replace(~r/<p>(.*?)<\/p>/s, "\\1\n")
    # List items
    |> String.replace(~r/<li>(.*?)<\/li>/s, "  \u2022 \\1\n")
    # Blockquotes → indented
    |> String.replace(~r/<blockquote>(.*?)<\/blockquote>/s, "  | \\1")
    # Strip remaining HTML tags (keep their text content)
    |> String.replace(~r/<[^>]+>/, "")
    # Decode common HTML entities
    |> decode_html_entities()
  end

  # Replace h1-h6 tags: uppercase the content and wrap with underline ANSI.
  @spec replace_heading_tags(String.t()) :: String.t()
  defp replace_heading_tags(html) do
    Regex.replace(~r/<h[1-6][^>]*>(.*?)<\/h[1-6]>/s, html, fn _, content ->
      # Strip any inner HTML tags (e.g., from anchors in headings)
      plain = String.replace(content, ~r/<[^>]+>/, "")
      "#{@ansi_underline}#{String.upcase(plain)}#{@ansi_reset}\n"
    end)
  end

  # Replace fenced code blocks (<pre>...</pre> in MDEx HTML output).
  # MDEx adds syntax-highlighting spans and <div class="line"> wrappers.
  # Extract plain text by stripping all inner HTML tags, then apply dim +
  # 2-space indent per line.
  @spec replace_code_blocks(String.t()) :: String.t()
  defp replace_code_blocks(html) do
    Regex.replace(~r/<pre[^>]*>(.*?)<\/pre>/s, html, fn _, content ->
      # Extract plain text: strip all HTML tags inside the pre block
      plain_text = String.replace(content, ~r/<[^>]+>/, "")

      # Decode HTML entities in code content
      decoded = decode_html_entities(plain_text)

      # Split into lines and apply dim + 2-space indent, skipping trailing empty line
      lines =
        decoded
        |> String.trim_trailing("\n")
        |> String.split("\n")
        |> Enum.map_join("\n", fn line -> "  #{@ansi_dim}#{line}#{@ansi_reset}" end)

      lines <> "\n"
    end)
  end

  # Decode common HTML entities produced by MDEx.
  @spec decode_html_entities(String.t()) :: String.t()
  defp decode_html_entities(text) do
    text
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&apos;", "'")
    |> String.replace("&nbsp;", " ")
  end
end
