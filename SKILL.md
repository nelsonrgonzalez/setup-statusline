---
name: setup-statusline
description: Sets up or reinstalls the Claude Code rich 3-line ANSI statusline on macOS, Linux, WSL, Git Bash, or Windows (PowerShell / CMD). Use when the user wants to install, reinstall, or troubleshoot the statusline on any machine.
allowed-tools: Bash, Read, Write, Edit
model: sonnet
---

Install the Claude Code rich statusline by following these steps in order.

## Step 1 — Detect environment

Run these commands and note the results:

```bash
uname -s          # OS: Darwin = macOS, Linux = Linux/WSL, MINGW* = Git Bash
bash --version    # Must be 3.2+
jq --version      # Must be present (not needed for PowerShell/CMD)
git --version     # Must be present
echo "$HOME"      # Confirm home directory
```

On Linux, also check for WSL:
```bash
grep -qi microsoft /proc/version 2>/dev/null && echo "WSL" || echo "native Linux"
```

On Windows (PowerShell or CMD), run instead:
```powershell
$PSVersionTable.PSVersion   # Must be 5.1 or higher
git --version               # Must be present
echo $env:USERPROFILE       # Confirm home directory
```

Determine the target platform from the results and proceed with the matching asset below.

## Step 2 — Install missing prerequisites

### Bash variants (Linux / macOS / WSL / Git Bash)

`jq` and `git` are required. If missing:

| OS | Install command |
|----|----------------|
| macOS | `brew install jq git` |
| Ubuntu / Debian / WSL | `sudo apt-get install -y jq git` |
| Fedora / RHEL | `sudo dnf install -y jq git` |
| Arch | `sudo pacman -S jq git` |
| Git Bash (Windows) | Download `jq.exe` from https://jqlang.github.io/jq/ and place in a directory on PATH |

If bash is older than 3.2, stop and tell the user — the script requires at minimum bash 3.2.

### PowerShell and CMD (Windows native)

No `jq` required — JSON is parsed natively by `ConvertFrom-Json`. Only `git` is needed:

```powershell
winget install Git.Git   # or download from https://git-scm.com/
```

Confirm PowerShell version is 5.1+: `$PSVersionTable.PSVersion`. PowerShell 7 (pwsh) is also supported and preferred if installed.

## Step 3 — Deploy the script

The skill's assets are organized by platform under `~/.claude/skills/setup-statusline/assets/`. Copy the correct asset(s) to `~/.claude/`:

| Platform | Asset | Destination |
|----------|-------|-------------|
| Linux | `assets/linux/statusline-command.sh` | `~/.claude/statusline-command.sh` |
| macOS | `assets/macos/statusline-command.sh` | `~/.claude/statusline-command.sh` |
| WSL | `assets/wsl/statusline-command.sh` | `~/.claude/statusline-command.sh` |
| Git Bash | `assets/gitbash/statusline-command.sh` | `~/.claude/statusline-command.sh` |
| PowerShell | `assets/windows-ps/statusline.ps1` | `~/.claude/statusline.ps1` |
| CMD | `assets/windows-ps/statusline.ps1` + `assets/windows-cmd/statusline.bat` | `~/.claude/statusline.ps1` + `~/.claude/statusline.bat` |

For bash variants:
```bash
# Replace <platform> with: linux, macos, wsl, or gitbash
cp ~/.claude/skills/setup-statusline/assets/<platform>/statusline-command.sh ~/.claude/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh
```

For PowerShell:
```powershell
Copy-Item "$env:USERPROFILE\.claude\skills\setup-statusline\assets\windows-ps\statusline.ps1" `
          "$env:USERPROFILE\.claude\statusline.ps1"
```

For CMD (needs both files):
```batch
copy "%USERPROFILE%\.claude\skills\setup-statusline\assets\windows-ps\statusline.ps1" "%USERPROFILE%\.claude\statusline.ps1"
copy "%USERPROFILE%\.claude\skills\setup-statusline\assets\windows-cmd\statusline.bat" "%USERPROFILE%\.claude\statusline.bat"
```

Verify deployment:
```bash
# Bash variants
head -3 ~/.claude/statusline-command.sh
```
```powershell
# PowerShell / CMD
Get-Content "$env:USERPROFILE\.claude\statusline.ps1" -TotalCount 3
```

## Step 4 — Update ~/.claude/settings.json

Read `~/.claude/settings.json`. Add or update the `statusLine` block using the command for the detected platform:

**Linux / macOS / WSL / Git Bash:**
```json
"statusLine": {
  "type": "command",
  "command": "bash ~/.claude/statusline-command.sh",
  "refreshInterval": 10
}
```

**PowerShell 7 (pwsh):**
```json
"statusLine": {
  "type": "command",
  "command": "pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"%USERPROFILE%\\.claude\\statusline.ps1\"",
  "refreshInterval": 10
}
```

**PowerShell 5.1 (Windows built-in):**
```json
"statusLine": {
  "type": "command",
  "command": "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"%USERPROFILE%\\.claude\\statusline.ps1\"",
  "refreshInterval": 10
}
```

**CMD:**
```json
"statusLine": {
  "type": "command",
  "command": "\"%USERPROFILE%\\.claude\\statusline.bat\"",
  "refreshInterval": 10
}
```

Preserve all other existing settings. If the file does not exist, create it with just the statusLine block wrapped in `{}`.

## Step 5 — Verify

**Bash variants:** if `/tmp/statusline-debug.json` exists (written by a previous Claude Code session), run a quick smoke-test:

```bash
cat /tmp/statusline-debug.json | bash ~/.claude/statusline-command.sh
```

**PowerShell / CMD:** the debug snapshot is written to `$env:TEMP\statusline-debug.json`:

```powershell
Get-Content "$env:TEMP\statusline-debug.json" | & pwsh -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\statusline.ps1"
```

The output should be 3 lines of ANSI-colored text. If it errors, diagnose and fix before reporting success.

If no debug file exists yet, skip the test — the statusline will activate on the next Claude Code session.

## Platform notes

Each asset is purpose-built for its platform with no runtime branching:

| Asset | Shell | JSON parser | Date command | Notes |
|-------|-------|-------------|--------------|-------|
| `linux/` | bash, `mapfile` | `jq` | `date -d @epoch` | Native Linux |
| `macos/` | bash 3.2+, while-loop | `jq` | `date -r epoch` | BSD date (not GNU) |
| `wsl/` | bash, `mapfile` | `jq` | `date -d @epoch` | Identical to Linux |
| `gitbash/` | bash, while-loop | `jq` | `date -d @epoch` | GNU date from Git for Windows |
| `windows-ps/` | PowerShell 5.1+ | `ConvertFrom-Json` | `.NET DateTime` | No jq needed |
| `windows-cmd/` | `.bat` launcher | — | — | Delegates to `statusline.ps1` |

**CMD and PowerShell ANSI support:** requires Windows Terminal, VS Code terminal, or Windows 10 v1511+ with Virtual Terminal Processing. Plain `cmd.exe` windows on older Windows will display raw escape codes instead of colors.

## What the statusline shows

Three lines of ANSI-colored output rendered in the Claude Code terminal on every turn:

```
❯ ~/.claude/skills [modify-statusline-command.sh] │ ⎇  main │ Sonnet 4.6 💡 high │
⛁ ██████▊███ 136k╱200k (68%) │ ◷ 5h:28% [↻4h3m @23:00] 7d:33% [↻2d8h] │
⬡ ↓1 ↑137 Σ↓690 Σ↑56.6k │ ⚡ ⊕1.3k ↻134.6k ♻99% │ $ 3.42 ⧗ 17m21s╱20h5m ∆ +632 -131 │
```

**Line 1 — Location · Git · Model** (blue / white / cyan)
- `❯ ~/path [session-name]` — working directory with `~` substitution; named session in brackets if set
- `⎇ branch +N ~N ?N` — git branch with staged (green), modified (yellow), untracked (dim) counts; `⎇ —` if not a git repo
- `Model 💡 ⚡ low–max` — model name color-coded by family (gold=Opus, green=Haiku, cyan=Sonnet); badges for thinking (💡), fast mode (⚡), effort level text (low/medium/high/xhigh/max), vim mode (N/I/V/VL)

**Line 2 — Context Bar · Rate Limits** (threshold-colored)
- `⛀/⛁/⚠ ██▊███ Nk╱Nk (N%)` — 10-block smooth progress bar; icon and fill color scale with usage: ⛀ green <65%, ⛁ yellow 65–74%, ⛁ red 75–79%, ⚠ bright-red-background ≥80% (autocompact threshold)
- `◷ 5h:N% [↻Xh @HH:MM] 7d:N% [↻Xd]` — 5-hour and 7-day rate limit usage; 5h includes countdown and local reset time; color: green <70%, black-on-yellow ≥70%, white-on-red ≥90%

**Line 3 — Tokens · Cache · Cost** (magenta / dark-gray / white backgrounds)
- `⬡ ↓N ↑N Σ↓N Σ↑N` — current-turn input/output (↓/↑) and session totals (Σ↓/Σ↑)
- `⚡ ⊕N ↻N ♻N%` — cache writes (⊕), cache reads (↻), efficiency ratio (♻); efficiency color: green ≥70%, yellow 40–69%, red <40%
- `$ N.NN ⧗ api╱wall ∆ +N -N` — cumulative cost, API time over wall-clock time, lines added (dark green) / removed (dark red)
