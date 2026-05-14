defmodule Foglet.TUI.Text do
  @moduledoc """
  Lightweight styled text composition for TUI render code.

  The value types are:

    * `%Foglet.TUI.Text.Span{}` - one styled run.
    * `%Foglet.TUI.Text.Line{}` - ordered spans on one row.
    * `%Foglet.TUI.Text{}` - ordered lines.

  Color helpers accept `Foglet.TUI.Theme` slot atoms such as `:primary`,
  `:dim`, or `:accent`. Slots are resolved only by `to_raxol/2`, keeping
  render code pure over an already-loaded theme snapshot. Raw binary or RGB
  color values are also accepted for existing widget contracts that already
  allow raw Raxol colors; raw terminal color atoms such as `:red` are rejected.
  """

  import Raxol.Core.Renderer.View, only: [column: 2, row: 2, text: 2]

  alias __MODULE__.Line
  alias __MODULE__.Span
  alias Foglet.TUI.Theme

  @style_atoms [:bold, :dim, :italic, :underline]

  defstruct lines: []

  @type color_ref :: Theme.slot_key() | String.t() | {byte(), byte(), byte()}
  @type t :: %__MODULE__{lines: [Line.t()]}

  defmodule Span do
    @moduledoc "A single styled text run."

    alias Foglet.TUI.Text

    defstruct content: "", fg: nil, bg: nil, style: []

    @type t :: %__MODULE__{
            content: String.t(),
            fg: Text.color_ref() | nil,
            bg: Text.color_ref() | nil,
            style: [atom()]
          }

    @spec new(String.Chars.t()) :: t()
    def new(content), do: %__MODULE__{content: to_string(content)}

    @spec new(String.Chars.t(), keyword()) :: t()
    def new(content, opts) when is_list(opts) do
      content
      |> new()
      |> Text.apply_opts(opts)
    end

    @spec append(t(), String.Chars.t()) :: t()
    def append(%__MODULE__{} = span, content),
      do: %{span | content: span.content <> to_string(content)}

    @spec fg(t(), Text.color_ref()) :: t()
    def fg(%__MODULE__{} = span, color), do: Text.fg(span, color)

    @spec bg(t(), Text.color_ref()) :: t()
    def bg(%__MODULE__{} = span, color), do: Text.bg(span, color)

    @spec bold(t()) :: t()
    def bold(%__MODULE__{} = span), do: Text.bold(span)

    @spec dim(t()) :: t()
    def dim(%__MODULE__{} = span), do: Text.dim(span)

    @spec italic(t()) :: t()
    def italic(%__MODULE__{} = span), do: Text.italic(span)

    @spec underline(t()) :: t()
    def underline(%__MODULE__{} = span), do: Text.underline(span)
  end

  defmodule Line do
    @moduledoc "A single row made from styled spans."

    alias Foglet.TUI.Text
    alias Foglet.TUI.Text.Span

    defstruct spans: []

    @type t :: %__MODULE__{spans: [Span.t()]}

    @spec new(String.Chars.t() | Span.t() | [Span.t()]) :: t()
    def new(spans_or_content)

    def new(spans) when is_list(spans), do: %__MODULE__{spans: Enum.map(spans, &span!/1)}
    def new(%Span{} = span), do: %__MODULE__{spans: [span]}
    def new(content), do: %__MODULE__{spans: [Span.new(content)]}

    @spec new(String.Chars.t() | Span.t() | [Span.t()], keyword()) :: t()
    def new(spans_or_content, opts) when is_list(opts) do
      spans_or_content
      |> new()
      |> Text.apply_opts(opts)
    end

    @spec append(t(), String.Chars.t() | Span.t()) :: t()
    def append(%__MODULE__{} = line, span_or_content),
      do: %{line | spans: line.spans ++ [span!(span_or_content)]}

    @spec fg(t(), Text.color_ref()) :: t()
    def fg(%__MODULE__{} = line, color), do: Text.fg(line, color)

    @spec bg(t(), Text.color_ref()) :: t()
    def bg(%__MODULE__{} = line, color), do: Text.bg(line, color)

    @spec bold(t()) :: t()
    def bold(%__MODULE__{} = line), do: Text.bold(line)

    @spec dim(t()) :: t()
    def dim(%__MODULE__{} = line), do: Text.dim(line)

    @spec italic(t()) :: t()
    def italic(%__MODULE__{} = line), do: Text.italic(line)

    @spec underline(t()) :: t()
    def underline(%__MODULE__{} = line), do: Text.underline(line)

    defp span!(%Span{} = span), do: span
    defp span!(content), do: Span.new(content)
  end

  @doc "Builds a multi-line text value."
  @spec new(String.Chars.t() | Span.t() | Line.t() | [Line.t() | Span.t() | String.Chars.t()]) ::
          t()
  def new(lines_or_content)

  def new(lines) when is_list(lines), do: %__MODULE__{lines: Enum.map(lines, &line!/1)}
  def new(%Line{} = line), do: %__MODULE__{lines: [line]}
  def new(%Span{} = span), do: %__MODULE__{lines: [Line.new(span)]}
  def new(content), do: %__MODULE__{lines: [Line.new(content)]}

  @doc "Builds a multi-line text value and applies style options."
  @spec new(
          String.Chars.t() | Span.t() | Line.t() | [Line.t() | Span.t() | String.Chars.t()],
          keyword()
        ) :: t()
  def new(lines_or_content, opts) when is_list(opts) do
    lines_or_content
    |> new()
    |> apply_opts(opts)
  end

  @doc "Appends a line, span, or plain string."
  @spec append(t(), Line.t() | Span.t() | String.Chars.t()) :: t()
  def append(%__MODULE__{} = text, %Line{} = line), do: %{text | lines: text.lines ++ [line]}

  def append(%__MODULE__{} = text, %Span{} = span),
    do: %{text | lines: text.lines ++ [Line.new(span)]}

  def append(%__MODULE__{} = text, content), do: append(text, Line.new(content))

  @doc "Sets foreground color from a theme slot or allowed raw color value."
  @spec fg(Span.t() | Line.t() | t(), color_ref()) :: Span.t() | Line.t() | t()
  def fg(value, color), do: map_spans(value, &%{&1 | fg: validate_color!(color)})

  @doc "Sets background color from a theme slot or allowed raw color value."
  @spec bg(Span.t() | Line.t() | t(), color_ref()) :: Span.t() | Line.t() | t()
  def bg(value, color), do: map_spans(value, &%{&1 | bg: validate_color!(color)})

  @doc "Adds bold styling."
  @spec bold(Span.t() | Line.t() | t()) :: Span.t() | Line.t() | t()
  def bold(value), do: add_style(value, :bold)

  @doc "Adds dim styling."
  @spec dim(Span.t() | Line.t() | t()) :: Span.t() | Line.t() | t()
  def dim(value), do: add_style(value, :dim)

  @doc "Adds italic styling."
  @spec italic(Span.t() | Line.t() | t()) :: Span.t() | Line.t() | t()
  def italic(value), do: add_style(value, :italic)

  @doc "Adds underline styling."
  @spec underline(Span.t() | Line.t() | t()) :: Span.t() | Line.t() | t()
  def underline(value), do: add_style(value, :underline)

  @doc """
  Converts a composed text value into the Raxol view tree used by current renderers.
  """
  @spec to_raxol(Span.t() | Line.t() | t(), Theme.t()) :: any()
  def to_raxol(%Span{} = span, %Theme{} = theme), do: text(span.content, span_opts(span, theme))

  def to_raxol(%Line{spans: [span]}, %Theme{} = theme), do: to_raxol(span, theme)

  def to_raxol(%Line{} = line, %Theme{} = theme) do
    row style: %{gap: 0} do
      Enum.map(line.spans, &to_raxol(&1, theme))
    end
  end

  def to_raxol(%__MODULE__{lines: [line]}, %Theme{} = theme), do: to_raxol(line, theme)

  def to_raxol(%__MODULE__{} = text_value, %Theme{} = theme) do
    column style: %{gap: 0} do
      Enum.map(text_value.lines, &to_raxol(&1, theme))
    end
  end

  @doc false
  def apply_opts(value, opts) when is_list(opts) do
    Enum.reduce(opts, value, fn
      {:fg, color}, acc ->
        fg(acc, color)

      {:bg, color}, acc ->
        bg(acc, color)

      {:style, styles}, acc when is_list(styles) ->
        Enum.reduce(styles, acc, &add_style(&2, &1))

      {:bold, true}, acc ->
        bold(acc)

      {:dim, true}, acc ->
        dim(acc)

      {:italic, true}, acc ->
        italic(acc)

      {:underline, true}, acc ->
        underline(acc)

      {_key, false}, acc ->
        acc

      {key, value}, _acc ->
        raise ArgumentError, "invalid text option #{inspect(key)}=#{inspect(value)}"
    end)
  end

  defp add_style(value, style) when style in @style_atoms do
    map_spans(value, &%{&1 | style: Enum.uniq(&1.style ++ [style])})
  end

  defp add_style(_value, style),
    do: raise(ArgumentError, "unsupported text style: #{inspect(style)}")

  defp map_spans(%Span{} = span, fun), do: fun.(span)

  defp map_spans(%Line{} = line, fun),
    do: %{line | spans: Enum.map(line.spans, fun)}

  defp map_spans(%__MODULE__{} = text_value, fun),
    do: %{text_value | lines: Enum.map(text_value.lines, &map_spans(&1, fun))}

  defp map_spans(value, _fun),
    do: raise(ArgumentError, "expected styled text value, got: #{inspect(value)}")

  defp span_opts(%Span{} = span, %Theme{} = theme) do
    []
    |> maybe_put(:fg, resolve_color(span.fg, theme, :fg))
    |> maybe_put(:bg, resolve_color(span.bg, theme, :bg))
    |> maybe_put(:style, span.style)
  end

  defp resolve_color(nil, _theme, _channel), do: nil

  defp resolve_color(slot, %Theme{} = theme, channel) when is_atom(slot) do
    theme
    |> Map.fetch!(slot)
    |> Map.fetch!(channel)
  end

  defp resolve_color(raw, _theme, _channel), do: raw

  defp validate_color!(color) when is_atom(color) do
    if color in Theme.slot_keys() do
      color
    else
      raise ArgumentError,
            "raw terminal color atoms are not accepted by Foglet.TUI.Text; use a Theme slot atom"
    end
  end

  defp validate_color!(color) when is_binary(color), do: color

  defp validate_color!({r, g, b} = color)
       when r in 0..255 and g in 0..255 and b in 0..255,
       do: color

  defp validate_color!(color), do: raise(ArgumentError, "invalid text color: #{inspect(color)}")

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, :style, []), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp line!(%Line{} = line), do: line
  defp line!(%Span{} = span), do: Line.new(span)
  defp line!(content), do: Line.new(content)
end
