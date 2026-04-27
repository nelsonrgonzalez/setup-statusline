#Requires -Version 5.1
# Claude Code statusline — PowerShell version (Windows native).
# Requires PowerShell 5.1+. No external tools needed — JSON is parsed natively
# with ConvertFrom-Json. ANSI colors require Windows Terminal or VS Code terminal.
#
# Claude Code pipes a JSON payload via stdin on every refresh (see refreshInterval
# in settings.json). All session data — model, context, cost, tokens, rate limits,
# git state — comes from that single payload. Nothing is fetched externally.

param()

# UTF-8 must be set before reading stdin so Unicode characters survive the pipe
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Read JSON payload from stdin
$rawJson = [Console]::In.ReadToEnd()
$rawJson | Out-File -FilePath "$env:TEMP\statusline-debug.json" -Encoding utf8 -NoNewline

# Parse JSON — no jq needed on Windows
$data = $null
try {
    $data = $rawJson | ConvertFrom-Json
} catch {
    [Console]::Out.WriteLine("statusline: JSON parse error")
    exit 1
}

$esc = [char]27

# --- Helpers ---

# Format integer as compact human-readable string (1500 -> "1.5k")
function fmt_num([long]$n) {
    if ($n -le 0) { return "" }
    if ($n -ge 1000) {
        $v = $n / 1000.0
        if ($v -eq [Math]::Floor($v)) { return ("{0}k" -f [int]$v) }
        return ("{0:0.0}k" -f $v)
    }
    return "$n"
}

# Format milliseconds as human-readable duration
function fmt_dur([long]$ms) {
    $s = [long][Math]::Floor($ms / 1000); $m = [long][Math]::Floor($s / 60); $s = $s % 60
    $h = [long][Math]::Floor($m / 60);    $m = $m % 60
    if ($h -gt 0 -and $m -gt 0) { return "${h}h${m}m" }
    if ($h -gt 0)                { return "${h}h" }
    if ($m -gt 0 -and $s -gt 0) { return "${m}m${s}s" }
    if ($m -gt 0)                { return "${m}m" }
    return "${s}s"
}

# Format seconds as countdown string (e.g. ↻2h14m)
function fmt_reset([long]$secs) {
    $d = [long][Math]::Floor($secs / 86400)
    $h = [long][Math]::Floor(($secs % 86400) / 3600)
    $m = [long][Math]::Floor(($secs % 3600) / 60)
    if ($d -gt 0 -and $h -gt 0) { return "↻${d}d${h}h" }
    if ($d -gt 0)                { return "↻${d}d" }
    if ($h -gt 0)                { return "↻${h}h${m}m" }
    return "↻${m}m"
}

# Convert Unix epoch to local HH:MM (24-hour). Works on PS 5.1+ (.NET 4.5+).
function to_localtime([long]$epoch) {
    $origin = [DateTime]::new(1970, 1, 1, 0, 0, 0, 0, 'Utc')
    return $origin.AddSeconds($epoch).ToLocalTime().ToString("HH:mm")
}

# Build a 10-block smooth Unicode progress bar
function build_bar([int]$pct, [string]$fillColor) {
    $width     = 10
    $emptyFg   = "$esc[90m"
    $partialBg = "$esc[100m"
    $eighths   = @('', '▏', '▎', '▍', '▌', '▋', '▊', '▉')

    $fVal   = $pct * 10.0 / 100
    $full   = [int][Math]::Floor($fVal)
    $eighth = [int](($fVal - $full) * 8)

    $bar = ""
    for ($i = 0; $i -lt $full; $i++) { $bar += "${fillColor}█" }

    $partial = 0
    if ($eighth -gt 0 -and $full -lt $width) {
        $bar += "${fillColor}${partialBg}" + $eighths[$eighth]
        $partial = 1
    }

    $bar += $emptyFg
    $empty = $width - $full - $partial
    for ($i = 0; $i -lt $empty; $i++) { $bar += "█" }
    return $bar
}

# Safe null-to-default helpers (PS 5.1 has no ?? operator)
function safe_str($v)  { if ($null -ne $v) { "$v" }    else { "" } }
function safe_long($v) { if ($null -ne $v) { [long]$v } else { [long]0 } }

# --- Extract fields from JSON payload ---
$cwd          = safe_str  $data.cwd
$modelId      = safe_str  $data.model.id
$modelDisplay = safe_str  $data.model.display_name
$ctxPct       = $data.context_window.used_percentage          # may be $null
$hasUsage     = ($null -ne $data.context_window.current_usage -and
                 $data.context_window.current_usage -is [PSCustomObject])
$inTokens     = safe_long $data.context_window.current_usage.input_tokens
$outTokens    = safe_long $data.context_window.current_usage.output_tokens
$cacheCreate  = safe_long $data.context_window.current_usage.cache_creation_input_tokens
$cacheRead    = safe_long $data.context_window.current_usage.cache_read_input_tokens
$totalIn      = safe_long $data.context_window.total_input_tokens
$totalOut     = safe_long $data.context_window.total_output_tokens
$winSize      = safe_long $data.context_window.context_window_size
$totalCost    = $data.cost.total_cost_usd
$totalDur     = safe_long $data.cost.total_duration_ms
$apiDur       = safe_long $data.cost.total_api_duration_ms
$linesAdded   = safe_long $data.cost.total_lines_added
$linesRemoved = safe_long $data.cost.total_lines_removed
$rl5hPct      = $data.rate_limits.five_hour.used_percentage   # may be $null
$rl7dPct      = $data.rate_limits.seven_day.used_percentage   # may be $null
$rl5hReset    = safe_long $data.rate_limits.five_hour.resets_at
$rl7dReset    = safe_long $data.rate_limits.seven_day.resets_at
$fastMode     = $data.fast_mode -eq $true
$thinking     = ($data.thinking.enabled -eq $true) -or ($data.thinking -eq $true)
$effort       = safe_str  $data.effort.level

# Fallback: read effortLevel from settings.json when not supplied in payload
if (-not $effort) {
    $settingsPath = "$env:USERPROFILE\.claude\settings.json"
    if (Test-Path $settingsPath) {
        try {
            $s = Get-Content $settingsPath -Raw -Encoding utf8 | ConvertFrom-Json
            if ($s.effortLevel) { $effort = $s.effortLevel }
        } catch { }
    }
}
$overflow     = $data.exceeds_200k_tokens -eq $true
$addedDirs    = if ($null -ne $data.workspace.added_dirs) { $data.workspace.added_dirs.Count } else { 0 }
$sessionName  = safe_str  $data.session_name
$vimMode      = safe_str  $data.vim.mode
$projectDir   = safe_str  $data.workspace.project_dir

# --- Section separators ---
$sep  = "$esc[0m $esc[2;37m│$esc[0m "
$tsep = " $esc[2;37m│$esc[0m"

# --- Location ---
$location = "$esc[44m$esc[1;30m❯ $cwd$esc[0m"
if ($sessionName) { $location += "$esc[44m$esc[1;30m [$sessionName]$esc[0m" }
if ($addedDirs -gt 0) { $location += "$esc[44m$esc[1;30m +$addedDirs$esc[0m" }
if ($projectDir -and $projectDir -ne $cwd) {
    $projBase = Split-Path $projectDir -Leaf
    $location += "$esc[44m$esc[2;30m ↑$projBase$esc[0m"
}

# --- Model color + badges ---
$modelLabel = if ($modelDisplay) { $modelDisplay } else { $modelId -replace '^claude-', '' }
$modelColor = if     ($modelId -like "*opus*")  { "$esc[1;33m" }
              elseif ($modelId -like "*haiku*") { "$esc[1;32m" }
              else                              { "$esc[1;36m" }

$modelBadges = ""
if ($thinking) { $modelBadges += " $esc[1;35m💡$esc[0m" }
if ($fastMode) { $modelBadges += " $esc[1;37m⚡$esc[0m" }
$modelBadges += switch ($effort) {
    "max"    { " $esc[1;37m$esc[41mmax$esc[0m" }
    "xhigh"  { " $esc[1;31mxhigh$esc[0m" }
    "high"   { " $esc[1;31mhigh$esc[0m" }
    "medium" { " $esc[1;33mmedium$esc[0m" }
    "low"    { " $esc[2;37mlow$esc[0m" }
    default  { "" }
}
$modelBadges += switch ($vimMode) {
    "NORMAL"      { " $esc[1;32mN$esc[0m" }
    "INSERT"      { " $esc[1;33mI$esc[0m" }
    "VISUAL"      { " $esc[1;35mV$esc[0m" }
    "VISUAL LINE" { " $esc[1;35mVL$esc[0m" }
    default       { "" }
}

# --- Context bar ---
# Autocompact fires at ~83.5%; ≥80% is treated as the critical threshold.
$ctxVal    = 0
$fillColor = "$esc[1;32m"
$winBg     = "$esc[40m$esc[1;37m"
$barIcon   = "⛀"
if ($null -ne $ctxPct) {
    $ctxVal = [int][Math]::Round([double]$ctxPct)
    if      ($ctxVal -ge 80) { $fillColor = "$esc[1;31m"; $winBg = "$esc[101m$esc[1;37m"; $barIcon = "⚠" }
    elseif  ($ctxVal -ge 75) { $fillColor = "$esc[1;31m"; $winBg = "$esc[40m$esc[1;37m";  $barIcon = "⛁" }
    elseif  ($ctxVal -ge 65) { $fillColor = "$esc[1;33m"; $winBg = "$esc[40m$esc[1;37m";  $barIcon = "⛁" }
    else                     { $fillColor = "$esc[1;32m"; $winBg = "$esc[40m$esc[1;37m";  $barIcon = "⛀" }
}

$winStr = ""
if ($null -ne $ctxPct -and $winSize -gt 0) {
    $used    = [long]([double]$ctxPct * $winSize / 100)
    $usedFmt = fmt_num $used
    $winFmt  = fmt_num $winSize
    if ($overflow) {
        $winStr = "⛔ $usedFmt╱$winFmt OVERFLOW"
    } else {
        $bar    = build_bar $ctxVal $fillColor
        # Numbers use neutral dark background regardless of warning level (no alarm bleed)
        $winStr = "$barIcon $bar$esc[0m$esc[40m$esc[1;37m $usedFmt╱$winFmt ($ctxVal%)"
    }
} elseif ($winSize -gt 0) {
    $wf = fmt_num $winSize
    if ($wf) { $winStr = "$barIcon $wf" }
}

# --- Git status ---
$gitStr = "$esc[2;37m⎇  —$esc[0m"
if ($cwd) {
    $null = & git -C "$cwd" rev-parse --git-dir 2>&1
    if ($LASTEXITCODE -eq 0) {
        $branch      = (& git -C "$cwd" branch --show-current 2>&1) -join ""
        $statusLines = & git -C "$cwd" status --short 2>&1
        $staged    = @($statusLines | Where-Object { $_ -match '^[MADRCU]' }).Count
        $modified  = @($statusLines | Where-Object { $_ -match '^ [MD]' }).Count
        $untracked = @($statusLines | Where-Object { $_ -match '^\?\?' }).Count
        $gitStr = "$esc[1;37m⎇  $(if ($branch) { $branch } else { 'HEAD' })$esc[0m"
        if ($staged    -gt 0) { $gitStr += " $esc[1;32m+$staged$esc[0m" }
        if ($modified  -gt 0) { $gitStr += " $esc[1;33m~$modified$esc[0m" }
        if ($untracked -gt 0) { $gitStr += " $esc[2;37m?$untracked$esc[0m" }
    }
}

# --- Token strings (only when per-turn data is present) ---
$inStr = ""; $outStr = ""; $ccStr = ""; $crStr = ""
if ($hasUsage) {
    $f = fmt_num $inTokens;    if ($f) { $inStr  = "↓$f" }
    $f = fmt_num $outTokens;   if ($f) { $outStr = "↑$f" }
    $f = fmt_num $cacheCreate; if ($f) { $ccStr  = "⊕$f" }
    $f = fmt_num $cacheRead;   if ($f) { $crStr  = "↻$f" }
}

# --- Cache efficiency ---
# ≥70% green (hot cache), 40–69% yellow (warming), <40% red (cold)
$effStr = ""; $effColor = ""
$totalCache = $cacheCreate + $cacheRead
if ($totalCache -gt 0) {
    $eff = [int][Math]::Round($cacheRead * 100.0 / $totalCache)
    $effStr = "$eff%"
    if      ($eff -ge 70) { $effColor = "$esc[1;32m" }
    elseif  ($eff -ge 40) { $effColor = "$esc[43m$esc[1;33m" }
    else                  { $effColor = "$esc[41m$esc[1;31m" }
}

# --- Session totals ---
$tinStr = ""; $toutStr = ""
$f = fmt_num $totalIn;  if ($f) { $tinStr  = "Σ↓$f" }
$f = fmt_num $totalOut; if ($f) { $toutStr = "Σ↑$f" }

# --- Cost (scaled precision) ---
$costStr = ""
if ($null -ne $totalCost) {
    $c = [double]$totalCost
    if ($c -gt 0) {
        if      ($c -ge 1.0)  { $costStr = "{0:0.00}"    -f $c }
        elseif  ($c -ge 0.1)  { $costStr = "{0:0.000}"   -f $c }
        elseif  ($c -ge 0.01) { $costStr = "{0:0.0000}"  -f $c }
        else                  { $costStr = "{0:0.00000}"  -f $c }
    }
}

# --- Duration (API-only / total wall-clock) ---
$durStr = ""
if ($apiDur -gt 0 -or $totalDur -gt 0) {
    if ($apiDur -gt 0) { $durStr = "⧗ $(fmt_dur $apiDur)╱$(fmt_dur $totalDur)" }
    else               { $durStr = "⧗ $(fmt_dur $totalDur)" }
}

# --- Lines added/removed (dark green additions, dark red removals) ---
$linesStr = ""
if ($linesAdded -gt 0 -or $linesRemoved -gt 0) {
    $linesStr = "∆"
    if ($linesAdded   -gt 0) { $linesStr += " $esc[32m+$linesAdded$esc[38;2;0;0;0m" }
    if ($linesRemoved -gt 0) { $linesStr += " $esc[31m-$linesRemoved$esc[38;2;0;0;0m" }
}

# --- Rate limits ---
# ≥90%: white on red (critical); ≥70%: black on yellow (warning); else green
$rlStr = ""; $rlColor = ""
if ($null -ne $rl5hPct -or $null -ne $rl7dPct) {
    $r5 = if ($null -ne $rl5hPct) { [int][Math]::Round([double]$rl5hPct) } else { 0 }
    $r7 = if ($null -ne $rl7dPct) { [int][Math]::Round([double]$rl7dPct) } else { 0 }
    $rlMax = [Math]::Max($r5, $r7)
    if      ($rlMax -ge 90) { $rlColor = "$esc[41m$esc[1;37m" }
    elseif  ($rlMax -ge 70) { $rlColor = "$esc[43m$esc[1;30m" }
    else                    { $rlColor = "$esc[1;32m" }

    $nowEpoch = [System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    $rl5hPart = ""
    if ($null -ne $rl5hPct) {
        $rl5hPart = "5h:$r5%"
        if ($rl5hReset -gt 0) {
            $in5h = $rl5hReset - $nowEpoch
            if ($in5h -gt 0) {
                $rt = to_localtime $rl5hReset
                $rl5hPart += " [$(fmt_reset $in5h) @$rt]"
            }
        }
    }
    $rl7dPart = ""
    if ($null -ne $rl7dPct) {
        $rl7dPart = "7d:$r7%"
        if ($rl7dReset -gt 0) {
            $in7d = $rl7dReset - $nowEpoch
            if ($in7d -gt 0) { $rl7dPart += " [$(fmt_reset $in7d)]" }
        }
    }
    $parts = @($rl5hPart, $rl7dPart) | Where-Object { $_ }
    $rlStr = "◷ $($parts -join ' ')"
}

# --- Assemble three output lines ---
# sep  = internal section divider  (space │ space)
# tsep = trailing section divider  (space │)

$line1 = $location + $sep + $gitStr
if ($modelLabel) { $line1 += $sep + $modelColor + $modelLabel + $modelBadges + "$esc[0m" + $tsep }

$line2 = ""
if ($winStr) { $line2  = "$winBg$winStr$esc[0m" }
if ($rlStr) {
    if ($line2) { $line2 += $sep }
    $line2 += $rlColor + $rlStr + "$esc[0m"
}
if ($line2)  { $line2 += $tsep }

$line3 = ""
$tokenArr = @($inStr, $outStr, $tinStr, $toutStr) | Where-Object { $_ }
$tokenParts = $tokenArr -join " "
if ($tokenParts) {
    if ($line3) { $line3 += $sep }
    $line3 += "$esc[45m$esc[1;30m⬡ $tokenParts$esc[0m"
}
$cacheArr = @($ccStr, $crStr) | Where-Object { $_ }
$cacheParts = $cacheArr -join " "
if ($cacheParts) {
    if ($line3) { $line3 += $sep }
    $line3 += "$esc[100m$esc[1;37m⚡ $cacheParts$esc[0m"
    if ($effStr) { $line3 += " $effColor$effStr$esc[0m" }
}
$costArr = @()
if ($costStr)  { $costArr += "$ $costStr" }
if ($durStr)   { $costArr += $durStr }
if ($linesStr) { $costArr += $linesStr }
$costParts = $costArr -join " "
if ($costParts) {
    if ($line3) { $line3 += $sep }
    $line3 += "$esc[107m$esc[1m$esc[38;2;0;0;0m$costParts$esc[0m$tsep"
}

$output = $line1
if ($line2) { $output += "`n$line2" }
if ($line3) { $output += "`n$line3" }

[Console]::Out.Write($output)
