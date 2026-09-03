#!/usr/bin/env bash
# Point every cross-reference in this repo at a different owner/repo.
#
# The skills reference each other by URL so they work when fetched cold, which means
# moving the repo means rewriting those URLs. This does it in one pass.
#
#   ./scripts/retarget.sh team-plain/skills
#   ./scripts/retarget.sh team-plain/skills main
#
# Review with `git diff` before committing.

set -euo pipefail

TARGET="${1:-}"
BRANCH="${2:-main}"

if [ -z "$TARGET" ]; then
  echo "usage: $0 <owner/repo> [branch]" >&2
  echo "example: $0 team-plain/skills" >&2
  exit 1
fi

cd "$(dirname "$0")/.."

CURRENT=$(grep -rhoE 'raw\.githubusercontent\.com/[^/]+/[^/]+/' --include="*.md" . \
          | head -1 | sed -E 's#raw\.githubusercontent\.com/([^/]+/[^/]+)/#\1#')

if [ -z "$CURRENT" ]; then
  echo "Could not determine the current owner/repo from the markdown files." >&2
  exit 1
fi

echo "Retargeting: $CURRENT -> $TARGET (branch: $BRANCH)"

FILES=$(git ls-files '*.md')
for f in $FILES; do
  # raw content URLs used by the skills to fetch each other
  sed -i '' -E "s#raw\.githubusercontent\.com/[^/]+/[^/]+/[^/]+/#raw.githubusercontent.com/${TARGET}/${BRANCH}/#g" "$f"
  # repo links (issues, browse)
  sed -i '' -E "s#github\.com/[^/[:space:])]+/[^/[:space:])]+(/(issues|blob|tree)[^[:space:])]*)?#github.com/${TARGET}\1#g" "$f"
  # skills.sh install line
  sed -i '' -E "s#npx skills add [^[:space:]]+#npx skills add ${TARGET}#g" "$f"
done

echo
echo "Rewritten. Remaining references to the old location (should be none):"
grep -rn "$CURRENT" --include="*.md" . || echo "  none"
echo
echo "Now: git diff, then verify the new URLs resolve once pushed:"
echo "  curl -s -o /dev/null -w '%{http_code}\\n' https://raw.githubusercontent.com/${TARGET}/${BRANCH}/plain-configuration/SKILL.md"
