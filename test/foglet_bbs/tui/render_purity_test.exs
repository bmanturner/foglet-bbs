defmodule Foglet.TUI.RenderPurityTest do
  use ExUnit.Case, async: true

  @screens_root "lib/foglet_bbs/tui/screens"

  @whole_file_render_suffixes [
    "/render.ex",
    "_surface.ex"
  ]

  @forbidden_render_patterns [
    {"Repo calls", ~r/\b(?:FogletBbs\.)?Repo\./},
    {"Config persistence reads/writes", ~r/\b(?:Foglet\.)?Config\.(?:get|get!|fetch|put|put!)\(/},
    {"PubSub calls", ~r/\b(?:Phoenix\.)?PubSub\./},
    {"Effect.task", ~r/\bEffect\.task\(/},
    {"process spawning", ~r/\b(?:Task|Process)\.(?:async|start|start_link|spawn|send_after)\(/},
    {"direct send", ~r/\bsend\(/},
    {"System calls", ~r/\bSystem\./},
    {"durable context mutations",
     ~r/\bFoglet\.(?:Accounts|Boards|Threads|Posts|BoardFeeds|Notifications|Oneliners|Moderation|Reporting|DMs)\.(?:create|update|delete|insert|mark|toggle|flush|advance|hide|report|send|subscribe|unsubscribe)/}
  ]

  @doc false
  def screen_source_files do
    Path.wildcard(Path.join(@screens_root, "**/*.ex"))
  end

  test "screen render entry points and render helpers avoid obvious side effects" do
    for path <- screen_source_files() do
      source = File.read!(path)

      assert {:ok, ast} = Code.string_to_quoted(source, file: path)

      for {name, body} <- render_functions(ast) do
        body_source = Macro.to_string(body)

        for {label, pattern} <- @forbidden_render_patterns do
          refute Regex.match?(pattern, body_source),
                 "#{path}:#{name} must not contain #{label}"
        end
      end
    end
  end

  test "dedicated render surface files contain no obvious runtime side effects" do
    for path <- screen_source_files(), whole_file_render_surface?(path) do
      source = File.read!(path)

      for {label, pattern} <- @forbidden_render_patterns do
        refute Regex.match?(pattern, source),
               "#{path} must not contain #{label}"
      end
    end
  end

  defp render_functions(ast) do
    {_ast, functions} =
      Macro.prewalk(ast, [], fn
        {kind, _meta, [{name, _fun_meta, args}, body]} = node, acc
        when kind in [:def, :defp] and is_atom(name) and is_list(args) ->
          acc =
            if render_function_name?(name) do
              [{name, body} | acc]
            else
              acc
            end

          {node, acc}

        node, acc ->
          {node, acc}
      end)

    functions
  end

  defp render_function_name?(:render), do: true

  defp render_function_name?(name) do
    name
    |> Atom.to_string()
    |> String.starts_with?("render_")
  end

  defp whole_file_render_surface?(path) do
    Enum.any?(@whole_file_render_suffixes, &String.ends_with?(path, &1))
  end
end
