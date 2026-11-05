#!/usr/bin/env bash
# scaffold.sh [--project <dir>]: the mechanical part of skills/install steps 2-5,
# at the repo root or, with --project, in a sub-project (skills/install § Sub-project).
# Create-only: one line per item, "created", "exists", "added" or "moved". Exit 0 all
# done, 3 a real .claude/ or CLAUDE.md is in the way (merge it, asking first, then rerun),
# 2 settings.json is not valid JSON (left untouched), 1 a symlink could not be made, or
# no such sub-project folder.
here="$(cd "$(dirname "$0")" && pwd)"; plugin="$(dirname "$here")"
sub=; [ "${1:-}" = --project ] && sub="${2:?usage: scaffold.sh [--project <dir>]}"
. "$here/target.sh"; target "$sub" || exit 1
cd "$dir" || exit 1
rc=0; keep() { [ "$1" -gt "$rc" ] && rc="$1"; }
copy() { if [ -e "$2" ]; then echo "exists  $2"; else cp "$1" "$2" && echo "created $2"; fi; }

mkdir -p .agents/memory .agents/rules
if [ -e .agents/.gitignore ]; then
  grep -qxF settings.local.json .agents/.gitignore \
    || { echo settings.local.json >> .agents/.gitignore; echo "added   .agents/.gitignore: settings.local.json"; }
else printf 'settings.local.json\n.obsidian\n' > .agents/.gitignore; echo "created .agents/.gitignore"; fi
"$here/link.sh" .agents .claude; keep $?

copy "$plugin/templates/rules/memory.md" .agents/rules/memory.md   # created → translate it
perl "$here/merge-json.pl" .agents/settings.json "$plugin/templates/settings.json"; keep $?

if [ -L CLAUDE.md ] && [ ! -e CLAUDE.md ]; then rm CLAUDE.md; fi   # dangling: drop it
if [ ! -e AGENTS.md ] && [ -f CLAUDE.md ] && [ ! -L CLAUDE.md ]; then
  { git mv CLAUDE.md AGENTS.md 2>/dev/null || mv CLAUDE.md AGENTS.md; } && echo "moved   CLAUDE.md -> AGENTS.md"
fi
[ -e AGENTS.md ] || { touch AGENTS.md; echo "created AGENTS.md (empty)"; }
"$here/link.sh" AGENTS.md CLAUDE.md; keep $?

# One repo, one commit policy: a same-repo sub-project links the root's, which a session
# started in the sub-project would not load otherwise.
if [ "$layout" = same-repo ]; then
  up="$(printf '%s' "$tag" | sed 's|[^/]*|..|g')"
  if [ -e .agents/rules/commit.md ] || [ -L .agents/rules/commit.md ]; then echo "exists  .agents/rules/commit.md"
  elif [ -f "$top/.agents/rules/commit.md" ]; then
    ( cd .agents/rules && "$here/link.sh" "../../$up/.agents/rules/commit.md" commit.md >/dev/null ); r=$?; keep $r
    [ $r = 0 ] && echo "created .agents/rules/commit.md -> the root's"
  else echo "skipped .agents/rules/commit.md: the root has none yet (link it once it does)"; fi
fi

exit "$rc"
