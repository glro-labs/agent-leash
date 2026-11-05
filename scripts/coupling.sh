#!/usr/bin/env bash
# coupling.sh <doc> <glob>...: of the commits that touch the globs, how many also touched
# <doc>. Adopted as a pointer note over those globs, memory-drift-guard would have blocked
# the rest: the figure that tells whether guarding the area is worth it.
usage="usage: coupling.sh <doc> <glob>..."
doc="${1:?$usage}"; shift; [ $# -gt 0 ] || { echo "$usage" >&2; exit 1; }
specs=(); for g in "$@"; do specs+=(":(glob)$g"); done
area="$(git log --format=%H -- "${specs[@]}" | sort)"
m=$(printf '%s' "$area" | grep -c .)
n=$(comm -12 <(printf '%s\n' "$area") <(git log --format=%H -- "$doc" | sort) | grep -c .)
echo "$n of $m commits touching $* also touched $doc; the guard would have blocked $((m - n))"
