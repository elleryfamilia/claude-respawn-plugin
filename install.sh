#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKETPLACE="claude-respawn-plugin"
PLUGIN="respawn@${MARKETPLACE}"

SKILL_SRC="${HERE}/plugins/respawn/skills/respawn"
COMMAND_SRC="${HERE}/plugins/respawn/commands/respawn.md"
SKILL_DEST="${HOME}/.claude/skills/respawn"
COMMAND_DEST="${HOME}/.claude/commands/respawn.md"

require_claude() {
  if ! command -v claude >/dev/null 2>&1; then
    echo "error: 'claude' CLI not found on PATH" >&2
    exit 1
  fi
}

remove_dev_symlinks() {
  local removed=0
  if [ -L "$SKILL_DEST" ]; then rm "$SKILL_DEST"; removed=1; fi
  if [ -L "$COMMAND_DEST" ]; then rm "$COMMAND_DEST"; removed=1; fi
  [ "$removed" = "1" ] && echo "removed dev-mode symlinks"
  return 0
}

cmd_install() {
  require_claude
  claude plugin validate "$HERE"
  claude plugin marketplace add "$HERE" || true  # idempotent; already-added is fine
  claude plugin install "$PLUGIN"
  echo "✓ Installed. Restart Claude Code to load /respawn."
}

cmd_uninstall() {
  require_claude
  claude plugin uninstall "$PLUGIN" 2>/dev/null || echo "(plugin was not installed)"
  claude plugin marketplace remove "$MARKETPLACE" 2>/dev/null || echo "(marketplace was not registered)"
  remove_dev_symlinks
  echo "✓ Uninstalled."
}

cmd_dev() {
  mkdir -p "${HOME}/.claude/skills" "${HOME}/.claude/commands"
  ln -sfn "$SKILL_SRC" "$SKILL_DEST"
  ln -sfn "$COMMAND_SRC" "$COMMAND_DEST"
  echo "✓ Dev symlinks installed:"
  echo "  $SKILL_DEST -> $SKILL_SRC"
  echo "  $COMMAND_DEST -> $COMMAND_SRC"
  echo "Note: uninstall the real plugin first ('./install.sh --uninstall') to avoid double-triggering."
  echo "Restart Claude Code to pick up changes."
}

case "${1:-}" in
  --uninstall) cmd_uninstall ;;
  --dev)       cmd_dev ;;
  ""|--install) cmd_install ;;
  *)
    echo "usage: $0 [--install|--uninstall|--dev]" >&2
    exit 2
    ;;
esac
