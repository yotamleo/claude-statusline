#!/usr/bin/env bash
# Pre-push hook: block direct push to main.
# Git pipes one line per pushed ref to stdin:
#   "local_ref local_sha remote_ref remote_sha"
# We refuse if any line's remote_ref is refs/heads/main.
set -uo pipefail

saw_line=0
while read -r local_ref local_sha remote_ref remote_sha; do
    saw_line=1
    # Malformed line: fewer than 4 fields means git's contract was violated.
    # Fail-closed rather than silently let an unparseable push through.
    if [ -z "$local_ref" ] || [ -z "$local_sha" ] || [ -z "$remote_ref" ] || [ -z "$remote_sha" ]; then
        echo "ERROR: no-push-to-main got malformed line from git pre-push stdin." >&2
        echo "       Refusing to allow push. (local_ref='$local_ref' remote_ref='$remote_ref')" >&2
        exit 1
    fi
    if [ "$remote_ref" = "refs/heads/main" ]; then
        echo "ERROR: Direct push to 'main' is not allowed." >&2
        echo "       Open a PR from a feature branch instead." >&2
        exit 1
    fi
done

# Empty stdin (no refs piped) — this happens for no-op pushes and tag-only
# pushes that don't update a branch ref. Allow; nothing to gate on.
if [ "$saw_line" -eq 0 ]; then
    exit 0
fi
exit 0
