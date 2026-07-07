#!/bin/bash
# session-start.sh — verify GitHub connectivity and prepare repo tooling for
# Claude Code sessions (web, Dispatch/routines, and local terminal).
#
# Goals:
#   - Confirm the git remote is reachable WITHOUT ever prompting for input.
#   - Make the repo's helper scripts usable.
#   - Surface a clear diagnostic if credentials are missing, instead of hanging.
#
# Safe to run repeatedly (idempotent) and never blocks on interactive input.
set -uo pipefail

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$REPO_ROOT" || exit 0

# Never let git or ssh stop to ask a human anything.
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new"

# 1. Ensure helper scripts are executable.
chmod +x scripts/*.sh 2>/dev/null || true

# 2. validate-links.sh depends on python3 — warn (don't fail) if it's absent.
if ! command -v python3 >/dev/null 2>&1; then
  echo "session-start: python3 not found — scripts/validate-links.sh will not run" >&2
fi

# 3. Verify the GitHub remote is reachable non-interactively.
#    In web/Dispatch sessions auth is injected by the Anthropic proxy; locally
#    it uses your SSH key (or credential helper). Either way, no prompt.
if git ls-remote --exit-code origin >/dev/null 2>&1; then
  echo "session-start: GitHub remote reachable — $(git remote get-url origin)"
else
  echo "session-start: cannot reach GitHub remote non-interactively." >&2
  echo "session-start: check credentials — see docs/CONTRIBUTING.md / repo access setup." >&2
fi

exit 0
