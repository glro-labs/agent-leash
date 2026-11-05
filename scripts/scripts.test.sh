#!/usr/bin/env bash
# Self-check for scripts/:  bash scripts/scripts.test.sh
#
# Runs scaffold, guards, coupling and the sub-project scripts in throwaway repos, twice
# where idempotency matters. Exits non-zero if any case regresses.
set -uo pipefail

S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for f in "$S"/*.sh; do bash -n "$f" || exit 1; [ -x "$f" ] || { echo "missing exec bit: $f"; exit 1; }; done
for f in "$S"/*.pl; do perl -c "$f" 2>/dev/null || { echo "does not compile: $f"; exit 1; }; done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/demo"; mkdir -p "$repo" && cd "$repo" && git init -q -b work || exit 1

fails=0
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails+1)); fi; }

# An existing settings.json with its own key order, one deny entry of its own, a number
# written as 2.50, and a hook entry whose "matcher" comes before its "hooks".
mkdir -p .agents && printf '{\n  "zeta": 1,\n  "permissions": {\n    "deny": ["Bash(rm:*)"]\n  },\n  "alpha": 2.50,\n  "hooks": {\n    "PreToolUse": [{ "matcher": "Bash", "hooks": [] }]\n  }\n}\n' > .agents/settings.json
echo "# Demo" > CLAUDE.md

out="$(bash "$S/scaffold.sh")"; r=$?
ok "scaffold exits 0"                 '[ $r = 0 ]'
ok ".claude is a link"                '[ -L .claude ]'
ok "CLAUDE.md moved to AGENTS.md"     '[ -L CLAUDE.md ] && grep -q "# Demo" AGENTS.md'
ok "deny entry kept, template added"  'grep -q "Bash(rm:\*)" .agents/settings.json && grep -q "git add" .agents/settings.json'
ok "read-only git allowed"            'grep -qF "Bash(git status:*)" .agents/settings.json'
ok "key order kept"                   '[ "$(grep -o "\"[a-z]*\":" .agents/settings.json | head -3 | tr -d "\n")" = "\"zeta\":\"permissions\":\"deny\":" ]'
ok "nested key order kept"            'grep -A1 "\"matcher\"" .agents/settings.json | grep -qF "\"hooks\": []"'
ok "number form kept"                 'grep -qF "\"alpha\": 2.50," .agents/settings.json'
ok "anti-drift rule created"          '[ -f .agents/rules/memory.md ]'
before="$(cat .agents/settings.json .agents/.gitignore)"
out="$(bash "$S/scaffold.sh")"; r=$?
ok "scaffold rerun creates nothing"   '[ $r = 0 ] && ! printf "%s" "$out" | grep -q "^created\|^added" && [ "$before" = "$(cat .agents/settings.json .agents/.gitignore)" ]'
rm .claude; mkdir .claude
bash "$S/scaffold.sh" >/dev/null 2>&1; r=$?
ok "a real .claude/ stops (exit 3)"   '[ $r = 3 ] && [ -d .claude ] && [ ! -L .claude ]'
rmdir .claude; bash "$S/scaffold.sh" >/dev/null

# guards: the repo's own copy, registered with the team's flags; a rerun keeps the team's
# registration and replaces only a stale copy.
g="$tmp/guards"; mkdir -p "$g/.agents" && cd "$g" && git init -q || exit 1
printf '{\n  "hooks": {\n    "PreToolUse": [{ "matcher": "Edit", "hooks": [{ "type": "command", "command": "lint.sh" }] }]\n  }\n}\n' > .agents/settings.json
ok "check: nothing yet"               '[ "$(bash "$S/guards.sh" --check | tr "\n" " ")" = "missing .agents/hooks/guard.sh unregistered " ]'
out="$(bash "$S/guards.sh" --no-master)"; r=$?
ok "guards exits 0"                   '[ $r = 0 ]'
ok "copy made, executable"            'cmp -s "$S/../hooks/guard.sh" .agents/hooks/guard.sh && [ -x .agents/hooks/guard.sh ]'
ok "registered with the flag"         'grep -qF "bash \\\"\$CLAUDE_PROJECT_DIR/.agents/hooks/guard.sh\\\" --no-master" .agents/settings.json'
ok "a hook of the team kept"          'grep -qF lint.sh .agents/settings.json'
before="$(cat .agents/settings.json)"; out="$(bash "$S/guards.sh" --no-secret)"
ok "rerun keeps the registration"     '[ "$before" = "$(cat .agents/settings.json)" ] && printf "%s" "$out" | grep -q "kept as the team set it"'
echo '# edited' >> .agents/hooks/guard.sh
out="$(bash "$S/guards.sh" --check)"
ok "check: a stale copy"              'printf "%s\n" "$out" | grep -qx "differs .agents/hooks/guard.sh"'
out="$(bash "$S/guards.sh")"
ok "rerun replaces a stale copy"      'printf "%s" "$out" | grep -q "^updated" && cmp -s "$S/../hooks/guard.sh" .agents/hooks/guard.sh'
touch .agents/hooks/master-guard.sh
out="$(bash "$S/guards.sh" --check)"
ok "check: an older guard copy"       'printf "%s\n" "$out" | grep -qx "old .agents/hooks/master-guard.sh"'
bash "$S/guards.sh" --no-such-check >/dev/null 2>&1; r=$?
ok "unknown flag exits 1"             '[ $r = 1 ]'
rm .agents/settings.json; rm -f .agents/hooks/guard.sh; echo "{ broken" > .agents/settings.json
bash "$S/guards.sh" >/dev/null 2>&1; r=$?
ok "invalid settings.json exits 2"    '[ $r = 2 ] && [ "$(cat .agents/settings.json)" = "{ broken" ]'

# coupling: 3 commits touch src/, 2 of them also the doc.
c="$tmp/coupling"; mkdir -p "$c/src" "$c/docs" && cd "$c" && git init -q && git config user.email t@t && git config user.name t && git config core.autocrlf false
for i in 1 2 3; do echo $i > src/a.c; [ $i = 3 ] || echo $i > docs/notes.md; git add src docs && git commit -qm $i; done
echo x > docs/notes.md && git commit -qam doc-only
ok "coupling counts the area"         'bash "$S/coupling.sh" docs/notes.md "src/**" | grep -q "^2 of 3 .* blocked 1$"'

# Sub-projects: a root with a same-repo sub-project (frontend/, and apps/web/ one level
# deeper), an own-repo one (backend/, a nested clone the root ignores) and a folder with
# only a CLAUDE.md of its own (docs-site/).
m="$tmp/mono"; mkdir -p "$m/frontend" "$m/apps/web" "$m/backend" "$m/docs-site" && cd "$m" && git init -q
git -C backend init -q && echo backend/ > .gitignore && echo "# Docs" > docs-site/CLAUDE.md
bash "$S/scaffold.sh" >/dev/null && echo "# Commit policy" > .agents/rules/commit.md
ok "target: same-repo"                '[ "$(bash "$S/target.sh" frontend | sed -n "s/^layout=//p;s/^tag=//p" | tr "\n" " ")" = "same-repo frontend " ]'
ok "target: own-repo"                 '[ "$(bash "$S/target.sh" backend | sed -n "s/^layout=//p;s/^tag=//p" | tr "\n" " ")" = "own-repo backend " ]'
ok "target: the root is not one"      '! bash "$S/target.sh" . >/dev/null 2>&1'
ok "target: a missing folder"         '! bash "$S/target.sh" nope >/dev/null 2>&1'
before="$(cat AGENTS.md .agents/settings.json; ls -A .agents .agents/rules)"
out="$(bash "$S/scaffold.sh" --project frontend)"; r=$?
ok "scaffold --project exits 0"       '[ $r = 0 ]'
ok "sub-project skeleton"             '[ -L frontend/.claude ] && [ -L frontend/CLAUDE.md ] && [ -f frontend/.agents/rules/memory.md ] && grep -q "git add" frontend/.agents/settings.json'
ok "commit.md links the root's"       '[ -L frontend/.agents/rules/commit.md ] && grep -q "Commit policy" frontend/.agents/rules/commit.md'
ok "root left alone"                  '[ "$before" = "$(cat AGENTS.md .agents/settings.json; ls -A .agents .agents/rules)" ]'
bash "$S/scaffold.sh" --project apps/web >/dev/null
ok "deeper commit.md link resolves"   'grep -q "Commit policy" apps/web/.agents/rules/commit.md'
out="$(bash "$S/scaffold.sh" --project frontend)"
ok "scaffold --project rerun"         '! printf "%s" "$out" | grep -q "^created\|^added"'
bash "$S/scaffold.sh" --project backend >/dev/null
ok "own-repo: its own policy"         '[ -f backend/.agents/rules/memory.md ] && [ ! -e backend/.agents/rules/commit.md ]'
bash "$S/guards.sh" --project frontend --no-master >/dev/null
ok "guards --project"                 '[ -x frontend/.agents/hooks/guard.sh ] && grep -qF "guard.sh\\\" --no-master" frontend/.agents/settings.json && [ ! -e .agents/hooks/guard.sh ]'
out="$(bash "$S/subprojects.sh")"
ok "subprojects lists them"           'printf "%s\n" "$out" | grep -qx "frontend	same-repo	harness" && printf "%s\n" "$out" | grep -qx "backend	own-repo	harness" && printf "%s\n" "$out" | grep -qx "docs-site	same-repo	candidate"'
ok "subprojects skips the root"       '! printf "%s\n" "$out" | grep -q "^\.\|^	"'

echo "failures=$fails"
[ "$fails" -eq 0 ]
