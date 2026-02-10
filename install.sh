#!/bin/bash
set -eo pipefail

# ============================================================
# Installer for git-author-update Claude Code skill
# ============================================================

COMMANDS_DIR="$HOME/.claude/commands"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing git-author-update skill..."
echo ""

mkdir -p "$COMMANDS_DIR"

cp "$SCRIPT_DIR/git-author-update.md" "$COMMANDS_DIR/git-author-update.md"
cp "$SCRIPT_DIR/git-author-update.sh" "$COMMANDS_DIR/git-author-update.sh"
chmod +x "$COMMANDS_DIR/git-author-update.sh"

echo "Installed to:"
echo "  $COMMANDS_DIR/git-author-update.md"
echo "  $COMMANDS_DIR/git-author-update.sh"
echo ""
echo "Usage:"
echo "  In Claude Code, type:  /user:git-author-update"
echo "  Or run directly:       bash ~/.claude/commands/git-author-update.sh --help"
echo ""
echo "Done."
