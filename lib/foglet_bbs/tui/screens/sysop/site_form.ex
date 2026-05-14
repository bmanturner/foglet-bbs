defmodule Foglet.TUI.Screens.Sysop.SiteForm do
  @moduledoc """
  SITE tab selectable field list plus one-field edit overlays.
  """

  alias Foglet.Config
  alias Foglet.SiteOps
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Modal
  alias Foglet.TUI.Screens.Sysop.SiteForm.State, as: SState
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.List.SelectableFieldList
  alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

  @type t :: SState.t()

  @spec site_keys() :: [String.t()]
  defdelegate site_keys, to: SState

  @spec visible_keys(t()) :: [String.t()]
  defdelegate visible_keys(state), to: SState

  @spec init(keyword()) :: t()
  def init(opts), do: SState.new(opts)

  @spec render(t(), Theme.t(), keyword()) :: any()
  def render(%SState{} = state, %Theme{} = theme, opts \\ []) do
    fields = list_fields(state)

    SelectableFieldList.render(fields, state.focused,
      theme: theme,
      width: Keyword.get(opts, :width, 80),
      height: Keyword.get(opts, :height, 12)
    )
  end

  @spec handle_key(map(), t()) :: {t(), [Effect.t() | {atom(), term()}]}
  def handle_key(%{key: :char, char: c}, %SState{} = state) when c in ["e", "E"] do
    open_selected_field(state)
  end

  def handle_key(%{key: :enter}, %SState{} = state) do
    open_selected_field(state)
  end

  def handle_key(%{key: :char, char: c}, %SState{} = state) when c in ["t", "T"] do
    trigger_test_email(state)
  end

  def handle_key(%{key: key} = event, %SState{} = state) when key in [:up, :down, :home, :end] do
    {move_selection(event, state), []}
  end

  def handle_key(%{key: key} = event, %SState{} = state)
      when key in [:tab, :shift_tab, :backtab] do
    {move_selection(event, state), []}
  end

  def handle_key(%{key: :char, char: c} = event, %SState{} = state)
      when c in ["j", "J", "k", "K", "g", "G"] do
    {move_selection(event, state), []}
  end

  def handle_key(%{key: :escape}, %SState{} = state), do: {SState.reseed_drafts(state), []}

  def handle_key(_event, %SState{} = state), do: {state, []}

  @spec submit_field(t(), map()) :: {t(), [Effect.t() | {atom(), term()}]}
  def submit_field(%SState{} = state, payload) do
    key = selected_key(state)
    atom_key = String.to_existing_atom(key)
    value = Map.get(payload, atom_key)
    merged_drafts = Map.put(state.drafts, key, normalize_field_value(key, value))

    validation_payload =
      atom_payload(merged_drafts, SState.visible_keys(%{state | drafts: merged_drafts}))

    case SState.validate_delivery_verification_pair(validation_payload) do
      {:error, errors} ->
        new_state = %{
          state
          | drafts: merged_drafts,
            errors: stringify_keys(errors),
            submit_state: {:error, "validation"}
        }

        {new_state, [error_modal(new_state, errors)]}

      :ok ->
        persist_selected(%{state | drafts: merged_drafts, errors: %{}}, key)
    end
  end

  @doc "Apply the async test-email result returned by `Foglet.SiteOps.send_test_email/1`."
  @spec handle_test_email_result(t(), term()) :: t()
  def handle_test_email_result(%SState{} = state, result) do
    case Effect.unwrap_task_result(result) do
      {:ok, _delivery} -> %{state | test_email_state: :sent}
      {:error, reason} -> %{state | test_email_state: {:error, reason}}
    end
  end

  defp persist_selected(%SState{current_user: actor} = state, key) do
    value = Map.fetch!(state.drafts, key)

    case Config.put(actor, key, value) do
      {:ok, _entry} ->
        {%{
           state
           | drafts: Map.put(SState.reseed_drafts(state).drafts, key, value),
             submit_state: :idle
         }, [Effect.dismiss_modal()]}

      {:error, :invalid_value} ->
        persist_error(state, key, "Invalid value (see min/max or enum)")

      {:error, :unknown_key} ->
        persist_error(state, key, "Unknown schema key")

      {:error, :forbidden} ->
        {state, [{:error_modal, "Permission denied. You may have been demoted.", :main_menu}]}

      {:error, :db_error} ->
        {state, [{:error_modal, "Database error saving site configuration.", :main_menu}]}
    end
  end

  defp persist_error(state, key, message) do
    atom_key = String.to_existing_atom(key)
    new_state = %{state | errors: %{key => message}, submit_state: {:error, "validation"}}
    {new_state, [error_modal(new_state, %{atom_key => message})]}
  end

  defp error_modal(%SState{} = state, errors) do
    form = build_field_form(state, errors)

    Effect.open_modal(%Modal{
      type: :form,
      title: form.title,
      message: form,
      on_cancel: :dismiss_modal
    })
  end

  defp trigger_test_email(%SState{test_email_state: :sending} = state), do: {state, []}

  defp trigger_test_email(%SState{} = state) do
    if SState.test_email_action_visible?(state) do
      actor = state.current_user

      {%{state | test_email_state: :sending},
       [Effect.task(:sysop_send_test_email, fn -> SiteOps.send_test_email(actor) end)]}
    else
      {%{state | test_email_state: {:error, :no_email_mode}}, []}
    end
  end

  defp build_field_form(%SState{} = state, errors \\ %{}) do
    full = SState.build_modal_form(state)
    key = selected_key(state)
    atom_key = String.to_existing_atom(key)
    field = Enum.find(full.fields, &(Map.fetch!(&1, :name) == atom_key)) || hd(full.fields)

    ModalForm.init(
      title: "Edit site: #{field.label}",
      show_footer: true,
      fields: [field],
      on_submit: fn payload -> Effect.modal_submit(:sysop, :site_field, payload) end,
      on_cancel: fn -> :dismiss_modal end
    )
    |> maybe_set_errors(errors)
  end

  defp open_selected_field(%SState{} = state) do
    form = build_field_form(state)
    modal = %Modal{type: :form, title: form.title, message: form, on_cancel: :dismiss_modal}
    {%{state | errors: %{}, submit_state: :idle}, [Effect.open_modal(modal)]}
  end

  defp maybe_set_errors(form, errors) when map_size(errors) == 0, do: form

  defp maybe_set_errors(form, errors) do
    form
    |> ModalForm.set_errors(errors)
    |> ModalForm.set_submit_state({:error, "validation"})
  end

  defp list_fields(%SState{} = state) do
    form = SState.build_modal_form(state)
    Enum.map(form.fields, &display_field/1)
  end

  defp display_field(%{choices: choices, value: value} = field) when is_list(choices) do
    label =
      Enum.find_value(choices, value, fn
        {label, ^value} -> label
        other when other == value -> other
        _ -> nil
      end)

    %{field | value: label}
  end

  defp display_field(field), do: field

  defp move_selection(event, %SState{} = state) do
    count = length(SState.visible_keys(state))
    focused = SelectableFieldList.move(state.focused, count, action_key(event))
    %{state | focused: focused}
  end

  defp selected_key(%SState{} = state),
    do: Enum.at(SState.visible_keys(state), state.focused) || hd(SState.visible_keys(state))

  defp action_key(%{key: :char, char: char}), do: char
  defp action_key(%{key: key} = event) when key in [:tab, :shift_tab, :backtab], do: event
  defp action_key(%{key: key}), do: key

  defp atom_payload(drafts, visible) do
    Map.new(visible, fn key -> {String.to_existing_atom(key), Map.get(drafts, key)} end)
  end

  defp normalize_field_value("invite_generation_per_user_limit", value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> value
    end
  end

  defp normalize_field_value(_key, value), do: value

  defp stringify_keys(errors) do
    Enum.reduce(errors, %{}, fn
      {k, v}, acc when is_atom(k) -> Map.put(acc, Atom.to_string(k), v)
      {k, v}, acc when is_binary(k) -> Map.put(acc, k, v)
    end)
  end
end
