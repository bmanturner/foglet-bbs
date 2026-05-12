defmodule Foglet.TUI.Screens.MainMenuReportIntegrationTest do
  use FogletBbs.DataCase, async: false

  alias Foglet.Moderation
  alias Foglet.Moderation.Report
  alias Foglet.Oneliners
  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Modal
  alias Foglet.TUI.Screens.MainMenu
  alias Foglet.TUI.Screens.MainMenu.State, as: MainMenuState
  alias FogletBbs.AccountsFixtures
  alias FogletBbs.Repo

  test "selected oneliner report submit creates a durable report and returns success" do
    reporter = AccountsFixtures.user_fixture()

    moderator =
      AccountsFixtures.user_fixture()
      |> Ecto.Changeset.change(role: :sysop, status: :active)
      |> Repo.update!()

    author = AccountsFixtures.user_fixture()
    {:ok, entry} = Oneliners.create_entry(author, %{body: "problem line"})

    local_state = %MainMenuState{
      recent_oneliners: [%{id: entry.id, body: entry.body, user: %{handle: author.handle}}],
      selected_oneliner_index: 0
    }

    context = Context.new(current_user: reporter, session_context: %{}, route: :main_menu)

    {next_local_state, effects} =
      MainMenu.update(
        {:modal_submit, :submit_oneliner_report,
         %{target_kind: :oneliner, target_id: entry.id, reason: "spam", notes: "details"}},
        local_state,
        context
      )

    assert next_local_state == local_state

    assert [
             %Effect{
               type: :task,
               payload: %{op: :submit_oneliner_report, screen_key: :main_menu, fun: task_fun}
             }
           ] = effects

    assert {:ok, %Report{} = report} = task_fun.()
    assert report.target_kind == :oneliner
    assert report.target_id == entry.id
    assert report.reason == "spam"
    assert report.notes == "details"
    assert report.reporter_id == reporter.id

    assert {:ok, workspace} = Moderation.workspace_snapshot(moderator)
    assert Enum.any?(workspace.queue, &(&1.id == report.id))

    {final_local_state, final_effects} =
      MainMenu.update(
        {:task_result, :submit_oneliner_report, {:ok, report}},
        next_local_state,
        context
      )

    assert final_local_state.oneliner_errors == %{}

    assert [
             %Effect{
               type: :modal,
               payload: {:open, %Modal{title: "Success", message: "Report submitted."}}
             }
           ] = final_effects
  end
end
