#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUSLINE="$SCRIPT_DIR/../bin/statusline.sh"

# ── Inline deps from original script ──────────────────────
iso_to_epoch() {
    local iso_str="$1"
    local epoch stripped
    epoch=$(date -d "${iso_str}" +%s 2>/dev/null)
    [ -n "$epoch" ] && echo "$epoch" && return 0
    stripped="${iso_str%%.*}"; stripped="${stripped%%Z}"; stripped="${stripped%%+*}"
    stripped="${stripped%%-[0-9][0-9]:[0-9][0-9]}"
    if [[ "$iso_str" == *"Z"* ]] || [[ "$iso_str" == *"+00:00"* ]]; then
        epoch=$(env TZ=UTC date -d "${stripped/T/ }" +%s 2>/dev/null)
    else
        epoch=$(date -d "${stripped/T/ }" +%s 2>/dev/null)
    fi
    [ -n "$epoch" ] && echo "$epoch" && return 0
    return 1
}

red='\033[38;2;255;85;85m'; green='\033[38;2;0;175;80m'
orange='\033[38;2;255;176;85m'; yellow='\033[38;2;230;200;0m'
white='\033[38;2;220;220;220m'; dim='\033[2m'; reset='\033[0m'

color_for_pct() {
    local pct=$1
    if   [ "$pct" -ge 90 ]; then printf "$red"
    elif [ "$pct" -ge 70 ]; then printf "$yellow"
    elif [ "$pct" -ge 50 ]; then printf "$orange"
    else printf "$green"; fi
}

build_bar() {
    local pct=$1 width=$2 filled empty bar_color fs="" es=""
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100
    filled=$(( pct * width / 100 )); empty=$(( width - filled ))
    bar_color=$(color_for_pct "$pct")
    for ((i=0; i<filled; i++)); do fs+="●"; done
    for ((i=0; i<empty; i++)); do es+="○"; done
    printf "${bar_color}${fs}${dim}${es}${reset}"
}

# ── Source cache functions from statusline.sh ──────────────
eval "$(sed -n '/^# ── Cache metrics functions/,/^# ── End cache metrics functions/p' "$STATUSLINE")"

# ── Test framework ─────────────────────────────────────────
PASS=0; FAIL=0
assert_eq() {
    local desc="$1" got="$2" want="$3"
    if [ "$got" = "$want" ]; then
        echo "PASS: $desc"; PASS=$(( PASS + 1 ))
    else
        echo "FAIL: $desc"; echo "  got:  '$got'"; echo "  want: '$want'"; FAIL=$(( FAIL + 1 ))
    fi
}

# ── format_tokens tests ────────────────────────────────────
assert_eq "format 0"       "$(format_tokens 0)"       "0"
assert_eq "format 999"     "$(format_tokens 999)"     "999"
assert_eq "format 1000"    "$(format_tokens 1000)"    "1k"
assert_eq "format 45321"   "$(format_tokens 45321)"   "45k"
assert_eq "format 1000000" "$(format_tokens 1000000)" "1.0M"
assert_eq "format 1234567" "$(format_tokens 1234567)" "1.2M"
assert_eq "format empty"   "$(format_tokens '')"      "0"
assert_eq "format bad"     "$(format_tokens abc)"     "0"

echo ""; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
