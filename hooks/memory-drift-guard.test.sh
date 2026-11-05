#!/usr/bin/env bash
# Self-check for the memory-drift-guard check of guard.sh:  bash hooks/memory-drift-guard.test.sh
#
# Each case builds a throwaway repo under $TMPDIR, so the real worktree and
# index are never touched. Exits non-zero if any case regresses.
set -uo pipefail

H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/guard.sh"
bash -n "$H" || exit 1
# The exec bit has to survive the clone: git records it, a plain `cp` does not.
[ -x "$H" ] || { echo "missing exec bit: guard.sh (git update-index --chmod=+x)"; exit 1; }
perl -MJSON::PP -e1 || { echo "perl with JSON::PP is required (the hook needs it too)"; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# note <dir> <name> <glob>...  writes .agents/memory/<name> covering the globs.
note() {
  local dir="$1" name="$2"; shift 2
  mkdir -p "$dir/.agents/memory"
  { echo ---; echo paths:; for g in "$@"; do echo "  - \"$g\""; done; echo ---; echo "# $name"; } \
    > "$dir/.agents/memory/$name"
}

fails=0
n=0
# t <expected exit> <command> <files to stage|-> [<file edited but unstaged>]
# The command runs from $tmp/cwd (an unrelated dir) when it starts with `git -C @`,
# `@` being replaced by the case's repo; otherwise from inside the repo.
t(){
  n=$((n+1)); local dir="$tmp/$n"
  mkdir -p "$dir" && git -C "$dir" init -q -b work
  note "$dir" jobs.md 'jobs/**'
  note "$dir" domains.md 'src/billing/**' 'src/enrollment/**'
  note "$dir" architecture.md 'index.php' 'main.go'
  note "$dir" templates.md '**/*.tmpl'
  mkdir -p "$dir/.agents/memory" && echo '# no frontmatter' > "$dir/.agents/memory/loose.md"
  printf -- '# paths: outside the frontmatter\n---\npaths:\n  - "docs/**"\n---\n' > "$dir/.agents/memory/late.md"
  printf -- '---\nkind: pointer\ndoc: "notes/classes.md"\npaths:\n  - "lib/**"\n---\n# Classes\n' > "$dir/.agents/memory/classes.md"
  git -C "$dir" add . && git -C "$dir" -c user.email=t@t -c user.name=t commit -q -m init
  local f
  for f in $3; do
    [ "$f" = - ] && continue
    mkdir -p "$dir/$(dirname "$f")" && echo x >> "$dir/$f" && git -C "$dir" add "$f"
  done
  if [ -n "${4:-}" ]; then
    mkdir -p "$dir/$(dirname "$4")" && echo x > "$dir/$4" && git -C "$dir" add "$4" \
      && git -C "$dir" -c user.email=t@t -c user.name=t commit -q -m base
    echo y >> "$dir/$4"
  fi
  local cmd="${2//@/$dir}" cwd="$dir"
  [ "$cmd" != "$2" ] && { cwd="$tmp/cwd"; mkdir -p "$cwd"; }
  local out; out="$(cd "$cwd" && printf '{"tool_input":{"command":%s}}' "$(perl -MJSON::PP -e 'print JSON::PP->new->allow_nonref->encode($ARGV[0])' "$cmd")" | bash "$H" ${GUARD_ARGS:-} 2>&1)"
  local r=$?; local s=ok
  [ "$r" = "$1" ] || { s=FAIL; fails=$((fails+1)); }
  printf '%-4s got=%s want=%s  <- %s [%s %s]\n' "$s" "$r" "$1" "$2" "$3" "${4:-}"
}

echo "== blocked: code staged without its note =="
t 2 'git commit -m x' 'jobs/nightly.sh'
t 2 'git commit -m x' 'src/billing/invoice.py'
t 2 'git commit -m x' 'index.php'
t 2 'git commit -m x' 'page.tmpl'
t 2 'git commit -m x' 'a/b/page.tmpl'
t 2 'git commit -m x' 'jobs/nightly.sh .agents/memory/domains.md'
t 2 'git -C . commit -m x' 'src/enrollment/a.py'
t 2 'git -C @ commit -m x' 'src/enrollment/a.py'
t 2 'git commit -m x' 'lib/a.rb'
echo "== blocked: staged by the same command =="
t 2 'git commit -am x' '-' 'jobs/nightly.sh'
t 2 'git add jobs/nightly.sh && git commit -m x' '-' 'jobs/nightly.sh'

echo "== the project turned memory-drift-guard off: a flag on the hook's command line =="
GUARD_ARGS=--no-memory-drift t 0 'git commit -m x' 'jobs/nightly.sh'
GUARD_ARGS=--no-secret t 2 'git commit -m x' 'jobs/nightly.sh'

echo "== allowed =="
t 0 'git commit -m x' 'jobs/nightly.sh .agents/memory/jobs.md'
t 0 'git commit -m x' 'src/billing/a.py src/enrollment/b.py .agents/memory/domains.md'
t 0 'git commit -m x' 'lib/a.rb notes/classes.md'
t 0 'git commit -m x' 'lib/a.rb .agents/memory/classes.md'
t 0 'git commit -m x' 'src/other/api.py package.json'
t 0 'git commit -m x' 'docs/x.md'
t 0 'SKIP_MEMORY_CHECK=1 git commit -m x' 'jobs/nightly.sh'
t 0 'git commit -m x' '-' 'jobs/nightly.sh'
t 0 'git commit --amend --no-edit' '-'
t 0 'git status' 'jobs/nightly.sh'
t 0 'git log --grep commit' 'jobs/nightly.sh'
t 0 'git -C /nope/missing commit -m x' 'jobs/nightly.sh'

echo "== sub-projects: each note's globs from its own folder =="
# A root repo with a same-repo sub-project (frontend/) and an own-repo one (backend/),
# each with a note over its src/; the root's note covers the root's src/.
# s <expected exit> <command> <cwd, from the root> <files to stage, from the root>
sub="$tmp/sub"; mkdir -p "$sub" && git -C "$sub" init -q -b work
note "$sub" app.md 'src/**'
note "$sub/frontend" pages.md 'src/**'
mkdir -p "$sub/backend" && git -C "$sub/backend" init -q -b work && note "$sub/backend" api.md 'src/**'
echo backend/ > "$sub/.gitignore"   # a nested clone the root's repo ignores
for r in "$sub/backend" "$sub"; do git -C "$r" add . && git -C "$r" -c user.email=t@t -c user.name=t commit -q -m init; done
s(){
  n=$((n+1))
  local f
  for f in $4; do
    local repo="$sub"; case "$f" in backend/*) repo="$sub/backend"; f="${f#backend/}" ;; esac
    mkdir -p "$repo/$(dirname "$f")" && echo "x$n" >> "$repo/$f" && git -C "$repo" add "$f"
  done
  local out; out="$(cd "$sub/$3" && printf '{"tool_input":{"command":%s}}' "$(perl -MJSON::PP -e 'print JSON::PP->new->allow_nonref->encode($ARGV[0])' "$2")" | bash "$H" 2>&1)"
  local r=$?; local st=ok
  [ "$r" = "$1" ] || { st=FAIL; fails=$((fails+1)); }
  printf '%-4s got=%s want=%s  <- %s (in %s) [%s]\n' "$st" "$r" "$1" "$2" "${3:-.}" "$4"
  git -C "$sub" reset -q; git -C "$sub/backend" reset -q
}
s 2 'git commit -m x' '' 'frontend/src/a.vue'
s 2 'git commit -m x' 'frontend' 'frontend/src/a.vue'
s 0 'git commit -m x' '' 'frontend/src/a.vue frontend/.agents/memory/pages.md'
s 2 'git commit -m x' '' 'src/a.php'
s 0 'git commit -m x' '' 'frontend/README.md'
s 2 'cd backend && git commit -m x' '' 'backend/src/a.py'
s 2 'cd "backend"; git commit -m x' '' 'backend/src/a.py'
s 0 'cd backend && git commit -m x' '' 'backend/src/a.py backend/.agents/memory/api.md'
s 0 'git commit -m x' '' 'backend/src/a.py'

echo "failures=$fails"
[ "$fails" -eq 0 ]
