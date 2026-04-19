# Baseline of pre-existing dialyzer warnings captured when `mix dialyzer` was
# first added to the precommit alias. Each entry is a {path, warning_type} pair
# that matches any warning of that type in that file.
#
# The goal is to fail precommit on NEW warnings while letting the existing
# noise coexist. When touching a file below, consider fixing its warnings and
# removing the ignore entry.
#
# Categories represented:
#   * :unknown_type          — Ecto-schema `t/0` types dialyzer can't resolve
#                              from `use Ecto.Schema`. Not a real bug.
#   * :call_without_opaque   — Ecto.Changeset / Ecto.Multi opaque-type
#                              false-positives.
#   * :contract_supertype    — `@spec` is broader than the success typing.
#                              Style warning, not a bug.

[
  {"lib/foglet_bbs/accounts.ex", :call_without_opaque},
  {"lib/foglet_bbs/boards.ex", :unknown_type},
  {"lib/foglet_bbs/boards/server.ex", :unknown_type},
  {"lib/foglet_bbs/boards/server.ex", :call_without_opaque},
  {"lib/foglet_bbs/posts.ex", :unknown_type},
  {"lib/foglet_bbs/posts.ex", :call_without_opaque},
  {"lib/foglet_bbs/threads.ex", :unknown_type},
  {"lib/foglet_bbs/threads.ex", :call_without_opaque},
  {"lib/foglet_bbs/tui/screens/board_list.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/screens/login.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/screens/new_thread.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/screens/post_composer.ex", :contract_supertype}
]
