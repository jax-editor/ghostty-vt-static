#!/usr/bin/env bash
# Cut a release: pick the next monotonic build counter N, tag
# vN-<short-commit>, and push to trigger the release workflow.
#
# Usage:
#   ./tag-release.sh             # interactive: shows next tag, asks to push
#   ./tag-release.sh --yes       # non-interactive
set -euo pipefail

cd "$(dirname "$0")"

short_commit=$(cut -c1-7 ghostty-commit | tr -d '[:space:]')
if [ -z "$short_commit" ]; then
    echo "Error: ghostty-commit is empty" >&2
    exit 1
fi

# Find the next monotonic N across all existing vN-* tags (any commit).
# N never resets when the upstream commit changes.
git fetch --tags --quiet || true
max_n=0
while IFS= read -r tag; do
    n=$(echo "$tag" | sed -nE 's/^v([0-9]+)-[0-9a-f]{7,40}$/\1/p')
    if [ -n "$n" ] && [ "$n" -gt "$max_n" ]; then
        max_n=$n
    fi
done < <(git tag --list 'v*-*')

next_n=$((max_n + 1))
tag="v${next_n}-${short_commit}"

echo "Next release tag: ${tag}"
echo "  upstream ghostty commit: $(cat ghostty-commit)"

if [ "${1:-}" != "--yes" ]; then
    read -r -p "Tag and push? [y/N] " ans
    case "$ans" in
        y|Y|yes|YES) ;;
        *) echo "Aborted."; exit 0 ;;
    esac
fi

git tag "$tag"
git push origin "$tag"
echo "Pushed ${tag}. Watch CI: https://github.com/jax-editor/ghostty-vt-static/actions"
