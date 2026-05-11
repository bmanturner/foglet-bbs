defmodule Foglet.TUI.Screens.Shared.Reporting do
  @moduledoc false

  alias Foglet.TUI.Effect
  alias Foglet.TUI.Modal
  alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

  @report_reason_choices [
    {"Spam / scam", "spam"},
    {"Harassment or dogpiling", "harassment"},
    {"Hate speech or slurs", "hate_speech"},
    {"Sexual or obscene content", "sexual_content"},
    {"Violence, threats, or intimidation", "violence_threats"},
    {"Self-harm or crisis risk", "self_harm"},
    {"Impersonation or deceptive identity", "impersonation"},
    {"Illegal or prohibited activity", "illegal_activity"},
    {"Privacy or doxxing", "privacy_doxxing"},
    {"Other", "other"}
  ]

  def report_modal(screen_key, kind, target, opts \\ []) do
    title = Keyword.get(opts, :title, "Report")
    values = Keyword.get(opts, :values, %{})
    errors = Keyword.get(opts, :errors, %{})

    form =
      ModalForm.init(
        title: title,
        fields: [
          %{
            name: :reason,
            type: :enum,
            label: "Reason",
            choices: @report_reason_choices,
            value: field_value(values, :reason)
          },
          %{
            name: :notes,
            type: :textarea,
            label: "Details",
            rows: 4,
            value: field_value(values, :notes),
            placeholder: "Optional context"
          }
        ],
        on_submit: fn payload ->
          Effect.modal_submit(screen_key, kind, Map.merge(payload, Map.new(target)))
        end,
        on_cancel: fn -> :dismiss_modal end,
        show_footer: true
      )
      |> maybe_set_form_errors(errors)

    %Modal{
      type: :form,
      title: title,
      message: form_modal_message(form, report_summary_lines(target))
    }
  end

  def resolution_modal(screen_key, kind, payload, opts \\ []) do
    title = Keyword.get(opts, :title, "Moderate Report")
    values = Keyword.get(opts, :values, %{})
    errors = Keyword.get(opts, :errors, %{})
    summary_lines = Keyword.get(opts, :summary_lines, [])

    form =
      ModalForm.init(
        title: title,
        fields: [
          %{
            name: :resolution_note,
            type: :textarea,
            label: "Moderator note",
            rows: 4,
            value: field_value(values, :resolution_note),
            placeholder: "Required"
          }
        ],
        on_submit: fn attrs ->
          Effect.modal_submit(screen_key, kind, Map.merge(attrs, Map.new(payload)))
        end,
        on_cancel: fn -> :dismiss_modal end,
        show_footer: true
      )
      |> maybe_set_form_errors(errors)

    %Modal{type: :form, title: title, message: form_modal_message(form, summary_lines)}
  end

  def success_modal(message) do
    %Modal{type: :success, title: "Success", message: message}
  end

  def public_profile_modal(screen_key, kind, profile, payload, opts \\ []) do
    message = %{
      profile: profile,
      report_target: %{screen_key: screen_key, kind: kind, payload: payload},
      footer_hint: Keyword.get(opts, :footer_hint, "[!] report user")
    }

    %Modal{type: :public_profile, title: "Public Profile", message: message}
  end

  def changeset_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.into(%{}, fn {field, messages} -> {field, Enum.join(messages, ", ")} end)
  end

  defp maybe_set_form_errors(%ModalForm{} = form, errors) when map_size(errors) == 0, do: form

  defp maybe_set_form_errors(%ModalForm{} = form, errors) do
    form
    |> ModalForm.set_errors(errors)
    |> ModalForm.set_submit_state({:error, summarize_form_errors(errors)})
  end

  defp summarize_form_errors(errors) do
    errors
    |> Map.values()
    |> Enum.find("Validation error.", &is_binary/1)
  end

  defp field_value(values, key) do
    Map.get(values, key) || Map.get(values, Atom.to_string(key)) || ""
  end

  defp form_modal_message(%ModalForm{} = form, []), do: form

  defp form_modal_message(%ModalForm{} = form, summary_lines) when is_list(summary_lines) do
    %{form: form, summary_lines: Enum.reject(summary_lines, &(&1 in [nil, ""]))}
  end

  defp report_summary_lines(target) when is_map(target) do
    [
      "Target: #{Map.get(target, :target_label) || Map.get(target, "target_label") || generic_target_label(target)}"
    ]
  end

  defp generic_target_label(target) do
    kind = Map.get(target, :target_kind) || Map.get(target, "target_kind") || "item"
    id = Map.get(target, :target_id) || Map.get(target, "target_id")

    case id do
      value when is_binary(value) and value != "" -> "#{kind} #{value}"
      _ -> to_string(kind)
    end
  end
end
