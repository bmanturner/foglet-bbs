defmodule Mix.Tasks.Foglet.GithubHygiene do
  use Mix.Task

  @shortdoc "Checks GitHub-facing branch, commit, and PR metadata for Foglet hygiene rules"

  @moduledoc """
  Validates GitHub-facing metadata so Paperclip identifiers stay in Paperclip,
  not in public GitHub artifacts by default.
  """

  @paperclip_id ~r/\bFOG-\d+\b/

  @conventional_commit ~r/^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)(\([^)]+\))?(!)?:\s\S.+/

  @switches [
    branch: :string,
    commit_subject: :keep,
    pr_title: :string,
    pr_body: :string,
    allow_paperclip_ids_in_pr_body: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    {opts, positional, invalid} = OptionParser.parse(args, strict: @switches)

    cond do
      invalid != [] ->
        fail!("Unknown options: #{Enum.map_join(invalid, ", ", &elem(&1, 0))}")

      positional != [] ->
        fail!("Unexpected positional arguments: #{Enum.join(positional, " ")}")

      true ->
        metadata = build_metadata(opts)
        failures = validate(metadata)

        if failures == [] do
          Mix.shell().info(success_message(metadata))
        else
          fail!(Enum.join(failures, "\n"))
        end
    end
  end

  defp build_metadata(opts) do
    %{
      branch: opts[:branch],
      commit_subjects: List.wrap(opts[:commit_subject]),
      pr_title: opts[:pr_title],
      pr_body: opts[:pr_body],
      allow_pr_body_override?: Keyword.get(opts, :allow_paperclip_ids_in_pr_body, false)
    }
  end

  defp validate(metadata) do
    []
    |> validate_branch(metadata.branch)
    |> validate_commit_subjects(metadata.commit_subjects)
    |> validate_pr_title(metadata.pr_title)
    |> validate_pr_body(metadata.pr_body, metadata.allow_pr_body_override?)
  end

  defp validate_branch(errors, nil), do: errors

  defp validate_branch(errors, branch) do
    if branch =~ @paperclip_id do
      errors ++
        [
          "Invalid branch name #{inspect(branch)}: Paperclip identifiers such as #{paperclip_example(branch)} are not allowed."
        ]
    else
      errors
    end
  end

  defp validate_commit_subjects(errors, subjects) do
    Enum.reduce(subjects, errors, fn subject, acc ->
      acc
      |> reject_paperclip_id(subject, "commit subject")
      |> require_conventional_commit(subject, "commit subject")
    end)
  end

  defp validate_pr_title(errors, nil), do: errors

  defp validate_pr_title(errors, title) do
    errors
    |> reject_paperclip_id(title, "PR title")
    |> require_conventional_commit(title, "PR title")
  end

  defp validate_pr_body(errors, nil, _override?), do: errors

  defp validate_pr_body(errors, body, false) do
    reject_paperclip_id(errors, body, "PR description")
  end

  defp validate_pr_body(errors, _body, true), do: errors

  defp reject_paperclip_id(errors, value, label) do
    case Regex.run(@paperclip_id, value || "") do
      [match | _] ->
        errors ++
          ["Invalid #{label} #{inspect(value)}: Paperclip identifier #{match} is not allowed."]

      nil ->
        errors
    end
  end

  defp require_conventional_commit(errors, value, label) do
    if Regex.match?(@conventional_commit, value || "") do
      errors
    else
      errors ++
        [
          "Invalid #{label} #{inspect(value)}: must match Conventional Commit style `type(scope): description` or `type: description`."
        ]
    end
  end

  defp paperclip_example(branch) do
    Regex.run(@paperclip_id, branch) |> List.first()
  end

  defp success_message(metadata) do
    override_note =
      if metadata.allow_pr_body_override? do
        " Override active for PR description Paperclip IDs."
      else
        ""
      end

    "GitHub metadata hygiene check passed." <> override_note
  end

  @spec fail!(String.t()) :: no_return()
  defp fail!(message) do
    Mix.shell().error(message)
    raise Mix.Error, message: message
  end
end
