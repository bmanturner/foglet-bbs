# Governance

## Pull Request Merge Approval

Pull requests must not be merged on the basis of an author-authored acceptance comment alone. A merge needs independent approval recorded before the merge:

- a formal GitHub approving review from someone other than the PR author, or
- a pull request comment from someone other than the PR author that begins with `Board approval: approved`.

The `Merge Governance / board approval` workflow checks this rule on pull requests, pull request review updates, and pull request comments. Repository administrators should require that check before merging to `main` as soon as GitHub branch protection or rulesets are available for this repository.

Current limitation: GitHub returned HTTP 403 for branch protection and repository rulesets on this private repository, so the workflow is an auditable guardrail until the repository plan/settings support required checks.
