---
plan: 02-04
phase: 02-domain-core
status: complete
completed: 2026-04-18
---

## Summary

Implemented `Foglet.Markdown.render/1` — an MDEx-based Markdown-to-ANSI transformer — and replaced all 8 pending markdown test stubs with 24 passing tests. This completes Phase 2: all 12 BOARD requirements are now implemented and tested.

## Implementation Approach: HTML Transform

Chose HTML transform over AST walking:
- `MDEx.to_html!(markdown)` parses CommonMark + GFM to HTML
- A series of `String.replace/3` and `Regex.replace/3` calls transform HTML tags to ANSI sequences
- Unknown/unsupported tags are stripped (text content kept)
- This is simpler and more stable than AST API which could change between MDEx versions

## ANSI Mapping (D-02)

| Element | HTML tag(s) | ANSI output |
|---------|------------|-------------|
| Bold | `<strong>` | `\e[1m...\e[0m` |
| Italic | `<em>` | `\e[3m...\e[0m` |
| Headings | `<h1>`-`<h6>` | `\e[4mUPPERCASED\e[0m\n` |
| Inline code | `<code>` | `\e[2m...\e[0m` |
| Code blocks | `<pre>...<code>...</code>...</pre>` | 2-space indent + `\e[2m...\e[0m` per line |
| Links | `<a href="url">text</a>` | `text (url)` |
| Images | `<img alt="alt" src="...">` | alt text only |

## MDEx HTML Deviation from Plan

MDEx with syntax highlighting enabled (default) outputs code blocks as:
```html
<pre class="lumis" style="color: ..."><code class="language-X" ...>
  <div class="line" data-line="1"><span style="color: ...">token</span>...</div>
</code></pre>
```

The plan assumed `<pre><code>content</code></pre>` — the actual output includes:
- `class` and `style` attributes on `<pre>` and `<code>`
- `<div class="line">` wrappers per line
- `<span style="color: ...">` for syntax tokens

The `replace_code_blocks/1` function handles this by:
1. Matching `<pre[^>]*>...</pre>` to capture all pre block content regardless of attributes
2. Stripping ALL inner HTML tags to extract plain text
3. Applying dim + 2-space indent per line

## Security (T-2-03)

`strip_ansi/1` removes raw `\x1b` ESC characters and CSI sequences (`\e[...m`) from user input before MDEx processes it. All ANSI sequences in output originate exclusively from parsed HTML tag types — user text cannot inject terminal color codes.

## Test Results

24 tests, 0 failures:
- Bold rendering (2 tests)
- Italic rendering (2 tests)
- Heading rendering: h1-h6 (3 tests)
- Inline code (1 test)
- Code blocks: dim + indent, no inner markdown expansion (2 tests)
- Links: text (url) format, no HTML (2 tests)
- Images: alt text only, no src (2 tests)
- ANSI injection defense: strip single/multiple/bare ESC, bold still works (4 tests)
- Edge cases: combined, plain text, empty, nested, paragraphs, entities (6 tests)

Full suite: 138 tests pass, 0 pending, 0 failures.

## Self-Check: PASSED

- `mix compile --warnings-as-errors` exits 0
- `mix credo --strict` exits 0
- `mix test test/foglet_bbs/markdown_test.exs` exits 0 (24 pass)
- `mix test` exits 0 (138 pass, 0 pending)
- `mix precommit` exits 0
- `grep "@tag :pending" test/foglet_bbs/markdown_test.exs` → no matches
