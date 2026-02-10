#!/bin/bash

COMMANDS_DIR="$HOME/.claude/commands"

echo "Uninstalling git-author-update skill..."

rm -f "$COMMANDS_DIR/git-author-update.md"
rm -f "$COMMANDS_DIR/git-author-update.sh"

echo "Removed from $COMMANDS_DIR"
echo "Done."
