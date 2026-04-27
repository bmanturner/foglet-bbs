defmodule Mix.Tasks.Foglet.Tui.Render do
  @moduledoc """
  Renders a Foglet BBS TUI screen as plain text so agents (and humans) can
  inspect the layout without an SSH client.

  ## Usage

      rtk mix foglet.tui.render <screen> [--width N] [--height N]
      rtk mix foglet.tui.render --list

  ## Options

    * `--width`   — terminal width in columns (default: 80)
    * `--height`  — terminal height in rows (default: 24)
    * `--list`    — print the available screen names and exit
    * `--no-frame` — omit the alignment ruler around the output

  ## Examples

      rtk mix foglet.tui.render main_menu
      rtk mix foglet.tui.render board_list --width 132 --height 50
      rtk mix foglet.tui.render post_reader --width 80 --height 30

  Authenticated screens are populated with a synthetic in-memory user and
  stub board/thread/post data — no Repo, no SSH, no PubSub. The output is
  layout + content only (no ANSI colors), so it diffs cleanly across runs.
  """
  @shortdoc "Render a TUI screen to ASCII for inspection"

  use Mix.Task

  alias Foglet.TUI.App
  alias Foglet.TUI.AsciiRenderer
  alias Foglet.TUI.RenderFixtures

  @switches [
    width: :integer,
    height: :integer,
    list: :boolean,
    no_frame: :boolean
  ]

  @default_width 80
  @default_height 24

  @impl Mix.Task
  def run(args) do
    {opts, positional, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [] do
      Mix.raise("Unknown options: #{inspect(invalid)}")
    end

    cond do
      opts[:list] ->
        list_screens()

      positional == [] ->
        Mix.shell().error("Missing screen argument.\n")
        Mix.shell().info(@moduledoc)
        exit({:shutdown, 1})

      true ->
        # `app.start` is intentionally NOT a @requirements — fixtures don't
        # need the Repo or SSH server. We only load the app modules.
        Mix.Task.run("loadpaths")
        Mix.Task.run("compile")

        Code.ensure_loaded!(RenderFixtures)
        Code.ensure_loaded!(App)
        Code.ensure_loaded!(AsciiRenderer)

        # ClockFormatter calls Timex which calls Tzdata, which requires its
        # own application to be running for the named ETS tables to exist.
        {:ok, _} = Application.ensure_all_started(:tzdata)

        seed_config_cache()

        screen = parse_screen(hd(positional))
        width = opts[:width] || @default_width
        height = opts[:height] || @default_height

        validate_size!(width, height)

        state = RenderFixtures.state_for(screen, {width, height})
        view = App.view(state)
        ascii = AsciiRenderer.render(view, {width, height})

        if opts[:no_frame] do
          IO.puts(ascii)
        else
          IO.puts(framed(ascii, screen, width, height))
        end
    end
  end

  defp list_screens do
    Mix.shell().info("Available screens:")

    Enum.each(RenderFixtures.screens(), fn screen ->
      Mix.shell().info("  #{screen}")
    end)
  end

  defp parse_screen(name) do
    atom =
      try do
        String.to_existing_atom(name)
      rescue
        ArgumentError -> nil
      end

    if atom in RenderFixtures.screens() do
      atom
    else
      Mix.raise("Unknown screen: #{inspect(name)}. Run with --list to see available screens.")
    end
  end

  defp validate_size!(width, height) do
    cond do
      width < 20 -> Mix.raise("--width must be at least 20")
      height < 5 -> Mix.raise("--height must be at least 5")
      width > 500 -> Mix.raise("--width must be at most 500")
      height > 200 -> Mix.raise("--height must be at most 200")
      true -> :ok
    end
  end

  # Render paths read schematized config keys (registration_mode,
  # delivery_mode, max_thread_title_length, max_post_length, …). Seeding the
  # ETS cache with the schema's declared defaults lets the renderer run
  # without a Repo or any DB rows.
  defp seed_config_cache do
    Foglet.Config.init_cache()

    Enum.each(Foglet.Config.Schema.defaults(), fn {key, value} ->
      :ets.insert(:foglet_config, {key, value})
    end)
  end

  defp framed(ascii, screen, width, height) do
    header = "── #{screen} #{width}×#{height} "
    rule = header <> String.duplicate("─", max(width - String.length(header), 0))
    footer = String.duplicate("─", width)
    [rule, ascii, footer] |> Enum.join("\n")
  end
end
