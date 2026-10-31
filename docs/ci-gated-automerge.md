# Coufunch CI-gated auto-merge pilot

This pilot automates **merge of explicitly approved, low-risk PRs** after the existing `iOS CI` workflow succeeds. It does not make every PR automatic, launch Codex, update Trello, or deploy the app.

## Safety policy

1. Changes are always made on a feature branch. Never push directly to `main`.
2. A PR must be authored by `iosdevbyul`, come from the same repository, target `main`, be open and non-draft.
3. The completed `iOS CI` run must have succeeded for the PR's **current head commit**. The workflow resolves the PR by its exact tested commit SHA, because GitHub sometimes supplies an empty `workflow_run.pull_requests` array.
4. The PR must carry `automerge-safe` and must **not** carry `manual-qa`. Add the approval label **before** the CI run finishes.
5. Changed files must not include GitHub workflows, scripts, project configuration, app entry point, secure-rendering code, assets, launch storyboard, localization catalogs, package lockfiles, or any path ending in `View.swift`, `Screen.swift`, or `Widget*.swift`.
6. Merging uses `gh pr merge --squash --match-head-commit`. It never uses `--admin` or checks out PR code with the privileged token.
7. Failure, missing event metadata, stale PR head, or missing labels cause a **safe skip**. UI, accessibility, security, dependencies, releases and other changes needing device checks are merged manually after acceptance.

This is a personal-repository workflow, not approval of external contributions. The path gate is a conservative safeguard and not a substitute for review. The CI currently runs on an iOS Simulator; it is not physical-iPhone acceptance.

## One-time GitHub repository setup

The workflow is deployed only when this pilot PR is reviewed, CI passes and the PR is manually merged into `main`.

Configure `main` protection at **Settings → Branches → Add branch protection rule** (or an equivalent ruleset):
- Branch name: `main`
- Require a pull request before merging
- Require status checks: the `build` job from `iOS CI`
- Require branches to be up to date before merging, so a changed `main` requires a fresh CI result
- Do not bypass the requirements for the automation; do not enable forced pushes

For a single-developer repository, do not enable a required approval count without planning for another reviewer; GitHub does not allow authors to approve their own PRs.

At **Settings → Actions → General → Workflow permissions**, ensure workflows can obtain the declared `contents: write` and `pull-requests: write` permissions. Review your organization's restrictions if any. This workflow performs a direct, conditional merge and **does not require GitHub's separate "Allow auto-merge" toggle**.

Create the two labels once:

```bash
gh label create automerge-safe --repo iosdevbyul/Coufunch --color 0E8A16 --description "CI-passed low-risk PR may auto-merge"
gh label create manual-qa --repo iosdevbyul/Coufunch --color D93F0B --description "Requires hands-on validation and manual merge"
```

If labels already exist, keep them; no need to recreate.

## Normal operation

1. Create and push a feature branch and open a PR.
2. For a genuinely low-risk, already reviewed change, opt in **before CI completes**:

   ```bash
   gh pr edit <PR_NUMBER> --repo iosdevbyul/Coufunch --add-label automerge-safe
   ```

3. After the PR's `iOS CI` workflow succeeds, `Merge approved PR after CI` will inspect the latest head and changed files. If every guard passes, it performs a squash merge.
4. For UI/device/interactive changes, instead use `manual-qa` and keep merging manual after on-device testing.

If the approval label was added after CI already finished, use GitHub's **Re-run jobs** on the PR's successful CI run to trigger a fresh completed event. Avoid retriggering by modifying unrelated code.

## Pilot acceptance

After the automation PR itself is manually merged, make a small documentation-only test PR. Apply `automerge-safe` before CI completion. Verify that it merges exactly once after CI success. Then make a second test PR with `manual-qa` or a `*View.swift` change and confirm the automation logs **Skipping** without merging it.

If no PR is merged, inspect the `Merge approved PR after CI` workflow logs. The pipeline deliberately skips ambiguous cases.

## Roadmap: Trello and Codex

Automatic Trello transitions and autonomous next-task implementation are **not configured in this phase**. They need a trusted GitHub-merge event handler, authorized Trello API credentials, an explicit and stable Next-task queue, a Codex runner with repository permissions and spending limits, plus stop/retry controls. Add this in a separate PR after the merge pilot is proven. Never let a CI-only success assert that an iPhone visual test passed.
