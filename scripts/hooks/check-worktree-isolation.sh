#!/usr/bin/env bash
# Pre-commit hook: refuse commits on `main` from the primary worktree.
# Fail-closed if branch detection errors (worktree state corrupt, detached HEAD).
set -uo pipefail

branch=$(git symbolic-ref --short HEAD 2>/dev/null) || {
    echo "ERROR: worktree-isolation could not determine current branch." >&2
    echo "       Refusing to allow commit. Fix git state and retry." >&2
    exit 1
}

if [ "$branch" = "main" ]; then
    echo "ERROR: Committing directly on 'main' is not allowed." >&2
    echo "       Create a feature branch first: git checkout -b type/short-slug" >&2
    exit 1
fi
exit 0
