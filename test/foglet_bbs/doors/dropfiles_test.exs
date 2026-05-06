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
    sysop_name: "Ada Lovelace"
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

    test "renders DOOR.SYS with exact CRLF-terminated lines" do
      assert {:ok, text} = Dropfiles.render(:door_sys, @attrs)

      assert text ==
               "COM0:\r\n" <>
                 "0\r\n" <>
                 "38400\r\n" <>
                 "Foglet BBS\r\n" <>
                 "alice\r\n" <>
                 "Alice Liddell\r\n" <>
                 "Wonderland\r\n" <>
                 "\r\n" <>
                 "132\r\n" <>
                 "37\r\n" <>
                 "GR\r\n" <>
                 "1\r\n" <>
                 "1\r\n" <>
                 "12/31/99\r\n" <>
                 "1440\r\n" <>
                 "1440\r\n" <>
                 "GR\r\n" <>
                 "9999\r\n" <>
                 "01/01/80\r\n" <>
                 "user-1\r\n" <>
                 "0\r\n" <>
                 "N\r\n" <>
                 "\r\n" <>
                 "\r\n" <>
                 "N\r\n" <>
                 "N\r\n" <>
                 "N\r\n" <>
                 "0\r\n" <>
                 "0\r\n" <>
                 "0\r\n" <>
                 "9999\r\n" <>
                 "01/01/80\r\n" <>
                 "mod\r\n" <>
                 "\r\n" <>
                 "0\r\n" <>
                 "0\r\n" <>
                 "0\r\n" <>
                 "132\r\n" <>
                 "37\r\n" <>
                 "session-1\r\n"
    end

    test "renders DORINFO.DEF with exact CRLF-terminated lines without reading process state" do
      assert {:ok, text} = Dropfiles.render(:dorinfo_def, @attrs)

      assert text ==
               "Foglet BBS\r\n" <>
                 "Ada\r\n" <>
                 "Lovelace\r\n" <>
                 "COM0\r\n" <>
                 "38400 BAUD,N,8,1\r\n" <>
                 "0\r\n" <>
                 "alice\r\n" <>
                 "Alice Liddell\r\n" <>
                 "Wonderland\r\n" <>
                 "80\r\n"
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

      assert {:ok, paths} = Dropfiles.write([:chain_txt, :door_sys, :dorinfo_def], @attrs, tmp)

      assert paths == %{
               chain_txt: Path.join(tmp, "CHAIN.TXT"),
               door_sys: Path.join(tmp, "DOOR.SYS"),
               dorinfo_def: Path.join(tmp, "DORINFO.DEF")
             }

      assert File.read!(paths.chain_txt) == elem(Dropfiles.render(:chain_txt, @attrs), 1)
      assert File.read!(paths.door_sys) == elem(Dropfiles.render(:door_sys, @attrs), 1)
      assert File.read!(paths.dorinfo_def) == elem(Dropfiles.render(:dorinfo_def, @attrs), 1)
    end
  end
end
