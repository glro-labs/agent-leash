---
name: update-memory
description: Reviews an existing .agents/memory/ catalog and fixes what is missing or has drifted - the anti-drift rule and index integrity (written without asking), then stale notes, merge conflicts, dead or overlapping paths globs, pointer notes, domain declarations, language (proposed). Use when the user asks to update, review, audit or refresh the memory of a project that already has it, after a long stretch of commits, to repair the index after a merge (--index), or as part of update.
argument-hint: "[--project <dir>] [--index]"
---

# update-memory

Review, not mapping: the catalog exists and this pass finds where it stopped matching
the code. Checking is reading — do not ask to read.

Two kinds of finding, and they are handled differently:

- **Mandatory** (checks 1–2) — the memory contract: index integrity and the anti-drift
  rule. They carry no policy, so fix them **without asking** and list them in the report.
- **Proposed** (checks 3–9) — everything else. **Ask before writing**, with the list of
  findings and the fix proposed for each; write on a yes.

**Sub-project** (`--project <dir>`, `/agent-leash:install` § Sub-project) → that folder is the
project: its `AGENTS.md`, its `.agents/`, and every path and glob relative to it. Run
`git ls-files` and the other commands in it (git pathspecs are relative to the folder a
command runs in).

No `.agents/memory/MEMORY.md` → there is nothing to review: `/agent-leash:memory` (bootstrap) is the way.

## Language

Settled as `/agent-leash:install` § Language says (the structure pass already did). Every fix you
write goes in it.

## Mandatory — written without asking

1. **Anti-drift rule.**
   - `.agents/rules/memory.md` missing → copy the template, translated into the declared
     language (keep the filename):

     ```bash
     [ -e .agents/rules/memory.md ] || { mkdir -p .agents/rules && cp "${CLAUDE_PLUGIN_ROOT}/templates/rules/memory.md" .agents/rules/memory.md; }
     ```

   - present → compare it with `${CLAUDE_PLUGIN_ROOT}/templates/rules/memory.md`. An instruction the
     template has and the project's copy lacks → add it, translated; the project's own
     additions stay. A last line pointing at the obsolete `agent-kit:memory` skill, or the
     older pointer "Procedure and note format: `/agent-leash:update <area>`" or the
     paragraph that named `<area>` (in any language) → replace it with the template's closing paragraph, translated.

2. **Index integrity.** First, merge-conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`)
   in `MEMORY.md` → resolve them: keep the union of both sides' lines, in their sections,
   one line per note (two hooks for the same note → the one that matches the note, or
   one rewritten from it), and drop the markers. Then: every link in `MEMORY.md` resolves; every note in `memory/` is
   linked from the index (an orphan is never found); every note links back to the
   index. Broken link → fix the link, or drop the line when the note is gone; orphan →
   add a line in the right section with a hook (written from the note, the way
   `/agent-leash:memory` § Phase 6 says); a note with no way back → add the back-to-index line.

## Proposed — written on a yes

Run all of them, then report once. Each finding: note, what is wrong, proposed fix.

3. **Globs.** For each note with a `paths:` frontmatter, every glob matches something:

   ```bash
   git ls-files ':(glob)<glob>' | head -1   # empty = dead glob
   ```

   A dead glob means the area moved or was deleted — find where it went, or the note
   itself is obsolete. Globs of two notes matching the same files → one file demands two
   notes; narrow one. `{a,b}` in a note's glob → split it, `memory-drift-guard` does not
   expand braces. At the root, a glob that reaches into a sub-project's folder
   (`scripts/subprojects.sh`) → that folder's own notes cover it: narrow the root's.

4. **Staleness — the one that matters.** For each note with `paths:`, the commits that
   touched its area since the note was last changed:

   ```bash
   since="$(git log -1 --format=%H -- .agents/memory/<note>.md)"
   git log --oneline "$since"..HEAD -- ':(glob)<glob1>' ':(glob)<glob2>'
   ```

   `SKIP_MEMORY_CHECK=1` commits land here too — that is the point: someone judged the
   note still held, and this pass checks. For each note with commits, read the note
   against those diffs (`git diff "$since"..HEAD -- <globs>`). Many notes → fan out to
   `agent-leash:explorer`, one per note, asking for "what in this note the diffs made
   wrong or incomplete"; you write the fixes.

   A pointer note (`kind: pointer`) is checked through its `doc:`: `since` is the last
   commit to the doc or the note (`git log -1 --format=%H -- <doc> .agents/memory/<note>.md`),
   and the fix goes into the doc. A `doc:` that no longer exists → the pointer is dead:
   find where the doc went, or propose turning the pointer into a regular note.

5. **Conflicted notes.** Merge-conflict markers in a note → its two sides, read against
   the code its `paths:` cover; propose the merged note. Unlike the index, the sides can
   disagree on what the code does.

6. **Area notes without `paths:`.** A note that describes a directory or module
   (`module-*`, a jobs/integration note) but has no frontmatter is invisible to the
   guard and gets no read rule. Propose the globs.

7. **Domain declaration.** The domain rules follow `kind: domain` in a note's
   frontmatter, not its filename. A `domain-*.md` without it → add `kind: domain`
   (the name already said so; no need to ask). Notes that `domains.md` links to as
   domains with no `kind:` → list them and ask which are domains; write `kind: domain`
   or `kind: module` on the answer, so the question is not asked again. Nothing to ask
   when `domains.md` maps a single domain.

8. **Language.** A note, heading or index line not in the declared language → list it
   and offer to translate (it is a rewrite). Glossary *terms* stay as the code names them.

9. **Gaps.** Foundation notes the index promises but that do not exist, or an area with
   heavy recent activity (`git log --since=6.months --name-only`) and no note → do not
   write them here: list them and offer `/agent-leash:memory <area>`.

## Fixing

Fix in place: a note describes the current state, it does not accumulate a changelog. Do
not invent to fill a gap — what you could not confirm goes in as explicit uncertainty.
Stage the notes you changed by name, together with nothing else (plus
`rules/memory.md` when check 1 wrote it).

## Report

The mandatory fixes made without asking, then the findings per proposed check (cut the
empty ones), what you fixed, what you left and why, and the `/agent-leash:memory <area>`
follow-ups — a fixed note that now holds a new "never"/"always" is a rule candidate.

## Index only — `--index`

`/agent-leash:update-memory --index` runs the index integrity check (mandatory check 2)
alone, without asking, e.g. after a merge left conflict markers in `MEMORY.md`. After
`--project <dir>`, the sub-project's. No `MEMORY.md` → stop: there is no index to repair.
The notes themselves are not edited, save a missing back-to-index line; a note with
conflict markers is listed, for the full pass (check 5) to merge. Stage `MEMORY.md` and
the notes that got a back link by name, report what changed, and run nothing else.

## Read rules follow the catalog

A fixed glob, a new `paths:` or a `kind: domain` declared here changes the rule a note
owes. After the memory checks, run `/agent-leash:update-rules` check 1 (read rules)
alone, without asking, so the rules do not lag the catalog; its proposed checks do not
run — list `/agent-leash:update-rules` for them when globs changed.
