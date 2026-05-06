defmodule Foglet.AppNameTest do
  use ExUnit.Case, async: false

  alias Foglet.AppName

  setup do
    original = Application.get_env(:foglet_bbs, :app_name)
    original_env = System.get_env("FOGLET_APP_NAME")

    on_exit(fn ->
      case original do
        nil -> Application.delete_env(:foglet_bbs, :app_name)
        value -> Application.put_env(:foglet_bbs, :app_name, value)
      end

      case original_env do
        nil -> System.delete_env("FOGLET_APP_NAME")
        value -> System.put_env("FOGLET_APP_NAME", value)
      end
    end)

    Application.delete_env(:foglet_bbs, :app_name)
    System.delete_env("FOGLET_APP_NAME")

    :ok
  end

  describe "name/0" do
    test "falls back to Foglet when no runtime app name is configured" do
      assert AppName.name() == "Foglet"
    end

    test "uses a configured public app name" do
      Application.put_env(:foglet_bbs, :app_name, "Foglet BBS")

      assert AppName.name() == "Foglet BBS"
    end

    test "uses FOGLET_APP_NAME when boot-time app config is absent" do
      System.put_env("FOGLET_APP_NAME", "Custom BBS")

      assert AppName.name() == "Custom BBS"
    end

    test "falls back to Foglet when the configured app name is blank or whitespace" do
      Application.put_env(:foglet_bbs, :app_name, "  \t\n  ")

      assert AppName.name() == "Foglet"
    end

    test "removes terminal control characters and trims surrounding whitespace" do
      Application.put_env(:foglet_bbs, :app_name, " \e[31mFog\nlet\tBBS\e[0m ")

      assert AppName.name() == "Foglet BBS"
    end

    test "clips very long configured names to a safe terminal width" do
      Application.put_env(:foglet_bbs, :app_name, String.duplicate("A", 80))

      assert AppName.name() == String.duplicate("A", 32)
    end
  end
end
