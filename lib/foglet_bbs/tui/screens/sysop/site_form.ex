defmodule Foglet.TUI.Screens.Sysop.SiteForm do
  @moduledoc """
  SITE tab body for Sysop — Modal.Form-backed wrapper (Phase 28 D-17).

  Structurally analogous to `Foglet.TUI.Screens.Account.ProfileForm`:
  rendering delegates to `Modal.Form.render/2`; events route through
  `Modal.Form.handle_event/2`. The bespoke draft + visibility + validation
  logic lives in `Foglet.TUI.Screens.Sysop.SiteForm.State`.

  The Modal.Form is rebuilt fresh per render so D-21 conditional visibility
  takes effect on the next paint without stateful re-sync. The state struct
  itself remains the source of truth — drafts, errors, and focus persist on
  the wrapper struct (`Foglet.TUI.Screens.Sysop.SiteForm.State`).

  ## Wrapper-owned behavior

  Two behaviors live at the wrapper boundary rather than inside Modal.Form:

  Ctrl+S (D-19): preserved at the wrapper level; routes to the same
  validate → `Foglet.Config.put/3` path that Enter-on-last-field uses by
  driving the form to the last visible index and dispatching `:enter`.

  Esc (FORM-06 / D-12): reseeds drafts via `SiteForm.State.reseed_drafts/1`;
  no inline status copy is produced.

  ## Sysop screen contract

  Preserved verbatim from the legacy SiteForm: the sysop screen calls
  `init/1`, `handle_key/2`, and `render/2` with the same signatures, so
  `lib/foglet_bbs/tui/screens/sysop.ex` (lines 121–124, 196, 234–268) is
  unchanged across the migration.
  """

  alias Foglet.Config
  alias Foglet.TUI.Screens.Sysop.SiteForm.State, as: SState
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm
  alias Foglet.TUI.Widgets.Modal.Form.SubmitStash

  @type t :: SState.t()

  @doc "The canonical Sysop SITE key list, in render order."
  @spec site_keys() :: [String.t()]
  defdelegate site_keys, to: SState

  @doc """
  Returns the visible-keys list for `state` per D-21.

  `invite_generation_per_user_limit` is hidden unless
  `invite_code_generators == "any_user"`. Delegated to
  `Foglet.TUI.Screens.Sysop.SiteForm.State.visible_keys/1`.
  """
  @spec visible_keys(t()) :: [String.t()]
  defdelegate visible_keys(state), to: SState

  @spec init(keyword()) :: t()
  def init(opts), do: SState.new(opts)

  @spec render(t(), Theme.t()) :: any()
  def render(%SState{} = state, %Theme{} = theme) do
    state
    |> SState.build_modal_form()
    |> apply_errors(state.errors)
    |> ModalForm.render(theme: theme)
  end

  @spec handle_key(map(), t()) :: {t(), [{atom(), term()}]}
  def handle_key(%{key: :char, char: "s", ctrl: true}, %SState{} = state) do
    # D-19: Ctrl+S routes to the same submit path Enter-on-last uses.
    submit(state)
  end

  def handle_key(%{key: :escape}, %SState{} = state) do
    # FORM-06 / D-12: reseed drafts; no inline status copy.
    {SState.reseed_drafts(state), []}
  end

  def handle_key(event, %SState{} = state) do
    form =
      state
      |> SState.build_modal_form()
      |> apply_errors(state.errors)
      |> set_focus(state.focused)

    {new_form, action} = ModalForm.handle_event(event, form)

    case action do
      :submitted -> finalize_submit(state, new_form)
      :cancelled -> {SState.reseed_drafts(state), []}
      _ -> {sync_back(state, new_form), []}
    end
  end

  # ---------- Private ----------

  defp submit(%SState{} = state) do
    visible = SState.visible_keys(state)
    last_idx = max(0, length(visible) - 1)

    form =
      state
      |> SState.build_modal_form()
      |> apply_errors(state.errors)
      |> set_focus(last_idx)

    {new_form, action} = ModalForm.handle_event(%{key: :enter}, form)

    if action == :submitted do
      finalize_submit(state, new_form)
    else
      {sync_back(state, new_form), []}
    end
  end

  defp finalize_submit(%SState{} = state, %ModalForm{} = new_form) do
    case SubmitStash.pop(SState) do
      {:site, {:ok, payload}} ->
        persist_payload(state, payload, new_form)

      {:site, {:error, errors_map}} ->
        # D-20: validation errors flow through Modal.Form.set_errors/2 AND
        # the wrapper's string-keyed errors map (preserved API).
        new_form2 = ModalForm.set_errors(new_form, errors_map)
        new_form2 = ModalForm.set_submit_state(new_form2, {:error, "validation"})

        new_state = %{
          state
          | errors: stringify_keys(errors_map),
            focused: clamp(state.focused, length(SState.visible_keys(state)))
        }

        # Sync drafts from the form so any in-flight typing is preserved.
        {sync_back(new_state, new_form2), []}

      _other ->
        # Defensive: stash empty or unexpected — treat as no-op submit.
        {sync_back(state, new_form), []}
    end
  end

  defp persist_payload(%SState{current_user: actor} = state, payload, %ModalForm{} = new_form) do
    visible = SState.visible_keys(state)

    {final_state, _final_form, events} =
      Enum.reduce_while(visible, {state, new_form, []}, fn key,
                                                           {acc_state, acc_form, acc_events} ->
        atom_key = String.to_existing_atom(key)
        value = Map.get(payload, atom_key)

        case Config.put(actor, key, value) do
          {:ok, _entry} ->
            new_state = %{
              acc_state
              | errors: Map.delete(acc_state.errors, key),
                drafts: Map.put(acc_state.drafts, key, value)
            }

            {:cont, {new_state, acc_form, acc_events}}

          {:error, :invalid_value} ->
            new_state = put_error(acc_state, key, "Invalid value (see min/max or enum)")
            {:cont, {new_state, acc_form, acc_events}}

          {:error, :unknown_key} ->
            new_state = put_error(acc_state, key, "Unknown schema key")
            {:cont, {new_state, acc_form, acc_events}}

          {:error, :forbidden} ->
            {:halt,
             {acc_state, acc_form,
              [{:error_modal, "Permission denied. You may have been demoted.", :main_menu}]}}

          {:error, :db_error} ->
            {:halt,
             {acc_state, acc_form,
              [{:error_modal, "Database error saving site configuration.", :main_menu}]}}
        end
      end)

    if events == [] do
      # All persisted: drive submit_state to :saved so the form shows "Saved." once.
      final_form2 = ModalForm.set_submit_state(new_form, :saved)
      {sync_back(final_state, final_form2), []}
    else
      {final_state, events}
    end
  end

  defp sync_back(%SState{} = state, %ModalForm{focus_index: idx} = form) do
    visible = SState.visible_keys(state)
    drafts = collect_drafts(form, visible, state.drafts)
    %{state | drafts: drafts, focused: clamp(idx, length(visible))}
  end

  defp collect_drafts(%ModalForm{} = form, visible, existing_drafts) do
    Enum.reduce(visible, existing_drafts, fn key, acc ->
      # site_keys are compile-time constants in SiteForm.State; the atoms
      # are reachable via SiteForm.State.build_modal_form/1 at startup.
      atom_key = String.to_existing_atom(key)
      val = ModalForm.field_value(form, atom_key)
      Map.put(acc, key, val)
    end)
  end

  defp apply_errors(%ModalForm{} = form, errors) when map_size(errors) == 0, do: form

  defp apply_errors(%ModalForm{} = form, errors) do
    atom_errors =
      Enum.reduce(errors, %{}, fn
        # Error keys are derived from site_keys (well-known atoms) — see
        # SiteForm.State.validate_delivery_verification_pair/1 for the source.
        {k, v}, acc when is_binary(k) -> Map.put(acc, String.to_existing_atom(k), v)
        {k, v}, acc when is_atom(k) -> Map.put(acc, k, v)
      end)

    ModalForm.set_errors(form, atom_errors)
  end

  defp set_focus(%ModalForm{fields: fields} = form, focused) do
    %{form | focus_index: clamp(focused, length(fields))}
  end

  defp clamp(_idx, 0), do: 0
  defp clamp(idx, _n) when idx < 0, do: 0
  defp clamp(idx, n) when idx >= n, do: n - 1
  defp clamp(idx, _n), do: idx

  defp put_error(%SState{} = state, key, msg) do
    %{state | errors: Map.put(state.errors, key, msg)}
  end

  defp stringify_keys(errors) do
    Enum.reduce(errors, %{}, fn
      {k, v}, acc when is_atom(k) -> Map.put(acc, Atom.to_string(k), v)
      {k, v}, acc when is_binary(k) -> Map.put(acc, k, v)
    end)
  end
end
