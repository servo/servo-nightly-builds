#!/usr/bin/env zsh
# usage: tools/bury-old-drafts.sh
# requires: zsh, gh, jq, rg
set -euo pipefail
missing() { >&2 echo "fatal: $1 not found"; exit 1; }
> /dev/null command -v gh || missing gh
> /dev/null command -v jq || missing jq
> /dev/null command -v rg || missing rg

set --
org_repo_slug=servo/servo-nightly-builds
now=$(date +\%s)
result=$(mktemp)
page=1
while :; do
    gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" \
        /repos/"$org_repo_slug"'/releases?per_page=100&page='$page > $result
    length=$(< $result jq length)
    if [ $length -eq 0 ]; then
        break
    fi
    for draft in $(< $result jq '.[] | select(.draft) | .id'); do
        created_at=$(< $result jq -r '.[] | select(.id == '"$draft"') | .created_at')
        created_at=$(date +\%s --date="$created_at")
        age=$((now - created_at))
        # Ignore young drafts, because their release builds may still be running
        if [ $age -lt 86400 ]; then
            >&2 echo "Warning: ignoring release $draft, which is only $age seconds old"
        else
            set -- "$@" "$draft"
        fi
    done
    >&2 echo "Page $page has $length releases; found $# drafts so far"
    page=$((page+1))
done
for draft; do
    # Mark as prerelease and unmark as draft
    set -- PATCH "/repos/$org_repo_slug/releases/$draft" -F prerelease=true -F draft=false
    echo "$@"
    if ! gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" \
        --method "$@" > $result; then
        < $result jq
        >&2 printf 'Delete release? [y/N] '
        read -r yn
        if [ "$yn" = y ]; then
            set -- DELETE "/repos/$org_repo_slug/releases/$draft"
            echo "$@"
            gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" \
                --method "$@"
        fi
    fi
done
