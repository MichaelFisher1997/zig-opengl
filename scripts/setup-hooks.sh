#!/usr/bin/env bash
set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"

echo "Configuring git hooks for: $REPO_ROOT"
git config core.hooksPath "$REPO_ROOT/.githooks"

echo ""
echo "Git hooks configured successfully!"
echo "Pre-push hook will run: format check + full test suite"
echo ""
echo "To bypass in emergencies: git push --no-verify"
