# claude-respawn-plugin

A Claude Code plugin that saves and restores session state across `/clear`. One command (`/respawn`) handles both directions — auto-detect when the signal is unambiguous, ask when not.

## Why

Claude Code sessions get long. Eventually the context window fills with files you've already moved past, exploration that didn't pan out, agent transcripts, and old tool output — and you need to `/clear` to keep working effectively. But the next task is usually *continuous* with what you were just doing: same plan, same constraints, same open questions, same decisions about which alternatives you've already rejected. Today, `/clear` throws all of that away and the next session re-litigates from scratch.

`/respawn` is the handoff across that forced clear. Before you clear, it writes the actual state — current task, plan to execute, files touched, decisions made (and alternatives rejected), what's blocked on you — to a private checkpoint. After the clear, the fresh session reads it back. You get the empty context window without losing the thread.

## Install

In any Claude Code session:

```
/plugin marketplace add https://github.com/elleryfamilia/claude-respawn-plugin
/plugin install respawn@claude-respawn-plugin
```

(The shorthand `/plugin marketplace add elleryfamilia/claude-respawn-plugin` also works, but uses SSH — pass the HTTPS URL if you don't have a GitHub SSH key set up.)

Then restart Claude Code.

### Local / dev install

If you want to hack on the plugin, clone and use the helper:

```sh
git clone https://github.com/elleryfamilia/claude-respawn-plugin ~/_git/claude-respawn-plugin
cd ~/_git/claude-respawn-plugin
./install.sh           # or ./install.sh --dev for symlink mode
```

## Usage

In any Claude Code session:

```
/respawn
```

The skill auto-detects mode:

- **Save mode** fires by default — writes a checkpoint to `~/.claude/respawn/respawn-<timestamp>.md` and prints the path.
- **Load mode** fires automatically when this is one of the first ~2 turns of a session AND no files have been edited AND a checkpoint < 30 minutes old exists for the current git repo. (The tight window matches the canonical use: clear context mid-conversation, immediately resume.)
- **Ambiguous** (checkpoint exists but is older than 30 min, or the session looks active): the skill asks before acting. Files older than 24h are ignored entirely — use `/respawn load` explicitly to reach them.

Then `/clear` and `/respawn` again in the fresh session to pick up where you left off.

### Explicit overrides

```
/respawn save              # force save
/respawn load              # force load (most recent for this repo)
/respawn load /path/file   # load a specific checkpoint
```

### What gets saved

Each checkpoint records: git root, branch, HEAD SHA, cwd, current task, status, files touched (with line ranges), decisions made (and alternatives rejected), next steps, open questions blocked on user, and free-form context that won't be obvious from the files.

### Where checkpoints live

`~/.claude/respawn/` (mode `0700`, private to your user). Loaded checkpoints are renamed to `*.loaded.md` so the same file can't auto-load twice. You can re-read a loaded file by passing its path explicitly to `/respawn load`.

## Safety properties

- **Repo-scoped matching.** A checkpoint records its `git rev-parse --show-toplevel` at save time. Auto-load only fires when the current repo matches. Cross-repo loads require an explicit prompt.
- **HEAD drift surfacing.** If HEAD has moved since save, the load acknowledgment flags the saved next-steps as potentially stale.
- **Consumed-checkpoint marker.** Successful loads rename the file to `*.loaded.md`, preventing accidental re-load on a future bare `/respawn`.
- **Private directory.** `~/.claude/respawn/` is mode `0700` — not `/tmp`, which is world-readable on macOS multi-user systems.
- **Ambiguity prompt.** When auto-detection is genuinely uncertain (active session + recent repo-matched checkpoint), the skill asks rather than guessing.

## Uninstall

```sh
./install.sh --uninstall
```

Runs `claude plugin uninstall respawn@claude-respawn-plugin` and `claude plugin marketplace remove claude-respawn-plugin`, plus removes dev-mode symlinks if present. Existing `~/.claude/respawn/*.md` files are left in place — `rm -rf ~/.claude/respawn/` if you want them gone.

## Iterating on the skill

Editing `SKILL.md` in this repo and re-running `./install.sh` won't pick up your changes immediately — the plugin install caches a copy. Two options:

```sh
# Option A: refresh the cached copy after each edit
claude plugin marketplace update claude-respawn-plugin
claude plugin update respawn@claude-respawn-plugin
# (restart Claude Code)

# Option B: dev mode — symlinks into ~/.claude/skills + ~/.claude/commands
./install.sh --uninstall    # remove the real install first to avoid double-trigger
./install.sh --dev          # symlinks live; edits show up after restart
```

Switch back with `./install.sh --uninstall && ./install.sh`.

## Layout

```
.
├── install.sh                              # validate → marketplace add → install
├── .claude-plugin/
│   └── marketplace.json                    # single-plugin marketplace manifest
└── plugins/
    └── respawn/
        ├── .claude-plugin/plugin.json      # per-plugin manifest
        ├── skills/respawn/SKILL.md         # SAVE + LOAD procedures
        └── commands/respawn.md             # thin slash-command wrapper
```
