# Memory — keep the notes in sync with the code

No `paths:` on purpose: it applies to any edit, so it loads in every session.

- Before changing code in an area, read the note that covers it — index:
  `.agents/memory/MEMORY.md`. Entering a domain means reading its note
  (`kind: domain`) first, even just to investigate.
- When code and note diverge — because you changed the code, or found the note wrong —
  fix the note **in the same task**, in place. It describes the current state; no
  changelog, no "update later".
- Stage the note together with the code. `memory-drift-guard` blocks a commit that
  touches an area whose note (`paths:` frontmatter) is not in it.
- `SKIP_MEMORY_CHECK=1` only after reading the note against the diff and confirming it
  still holds — never to skip the reading.
- A note that describes an area of code declares it in `paths:`; without it the guard
  cannot see the note.

Code with no note, or a note too thin to work from → `/agent-leash:memory <area>`,
where `<area>` is a directory (`src/payments`), a named module (`billing`) or a
feature that spans folders (`authentication`). It writes the note with its `paths:`,
asks for the note's read rule (`/agent-leash:rules <area>`) and adds its index line, and
asks before writing. In a sub-project: `/agent-leash:memory --project <dir> <area>`.
