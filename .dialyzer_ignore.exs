# Dialyzer ignore list — post v2.1 cleanup baseline (Phase 46, plan 03).
# Invariant: every kept entry has a stated reason in the shared comment
# block immediately above it. Buckets in order: A → C2 → C* → D.
[
  # Bucket A — Ecto schema t/0 false positives.
  # Dialyzer cannot resolve `t/0` from `use Ecto.Schema`; not a real bug.
  {"lib/foglet_bbs/boards.ex", :unknown_type},
  {"lib/foglet_bbs/boards/server.ex", :unknown_type},
  {"lib/foglet_bbs/posts.ex", :unknown_type},
  {"lib/foglet_bbs/posts/reader_window.ex", :unknown_type},
  {"lib/foglet_bbs/threads.ex", :unknown_type},

  # Bucket C2 — Raxol element() return — opaque from caller perspective.
  # Widget/screen render/1,2 returns Raxol DSL elements composed from
  # internal types not exported in a Dialyzer-resolvable way; narrowing
  # emits a fresh :contract_supertype on the same line (Pitfall 1 in
  # 46-RESEARCH.md). init/1, update/3 on these screens already narrow.
  {"lib/foglet_bbs/tui/screens/new_thread.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/screens/post_reader.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/size_gate.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/widgets/display/progress.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/widgets/display/tree.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/widgets/input/button.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/widgets/input/checkbox.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/widgets/input/menu.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/widgets/input/tabs.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/widgets/post/post_card.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/widgets/progress/spinner.ex", :contract_supertype},

  # Bucket C* — multi-shape state maps. Login (:menu/:login_form/
  # :reset_request/:reset_consume) and register (:invite_code/:combined)
  # have variant required-field sets; a single @type t/0 collapses to
  # map(). Tagged-union refactor out of scope per 46-CONTEXT D-03.
  {"lib/foglet_bbs/tui/screens/login.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/screens/login/state.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/screens/register/state.ex", :contract_supertype},
  {"lib/foglet_bbs/tui/screens/verify/state.ex", :contract_supertype},

  # Bucket D — Phase 25 Account forms intentionally expose a defensive
  # :no_match fallback even though current call sites only route
  # supported form events. Keeps state-corruption bugs from crashing.
  {"lib/foglet_bbs/tui/screens/account/prefs_form.ex",
   "The pattern can never match the type true."},
  {"lib/foglet_bbs/tui/screens/account/profile_form.ex",
   "The pattern can never match the type true."}
]
