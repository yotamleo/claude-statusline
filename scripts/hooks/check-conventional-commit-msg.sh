#!/usr/bin/env bash
# Commit-msg hook: enforce Conventional Commits subject line.
# Format: type(scope?)!?: subject
#   type: feat, fix, chore, docs, refactor, test, perf, build, ci, revert, style
#   scope: optional, in parens
#   !: optional breaking-change marker
#   subject: free text, must be non-empty
#
# Allow merge/revert auto-generated messages to pass.
set -uo pipefail

msg_file="${1:-}"
if [ -z "$msg_file" ] || [ ! -f "$msg_file" ]; then
    echo "ERROR: commit-msg hook invoked without a valid message file." >&2
    exit 1
fi

subject=$(sed -n '1p' "$msg_file")

# Skip auto-generated merge/revert commits — git creates these and they
# don't follow Conventional Commits.
case "$subject" in
    "Merge "*|"Revert "*) exit 0 ;;
esac

regex='^(feat|fix|chore|docs|refactor|test|perf|build|ci|revert|style)(\([a-z0-9._/-]+\))?!?: .+'
if ! printf '%s' "$subject" | grep -Eq "$regex"; then
    {
        echo "ERROR: commit subject does not match Conventional Commits."
        echo "       Got:      $subject"
        echo "       Expected: <type>(<scope>): <message>"
        echo "       Types:    feat|fix|chore|docs|refactor|test|perf|build|ci|revert|style"
    } >&2
    exit 1
fi
exit 0
