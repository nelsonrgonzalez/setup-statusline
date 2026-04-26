---
name: setup-statusline
description: Sets up or reinstalls the Claude Code rich 3-line ANSI statusline on macOS, Linux, or Windows (WSL/Git Bash). Use when the user wants to install, reinstall, or troubleshoot the statusline on any machine.
allowed-tools: Bash, Read, Write, Edit
model: sonnet
---

Install the Claude Code rich statusline by following these steps in order.

## Step 1 — Detect environment

Run these commands and note the results:

```bash
uname -s          # OS: Darwin = macOS, Linux = Linux/WSL, MINGW* = Git Bash
bash --version    # Must be 3.2+; 4.0+ preferred
jq --version      # Must be present
git --version     # Must be present
echo "$HOME"      # Confirm home directory
```

If running on Linux, also check for WSL:
```bash
grep -qi microsoft /proc/version 2>/dev/null && echo "WSL" || echo "native Linux"
```

## Step 2 — Install missing prerequisites

If `jq` is missing, show the appropriate install command and ask the user to run it, then continue:

| OS | Install command |
|----|----------------|
| macOS | `brew install jq` |
| Ubuntu / Debian / WSL | `sudo apt-get install -y jq` |
| Fedora / RHEL | `sudo dnf install -y jq` |
| Arch | `sudo pacman -S jq` |
| Git Bash (Windows) | Download jq.exe from https://jqlang.github.io/jq/ and place in a directory on PATH |

If `git` is missing, similar instructions apply (brew, apt-get, etc.).

If bash is older than 3.2, stop and tell the user — the script requires at minimum bash 3.2.

## Step 3 — Deploy the script

Find the skill's own assets directory. The skill lives at `~/.claude/skills/setup-statusline/`. Read the asset script and write it to `~/.claude/statusline-command.sh`:

```bash
cp ~/.claude/skills/setup-statusline/assets/statusline-command.sh ~/.claude/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh
```

Verify it was written:
```bash
head -3 ~/.claude/statusline-command.sh
```

## Step 4 — Update ~/.claude/settings.json

Read `~/.claude/settings.json`. Add or update the `statusLine` block so it reads:

```json
"statusLine": {
  "type": "command",
  "command": "bash ~/.claude/statusline-command.sh",
  "refreshInterval": 10
}
```

Preserve all other existing settings. If the file does not exist, create it with just the statusLine block wrapped in `{}`.

## Step 5 — Verify

If `/tmp/statusline-debug.json` exists (left by a previous Claude Code session), do a quick smoke-test:

```bash
cat /tmp/statusline-debug.json | bash ~/.claude/statusline-command.sh
```

The output should be 3 lines of ANSI-colored text. If it errors, diagnose and fix before reporting success.

If the debug file does not exist, skip the test and tell the user the statusline will activate on their next Claude Code session.

## Platform notes

The script handles OS differences internally at runtime:
- **macOS**: uses `date -r <epoch>` for local time conversion; bash 3.2 compatible (no `mapfile`)
- **Linux / WSL**: uses `date -d @<epoch>` for local time conversion
- **Git Bash (Windows)**: uses GNU date (`date -d`); ANSI colors require Windows Terminal or similar — does not work in plain cmd.exe
- **All platforms**: requires `jq` on PATH, `git` on PATH, bash 3.2+

## What the statusline shows

Three lines of ANSI-colored output rendered in the Claude Code terminal on every turn:

```
❯ ~/.claude/skills [modify-statusline-command.sh] │ ⎇ main │ Sonnet 4.6 💡 𐄛 │
⛁ ██████▊███ 136k╱200k (68%) │ ◷ 5h:28% [↻4h3m @23:00] 7d:33% [↻2d8h] │
⬡ ↓1 ↑137 Σ↓690 Σ↑56.6k │ ⚡ ⊕1.3k ↻134.6k ♻99% │ $ 3.42 ⧗ 17m21s╱20h5m ∆ +632 -131 │
```

**Line 1 — Location · Git · Model** (blue / white / cyan)
- `❯ ~/path [session-name]` — working directory with `~` substitution; named session in brackets if set
- `⎇ branch +N ~N ?N` — git branch with staged (green), modified (yellow), untracked (dim) counts; `⎇ —` if not a git repo
- `Model 💡 ⚡ 𐄙–𐄝` — model name color-coded by family; badges for thinking (💡), fast mode (⚡), effort level (Aegean glyphs low→max), vim mode (N/I/V/VL)

**Line 2 — Context Bar · Rate Limits** (threshold-colored)
- `⛀/⛁/⚠ ██▊███ Nk╱Nk (N%)` — 10-block smooth progress bar; icon and fill color scale with usage: ⛀ green <65%, ⛁ yellow 65–74%, ⛁ red 75–79%, ⚠ bright-red-background ≥80% (autocompact threshold)
- `◷ 5h:N% [↻Xh @HH:MM] 7d:N% [↻Xd]` — 5-hour and 7-day rate limit usage; 5h includes countdown and local reset time; color: green <70%, black-on-yellow ≥70%, white-on-red ≥90%

**Line 3 — Tokens · Cache · Cost** (magenta / dark-gray / white backgrounds)
- `⬡ ↓N ↑N Σ↓N Σ↑N` — current-turn input/output (↓/↑) and session totals (Σ↓/Σ↑)
- `⚡ ⊕N ↻N ♻N%` — cache writes (⊕), cache reads (↻), efficiency ratio (♻); efficiency color: green ≥70%, yellow 40–69%, red <40%
- `$ N.NN ⧗ api╱wall ∆ +N -N` — cumulative cost, API time over wall-clock time, lines added/removed
