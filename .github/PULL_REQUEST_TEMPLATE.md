<!--
Keep this PR small and focused. Prefer 1 commit per PR.
Commit subjects must follow Conventional Commits (enforced by lefthook):
  type(scope): description   type ∈ {feat, fix, chore, docs, refactor, ci}
-->

## Summary

<!-- What does this PR change and why? 1-3 sentences. -->

## Changes

<!-- Bullet list of the concrete changes. -->
-

## Verification

<!-- How was this checked? (CI passing is enforced by branch protection.) -->
- [ ] `lefthook run pre-commit` passes locally (lint, config, secrets)
- [ ] Manually verified the affected dotfile(s) load

## Checklist

- [ ] Branched off `main` — no direct commits to `main`
- [ ] Commit subjects follow Conventional Commits
- [ ] No secrets / sensitive files committed (gitleaks clean)

## Related

<!-- Closes #123, refs #456, or "none". -->
