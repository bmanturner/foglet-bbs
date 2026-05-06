defmodule Foglet.Doors.DropfilesTest do
  use ExUnit.Case, async: true

  alias Foglet.Doors.Dropfiles

  @attrs %{
    user: %{
      id: "user-1",
      handle: "alice",
      real_name: "Alice Liddell",
      role: :mod,
      location: "Wonderland"
    },
    session: %{
      user_id: "user-1",
      handle: "alice",
      role: :mod,
      session_id: "session-1",
      terminal_size: {132, 37}
    },
    sysop_name: "Ada Lovelace",
    time_remaining_minutes: 42,
    node_number: 7
  }

  describe "render/2" do
    test "renders CHAIN.TXT with exact CRLF-terminated lines" do
      assert {:ok, text} = Dropfiles.render(:chain_txt, @attrs)

      assert text ==
               "alice\r\n" <>
                 "Alice Liddell\r\n" <>
                 "132\r\n" <>
                 "37\r\n" <>
                 "mod\r\n" <>
                 "user-1\r\n"
    end

    test "renders DOOR.SYS with exact parser-critical line positions" do
      assert {:ok, text} = Dropfiles.render(:door_sys, @attrs)

      lines = dropfile_lines(text)

      assert length(lines) == 40
      assert Enum.at(lines, 0) == "COM0:"
      assert Enum.at(lines, 1) == "38400"
      assert Enum.at(lines, 3) == "7"
      assert Enum.at(lines, 9) == "Alice Liddell"
      assert Enum.at(lines, 10) == "Wonderland"
      assert Enum.at(lines, 15) == "90"
      assert Enum.at(lines, 19) == "42"
      assert Enum.at(lines, 20) == "GR"
      assert Enum.at(lines, 21) == "37"
      assert Enum.at(lines, 25) == "1"
      assert Enum.at(lines, 35) == "Ada Lovelace"
      assert Enum.at(lines, 36) == "alice"
      assert Enum.at(lines, 39) == "session-1"

      assert text == Enum.join(lines, "\r\n") <> "\r\n"
    end

    test "renders DOOR32.SYS with exact line positions" do
      assert {:ok, text} = Dropfiles.render(:door32_sys, @attrs)

      assert text ==
               "0\r\n" <>
                 "0\r\n" <>
                 "38400\r\n" <>
                 "Foglet\r\n" <>
                 "user-1\r\n" <>
                 "Alice Liddell\r\n" <>
                 "alice\r\n" <>
                 "90\r\n" <>
                 "42\r\n" <>
                 "7\r\n" <>
                 "session-1\r\n"

      assert dropfile_lines(text) == [
               "0",
               "0",
               "38400",
               "Foglet",
               "user-1",
               "Alice Liddell",
               "alice",
               "90",
               "42",
               "7",
               "session-1"
             ]
    end

    test "renders DOOR32.SYS real name fallback, safe default time, and safe default node" do
      attrs =
        @attrs
        |> put_in([:user, :real_name], "")
        |> Map.delete(:time_remaining_minutes)
        |> Map.delete(:node_number)

      assert {:ok, text} = Dropfiles.render(:door32_sys, attrs)

      lines = dropfile_lines(text)

      assert length(lines) == 11
      assert Enum.at(lines, 5) == "alice"
      assert Enum.at(lines, 7) == "90"
      assert Enum.at(lines, 8) == "1440"
      assert Enum.at(lines, 9) == "1"
    end

    test "renders DOOR32.SYS role security levels" do
      assert {:ok, sysop_text} =
               Dropfiles.render(:door32_sys, put_in(@attrs, [:user, :role], :sysop))

      assert {:ok, mod_text} = Dropfiles.render(:door32_sys, put_in(@attrs, [:user, :role], :mod))

      assert {:ok, user_text} =
               Dropfiles.render(:door32_sys, put_in(@attrs, [:user, :role], :user))

      assert Enum.at(dropfile_lines(sysop_text), 7) == "100"
      assert Enum.at(dropfile_lines(mod_text), 7) == "90"
      assert Enum.at(dropfile_lines(user_text), 7) == "50"
    end

    test "renders DORINFO.DEF with exact CRLF-terminated lines without reading process state" do
      assert {:ok, text} = Dropfiles.render(:dorinfo_def, @attrs)

      assert text ==
               "Foglet\r\n" <>
                 "Ada\r\n" <>
                 "Lovelace\r\n" <>
                 "COM0\r\n" <>
                 "38400 BAUD,N,8,1\r\n" <>
                 "0\r\n" <>
                 "alice\r\n" <>
                 "Alice Liddell\r\n" <>
                 "Wonderland\r\n" <>
                 "90\r\n"
    end

    test "rejects unsupported formats" do
      assert Dropfiles.render(:not_a_dropfile, @attrs) == {:error, :unsupported_format}
      assert Dropfiles.filename(:not_a_dropfile) == {:error, :unsupported_format}
    end
  end

  describe "write/3" do
    test "writes requested formats by atom with fixed filenames" do
      tmp =
        Path.join(
          System.tmp_dir!(),
          "foglet-dropfiles-test-#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)

      assert {:ok, paths} =
               Dropfiles.write([:chain_txt, :door_sys, :door32_sys, :dorinfo_def], @attrs, tmp)

      assert paths == %{
               chain_txt: Path.join(tmp, "CHAIN.TXT"),
               door_sys: Path.join(tmp, "DOOR.SYS"),
               door32_sys: Path.join(tmp, "DOOR32.SYS"),
               dorinfo_def: Path.join(tmp, "DORINFO.DEF")
             }

      assert File.read!(paths.chain_txt) == elem(Dropfiles.render(:chain_txt, @attrs), 1)
      assert File.read!(paths.door_sys) == elem(Dropfiles.render(:door_sys, @attrs), 1)
      assert File.read!(paths.door32_sys) == elem(Dropfiles.render(:door32_sys, @attrs), 1)
      assert File.read!(paths.dorinfo_def) == elem(Dropfiles.render(:dorinfo_def, @attrs), 1)
    end
  end

  defp dropfile_lines(text) do
    text
    |> String.split("\r\n", trim: false)
    |> List.delete_at(-1)
  end
end
