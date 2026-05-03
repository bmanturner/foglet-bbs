defmodule Foglet.TUI.Screens.Sysop.SiteForm.State do
  @moduledoc """
  Sibling state module for `Foglet.TUI.Screens.Sysop.SiteForm` (Phase 28 D-17).

  Owns the bespoke draft + errors + visibility logic. The Modal.Form is built
  ephemerally per render via `build_modal_form/1` so conditional-visibility
  changes (D-21) take effect on the next render without stateful re-sync.

  Field type mapping (D-18):

    * Schema `:string` + `enum: [...]` → ModalForm `:enum` with `choices`
    * Schema `:string` + `enum: nil`   → ModalForm `:text`
    * Schema `:integer`                → ModalForm `:integer`
    * Schema `:boolean`                → ModalForm `:boolean`

  Submit path (D-20):

    1. Run `validate_delivery_verification_pair/1`.
    2. If invalid: return an explicit modal-submit effect with
                   `{:error, errors_map}` for the wrapper.
    3. If valid:   return an explicit modal-submit effect with
                   `{:ok, payload}` for the wrapper to call `Foglet.Config.put/3`.

  Cancel path: Modal.Form returns `:cancelled` so the wrapper can drive
  `reseed_drafts/1` on the next render.
  """

  alias Foglet.Config
  alias Foglet.Config.Schema
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

  @site_keys [
    "registration_mode",
    "invite_code_generators",
    "delivery_mode",
    "require_email_verification",
    "invite_generation_per_user_limit"
  ]

  # Operator-facing field labels for enum SITE keys (FOG-342 / FOG-344).
  # Keys not listed here keep the raw schema key as their label.
  @field_labels %{
    "registration_mode" => "Account registration",
    "invite_code_generators" => "Invite code generators",
    "delivery_mode" => "Email delivery"
  }

  # Operator-facing per-value labels for enum SITE keys (FOG-342 / FOG-344).
  # Persisted values remain the raw schema strings; the labels are display only.
  @value_labels %{
    "registration_mode" => %{
      "open" => "Open — anyone can sign up",
      "invite_only" => "Invite only — requires an invite code",
      "sysop_approved" => "Sysop approval — applications queue for review"
    },
    "invite_code_generators" => %{
      "sysop_only" => "Sysops only",
      "mods" => "Sysops and moderators",
      "any_user" => "Any signed-in user"
    },
    "delivery_mode" => %{
      "email" => "Send email",
      "no_email" => "No email (offline mode)"
    }
  }

  # Compile-time atom interning — guarantees String.to_existing_atom/1 will
  # succeed for every site key when build_field/2 derives field-name atoms.
  # Without this, the rarely-referenced :invite_generation_per_user_limit
  # would not be in the atom table on a fresh boot.
  @site_keys_atoms [
    :registration_mode,
    :invite_code_generators,
    :delivery_mode,
    :require_email_verification,
    :invite_generation_per_user_limit
  ]
  @doc false
  def __site_keys_atoms__, do: @site_keys_atoms

  @type t :: %__MODULE__{
          current_user: term() | nil,
          drafts: %{optional(String.t()) => term()},
          errors: %{optional(String.t()) => String.t()},
          focused: non_neg_integer(),
          submit_state: ModalForm.submit_state()
        }

  # Phase 28 Plan 06 (BL-02): submit_state persists the FORM-05 lifecycle
  # across the per-render Modal.Form rebuild. Without this, sync_back/2
  # discards the form's submit_state every event, the FORM-05 lock guard
  # has zero effect on this consumer, and the D-08/D-09 status row
  # ("Saved." / "Error: validation") never reaches the operator.
  defstruct current_user: nil,
            drafts: %{},
            errors: %{},
            focused: 0,
            submit_state: :idle

  @doc "The canonical Sysop SITE key list, in render order."
  @spec site_keys() :: [String.t()]
  def site_keys, do: @site_keys

  @doc """
  Build a fresh SiteForm.State seeded from `Foglet.Config.get!/1`.

  Options:
    * `:current_user` — the actor whose Config.put/3 calls will be authorized.
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      current_user: Keyword.get(opts, :current_user),
      drafts: load_drafts(),
      errors: %{},
      focused: 0
    }
  end

  @doc """
  Reseed drafts from `Foglet.Config.get!/1` and clear local errors/focus.

  Used by the Esc handler (D-12 / FORM-06) to drop unsaved edits without
  emitting any inline status copy.
  """
  @spec reseed_drafts(t()) :: t()
  def reseed_drafts(%__MODULE__{} = state) do
    # Phase 28 Plan 06 (BL-02): Esc reseed drops in-flight FORM-05 lifecycle
    # along with drafts (D-12 honest-Esc semantics — no stale "Saved." or
    # "Error: …" pinned across a discard).
    %{state | drafts: load_drafts(), errors: %{}, focused: 0, submit_state: :idle}
  end

  @doc """
  Returns visible keys per D-21.

  `invite_generation_per_user_limit` is hidden unless
  `invite_code_generators == "any_user"`.
  """
  @spec visible_keys(t()) :: [String.t()]
  def visible_keys(%__MODULE__{drafts: drafts}) do
    generators = Map.get(drafts, "invite_code_generators")

    Enum.reject(@site_keys, fn
      "invite_generation_per_user_limit" -> generators != "any_user"
      _ -> false
    end)
  end

  @doc """
  Build a fresh `Modal.Form` snapshot per render (D-18, D-21).

  The form is constructed from the current draft state — conditional visibility
  (D-21) takes effect on the next render automatically because `visible_keys/1`
  drives the field list every time.
  """
  @spec build_modal_form(t()) :: ModalForm.t()
  def build_modal_form(%__MODULE__{} = state) do
    visible = visible_keys(state)
    fields = Enum.map(visible, &build_field(&1, state))

    ModalForm.init(
      title: "Site policy",
      # Phase 28 Plan 04: Sysop's global command bar advertises Q/Tabs/Jump but
      # NOT Enter/Esc, so the SITE form opts into Modal.Form's footer to
      # advertise "[Enter] Submit   [Esc] Cancel" at the body level. The Phase 28
      # D-09 status row (Saving…/Saved./Error: …) replaces this footer when
      # active. This matches the legacy SiteForm's screen-level footer.
      show_footer: true,
      fields: fields,
      on_submit: fn payload ->
        case validate_delivery_verification_pair(payload) do
          :ok -> Effect.modal_submit(:sysop, :site_settings, {:ok, payload})
          {:error, errors} -> Effect.modal_submit(:sysop, :site_settings, {:error, errors})
        end
      end,
      on_cancel: fn -> :ok end
    )
  end

  @doc """
  Pre-flight invariant (D-20).

  When delivery_mode == "no_email" and require_email_verification == true, the
  combination is rejected with field-level errors keyed by atom field name.
  """
  @spec validate_delivery_verification_pair(map()) ::
          :ok | {:error, %{atom() => String.t()}}
  def validate_delivery_verification_pair(%{} = payload) do
    delivery = Map.get(payload, :delivery_mode)
    require_v = Map.get(payload, :require_email_verification)

    if delivery == "no_email" and require_v == true do
      {:error,
       %{
         delivery_mode: "No-email mode cannot require email verification",
         require_email_verification: "Email verification requires delivery_mode=email"
       }}
    else
      :ok
    end
  end

  # ---------- Private ----------

  defp load_drafts do
    Map.new(@site_keys, fn k -> {k, Config.get!(k)} end)
  end

  defp build_field(key, %__MODULE__{drafts: drafts}) do
    {:ok, spec} = Schema.fetch_spec(key)
    raw_value = Map.get(drafts, key)

    base = %{
      # site_keys are listed in @site_keys at compile time, and the
      # corresponding atoms (e.g. :delivery_mode) are referenced throughout
      # the codebase (Schema specs, SiteForm wrapper) — safe to use
      # to_existing_atom here.
      name: String.to_existing_atom(key),
      label: Map.get(@field_labels, key, key),
      value: raw_value,
      description: spec.description
    }

    case spec do
      %{type: :string, enum: enum} when is_list(enum) ->
        Map.merge(base, %{type: :enum, choices: choices_for(key, enum)})

      %{type: :string, enum: nil} ->
        Map.merge(base, %{type: :text})

      %{type: :integer} ->
        Map.merge(base, %{type: :integer, value: stringify_int(raw_value)})

      %{type: :boolean} ->
        Map.merge(base, %{type: :boolean, value: !!raw_value})
    end
  end

  # Build the `[{label, value}, ...]` choices list for a given enum SITE key.
  # Falls back to the raw value as the label if a value is not in the label
  # map — defense against schema drift so a new enum value never crashes the
  # form.
  defp choices_for(key, enum) when is_list(enum) do
    labels = Map.get(@value_labels, key, %{})
    Enum.map(enum, fn value -> {Map.get(labels, value, value), value} end)
  end

  defp stringify_int(nil), do: ""
  defp stringify_int(int) when is_integer(int), do: Integer.to_string(int)
  defp stringify_int(s) when is_binary(s), do: s
end
