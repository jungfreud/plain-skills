#!/usr/bin/env bash
# Rewrite this bundle's own repository links before relocation. Requires Python 3.
# Usage: ./scripts/retarget.sh team-plain/repository [branch]
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - "$@" <<'PY'
import pathlib, re, subprocess, sys
if len(sys.argv) not in (2, 3) or not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', sys.argv[1]):
    sys.exit('usage: retarget.sh <owner/repo> [branch]')
target = sys.argv[1]
branch = sys.argv[2] if len(sys.argv) == 3 else 'main'
if not re.fullmatch(r'[A-Za-z0-9_./-]+', branch) or '..' in branch:
    sys.exit('Invalid branch/ref')
readme = pathlib.Path('README.md').read_text()
match = re.search(r'raw\.githubusercontent\.com/([^/]+/[^/]+)/(.+?)/skills/', readme)
if not match:
    sys.exit('Cannot determine current bundle repository from README.md')
current = match[1]
files = subprocess.check_output(['git', 'ls-files', '-z', '*.md']).decode().split('\0')
for name in filter(None, files):
    p = pathlib.Path(name)
    old = p.read_text()
    # Match this repository only. Branches may contain slashes; /skills/ is the boundary.
    new = re.sub(r'raw\.githubusercontent\.com/' + re.escape(current) + r'/.*?/skills/',
                 'raw.githubusercontent.com/' + target + '/' + branch + '/skills/', old)
    new = re.sub(r'github\.com/' + re.escape(current) + r'(?=[/\s)#]|$)', 'github.com/' + target, new)
    new = new.replace('npx skills add ' + current, 'npx skills add ' + target)
    if new != old:
        p.write_text(new)
        print(name)
print('Retargeted ' + current + ' → ' + target + ' (' + branch + '). Review git diff before publishing.')
PY
