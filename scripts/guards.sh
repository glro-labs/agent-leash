#!/usr/bin/env bash
# guards.sh [--project <dir>] [--no-master] [--no-secret] [--no-memory-drift]   skills/install step 2
# guards.sh [--project <dir>] --check                                           skills/update-hooks
# The repo's own, versioned copy of the guards: hooks/guard.sh copied to
# .agents/hooks/guard.sh and registered in .agents/settings.json, so they run for
# everyone on the repo whether or not they have the plugin. The flags are the checks
# the team turned off; they go on the hook's command line, where guard.sh reads them.
#   - The copy is the plugin's file: an older one is replaced ("updated"), and the diff
#     is the user's to review and commit like any other.
#   - A registration already in settings.json is the team's choice (its flags, or a
#     command they changed): it is never rewritten, and the flags are then ignored.
# --check writes nothing: one line for the copy (current, differs, missing), one for the
# registration (registered <command>, unregistered), and one per guard copy an older
# version left (old <path>).
# --project: a sub-project's own copy and registration Claude Code reads
# settings.json only from the folder a session starts in, so a session started there
# runs that copy, and $CLAUDE_PROJECT_DIR is that folder.
# Exit 0 done, 2 settings.json is not valid JSON (left untouched), 1 not a git repo or no
# such sub-project folder.
here="$(cd "$(dirname "$0")" && pwd)"; plugin="$(dirname "$here")"
sub=; [ "${1:-}" = --project ] && { sub="${2:?usage: guards.sh [--project <dir>] ...}"; shift 2; }
. "$here/target.sh"; target "$sub" || exit 1
cd "$dir" || exit 1
src="$plugin/hooks/guard.sh"; copy=.agents/hooks/guard.sh; settings=.agents/settings.json

# The command lines in settings.json that run the repo's copy, one per line.
registered() {
  [ -f "$settings" ] && perl -MJSON::PP -0777 -ne '
    my $j = eval { decode_json($_) } or exit 0;
    for my $e (map { ref eq "HASH" && ref $_->{hooks} eq "ARRAY" ? @{ $_->{hooks} } : () }
               @{ ref $j->{hooks} eq "HASH" && ref $j->{hooks}{PreToolUse} eq "ARRAY" ? $j->{hooks}{PreToolUse} : [] }) {
      my $c = ref $e eq "HASH" ? $e->{command} // "" : "";
      print "$c\n" if $c =~ m{\.agents/hooks/guard\.sh};
    }' "$settings"
}

if [ "${1:-}" = --check ]; then
  if [ ! -f "$copy" ]; then echo "missing $copy"
  elif cmp -s "$src" "$copy"; then echo "current $copy"
  else echo "differs $copy"; fi
  reg="$(registered)"
  if [ -n "$reg" ]; then printf 'registered %s\n' "$reg"; else echo "unregistered"; fi
  for f in .agents/hooks/master-guard.sh .agents/hooks/secret-guard.sh .agents/hooks/memory-drift-guard.sh; do
    [ -e "$f" ] && echo "old $f"
  done
  exit 0
fi

flags=
for a in "$@"; do
  case "$a" in
    --no-master|--no-secret|--no-memory-drift) flags="$flags $a" ;;
    *) echo "unknown flag: $a" >&2; exit 1 ;;
  esac
done

mkdir -p .agents/hooks
if [ ! -f "$copy" ]; then cp "$src" "$copy" && echo "created $copy"
elif cmp -s "$src" "$copy"; then echo "exists  $copy"
else cp "$src" "$copy" && echo "updated $copy"; fi
chmod +x "$copy"

if [ -n "$(registered)" ]; then
  echo "exists  $settings: guard hook (kept as the team set it)"
  exit 0
fi
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
# $CLAUDE_PROJECT_DIR is expanded by the shell Claude Code runs the hook in, not here.
perl -MJSON::PP -e 'print JSON::PP->new->pretty->encode({ hooks => { PreToolUse => [
  { matcher => "Bash", hooks => [ { type => "command", command => $ARGV[0] } ] } ] } })' \
  "bash \"\$CLAUDE_PROJECT_DIR/$copy\"$flags" > "$tmp"
perl "$here/merge-json.pl" "$settings" "$tmp"
