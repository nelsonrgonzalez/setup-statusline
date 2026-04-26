#!/usr/bin/env bash
# Claude Code statusline — macOS version (bash 3.2+ compatible).
# Claude Code pipes a JSON payload via stdin on every refresh (see refreshInterval
# in settings.json). All session data — model, context, cost, tokens, rate limits,
# git state — comes from that single payload. Nothing is fetched externally.
input=$(cat)
printf '%s\n' "$input" > /tmp/statusline-debug.json   # snapshot for debugging

# Format a raw integer as a compact human-readable string.
# Examples: 500 -> "500", 1500 -> "1.5k", 45000 -> "45k", 200000 -> "200k"
fmt_num() {
  local n="$1"
  if [ -z "$n" ] || [ "$n" -eq 0 ] 2>/dev/null; then
    echo ""
    return
  fi
  awk -v n="$n" 'BEGIN {
    if (n >= 1000) {
      v = n / 1000
      if (v == int(v)) printf "%dk", int(v)
      else              printf "%.1fk", v
    } else {
      printf "%d", n
    }
  }'
}

# Format milliseconds as a human-readable duration (s / m:s / h:m).
fmt_dur() {
  local ms="$1"
  awk -v ms="$ms" 'BEGIN {
    s = int(ms / 1000); m = int(s / 60); s = s % 60
    h = int(m / 60);   m = m % 60
    if      (h > 0 && m > 0) printf "%dh%dm", h, m
    else if (h > 0)           printf "%dh", h
    else if (m > 0 && s > 0) printf "%dm%ds", m, s
    else if (m > 0)           printf "%dm", m
    else                      printf "%ds", s
  }'
}

# Format seconds until reset as a countdown string (e.g. ↻2h14m, ↻3d6h).
fmt_reset() {
  local secs="$1"
  awk -v s="$secs" 'BEGIN {
    d = int(s / 86400); h = int((s % 86400) / 3600); m = int((s % 3600) / 60)
    if      (d > 0 && h > 0) printf "↻%dd%dh", d, h
    else if (d > 0)           printf "↻%dd", d
    else if (h > 0)           printf "↻%dh%dm", h, m
    else                      printf "↻%dm", m
  }'
}

# Convert a Unix epoch timestamp to local HH:MM (24-hour).
# macOS/BSD uses `date -r <epoch>` (not GNU date).
_localtime() { date -r "$1" "+%H:%M"; }

# Build a 10-block smooth progress bar using Unicode eighth-block characters.
# fill_color is an ANSI escape string (e.g. "\033[01;31m" for bright red).
# Empty blocks are dark gray █; partial blocks use a dark gray background to
# eliminate the visual gap that lighter shade characters (░) would introduce.
build_bar() {
  local pct="$1" fill_color="$2" width=10 bar="" i
  local full=0 eighth=0
  local empty_fg="\033[90m" partial_bg="\033[100m"
  read -r full eighth < <(awk -v p="$pct" 'BEGIN {
    f = p * 10 / 100
    full = int(f)
    printf "%d %d\n", full, int((f - full) * 8)
  }')
  for ((i=0; i<full; i++)); do bar="${bar}${fill_color}█"; done
  local partial=0
  if [ "$eighth" -gt 0 ] && [ "$full" -lt "$width" ]; then
    bar="${bar}${fill_color}${partial_bg}"
    case "$eighth" in
      1) bar="${bar}▏" ;; 2) bar="${bar}▎" ;; 3) bar="${bar}▍" ;;
      4) bar="${bar}▌" ;; 5) bar="${bar}▋" ;; 6) bar="${bar}▊" ;;
      7) bar="${bar}▉" ;;
    esac
    partial=1
  fi
  bar="${bar}${empty_fg}"
  for ((i=0; i<$((width - full - partial)); i++)); do bar="${bar}█"; done
  printf '%s\n' "$bar"
}

# Parse all 29 fields from the JSON payload in a single jq invocation.
# Field indices are referenced by number in the variable assignments below.
# Uses a while-loop instead of mapfile for bash 3.2 compatibility (macOS default shell).
_f=()
while IFS= read -r _jq_line; do
  _f+=("$_jq_line")
done < <(printf '%s\n' "$input" | jq -r '
  (.cwd // ""),                                                                    # [0]  working directory
  (.model.id // ""),                                                               # [1]  raw model id (e.g. claude-sonnet-4-6)
  (.model.display_name // ""),                                                     # [2]  human label (e.g. Sonnet 4.6)
  (if .context_window.used_percentage != null then (.context_window.used_percentage | tostring) else "" end),  # [3]  context % used
  (if (.context_window.current_usage | type) == "object" then "1" else "" end),   # [4]  "1" if per-turn token data is present
  ((.context_window.current_usage.input_tokens // 0) | tostring),                 # [5]  current-turn input tokens
  ((.context_window.current_usage.output_tokens // 0) | tostring),                # [6]  current-turn output tokens
  ((.context_window.current_usage.cache_creation_input_tokens // 0) | tostring),  # [7]  cache write tokens
  ((.context_window.current_usage.cache_read_input_tokens // 0) | tostring),      # [8]  cache read tokens
  ((.context_window.total_input_tokens // 0) | tostring),                         # [9]  session total input
  ((.context_window.total_output_tokens // 0) | tostring),                        # [10] session total output
  ((.context_window.context_window_size // 0) | tostring),                        # [11] context window capacity
  (.cost.total_cost_usd // ""),                                                    # [12] session cost in USD
  ((.cost.total_duration_ms // 0) | tostring),                                    # [13] total wall-clock duration ms
  ((.cost.total_api_duration_ms // 0) | tostring),                                # [14] API-only duration ms
  ((.cost.total_lines_added // 0) | tostring),                                    # [15] lines added this session
  ((.cost.total_lines_removed // 0) | tostring),                                  # [16] lines removed this session
  (if .rate_limits.five_hour.used_percentage != null then (.rate_limits.five_hour.used_percentage | round | tostring) else "" end),  # [17] 5h rate limit %
  (if .rate_limits.seven_day.used_percentage != null then (.rate_limits.seven_day.used_percentage | round | tostring) else "" end),  # [18] 7d rate limit %
  ((.rate_limits.five_hour.resets_at // 0) | tostring),                           # [19] 5h reset Unix timestamp
  ((.rate_limits.seven_day.resets_at // 0) | tostring),                           # [20] 7d reset Unix timestamp
  (if .fast_mode == true then "1" else "" end),                                   # [21] fast mode active
  (if .thinking.enabled == true then "1" else "" end),                            # [22] extended thinking active
  (.effort.level // ""),                                                           # [23] effort level (low/medium/high/xhigh/max)
  (if .exceeds_200k_tokens == true then "1" else "" end),                         # [24] context overflow flag
  ((.workspace.added_dirs // []) | length | tostring),                            # [25] number of extra workspace dirs
  (.session_name // ""),                                                           # [26] named session (if set)
  (.vim.mode // ""),                                                               # [27] vim mode (NORMAL/INSERT/VISUAL)
  (.workspace.project_dir // "")                                                  # [28] VS Code project root (may differ from cwd)
')

# Assign fields to named variables, grouped by concern.
# cu ("current usage") is "1" when per-turn token data is present in the payload.
cwd="${_f[0]}";        model_raw="${_f[1]}";     model_display="${_f[2]}"; ctx_pct="${_f[3]}";  cu="${_f[4]}"
_in="${_f[5]}";        _out="${_f[6]}";           _cc="${_f[7]}";           _cr="${_f[8]}"
_tin="${_f[9]}";       _tout="${_f[10]}";         _win="${_f[11]}";         _cost="${_f[12]}"
_dur="${_f[13]}";      _api_dur="${_f[14]}";      _lines_add="${_f[15]}";   _lines_rem="${_f[16]}"
_rl5h="${_f[17]}";     _rl7d="${_f[18]}";         _rl5h_reset="${_f[19]}";  _rl7d_reset="${_f[20]}"
_fast="${_f[21]}";     _think="${_f[22]}";        _effort="${_f[23]}";      _overflow="${_f[24]}"; _added_dirs="${_f[25]}"
_session_name="${_f[26]}"; _vim_mode="${_f[27]}"; _project_dir="${_f[28]}"

# Location: cwd with ~ substitution for home directory
if [ "$cwd" = "$HOME" ]; then
  display_cwd="~"
elif [ "${cwd#"$HOME/"}" != "$cwd" ]; then
  display_cwd="~/${cwd#"$HOME/"}"
else
  display_cwd="$cwd"
fi
location=$(printf "\033[44m\033[01;34m❯ %s\033[00m" "${display_cwd}")
[ -n "$_session_name" ] && location="${location}\033[44m\033[01;34m [${_session_name}]\033[00m"
[ "${_added_dirs:-0}" -gt 0 ] 2>/dev/null && location="${location}\033[44m\033[01;34m +${_added_dirs}\033[00m"
if [ -n "$_project_dir" ] && [ "$_project_dir" != "$cwd" ]; then
  location="${location}\033[44m\033[02;34m ↑${_project_dir##*/}\033[00m"
fi

# Model color, display label, and active mode badges
model_short="${model_raw#claude-}"
model_label="${model_display:-$model_short}"
case "$model_raw" in
  *opus*)  model_color="\033[01;33m" ;;
  *haiku*) model_color="\033[01;32m" ;;
  *)       model_color="\033[01;36m" ;;
esac
model_badges=""
[ -n "$_think" ] && model_badges="${model_badges} \033[01;35m💡\033[00m"
[ -n "$_fast"  ] && model_badges="${model_badges} \033[01;37m⚡\033[00m"
case "$_effort" in
  max)    model_badges="${model_badges} \033[01;37m\033[41m𐄝\033[00m" ;;
  xhigh)  model_badges="${model_badges} \033[01;31m𐄜\033[00m" ;;
  high)   model_badges="${model_badges} \033[01;31m𐄛\033[00m" ;;
  medium) model_badges="${model_badges} \033[01;33m𐄚\033[00m" ;;
  low)    model_badges="${model_badges} \033[02;37m𐄙\033[00m" ;;
esac
case "$_vim_mode" in
  NORMAL)        model_badges="${model_badges} \033[01;32mN\033[00m" ;;
  INSERT)        model_badges="${model_badges} \033[01;33mI\033[00m" ;;
  VISUAL)        model_badges="${model_badges} \033[01;35mV\033[00m" ;;
  "VISUAL LINE") model_badges="${model_badges} \033[01;35mVL\033[00m" ;;
esac

# Context bar thresholds
if [ -n "$ctx_pct" ]; then
  ctx_val=$(printf '%.0f' "$ctx_pct")
  if [ "$ctx_val" -ge 80 ]; then
    fill_color="\033[01;31m"; win_bg="\033[101m\033[01;37m"; bar_icon="⚠"
  elif [ "$ctx_val" -ge 75 ]; then
    fill_color="\033[01;31m"; win_bg="\033[40m\033[01;37m";  bar_icon="⛁"
  elif [ "$ctx_val" -ge 65 ]; then
    fill_color="\033[01;33m"; win_bg="\033[40m\033[01;37m";  bar_icon="⛁"
  else
    fill_color="\033[01;32m"; win_bg="\033[40m\033[01;37m";  bar_icon="⛀"
  fi
else
  fill_color="\033[01;32m"; win_bg="\033[40m\033[01;37m"; bar_icon="⛀"
fi

if [ -n "$cu" ]; then
  in_str=$(fmt_num "$_in");   [ -n "$in_str"  ] && in_str="↓${in_str}"
  out_str=$(fmt_num "$_out"); [ -n "$out_str" ] && out_str="↑${out_str}"
  cc_str=$(fmt_num "$_cc");   [ -n "$cc_str"  ] && cc_str="⊕${cc_str}"
  cr_str=$(fmt_num "$_cr");   [ -n "$cr_str"  ] && cr_str="↻${cr_str}"
else
  in_str=""; out_str=""; cc_str=""; cr_str=""
fi

_total_cache=$(( ${_cc:-0} + ${_cr:-0} ))
if [ "$_total_cache" -gt 0 ] 2>/dev/null; then
  _eff=$(awk -v cr="${_cr:-0}" -v tot="$_total_cache" 'BEGIN { printf "%.0f", cr / tot * 100 }')
  eff_str="♻${_eff}%"
  if   [ "$_eff" -ge 70 ]; then eff_color="\033[01;32m"
  elif [ "$_eff" -ge 40 ]; then eff_color="\033[43m\033[01;33m"
  else                          eff_color="\033[41m\033[01;31m"
  fi
else
  eff_str=""; eff_color=""
fi

tin_str=$(fmt_num "$_tin");   [ -n "$tin_str"  ] && tin_str="Σ↓${tin_str}"
tout_str=$(fmt_num "$_tout"); [ -n "$tout_str" ] && tout_str="Σ↑${tout_str}"

if [ -n "$_cost" ] && awk -v c="$_cost" 'BEGIN { exit (c > 0 ? 0 : 1) }'; then
  cost_str=$(awk -v c="$_cost" 'BEGIN {
    if      (c >= 1.0)  printf "%.2f", c
    else if (c >= 0.1)  printf "%.3f", c
    else if (c >= 0.01) printf "%.4f", c
    else                printf "%.5f", c
  }')
else
  cost_str=""
fi

dur_str=""
if { [ "${_api_dur:-0}" -gt 0 ] || [ "${_dur:-0}" -gt 0 ]; } 2>/dev/null; then
  if [ "${_api_dur:-0}" -gt 0 ] 2>/dev/null; then
    dur_str="⧗ $(fmt_dur "$_api_dur")╱$(fmt_dur "$_dur")"
  else
    dur_str="⧗ $(fmt_dur "$_dur")"
  fi
fi

lines_str=""
if { [ "${_lines_add:-0}" -gt 0 ] || [ "${_lines_rem:-0}" -gt 0 ]; } 2>/dev/null; then
  lines_str="∆"
  [ "${_lines_add:-0}" -gt 0 ] && lines_str="${lines_str} \033[32m+${_lines_add}\033[30m"
  [ "${_lines_rem:-0}" -gt 0 ] && lines_str="${lines_str} \033[31m-${_lines_rem}\033[30m"
fi

rl_str=""
rl_color=""
if [ -n "$_rl5h" ] || [ -n "$_rl7d" ]; then
  _rl_max=$(awk -v a="${_rl5h:-0}" -v b="${_rl7d:-0}" 'BEGIN { printf "%d", (a > b ? a : b) }')
  if   [ "$_rl_max" -ge 90 ] 2>/dev/null; then rl_color="\033[41m\033[01;37m"
  elif [ "$_rl_max" -ge 70 ] 2>/dev/null; then rl_color="\033[43m\033[01;30m"
  else                                          rl_color="\033[01;32m"
  fi
  now=$(date +%s)
  rl5h_part=""
  if [ -n "$_rl5h" ]; then
    rl5h_part="5h:${_rl5h}%"
    if [ "${_rl5h_reset:-0}" -gt 0 ] 2>/dev/null; then
      _5h_in=$(( _rl5h_reset - now ))
      [ "$_5h_in" -gt 0 ] && rl5h_part="${rl5h_part} [$(fmt_reset "$_5h_in") @$(_localtime "${_rl5h_reset}")]"
    fi
  fi
  rl7d_part=""
  if [ -n "$_rl7d" ]; then
    rl7d_part="7d:${_rl7d}%"
    if [ "${_rl7d_reset:-0}" -gt 0 ] 2>/dev/null; then
      _7d_in=$(( _rl7d_reset - now ))
      [ "$_7d_in" -gt 0 ] && rl7d_part="${rl7d_part} [$(fmt_reset "$_7d_in")]"
    fi
  fi
  rl_parts="${rl5h_part}${rl7d_part:+ ${rl7d_part}}"
  rl_str="◷ ${rl_parts}"
fi

if [ -n "$ctx_pct" ] && [ "${_win:-0}" -gt 0 ] 2>/dev/null; then
  _used=$(awk -v p="$ctx_pct" -v w="$_win" 'BEGIN { printf "%d", int(p * w / 100) }')
  used_fmt=$(fmt_num "$_used")
  win_fmt=$(fmt_num "$_win")
  if [ -n "$_overflow" ]; then
    win_bg="\033[101m\033[01;37m"
    win_str="⛔ ${used_fmt}╱${win_fmt} OVERFLOW"
  else
    bar=$(build_bar "${ctx_val:-0}" "$fill_color")
    win_str="${bar_icon} ${bar}\033[00m\033[40m\033[01;37m ${used_fmt}╱${win_fmt} (${ctx_val}%)"
  fi
else
  win_str=$(fmt_num "$_win")
  [ -n "$win_str" ] && win_str="${bar_icon} ${win_str}"
fi

if [ -n "$cwd" ] && git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  _branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
  _git_out=$(git -C "$cwd" status --short 2>/dev/null)
  read -r _gstaged _gmodified _guntracked < <(printf '%s\n' "$_git_out" | awk '
    /^[MADRCU]/ { s++ }
    /^ [MD]/    { m++ }
    /^\?\?/     { u++ }
    END { printf "%d %d %d\n", s+0, m+0, u+0 }
  ')
  git_str="\033[01;37m⎇ ${_branch:-HEAD}\033[00m"
  [ "$_gstaged"    -gt 0 ] && git_str="${git_str} \033[01;32m+${_gstaged}\033[00m"
  [ "$_gmodified"  -gt 0 ] && git_str="${git_str} \033[01;33m~${_gmodified}\033[00m"
  [ "$_guntracked" -gt 0 ] && git_str="${git_str} \033[02;37m?${_guntracked}\033[00m"
else
  git_str="\033[02;37m⎇ —\033[00m"
fi

sep="\033[00m \033[02;37m│\033[00m "
tsep=" \033[02;37m│\033[00m"

line1="$location"
line1="${line1}${sep}${git_str}"
[ -n "$model_label" ] && line1="${line1}${sep}${model_color}${model_label}${model_badges}\033[00m${tsep}"

line2=""
[ -n "$win_str" ] && line2="${win_bg}${win_str}\033[00m"
[ -n "$rl_str"  ] && line2="${line2:+${line2}${sep}}${rl_color}${rl_str}\033[00m"
[ -n "$line2"   ] && line2="${line2}${tsep}"

line3=""
token_parts=""
[ -n "$in_str" ]   && token_parts="${token_parts:+${token_parts} }${in_str}"
[ -n "$out_str" ]  && token_parts="${token_parts:+${token_parts} }${out_str}"
[ -n "$tin_str" ]  && token_parts="${token_parts:+${token_parts} }${tin_str}"
[ -n "$tout_str" ] && token_parts="${token_parts:+${token_parts} }${tout_str}"
[ -n "$token_parts" ] && line3="${line3:+${line3}${sep}}\033[45m\033[01;35m⬡ ${token_parts}\033[00m"
cache_parts=""
[ -n "$cc_str" ] && cache_parts="${cache_parts:+${cache_parts} }${cc_str}"
[ -n "$cr_str" ] && cache_parts="${cache_parts:+${cache_parts} }${cr_str}"
if [ -n "$cache_parts" ]; then
  line3="${line3:+${line3}${sep}}\033[100m\033[01;37m⚡ ${cache_parts}\033[00m"
  [ -n "$eff_str" ] && line3="${line3} ${eff_color}${eff_str}\033[00m"
fi
if [ -n "$cost_str" ] || [ -n "$dur_str" ] || [ -n "$lines_str" ]; then
  _cparts=""
  [ -n "$cost_str"  ] && _cparts="${_cparts:+${_cparts} }$ ${cost_str}"
  [ -n "$dur_str"   ] && _cparts="${_cparts:+${_cparts} }${dur_str}"
  [ -n "$lines_str" ] && _cparts="${_cparts:+${_cparts} }${lines_str}"
  line3="${line3:+${line3}${sep}}\033[107m\033[30m${_cparts}\033[00m${tsep}"
fi

output="$line1"
[ -n "$line2" ] && output="${output}\n${line2}"
[ -n "$line3" ] && output="${output}\n${line3}"
printf "%b" "$output"
