#!/usr/bin/env bash
# target.sh [<dir>]: the folder a setup step works on. Run it to print the values;
# the other scripts source it for target() once they have read --project.
#   no <dir>  the cwd's git root: dir=top, layout=root, tag empty.
#   <dir>     a sub-project with a harness of its own, below the root: layout=same-repo
#             when <dir> sits inside the root's repo, own-repo when it is a repo of its
#             own (a nested clone or a submodule) inside it. top is the root's git root,
#             tag <dir>'s path from there (frontend, apps/web).
# target() returns 1 with a message: not a git repo, no such folder, or <dir> is a root
# itself (no repo around it, or the root's own folder).
target() {
  if [ -z "${1:-}" ]; then
    top="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo" >&2; return 1; }
    dir="$top" layout=root tag=; return 0
  fi
  dir="$(cd "$1" 2>/dev/null && pwd)" || { echo "no such folder: $1" >&2; return 1; }
  local pre
  pre="$(git -C "$dir" rev-parse --show-prefix 2>/dev/null)" || { echo "not in a git repo: $1" >&2; return 1; }
  if [ -n "$pre" ]; then
    layout=same-repo; top="$(git -C "$dir" rev-parse --show-toplevel)"; tag="${pre%/}"
  else
    # Its own git root: a sub-project only when a repo holds the folder around it.
    pre="$(git -C "$dir/.." rev-parse --show-prefix 2>/dev/null)" \
      || { echo "$1 is a root, not a sub-project (no repo around it): run without --project" >&2; return 1; }
    layout=own-repo; top="$(git -C "$dir/.." rev-parse --show-toplevel)"; tag="$pre${dir##*/}"
  fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  target "${1:-}" || exit 1
  printf 'top=%s\ndir=%s\nlayout=%s\ntag=%s\n' "$top" "$dir" "$layout" "$tag"
fi
