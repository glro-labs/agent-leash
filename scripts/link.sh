#!/usr/bin/env bash
# link.sh <target> <name>: make <name> a symlink to <target> (relative, from cwd).
# Exit 0 created or already a link, 3 <name> is a real file or directory (merge it,
# asking first: skills/install step 1), 1 no symlink could be made.
target="$1" name="$2"
if [ -L "$name" ] && [ ! -e "$name" ]; then rm "$name"; fi   # dangling: still holds the name
[ -L "$name" ] && { echo "exists  $name"; exit 0; }
[ -e "$name" ] && { echo "not a link: $name is a real file or directory" >&2; exit 3; }
ln -s "$target" "$name" 2>/dev/null
[ -L "$name" ] && { echo "created $name"; exit 0; }
# Git Bash's ln -s copies by default. Native links need Developer Mode or admin, and
# often work without either: retry before giving up. The copy is ours, made just now.
rm -rf "$name"
MSYS=winsymlinks:nativestrict ln -s "$target" "$name" 2>/dev/null
if [ -L "$name" ]; then
  echo "created $name (native link via MSYS=winsymlinks:nativestrict; follow-up: GUIDE.md § Windows, so later links and checkouts stay links)"
  exit 0
fi
rm -rf "$name"
echo "cannot create the symlink $name -> $target: see GUIDE.md § Windows" >&2
exit 1
