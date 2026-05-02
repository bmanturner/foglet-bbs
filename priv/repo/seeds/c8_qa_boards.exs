# QA seed for FOG-256 (C8) — test boards covering chat-disabled, chat-permanent,
# and chat-ephemeral (60s TTL) cases. Idempotent. Run with:
#
#     mix run priv/repo/seeds/c8_qa_boards.exs

import Ecto.Query, warn: false

alias Foglet.Boards.Board
alias Foglet.Boards.Category
alias FogletBbs.Repo

category =
  case Repo.get_by(Category, name: "QA") do
    nil ->
      Repo.insert!(%Category{
        name: "QA",
        description: "QA test fixtures (FOG-256)",
        display_order: 99,
        archived: false
      })

    existing ->
      existing
  end

boards = [
  %{
    slug: "qa-no-chat",
    name: "QA No Chat",
    description: "Chat-disabled board for FOG-256 scenario 1.",
    chat_enabled: false,
    chat_storage_mode: :ephemeral,
    chat_message_ttl_seconds: 7200
  },
  %{
    slug: "qa-perm-chat",
    name: "QA Perm Chat",
    description: "Chat-enabled permanent board for FOG-256 scenarios 2-6, 8-9.",
    chat_enabled: true,
    chat_storage_mode: :permanent,
    chat_message_ttl_seconds: 7200
  },
  %{
    slug: "qa-eph-chat",
    name: "QA Eph Chat",
    description: "Chat-enabled ephemeral (60s TTL) board for FOG-256 scenarios 7-8.",
    chat_enabled: true,
    chat_storage_mode: :ephemeral,
    chat_message_ttl_seconds: 60
  }
]

Enum.each(boards, fn attrs ->
  case Repo.get_by(Board, slug: attrs.slug) do
    nil ->
      Repo.insert!(
        struct(Board, %{
          slug: attrs.slug,
          name: attrs.name,
          description: attrs.description,
          display_order: 100,
          readable_by: :public,
          postable_by: :members,
          default_subscription: false,
          required_subscription: false,
          archived: false,
          category_id: category.id,
          chat_enabled: attrs.chat_enabled,
          chat_storage_mode: attrs.chat_storage_mode,
          chat_message_ttl_seconds: attrs.chat_message_ttl_seconds
        })
      )

      IO.puts("  [c8 seed] inserted board #{attrs.slug}")

    _existing ->
      IO.puts("  [c8 seed] board #{attrs.slug} already present")
  end
end)

# QA users (qa1, qa2) for two-session scenarios. Auto-confirmed.
alias Foglet.Accounts
alias Foglet.Accounts.User

now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
qa_password_hash = Argon2.hash_pwd_salt("qapassword123!")

Enum.each([
  {"qa1", "qa1@localhost"},
  {"qa2", "qa2@localhost"}
], fn {handle, email} ->
  case Repo.get_by(User, handle: handle) do
    nil ->
      Repo.insert!(
        %User{
          handle: handle,
          email: email,
          password_hash: qa_password_hash,
          confirmed_at: now,
          role: :user,
          show_in_last_callers: true
        },
        on_conflict: :nothing
      )

      IO.puts("  [c8 seed] inserted user #{handle}")

    _existing ->
      IO.puts("  [c8 seed] user #{handle} already present")
  end
end)

IO.puts("C8 QA seed complete.")
