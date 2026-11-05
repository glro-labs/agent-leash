---
name: install
description: Creates the .agents/ structure (memory, rules, settings, .claude symlink) and the repo's own guards in a project that does not have them yet, then hands off to the memory and rules skills. Use when the user asks to initialize/configure the agents directory, the memory base or the .agents of a new repository. With --project <dir>, sets the same harness up in a sub-project folder (a monorepo's frontend/ or backend/).
argument-hint: "[--project <dir>]"
---

# install

Sets up a project's `.agents/` skeleton. **Idempotent**: run again on an already
initialized project and it only creates what is missing, touching nothing that exists.
The mechanical steps are scripts in `${CLAUDE_PLUGIN_ROOT}/scripts/`: run them as the steps
say, never retype their contents into the shell.

## Language of what you write

This skill is written in English; what it *generates* in `.agents/` and `AGENTS.md` is
written in the project's language, and so is everything the `memory` and `rules` skills
write later — notes, index, rules, headings, the "back to the index" line.

That language is a project fact, so it is **declared, not re-guessed** on every run:

1. `AGENTS.md` already declares it (the line under *Memory Catalog*, see step 4) → use it.
2. Otherwise, propose one from the evidence — README, code comments, `git log` subjects —
   and **confirm with the user** before writing anything. Code identifiers in English do
   not make the project English: the team's prose (docs, comments, commit messages)
   decides. Evidence split or absent → ask, do not default.
3. Record the answer in step 4. Any later session — with or without these skills — then
   writes notes and rules in it, because `AGENTS.md` loads every time.

Filenames, keys and paths stay as specified here regardless (English kebab-case): the
skills find `rules/memory.md`, `rules/commit.md` and `memory/MEMORY.md` by name.

## Convention

Everything lives in `.agents/` (tool-neutral) and `.claude` is a symlink to it so
Claude Code sees it. That way other agent CLIs reuse the same directory. Same idea at
the root: the instructions file is `AGENTS.md` and `CLAUDE.md` is a symlink to it.

```
.agents/
  memory/            → note graph, one note per domain, MEMORY.md index (memory skill)
  rules/             → path-scoped instructions the harness injects (rules skill)
  settings.json      → permissions, the guard hook (+ attribution, from the rules skill)
  agents/            → project subagents (optional)
  skills/            → project skills (optional)
  hooks/guard.sh     → the repo's own guards: master, secrets, memory drift
  .gitignore
.claude -> .agents
AGENTS.md
CLAUDE.md -> AGENTS.md
```

## 0. Preflight and questions

```bash
cd "$(git rev-parse --show-toplevel)" || exit 1   # not a git repo → stop and say so
```

`--project <dir>` in `$ARGUMENTS` → a sub-project: § Sub-project below says what changes
in each step. No flag → the root.

Survey without writing (step 1), then **another tool's harness**: git tracks `.agents/`,
`AGENTS.md`, `CLAUDE.md` or `.claude/` and `.agents/rules/memory.md` does not name
`/agent-leash:memory` → say what was found: setting the harness up changes files the
whole team shares, and in someone else's repo that isn't one person's call. Go on only on
an explicit yes.

Then ask **one round of questions, before writing anything**, in the user's language:

- **Repo language** — proposed from the evidence (above). Skip it when `AGENTS.md`
  already declares one.
- **What will be created** — the repo structure, each item marked "create" or "exists,
  kept".
- **Guards** — one multiple-choice question, every box checked by default: which checks
  the repo carries, for everyone who works on it with Claude Code, plugin or not.
  `master-guard` blocks commits, merges, `reset --hard` and pushes on `main`/`master` (a
  team that commits straight to `main` unchecks it); `secret-guard` blocks a commit that
  adds a key, a token or a `.env`; `memory-drift-guard` blocks a commit that changes code
  without its memory note (`SKIP_MEMORY_CHECK=1` covers the one case where the note still
  holds). Say they bind the whole team once committed. Skip the question when
  `scripts/guards.sh --check` prints `registered`: the team chose already.
- **What the move breaks** — when `.claude/` or `CLAUDE.md` is about to move, the step 1
  `git grep` hits, each with its proposed fix.

Everything already answered in the user's request counts as answered. The `memory` and
`rules` skills keep their own asks (the notes to write, the commit policy); do not batch
those into this round.

## Steps

1. **Survey what already exists** before writing anything. Every step below is
   conditional: what is already there stays as it is (do not overwrite, do not "fix"
   content), what is missing you create. At the end, report created vs. already
   existed.

   ```bash
   ls -ld .agents .claude AGENTS.md CLAUDE.md .agents/settings.json .agents/rules \
          .agents/rules/memory.md .agents/memory/MEMORY.md 2>&1
   git grep -nIF -e .claude/ -e CLAUDE.md -- . ':!.agents' ':!.claude' 2>/dev/null
   ```

   **List the `git grep` hits before moving anything.** Moving `.claude/` into `.agents/`
   or renaming `CLAUDE.md` breaks what names them, silently: a hook that treats
   `.claude/` as a docs prefix now counts `.agents/` edits as code; a `.gitignore` line
   such as `.claude/worktrees/` stops matching, because git sees `.claude` as a symlink
   file; an instruction ("don't move `.claude/`") contradicts the move. For each hit, say
   what the move does to it and propose the fix (usually `.claude/` → `.agents/`). No
   hits → say so in one line.

   Exceptions where you *do* adjust what exists, because it is structure and not content:

   - `CLAUDE.md` is a regular file and `AGENTS.md` does not exist → the script renames
     it (`git mv CLAUDE.md AGENTS.md`) and creates the symlink. Content is preserved.
   - `.agents/settings.json` exists but is missing a `deny` or `allow` entry of the
     template → the script adds what is missing, preserving the rest and its key order.
   - `.claude` or `CLAUDE.md` exists but is **not a symlink** (`[ ! -L .claude ]`):
     - a small file whose content is just `.agents` / `AGENTS.md` → cloned with
       `core.symlinks=false` (almost always Windows), and Claude Code sees neither the
       settings nor the instructions. Repair, no content is at stake:

       ```bash
       git config core.symlinks true && rm .claude CLAUDE.md && git checkout -- .claude CLAUDE.md
       ```

       Needs Developer Mode on (GUIDE.md § Windows); still not a link afterwards → stop
       and say so.
     - a real `.claude/` directory, or a `CLAUDE.md` with its own content next to an
       `AGENTS.md` → a copy made by hand, or a harness from before agent-leash. Diff it
       against `.agents/` / `AGENTS.md`, show what only the copy has, and **ask** before
       merging it in and replacing the copy with the link (the script exits 3 until then).

2. **Create whatever structure is missing** — one script, create-only, one line per item:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/scaffold.sh"
   ```

   It makes `.agents/{memory,rules}`, `.agents/.gitignore` (with `settings.local.json`),
   the `.claude -> .agents` link, `rules/memory.md` from the template, `settings.json` (or
   the `deny` and `allow` entries it lacks), and `AGENTS.md` with `CLAUDE.md -> AGENTS.md`.
   Exit 0 → done; 3 → a real `.claude/` or `CLAUDE.md` is in the way (step 1); 2 →
   `settings.json` is not valid JSON: report it and stop, do not hand-edit around it; 1 →
   no symlink could be made: on Windows, point at GUIDE.md § Windows and stop.

   A link line saying `native link via MSYS=winsymlinks:nativestrict` worked, but this
   machine lacks the permanent setup: report GUIDE.md § Windows (`core.symlinks`, the
   `~/.bashrc` line) as a follow-up, not a blocker.

   `rules/memory.md` is the anti-drift rule — the always-on instruction to fix a note in
   the same task that made it wrong, which `memory-drift-guard` then enforces at commit.
   Freshly created, translate it into the project's language (keep the filename).

   Then the guards, with a flag for each one the user unchecked (`--no-master`,
   `--no-secret`, `--no-memory-drift`):

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/guards.sh" [--no-master] [--no-secret] [--no-memory-drift]
   ```

   It copies the plugin's `hooks/guard.sh` to `.agents/hooks/guard.sh` and registers it in
   `.agents/settings.json`. The copy is the plugin's file, the one exception to
   create-only: an older copy is replaced (`updated`). A registration already there is
   never rewritten. All three unchecked → skip the script, and say the repo then carries
   no guards: the plugin runs none.

3. **`.agents/settings.json`** denies blind `git add` and allows the read-only git
   commands (`git status`, `git diff`, `git log`, `git show`) that every pass and agent
   runs, so they don't prompt. Agent co-author attribution is the user's choice: the
   `rules` skill asks it with the commit policy and writes `attribution` then; do not set
   it here. Never write `extraKnownMarketplaces` or `enabledPlugins` entries for this
   plugin: the project's config carries the project's policy, not the tool that set it up.

   The `deny` list stops a stray `.env` or real config from being staged at all;
   `secret-guard` is the net behind it.

4. **`AGENTS.md` at the root, with `CLAUDE.md` as a symlink to it.** The real file is
   `AGENTS.md` (a convention other CLIs also read); Claude Code sees it through the
   symlink. The script made both; write the content.

   If `AGENTS.md` does not mention the memory yet, append this (leaving the rest
   alone), in the project's language:

   ```markdown
   ## Memory Catalog

   Persistent instructions live in `./.agents/memory/`. Index:
   [.agents/memory/MEMORY.md](.agents/memory/MEMORY.md). Before any action in a
   domain, read the matching file — the rules live there, not here.

   Notes and rules under `.agents/` are written in <language> (`<tag>`).
   ```

   If the section exists but has no language line, add just that line to it. Example
   for a Portuguese project: `Notas e regras em .agents/ são escritas em português
   (pt-BR).`

5. **Hand off to the mapping skills.** The structure is empty until they run; both read a
   lot and ask before writing, so offer them instead of starting unasked:

   - `/agent-leash:memory` — no `MEMORY.md` yet: maps the repository into `AGENTS.md`
     and the catalog (phases 0–4, then stops).
   - `/agent-leash:rules` — no `rules/commit.md` yet: asks the commit policy and writes
     it, then the read rules and the path-scoped rules for the candidates the memory pass
     found.

   If the user already asked for the whole setup in one go, run them in that order.

6. **Report.**
   - **Repo:** created vs. already existed, per file; both links real
     (`[ -L .claude ] && [ -L CLAUDE.md ]`); the step 1 hits and what was done about each.
   - **Guards:** which checks the registration runs, and that `.agents/hooks/guard.sh`
     and `.agents/settings.json` are versioned: they run for every teammate from the next
     session.
   - **Drift guard coverage:** the notes that declare `paths:`, with their globs. None →
     say so plainly: `memory-drift-guard` and the read rules cover no code until a note
     declares its paths (`/agent-leash:memory <area>`).
   - **Open questions** the memory pass could not answer, and any code defect it came
     across.
   - **Restart the session** so the new rules and settings load. When `.claude` is a
     symlink, Claude Code treats its settings as supplied by the repo: its allow rules
     wait until the folder is trusted (deny rules always apply).
   - Windows teammates must clone with symlinks on (`git clone -c core.symlinks=true`,
     Developer Mode enabled) — without it their `.claude` is a text file and the harness
     is silently off.
   - Repo changes are staged by name (`git add <file>…`, never `-A`); committing follows
     `rules/commit.md`. No commit unless the user asks.

## Sub-project — `--project <dir>`

A folder below the root that gets a harness of its own (a monorepo's `frontend/` and
`backend/`). Claude Code reads `settings.json` only from the folder a session starts in,
never from a parent, so a session started in `frontend/` gets neither the root's deny list
nor its guards unless `frontend/` carries them. Resolve it after the preflight's `cd`:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/target.sh" <dir>   # top, dir, layout (same-repo | own-repo), tag; a message → stop and say it
```

Layout comes from git, never a question: **same-repo** is a folder of the root's repo,
**own-repo** a repo of its own inside the root's folder (a nested clone or a submodule).
`cd` to the printed `top` and run every script from there with `--project <tag>`; the
survey commands (`ls`, `git grep`) run in `dir`. Say the layout in the questions round.

- **Questions:** the survey and the questions are the sub-project's. Repo language →
  propose the root's. Guards → the root's registration (`scripts/guards.sh --check` at the
  root) is the default answer.
- **Step 2:** `scripts/scaffold.sh --project <tag>`, then `scripts/guards.sh --project
  <tag>` with the flags. Same-repo: `rules/commit.md` becomes a link to the root's (one
  repo, one policy). Own-repo: its policy is asked by the `rules` skill.
- **Step 4:** language declared in the sub-project's own `AGENTS.md`. The root
  `AGENTS.md` (when it has one) gets a `Sub-projects` section, in the project's language,
  one line per sub-project: its folder, that it carries its own `AGENTS.md` and
  `.agents/`, and that a session started there loads only its settings. Add this one's
  line when missing.
- **Step 5:** `/agent-leash:memory --project <dir>` maps the sub-project only, `paths:`
  relative to its folder; `/agent-leash:rules --project <dir>` likewise.
- **Report:** also the layout, and that a session started in the sub-project loads its
  settings and guards, not the root's.

`scripts/subprojects.sh` lists the sub-projects below the root (with `.agents/`) and the
candidates (a `CLAUDE.md`, `AGENTS.md` or `.claude/` of their own, no `.agents/` yet).

## What this skill does NOT do

Anything specific to a single project (a homegrown database client, a homegrown
linter) stays in that repository's own `.agents/hooks/` and `.agents/skills/`. Only
what has already served more than one project becomes a marketplace plugin.
