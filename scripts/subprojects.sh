#!/usr/bin/env bash
# subprojects.sh: the folders below the root that are, or look like, sub-projects,
# for /agent-leash:update to list. One line each, tab-separated: tag, layout
# (same-repo, own-repo) and state:
#   harness    it has .agents/ and AGENTS.md: `--project <tag>` maintains it.
#   candidate  a CLAUDE.md, AGENTS.md or .claude/ of its own but no .agents/:
#              `--project <tag>` would set it up (skills/install step 1 merges its .claude/).
# Writes nothing. Dependency and build folders are skipped. Exit 1 not a git repo.
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/target.sh"; target || exit 1
cd "$top" || exit 1
find . -mindepth 2 -maxdepth 6 \
  \( -name .git -o -name node_modules -o -name vendor -o -name .venv -o -name dist -o -name build -o -name target \) -prune \
  -o \( -name .agents -o -name .claude -o -name AGENTS.md -o -name CLAUDE.md \) -print 2>/dev/null \
  | sed 's|^\./||; s|/[^/]*$||' | sort -u | while IFS= read -r d; do
  case "$d" in .agents|.agents/*|*/.agents/*|*/.claude/*) continue ;; esac
  (
    target "$d" 2>/dev/null || exit 0
    state=candidate; [ -d "$d/.agents" ] && [ -e "$d/AGENTS.md" ] && state=harness
    printf '%s\t%s\t%s\n' "$tag" "$layout" "$state"
  )
done
