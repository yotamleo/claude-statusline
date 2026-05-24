# claude-statusline (yotamleo fork) — Project Rules

Fork of [nilbuild/claude-statusline](https://github.com/nilbuild/claude-statusline).
This file documents the workflow protections enforced in this fork.

## Git Workflow

- All feature work on a feature branch. Never commit directly to `main`.
- All changes go via PR. No direct pushes to `main`.
- Use Conventional Commits: `type(scope?): subject`
  - Types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`, `revert`, `style`
  - Validated by `scripts/hooks/check-conventional-commit-msg.sh`.

## Pre-commit Enforcement

Source of truth: `.pre-commit-config.yaml`. Install once after cloning:

```bash
pip install pre-commit
pre-commit install --hook-type pre-commit --hook-type commit-msg --hook-type pre-push
```

Stages currently wired:

- **Format/lint (pre-commit):** trailing-whitespace, end-of-file-fixer,
  check-yaml, check-json, mixed-line-ending (forces LF), shellcheck
  (severity=error — catches genuine bugs without nitpicks).
- **Secrets (pre-commit):** gitleaks.
- **Branch hygiene (pre-commit):** worktree-isolation — blocks any commit when
  current branch == `main`. Fail-closed if branch detection errors.
- **Commit-msg:** conventional-commit-msg — validates `type(scope?): subject`
  format; auto-generated `Merge`/`Revert` messages pass through.
- **Pre-push:** no-push-to-main — refuses any push whose remote ref is
  `refs/heads/main`. Catches both ordinary push and explicit
  `push HEAD:refs/heads/main` bypass attempts.

## Line endings

`.gitattributes` forces LF for all shell scripts. CRLF in bash scripts
breaks on Linux/macOS (literal `\r` characters get embedded in variable
values and ANSI escape sequences). The `mixed-line-ending` pre-commit
hook rewrites CRLF to LF on commit *and fails the commit on first hit*
— you have to `git add` the corrected file and re-commit.

**Windows operators:** set `git config --global core.autocrlf false`
before cloning, otherwise git's smudge filter will re-CRLF the working
tree after each checkout and fight the pre-commit hook every commit.

## Upstream sync

This fork periodically merges from upstream `nilbuild/claude-statusline`.
The merge commit itself bypasses the conventional-commit validator (the
`Merge ` prefix is explicitly skipped) but upstream commits must still
pass shellcheck and gitleaks before they land here.
