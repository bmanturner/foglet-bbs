defmodule Foglet.TUI.Widgets.Profile.PublicProfileCardTest do
  use ExUnit.Case, async: true

  alias Foglet.Accounts.PublicProfile
  alias Foglet.Sessions.PresenceSummary
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Profile.PublicProfileCard

  describe "render/2 role row" do
    test "omits the role row for normal member profiles" do
      rendered =
        :user
        |> profile()
        |> PublicProfileCard.render(Theme.default())

      contents = text_contents(rendered)

      assert "@foglet" in contents
      refute "member" in contents
      refute "user" in contents
      assert Enum.any?(contents, &String.starts_with?(&1, "─"))
      assert "Posts:      " in contents
    end

    test "keeps moderator and sysop role badges" do
      mod_contents =
        :mod
        |> profile()
        |> PublicProfileCard.render(Theme.default())
        |> text_contents()

      sysop_contents =
        :sysop
        |> profile()
        |> PublicProfileCard.render(Theme.default())
        |> text_contents()

      assert "✦ MOD" in mod_contents
      assert "✹ SYSOP" in sysop_contents
    end
  end

  defp profile(role) do
    %PublicProfile{
      handle: "foglet",
      role: role,
      post_count: 0,
      joined_at: ~U[2026-01-01 00:00:00Z],
      presence: %PresenceSummary{}
    }
  end

  defp text_contents(%{type: :text, content: content}), do: [content]

  defp text_contents(%{children: children}) when is_list(children) do
    Enum.flat_map(children, &text_contents/1)
  end

  defp text_contents(_), do: []
end
