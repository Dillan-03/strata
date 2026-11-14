# Repository templates

Plain-Markdown copies of the templates this project uses, for drafting outside GitHub's issue forms (in an editor, a script, or with an AI agent).

| Template | Use for | GitHub form |
| --- | --- | --- |
| [FEATURE_TEMPLATE.md](FEATURE_TEMPLATE.md) | New functionality | `.github/ISSUE_TEMPLATE/feature.yml` |
| [BUG_TEMPLATE.md](BUG_TEMPLATE.md) | Defects and regressions | `.github/ISSUE_TEMPLATE/bug.yml` |
| [CHORE_TEMPLATE.md](CHORE_TEMPLATE.md) | Setup, credentials, infrastructure | `.github/ISSUE_TEMPLATE/chore.yml` |
| [PR_TEMPLATE.md](PR_TEMPLATE.md) | Pull requests | `.github/PULL_REQUEST_TEMPLATE.md` |

## Title rules

Every issue title starts with exactly one of `[Feature]`, `[Bug]` or `[Chore]`. The **Issue title** workflow fixes obvious variants such as `feat: …` and comments on anything else.

## Workflow

Issue → `feature/issue-<n>-<slug>` (or `fix/…`, `chore/…`) branch → tests → PR with `Closes #<n>` → green CI → squash merge → issue closed.

Chores that need the repository owner get `status:needs-user-action` and stay open until the setup is verified, not just reported as done.
