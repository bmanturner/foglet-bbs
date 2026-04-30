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
  {"lib/foglet_bbs/boards.ex", :unknown_type},
  {"lib/foglet_bbs/boards/server.ex", :unknown_type},
  {"lib/foglet_bbs/posts.ex", :unknown_type},
  {"lib/foglet_bbs/threads.ex", :unknown_type},
  {"lib/foglet_bbs/tui/screens/account.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/screens/board_list.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/screens/login.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/screens/login/state.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/screens/main_menu.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/screens/moderation.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/screens/new_thread.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/screens/sysop.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/screens/post_composer.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/screens/post_reader.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/screens/register.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/screens/register/state.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/screens/thread_list.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/screens/verify.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/screens/verify/state.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/size_gate.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/widgets/display/progress.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/widgets/display/tree.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/widgets/input/button.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/widgets/input/checkbox.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/widgets/input/menu.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/widgets/input/tabs.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/widgets/post/post_card.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/widgets/progress/spinner.ex", :contract_supertype},
  # Phase 25 Account forms intentionally expose a defensive :no_match fallback
  # even though current call sites only route supported form events.
  {"lib/foglet_bbs/tui/screens/account/prefs_form.ex",
   "The pattern can never match the type true."},
  {"lib/foglet_bbs/tui/screens/account/profile_form.ex",
   "The pattern can never match the type true."}
]
