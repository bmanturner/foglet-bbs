defmodule Foglet.TUI.Widgets.Profile.PublicProfileCardTest do
  use ExUnit.Case, async: true

  alias Foglet.Accounts.PublicProfile
  alias Foglet.Sessions.PresenceSummary
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Profile.PublicProfileCard

  describe "render/2 role row" do
    test "renders door presence as Playing <door name>" do
      contents =
        :user
        |> profile()
        |> Map.put(:presence, %PresenceSummary{
          activity: {:playing_door, %{id: "lord", name: "Legend of the Red Dragon"}},
          label: "Playing Legend of the Red Dragon",
          online?: true
        })
        |> PublicProfileCard.render(Theme.default())
        |> text_contents()
        |> Enum.join("\n")

      assert contents =~ "Presence:   \nPlaying Legend of the Red Dragon"
      refute contents =~ "Last seen"
    end

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
      assert detail_value(contents, "Posts") == "0"
      assert detail_value(contents, "Karma") == "0"
    end

    test "renders nonzero karma with existing stats" do
      contents =
        :user
        |> profile()
        |> Map.put(:post_count, 3)
        |> Map.put(:karma, 17)
        |> PublicProfileCard.render(Theme.default())
        |> text_contents()

      assert detail_value(contents, "Posts") == "3"
      assert detail_value(contents, "Karma") == "17"
      assert detail_value(contents, "Joined") == "2026-01-01"
      assert detail_value(contents, "Presence") == "Offline"
    end

    test "renders zero karma without regressing offline last-seen row" do
      contents =
        :user
        |> profile()
        |> Map.put(:karma, 0)
        |> Map.put(:last_seen_at, ~U[2026-01-02 00:00:00Z])
        |> PublicProfileCard.render(Theme.default())
        |> text_contents()

      assert detail_value(contents, "Karma") == "0"
      assert detail_value(contents, "Presence") == "Offline"
      assert detail_value(contents, "Last seen") =~ "ago"
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
      karma: 0,
      joined_at: ~U[2026-01-01 00:00:00Z],
      presence: %PresenceSummary{}
    }
  end

  defp detail_value(contents, label) do
    label_text = String.pad_trailing(label <> ":", 12)

    contents
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find_value(fn
      [^label_text, value] -> value
      _ -> nil
    end)
  end

  defp text_contents(%{type: :text, content: content}), do: [content]

  defp text_contents(%{children: children}) when is_list(children) do
    Enum.flat_map(children, &text_contents/1)
  end

  defp text_contents(_), do: []
end
