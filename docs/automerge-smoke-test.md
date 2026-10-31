# CI-gated auto-merge smoke test

This intentionally small documentation-only change verifies the auto-merge workflow introduced in Coufunch PR #110.

Expected behavior for this test PR:

1. The existing `iOS CI` workflow builds and tests successfully.
2. The PR has the `automerge-safe` label, is not a draft, and does not have the `manual-qa` label.
3. The `Merge approved PR after CI` workflow confirms that the exact tested commit is still the PR head.
4. The workflow squash-merges this PR into `main` if GitHub Actions has the required write permissions.

This test does not change application code, UI, security behavior, or project configuration.

**Record the actual outcome from the PR and workflow logs.** A successful CI alone does not demonstrate successful automatic merging.
