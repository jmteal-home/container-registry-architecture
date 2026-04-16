#!/usr/bin/env bash
# validate-links.sh — check all relative markdown links in the docs/ tree resolve
# Usage: ./scripts/validate-links.sh

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCS_DIR="$REPO_ROOT/docs"
ERRORS=0

echo "Validating relative links in $DOCS_DIR..."

while IFS= read -r -d '' file; do
    dir="$(dirname "$file")"
    # Extract relative .md links using Python for reliable regex handling
    while IFS= read -r link; do
        # Strip fragment (#section-anchor) if present
        target_path="${link%%#*}"
        [[ -z "$target_path" ]] && continue
        full_target="$dir/$target_path"
        if [[ ! -f "$full_target" ]]; then
            echo "  BROKEN: $(basename $file) -> $target_path"
            ((ERRORS++)) || true
        fi
    done < <(python3 -c "
import re, sys
text = open('$file').read()
# Match relative links: [text](path.md) or [text](path.md#anchor)
# Exclude http/https links
for m in re.finditer(r'\[([^\]]+)\]\(([^)]+\.md(?:#[^)]*)?)\)', text):
    link = m.group(2)
    if not link.startswith('http'):
        print(link)
")
done < <(find "$DOCS_DIR" -name '*.md' -print0)

if [[ $ERRORS -eq 0 ]]; then
    echo "  ✓ All links valid."
else
    echo ""
    echo "  $ERRORS broken link(s) found."
    exit 1
fi
