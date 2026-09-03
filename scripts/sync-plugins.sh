#!/usr/bin/env bash
# Regenerates plugins/ from skills/.
#
# skills/ is the single source of truth. Claude Code loads skills from skills/
# at the plugin root; Cursor loads one plugin per directory under plugins/
# (see .cursor-plugin/marketplace.json). Rather than hand-maintain two copies,
# plugins/ is generated from skills/ by this script.
#
#   ./scripts/sync-plugins.sh          regenerate plugins/
#   ./scripts/sync-plugins.sh --check  fail if plugins/ is out of date (CI)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

cursor_plugin_json() {
    local name="$1" description="$2"
    cat <<JSON
{
  "name": "$name",
  "displayName": "$(echo "$name" | sed 's/plain-/Plain /; s/\b\(.\)/\u\1/g')",
  "version": "0.1.0",
  "description": "$description",
  "author": {
    "name": "Plain",
    "email": "support@plain.com"
  },
  "license": "MIT",
  "keywords": ["cursor", "plugin", "skills", "plain"],
  "logo": "./assets/logo.svg"
}
JSON
}

describe() {
    # Pull the skill's own description out of its YAML frontmatter, so the
    # Cursor manifest can never drift from what the skill actually says.
    awk '/^description: /{sub(/^description: /,""); print; exit}' "$ROOT/skills/$1/SKILL.md"
}

build() {
    local dest="$1"
    rm -rf "$dest"
    for skill in plain-configuration plain-onboarding plain-insights; do
        mkdir -p "$dest/$skill/.cursor-plugin" "$dest/$skill/assets"
        # SKILL.md sits at the plugin root for Cursor's single-skill plugin shape.
        cp "$ROOT/skills/$skill/SKILL.md" "$dest/$skill/SKILL.md"
        [ -d "$ROOT/skills/$skill/references" ] && cp -R "$ROOT/skills/$skill/references" "$dest/$skill/"
        cp "$ROOT/assets/logo.svg" "$dest/$skill/assets/logo.svg"
        cursor_plugin_json "$skill" "$(describe "$skill")" > "$dest/$skill/.cursor-plugin/plugin.json"
    done
}

if [ "$CHECK" = 1 ]; then
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    build "$tmp/plugins"
    if diff -r "$tmp/plugins" "$ROOT/plugins" >/dev/null 2>&1; then
        echo "plugins/ is in sync with skills/"
    else
        echo "plugins/ is OUT OF DATE. Run ./scripts/sync-plugins.sh and commit the result." >&2
        diff -r "$tmp/plugins" "$ROOT/plugins" || true
        exit 1
    fi
else
    build "$ROOT/plugins"
    echo "plugins/ regenerated from skills/"
fi
