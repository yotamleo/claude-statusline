#!/usr/bin/env bash
# Pre-push hook: block direct push to main.
# Git pipes one line per pushed ref to stdin:
#   "local_ref local_sha remote_ref remote_sha"
# We refuse if any line's remote_ref is refs/heads/main.
set -uo pipefail

while read -r _local_ref _local_sha remote_ref _remote_sha; do
    if [ "$remote_ref" = "refs/heads/main" ]; then
        echo "ERROR: Direct push to 'main' is not allowed." >&2
        echo "       Open a PR from a feature branch instead." >&2
        exit 1
    fi
done
exit 0
