---
name: respawn
description: Use when the user wants to save a checkpoint of the current Claude Code session for later, restore a prior checkpoint, resume where they left off after /clear, preserve context before clearing, hand off state to a fresh session, or says things like "respawn", "save my place", "checkpoint this", "restore my context", "pick up where we left off", or "continue after clearing". Auto-detects save vs load with a safety prompt when ambiguous. Supports explicit `respawn save` and `respawn load` overrides, plus free-form steering text to shape the saved checkpoint.
---

# Respawn

Persist current Claude Code session state to a private file, or restore from a prior checkpoint. One command (`/respawn`) covers both directions — auto-detect when unambiguous, ask when not.

`/respawn` is a *handoff* to a fresh session, not a recap of the current one. If the user is mid-flow and would benefit from a summary without clearing context, point them at `/compact` instead — see the no-next-step check below.

Checkpoint files live in `~/.claude/respawn/` (mode `0700`, private to the user). Filename pattern: `respawn-<YYYYMMDD-HHMMSS>.md`. After a successful load, the file is renamed to `respawn-<ts>.loaded.md` so the same checkpoint can't be auto-loaded twice.

## Step 1 — Determine mode

Parse the argument string the user passed:

- Empty → bare `respawn` — apply the auto-detect decision tree below.
- First token is `save` → SAVE. Remainder (if any) is `<steering text>` — free-form guidance that shapes SAVE generation (e.g. "focus on auth migration; skip dead-code notes"). Not persisted as its own section; used only during this SAVE.
- First token is `load` → LOAD.
  - If a remainder is present, it is the explicit file path. Resolve it; if the file does not exist, stop with: `No file at <path>. Pass an existing checkpoint path or just /respawn load to use the most recent for this repo.` Do not silently fall back.
  - If no remainder, locate the most recent for this repo (see Step 3).
- First token is anything else → SAVE with the entire argument string treated as `<steering text>`. (This is the `respawn <free-form>` shorthand. `save` and `load` are the only reserved verbs.)

For bare `respawn`, apply this decision tree:

1. Find candidate checkpoints: `respawn-*.md` (not `.loaded.md`) under `~/.claude/respawn/` whose recorded `Git root:` matches the current `git rev-parse --show-toplevel 2>/dev/null` and whose mtime is < 24h.
2. **No candidate** → SAVE.
3. **Candidate < 30 minutes old AND current session is "fresh"** (≤ 2 user turns AND no Write/Edit/NotebookEdit calls this session) → LOAD the newest candidate. The tight 30-minute window matches the common case: clear context mid-conversation, immediately resume.
4. **Otherwise (candidate is 30min–24h old, OR session looks active)** → ask the user once and wait:
   > Found respawn point for this repo from <relative time>. Load it, or save current state? (load/save)
5. If the runtime doesn't give access to "turn count" or "edit history," skip step 3 and always ask (step 4) when a candidate exists.

Announce the chosen action in one line before acting, e.g. `Respawning (save mode)…` or `Respawning (load mode) from <path>…`.

## Step 2 — SAVE procedure

1. **Ensure directory.** `mkdir -p ~/.claude/respawn && chmod 700 ~/.claude/respawn`.
2. **Capture identity** by running these commands:
   - timestamp: `date -u +%Y-%m-%dT%H:%M:%SZ` (header) and `date +%Y%m%d-%H%M%S` (filename)
   - `git rev-parse --show-toplevel 2>/dev/null` → `git_root` (use `n/a` if not in a repo)
   - `git rev-parse --abbrev-ref HEAD 2>/dev/null` → `branch`
   - `git rev-parse HEAD 2>/dev/null` → `head_sha`
   - `pwd` → `cwd`
3. **Path:** `~/.claude/respawn/respawn-<filename-timestamp>.md`. Overwrite on same-second collision — not worth special handling.
4. **Identify the handoff.** Before assembling content, judge whether this session has a *concrete actionable next step* — work the next session can pick up and execute without asking the user. Examples that qualify: a planned task mid-execution, a failing test to fix, a reviewed plan ready to implement, an unresolved blocker with known investigation paths. Examples that do not: "the conversation ended at a natural stopping point," "we discussed options but nothing was decided," "task is complete with no follow-up."
5. **No-next-step check.** If step 4 found no concrete next step, ask once:
   > No clear next step to hand off. `/compact` may be a better fit if you want to keep working in this session. Save a recap-style checkpoint anyway? (y/n)
   - `y` → proceed to step 6 with `Plan to execute: _recap only — no forward-looking handoff_` and `Next steps: _none — recap only_`.
   - `n` → stop, no file written.
   This check fires regardless of whether the user passed `save` explicitly or included steering text. Vague steering does not bypass it — only a real next step does. If steering text itself contains a concrete next step ("save: implement the migration plan we just agreed on"), step 4 will detect it and the check won't fire.
6. **Assemble content** using the template below.
   - `Plan to execute` is mandatory: populate with objective + approach + first step when a plan exists, or use the recap-only sentinel from step 5.
   - `Current task` and `Status` describe what the *next session* is doing or needs to do, not a history of this session.
   - If `<steering text>` was passed, let it shape what you emphasize and what you trim (it is not stored as its own section — it is generation guidance only).
   - Empty optional sections (`Files touched`, `Decisions made`, `Open questions`, `Context that won't be obvious`) become `_none_`. `Plan to execute` and `Next steps` always have content (either real or the recap-only sentinel).
7. **Secrets:** if the conversation included API keys, passwords, or `.env` values, redact them inline as `<REDACTED: <what it was for>>`. Defense-in-depth on top of the private directory.
8. **Write the file.**
9. **Print two lines** (shape, not exact prose):
   ```
   Respawn point saved: <path>
   Next session: /respawn
   ```

## Respawn file template

Write the file with these headers. LOAD parses by matching `## <header>` strings (header-based, not positional), so additions and reordering are safe as long as headers match exactly.

```
# Claude Code Respawn Point
_Saved: <ISO-8601 UTC>_
_Git root: <absolute path, or n/a>_
_Branch: <branch, or n/a>_
_HEAD: <head sha, or n/a>_
_Cwd at save: <absolute path>_

## Current task
<1-3 sentences: what the next session is working on or needs to take on. Forward-looking — frame from the perspective of the session that will read this, not the one that wrote it.>

## Status
<1-2 sentences: where the work stands right now — in-progress / blocked / ready-to-implement / ready-to-test.>

## Plan to execute
<MANDATORY. Either:
  - objective + approach + first concrete action, in 3-10 lines, OR
  - the literal string: _recap only — no forward-looking handoff_
Use the recap-only sentinel only after the no-next-step prompt has fired and the user opted to save anyway.>

## Next steps
<numbered list, concrete. First item must be actionable without asking the user. Each item ≤ 2 sentences. If recap-only, write: _none — recap only_.>
1. <action>
2. <action>

## Open questions blocked on user
<bulleted list of things the next session must ask before proceeding. If none, _none_.>
- <question>

## Files touched
<bulleted list of absolute paths with sub-bullets for line ranges + what + why. List ALL files touched. If genuinely none, write _none_. Appendix — not surfaced in LOAD acknowledgment unless the user asks.>
- /absolute/path/file.ts
  - lines 42-87: <what + why>

## Decisions made
<bulleted list. Each entry: decision + alternative(s) rejected + one-line reason. List ALL. If none, _none_. Appendix — not surfaced in LOAD acknowledgment unless the user asks.>
- Chose A over B because <reason>.

## Context that won't be obvious from the files
<free-form prose: constraints discovered, dead ends explored, external service quirks. Write _none_ if truly nothing. Surfaced inline in LOAD acknowledgment when populated.>
```

## Step 3 — LOAD procedure

1. **Locate file.**
   - Explicit path provided → use it (including `.loaded.md` files). If the path does not exist, stop per Step 1's load-with-path rule.
   - Else: list `respawn-*.md` (not `.loaded.md`) under `~/.claude/respawn/`, parse the header for `Git root:` (header-based — match the literal string `_Git root:`), pick the newest whose value matches the current `git rev-parse --show-toplevel`.
   - If no repo-matched file but other files exist → ask:
     > No respawn point for this repo. Load most recent (<path>, saved <relative time> for <other git root>)? (y/n)
   - If no files at all → reply with one line and stop:
     > No respawn point found in ~/.claude/respawn/. Start fresh or pass a path: /respawn load /path/to/file.md
2. **Stale check for explicit `load`:** if chosen file mtime > 24h, list up to 5 most recent and ask which to load. (Repo-matched auto-load is already gated to < 24h.)
3. **Read fully** (Read tool — files are small). Parse by matching `## <header>` strings; section order in the file does not matter. Missing optional sections are treated as `_none_`.
4. **Compare identity:**
   - `Cwd at save` vs current `pwd` → note in acknowledgment if different. Do not auto-`cd`.
   - `Branch` vs current branch → note if different.
   - `HEAD` vs current `git rev-parse HEAD` → if different, note: `Note: HEAD has moved since save (was <short-sha>, now <short-sha>). Some next steps may be stale.`
5. **Acknowledge.** The acknowledgment IS the briefing for this session — bias toward showing the plan and the work, not file metadata. Shape (not exact prose):
   - `Respawned from: <path>`
   - Task: one-line from `Current task`.
   - Status: one-line from `Status`.
   - **Plan:** print the full `Plan to execute` block verbatim, unless it is the recap-only sentinel — in which case print `Plan: recap only (no forward-looking handoff)`.
   - **Next steps:** print the full numbered list verbatim, unless `_none — recap only_`.
   - If `Context that won't be obvious from the files` is populated and not `_none_`: surface it inline under "Context:".
   - `Open questions: <count>` — and if > 0, list them as bullets immediately after.
   - Any identity-drift notes from step 4.
   - End with: `Proceed with the first next step, or redirect?` (or, for recap-only: `Loaded for context — no next step queued. What would you like to do?`).
   - Do NOT surface `Files touched` or `Decisions made` in the acknowledgment. They are appendix sections available in the file if the user asks.
6. **Wait** for the user. Do not begin executing.
7. **Mark consumed.** After the acknowledgment is sent, rename the file: `mv <path> <path%.md>.loaded.md`. This prevents the same checkpoint from auto-loading again. The user can still pass the explicit `.loaded.md` path to re-read it.

## Edge cases

- **Old checkpoints without `Plan to execute`:** treat as `_none_` and fall through to printing `Next steps` directly under the task/status lines. End with the standard "Proceed with the first next step, or redirect?" prompt. Old checkpoints remain fully loadable.
- **Old checkpoints whose section order differs from the current template:** header-based parsing handles this — section order is irrelevant.
- **Malformed file** (missing `Current task` AND `Status` AND `Next steps`): proceed with best-effort acknowledgment from what's there, and append `(file appears malformed — some sections missing)`.
- **`Files touched` paths no longer exist:** mention in acknowledgment only if the user asks about files.
- **`Cwd at save` no longer exists:** mention in acknowledgment.
- **SAVE write fails** (full disk, perms): surface the error to the user and ask where to write instead.
- **Concurrent SAVE in same second:** the second one wins (overwrites). This is acceptable — concurrent Claude sessions saving in the same second is vanishingly rare.
