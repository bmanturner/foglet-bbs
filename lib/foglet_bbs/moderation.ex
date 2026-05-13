defmodule Foglet.Moderation do
  @moduledoc """
  Moderation context for durable audit actions and report intake workflows.
  """

  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias Foglet.Accounts.User
  alias Foglet.Authorization
  alias Foglet.Boards
  alias Foglet.Boards.Board
  alias Foglet.Moderation.{Action, Report}
  alias Foglet.Notifications
  alias Foglet.Oneliners.Entry
  alias Foglet.Posts.Post
  alias Foglet.QueryHelpers
  alias FogletBbs.Repo

  @default_limit 50
  @workspace_limit 20
  @max_limit 100

  @type scope :: :site | {:board, Ecto.UUID.t()}

  @doc """
  Returns the read-only moderation workspace snapshot visible to an actor.

  The scope list is the trust boundary: actors with no `:list_reports` scope
  receive no populated workspace data.
  """
  @spec workspace_snapshot(User.t() | nil) ::
          {:ok,
           %{
             scopes: [scope(), ...],
             queue: [Report.t()],
             log: [Action.t()],
             users: [map()],
             boards: [map()],
             sanctions_available?: false
           }}
          | {:error, :forbidden}
  def workspace_snapshot(actor) do
    case Authorization.scopes_for(actor, :list_reports) do
      [] ->
        {:error, :forbidden}

      scopes ->
        {:ok,
         %{
           scopes: scopes,
           queue: list_open_reports_for_scopes(scopes, limit: @workspace_limit),
           log: list_actions_for_scopes(scopes, limit: @workspace_limit),
           users: active_user_rows(limit: @workspace_limit),
           boards: board_scope_rows(scopes, limit: @workspace_limit),
           sanctions_available?: false
         }}
    end
  end

  @doc """
  Creates a moderation report for a post, oneliner, or user.

  To keep the moderation queue usable, a reporter may have only one open report
  for a specific target. Once moderators resolve or dismiss that report, the
  same reporter may submit a new report for the same target if needed.
  """
  @spec create_report(User.t() | nil, map()) :: {:ok, Report.t()} | {:error, term()}
  def create_report(actor, attrs) do
    with :ok <- Bodyguard.permit(Foglet.Authorization, :create_report, actor, :site),
         %User{} = reporter <- actor,
         {:ok, changeset} <- build_report_changeset(reporter, attrs),
         {:ok, changeset} <- validate_no_duplicate_open_report(changeset),
         {:ok, report} <- Repo.insert(changeset) do
      {:ok, Repo.preload(report, [:reporter, :resolved_by])}
    end
  end

  @doc """
  Lists open reports visible to moderators and sysops.
  """
  @spec list_open_reports(User.t() | nil, keyword()) :: {:ok, [Report.t()]} | {:error, :forbidden}
  def list_open_reports(actor, opts \\ []) do
    with :ok <- Bodyguard.permit(Foglet.Authorization, :list_reports, actor, :site) do
      {:ok, list_open_reports_for_scopes(Authorization.scopes_for(actor, :list_reports), opts)}
    end
  end

  @doc """
  Marks an open report as resolved.
  """
  @spec resolve_report(User.t() | nil, Report.t() | Ecto.UUID.t(), map()) ::
          {:ok, Report.t()} | {:error, :forbidden | :not_found | :not_open | Changeset.t()}
  def resolve_report(actor, report_or_id, attrs) do
    update_report_status(actor, report_or_id, attrs, :resolved)
  end

  @doc """
  Marks an open report as dismissed.
  """
  @spec dismiss_report(User.t() | nil, Report.t() | Ecto.UUID.t(), map()) ::
          {:ok, Report.t()} | {:error, :forbidden | :not_found | :not_open | Changeset.t()}
  def dismiss_report(actor, report_or_id, attrs) do
    update_report_status(actor, report_or_id, attrs, :dismissed)
  end

  @doc """
  Records a successful oneliner hide audit row.
  """
  @spec record_hide_oneliner!(User.t(), Entry.t(), String.t(), map()) :: Action.t()
  def record_hide_oneliner!(%User{} = moderator, %Entry{} = entry, reason, metadata \\ %{}) do
    %Action{mod_id: moderator.id}
    |> Action.changeset(%{
      kind: :hide_oneliner,
      target_kind: :oneliner,
      target_id: entry.id,
      reason: reason,
      metadata: normalize_metadata(metadata)
    })
    |> Repo.insert!()
  end

  @doc """
  Lists moderation audit actions visible to the provided authorization scopes.

  Oneliners are site-scoped in v1.1. Board-scope tuples are accepted to preserve
  the future scope contract, but they do not see site-scoped oneliner actions.
  """
  @spec list_actions_for_scopes([scope()], keyword()) :: [Action.t()]
  def list_actions_for_scopes(scopes, opts \\ [])

  def list_actions_for_scopes([], _opts), do: []

  def list_actions_for_scopes(scopes, opts) when is_list(scopes) do
    if :site in scopes do
      limit = bounded_limit(Keyword.get(opts, :limit, @default_limit))

      Repo.all(
        from action in Action,
          where: action.kind == :hide_oneliner and action.target_kind == :oneliner,
          order_by: [desc: action.inserted_at],
          limit: ^limit,
          preload: [:mod]
      )
    else
      []
    end
  end

  @doc """
  Returns read-only board rows visible for the provided moderation scopes.

  Board-scope tuples are accepted even though v1.1 currently grants site scopes
  to moderators and sysops.
  """
  @spec board_scope_rows([scope()], keyword()) :: [map()]
  def board_scope_rows(scopes, opts \\ [])

  def board_scope_rows([], _opts), do: []

  def board_scope_rows(scopes, opts) when is_list(scopes) do
    limit = bounded_limit(Keyword.get(opts, :limit, @workspace_limit))

    scope_query =
      if :site in scopes do
        dynamic([b: b], true)
      else
        board_ids =
          scopes
          |> Enum.flat_map(fn
            {:board, board_id} -> [board_id]
            _scope -> []
          end)

        dynamic([b: b], b.id in ^board_ids)
      end

    from(b in Board, as: :b)
    |> join(:inner, [b: b], c in assoc(b, :category), as: :c)
    |> where(^scope_query)
    |> order_by([b: b, c: c], asc: c.display_order, asc: b.display_order)
    |> limit(^limit)
    |> preload([b: b, c: c], category: c)
    |> QueryHelpers.active_boards()
    |> Repo.all()
    |> Enum.map(&board_row/1)
  end

  defp active_user_rows(opts) do
    limit = bounded_limit(Keyword.get(opts, :limit, @workspace_limit))

    from(user in User,
      where: user.status == :active,
      order_by: [asc: user.handle],
      limit: ^limit,
      select: %{
        id: user.id,
        handle: user.handle,
        role: user.role,
        status: user.status,
        inserted_at: user.inserted_at,
        last_seen_at: user.last_seen_at
      }
    )
    |> QueryHelpers.not_deleted()
    |> Repo.all()
  end

  defp build_report_changeset(%User{} = reporter, attrs) do
    changeset =
      %Report{reporter_id: reporter.id}
      |> Report.create_changeset(attrs)

    if changeset.valid? do
      validate_report_target(changeset)
    else
      {:error, changeset}
    end
  end

  defp validate_report_target(%Changeset{} = changeset) do
    target_kind = Changeset.get_field(changeset, :target_kind)
    target_id = Changeset.get_field(changeset, :target_id)

    if report_target_exists?(target_kind, target_id) do
      {:ok, changeset}
    else
      {:error,
       Changeset.add_error(
         changeset,
         :target_id,
         "does not reference an existing reportable target"
       )}
    end
  end

  defp validate_no_duplicate_open_report(%Changeset{} = changeset) do
    reporter_id = Changeset.get_field(changeset, :reporter_id)
    target_kind = Changeset.get_field(changeset, :target_kind)
    target_id = Changeset.get_field(changeset, :target_id)

    duplicate_query =
      from report in Report,
        where:
          report.reporter_id == ^reporter_id and report.target_kind == ^target_kind and
            report.target_id == ^target_id and report.status == :open

    if Repo.exists?(duplicate_query) do
      {:error, Changeset.add_error(changeset, :target_id, "already has an open report from you")}
    else
      {:ok, changeset}
    end
  end

  defp report_target_exists?(:post, target_id) do
    case Ecto.UUID.cast(target_id) do
      {:ok, uuid} ->
        Repo.exists?(from post in Post, where: post.id == ^uuid and is_nil(post.deleted_at))

      :error ->
        false
    end
  end

  defp report_target_exists?(:oneliner, target_id) do
    case Ecto.UUID.cast(target_id) do
      {:ok, uuid} ->
        Repo.exists?(from entry in Entry, where: entry.id == ^uuid and entry.hidden == false)

      :error ->
        false
    end
  end

  defp report_target_exists?(:user, target_id) do
    case Ecto.UUID.cast(target_id) do
      {:ok, uuid} ->
        Repo.exists?(
          from user in User,
            where: user.id == ^uuid and user.status == :active and is_nil(user.deleted_at)
        )

      :error ->
        false
    end
  end

  defp report_target_exists?(_target_kind, _target_id), do: false

  defp list_open_reports_for_scopes([], _opts), do: []

  defp list_open_reports_for_scopes(scopes, opts) when is_list(scopes) do
    if :site in scopes do
      limit = bounded_limit(Keyword.get(opts, :limit, @default_limit))

      Repo.all(
        from report in Report,
          where: report.status == :open,
          order_by: [desc: report.inserted_at],
          limit: ^limit,
          preload: [:reporter, :resolved_by]
      )
      |> Enum.map(&with_target_summary/1)
    else
      []
    end
  end

  defp update_report_status(actor, report_or_id, attrs, status)
       when status in [:resolved, :dismissed] do
    action = if status == :resolved, do: :resolve_report, else: :dismiss_report

    with :ok <- Bodyguard.permit(Foglet.Authorization, action, actor, :site),
         %User{} = resolver <- actor,
         {:ok, %Report{} = report} <- fetch_report(report_or_id),
         :ok <- ensure_open_report(report) do
      persist_report_status(report, attrs, status, resolver.id)
    end
  end

  defp persist_report_status(%Report{} = report, attrs, status, resolver_id) do
    Repo.transact(fn ->
      report
      |> Report.resolution_changeset(attrs, status, resolver_id)
      |> Repo.update()
      |> case do
        {:ok, updated} ->
          updated = Repo.preload(updated, [:reporter, :resolved_by])

          with {:ok, _notification} <- emit_report_outcome_notification(updated) do
            {:ok, updated}
          end

        {:error, %Changeset{} = changeset} ->
          {:error, changeset}
      end
    end)
  end

  defp emit_report_outcome_notification(%Report{} = report) do
    Notifications.create_notification(%{
      user_id: report.reporter_id,
      actor_id: report.resolved_by_id,
      kind: :mod_action,
      dedupe_key: "mod_action:report:#{report.id}:#{report.status}",
      payload: %{
        action_id: report.id,
        action_kind: report_notification_action_kind(report.status),
        reason: report_notification_reason(report.status)
      }
    })
  end

  defp report_notification_action_kind(:resolved), do: "resolve_report"
  defp report_notification_action_kind(:dismissed), do: "dismiss_report"

  defp report_notification_reason(:resolved), do: "Your report was resolved."
  defp report_notification_reason(:dismissed), do: "Your report was dismissed."

  defp fetch_report(%Report{} = report),
    do: {:ok, report |> Repo.preload([:reporter, :resolved_by]) |> with_target_summary()}

  defp fetch_report(report_id) when is_binary(report_id) do
    case Repo.get(Report, report_id) do
      nil -> {:error, :not_found}
      report -> {:ok, report |> Repo.preload([:reporter, :resolved_by]) |> with_target_summary()}
    end
  end

  defp fetch_report(_report_or_id), do: {:error, :not_found}

  defp ensure_open_report(%Report{status: :open}), do: :ok
  defp ensure_open_report(%Report{}), do: {:error, :not_open}

  defp board_row(%Board{} = board) do
    %{
      id: board.id,
      slug: board.slug,
      name: board.name,
      description: board.description,
      category_name: board.category.name,
      scope: Boards.scope_for(board)
    }
  end

  defp with_target_summary(%Report{target_kind: :oneliner, target_id: target_id} = report) do
    entry = Repo.one(from entry in Entry, where: entry.id == ^target_id, preload: [:user])

    case entry do
      %Entry{} = entry ->
        label = "oneliner by @#{entry.user.handle}: #{truncate_target(entry.body, 52)}"
        %{report | target_label: label, target_source: entry.body}

      _ ->
        report
    end
  end

  defp with_target_summary(%Report{target_kind: :user, target_id: target_id} = report) do
    case Repo.get(User, target_id) do
      %User{} = user ->
        %{report | target_label: "user @#{user.handle}", target_source: user.handle}

      _ ->
        report
    end
  end

  defp with_target_summary(%Report{target_kind: :post, target_id: target_id} = report) do
    post =
      Repo.one(
        from post in Post,
          where: post.id == ^target_id,
          preload: [:user, :board]
      )

    case post do
      %Post{} = post ->
        board =
          if Ecto.assoc_loaded?(post.board) and post.board, do: post.board.slug, else: "unknown"

        user =
          if Ecto.assoc_loaded?(post.user) and post.user, do: post.user.handle, else: "unknown"

        body = truncate_target(post.body || "", 40)
        label = "post ##{post.message_number || "?"} in #{board} by @#{user}: #{body}"
        %{report | target_label: label, target_source: post.body}

      _ ->
        report
    end
  end

  defp with_target_summary(%Report{} = report), do: report

  defp truncate_target(value, limit) do
    value = to_string(value || "")

    if String.length(value) > limit do
      String.slice(value, 0, max(limit - 1, 0)) <> "…"
    else
      value
    end
  end

  defp normalize_metadata(metadata) when is_map(metadata) do
    Map.new(metadata, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_metadata(_metadata), do: %{}

  defp bounded_limit(limit) when is_integer(limit) do
    limit
    |> max(0)
    |> min(@max_limit)
  end

  defp bounded_limit(_limit), do: @default_limit
end
