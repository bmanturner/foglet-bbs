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
    2. If invalid: stash `{:site, {:error, errors_map}}` for the wrapper.
    3. If valid:   stash `{:site, {:ok, payload}}` for the wrapper to call
                   `Foglet.Config.put/3`.

  Cancel path: stash `{:site, :cancelled}` so the wrapper can drive
  `reseed_drafts/1` on the next render.
  """

  alias Foglet.Config
  alias Foglet.Config.Schema
  alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm
  alias Foglet.TUI.Widgets.Modal.Form.SubmitStash

  @site_keys [
    "registration_mode",
    "invite_code_generators",
    "delivery_mode",
    "require_email_verification",
    "invite_generation_per_user_limit"
  ]

  @type t :: %__MODULE__{
          current_user: term() | nil,
          drafts: %{optional(String.t()) => term()},
          errors: %{optional(String.t()) => String.t()},
          focused: non_neg_integer()
        }

  defstruct current_user: nil, drafts: %{}, errors: %{}, focused: 0

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
    %{state | drafts: load_drafts(), errors: %{}, focused: 0}
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
      show_footer: false,
      fields: fields,
      on_submit: fn payload ->
        case validate_delivery_verification_pair(payload) do
          :ok -> SubmitStash.stash(__MODULE__, {:site, {:ok, payload}})
          {:error, errors} -> SubmitStash.stash(__MODULE__, {:site, {:error, errors}})
        end
      end,
      on_cancel: fn -> SubmitStash.stash(__MODULE__, {:site, :cancelled}) end
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
    base = %{name: String.to_atom(key), label: key, value: raw_value}

    case spec do
      %{type: :string, enum: enum} when is_list(enum) ->
        Map.merge(base, %{type: :enum, choices: enum})

      %{type: :string, enum: nil} ->
        Map.merge(base, %{type: :text})

      %{type: :integer} ->
        Map.merge(base, %{type: :integer, value: stringify_int(raw_value)})

      %{type: :boolean} ->
        Map.merge(base, %{type: :boolean, value: !!raw_value})
    end
  end

  defp stringify_int(nil), do: ""
  defp stringify_int(int) when is_integer(int), do: Integer.to_string(int)
  defp stringify_int(s) when is_binary(s), do: s
end
