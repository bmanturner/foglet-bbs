defmodule Foglet.Markdown do
  @moduledoc """
  Renders CommonMark Markdown to a structured list of `{text, style}` tuples
  suitable for Raxol `text/2` rendering.

  ## Style Mapping (D-02)

  | Markdown element   | Style atom   |
  |--------------------|--------------|
  | `**bold**`         | `:bold`      |
  | `*italic*`         | `:italic`    |
  | `# Heading`        | `:underline` (uppercased) |
  | `` `code` ``       | `:dim`       |
  | ` ```block``` `    | `:dim` (2-space indent)   |
  | `[text](url)`      | `:plain` as `"text (url)"` |
  | `![alt](url)`      | `:plain` (alt text only)  |

  ## Security

  Raw ANSI escape sequences in user input are stripped before rendering.
  All styled output originates from the parsed Markdown AST — user text
  cannot inject terminal style through post bodies (T-2-03).
  """

  @type style_atom :: :plain | :bold | :italic | :dim | :underline
  @type rendered :: [{String.t(), style_atom()}]

  # Unique marker tokens — chosen to be outside printable ASCII
  # so they cannot appear in normal user text.
  @bold_open "\x00BOLD_OPEN\x00"
  @bold_close "\x00BOLD_CLOSE\x00"
  @italic_open "\x00ITALIC_OPEN\x00"
  @italic_close "\x00ITALIC_CLOSE\x00"
  @dim_open "\x00DIM_OPEN\x00"
  @dim_close "\x00DIM_CLOSE\x00"
  @underline_open "\x00UNDERLINE_OPEN\x00"
  @underline_close "\x00UNDERLINE_CLOSE\x00"

  @doc """
  Render a Markdown string to a list of `{text, style_atom}` tuples.

  Accepts CommonMark + GFM Markdown via MDEx. Returns a structured list
  suitable for Raxol `text/2` rendering. Raw ANSI escape sequences in
  the input are stripped (T-2-03).

  ## Examples

      iex> Foglet.Markdown.render("**hello**")
      [{"hello", :bold}]

      iex> Foglet.Markdown.render("[click](https://example.com)")
      [{"click (https://example.com)", :plain}, {"\\n", :plain}]

  """
  @spec render(String.t()) :: rendered()
  def render(markdown) when is_binary(markdown) do
    # Strip raw ANSI escape sequences from user input (T-2-03)
    sanitized = strip_ansi(markdown)

    if sanitized == "" do
      []
    else
      # Parse to HTML via MDEx (CommonMark + GFM with syntax highlighting)
      html = MDEx.to_html!(sanitized)

      # Transform HTML to marker-delimited string
      marked = transform_html_to_markers(html)

      # Parse markers into {text, style} tuples
      parse_markers(marked)
      |> clean_tuples()
    end
  end

  # ---------- Private helpers ----------

  # Strip raw ESC characters from user-supplied text before passing to MDEx.
  # Prevents injection of terminal escape sequences through post bodies.
  @spec strip_ansi(String.t()) :: String.t()
  defp strip_ansi(text) do
    # Remove ESC character (\x1b) and any following CSI sequence (optional).
    String.replace(text, ~r/\x1b(\[[0-9;]*[A-Za-z~])?/, "")
  end

  # Walk the HTML output from MDEx and replace known tags with markers.
  # Code blocks are handled first to prevent inner tag expansion.
  @spec transform_html_to_markers(String.t()) :: String.t()
  defp transform_html_to_markers(html) do
    html
    # Code blocks first — MDEx wraps fenced code in <pre>...</pre> with syntax
    # highlighting spans. Extract plain text then apply dim + 2-space indent.
    |> replace_code_blocks()
    # Headings → uppercase + underline markers (all h1-h6 treated uniformly per D-02)
    |> replace_heading_tags()
    # Bold
    |> String.replace(
      ~r/<strong>(.*?)<\/strong>/s,
      "#{@bold_open}\\1#{@bold_close}"
    )
    # Italic
    |> String.replace(
      ~r/<em>(.*?)<\/em>/s,
      "#{@italic_open}\\1#{@italic_close}"
    )
    # Inline code
    |> String.replace(
      ~r/<code[^>]*>(.*?)<\/code>/s,
      "#{@dim_open}\\1#{@dim_close}"
    )
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

  # Replace h1-h6 tags: uppercase the content and wrap with underline markers.
  @spec replace_heading_tags(String.t()) :: String.t()
  defp replace_heading_tags(html) do
    Regex.replace(~r/<h[1-6][^>]*>(.*?)<\/h[1-6]>/s, html, fn _, content ->
      # Strip any inner HTML tags (e.g., from anchors in headings)
      plain = String.replace(content, ~r/<[^>]+>/, "")
      "#{@underline_open}#{String.upcase(plain)}#{@underline_close}\n"
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

      # Split into lines and apply dim markers + 2-space indent
      lines =
        decoded
        |> String.trim_trailing("\n")
        |> String.split("\n")
        |> Enum.map_join("\n", fn line ->
          "#{@dim_open}  #{line}#{@dim_close}"
        end)

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

  # Parse marker-delimited string into {text, style} tuples.
  # Walks the string tracking the current active style context.
  @spec parse_markers(String.t()) :: rendered()
  defp parse_markers(text) do
    markers = [
      {@bold_open, :bold},
      {@bold_close, nil},
      {@italic_open, :italic},
      {@italic_close, nil},
      {@dim_open, :dim},
      {@dim_close, nil},
      {@underline_open, :underline},
      {@underline_close, nil}
    ]

    # Build a single regex that splits on any marker
    pattern =
      Enum.map_join(markers, "|", fn {m, _} -> Regex.escape(m) end)

    regex = Regex.compile!("(#{pattern})")

    text
    |> String.split(regex, include_captures: true)
    |> Enum.reduce({[], :plain}, fn chunk, {acc, current_style} ->
      case find_marker(chunk, markers) do
        {:open, style} ->
          {acc, style}

        :close ->
          {acc, :plain}

        :not_a_marker ->
          if chunk == "" do
            {acc, current_style}
          else
            {[{chunk, current_style} | acc], current_style}
          end
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp find_marker(chunk, markers) do
    case Enum.find(markers, fn {m, _} -> m == chunk end) do
      {_m, nil} -> :close
      {_m, style} -> {:open, style}
      nil -> :not_a_marker
    end
  end

  # Remove empty strings and clean up whitespace-only plain tuples
  # that are only newlines (keep them as {"\n", :plain}).
  @spec clean_tuples(rendered()) :: rendered()
  defp clean_tuples(tuples) do
    tuples
    |> Enum.reject(fn {s, _} -> s == "" end)
    |> Enum.flat_map(fn {s, style} ->
      # Split on newlines and emit {"\n", :plain} separators
      # Only do this for plain text — styled text keeps its newlines embedded
      if style == :plain and String.contains?(s, "\n") do
        s
        |> String.split("\n")
        |> Enum.flat_map(fn part ->
          if part == "" do
            [{"\n", :plain}]
          else
            [{part, :plain}, {"\n", :plain}]
          end
        end)
        |> then(fn parts ->
          # Remove trailing newline if it's the last thing
          case List.last(parts) do
            {"\n", :plain} -> List.delete_at(parts, -1)
            _ -> parts
          end
        end)
      else
        [{s, style}]
      end
    end)
    |> Enum.reject(fn {s, _} -> s == "" end)
    # Merge adjacent plain+newline tuples and deduplicate consecutive newlines
    |> deduplicate_newlines()
  end

  defp deduplicate_newlines(tuples) do
    Enum.reduce(tuples, [], fn item, acc ->
      case {item, acc} do
        {{"\n", :plain}, [{"\n", :plain} | _]} ->
          # Skip duplicate consecutive newlines
          acc

        _ ->
          [item | acc]
      end
    end)
    |> Enum.reverse()
  end
end
