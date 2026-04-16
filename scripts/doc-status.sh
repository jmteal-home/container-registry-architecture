#!/usr/bin/env bash
# doc-status.sh — print a status summary of all documents
# Usage: ./scripts/doc-status.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCS_DIR="$REPO_ROOT/docs"

printf "%-10s %-8s %-55s\n" "DOC-ID" "STATUS" "TITLE"
printf "%-10s %-8s %-55s\n" "------" "------" "-----"

find "$DOCS_DIR" -name 'DOC-*.md' | sort | while read -r f; do
    doc_id=$(grep -m1 '^document_id:' "$f" | awk '{print $2}')
    status=$(grep -m1 '^status:' "$f" | awk '{print $2}')
    title=$(grep -m1 '^title:' "$f" | sed 's/^title: *//;s/"//g')
    printf "%-10s %-8s %-55s\n" "$doc_id" "$status" "$title"
done
