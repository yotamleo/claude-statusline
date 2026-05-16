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
if ! declare -f format_tokens >/dev/null 2>&1; then
    echo "ERROR: failed to source cache functions from $STATUSLINE" >&2; exit 1
fi

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

# ── get_model_savings_rate tests ───────────────────────────
get_model_savings_rate "claude-sonnet-4-6"
assert_eq "sonnet read_savings_rate"   "$read_savings_rate"   "0.00000270"
assert_eq "sonnet write_overhead_rate" "$write_overhead_rate" "0.00000075"

get_model_savings_rate "claude-opus-4-7"
assert_eq "opus read_savings_rate"     "$read_savings_rate"   "0.00001350"
assert_eq "opus write_overhead_rate"   "$write_overhead_rate" "0.00000375"

get_model_savings_rate "claude-haiku-4-5"
assert_eq "haiku read_savings_rate"    "$read_savings_rate"   "0.00000072"
assert_eq "haiku write_overhead_rate"  "$write_overhead_rate" "0.00000020"

get_model_savings_rate "unknown-model"
assert_eq "fallback read_savings_rate" "$read_savings_rate"   "0.00000270"

# ── compute_cache_ttl tests ────────────────────────────────
NOW=$(date +%s)

# 1h cache: wrote 30 minutes ago → ~30m remaining, pct ~50%
WROTE_30M_AGO=$(date -d "@$(( NOW - 1800 ))" -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
    || date -u -r $(( NOW - 1800 )) +"%Y-%m-%dT%H:%M:%SZ")
compute_cache_ttl "$WROTE_30M_AGO" 3600
if [ "$cache_ttl_pct" -ge 45 ] && [ "$cache_ttl_pct" -le 55 ]; then
    echo "PASS: 1h cache 30m ago pct ~50% (got ${cache_ttl_pct}%)"; PASS=$(( PASS + 1 ))
else
    echo "FAIL: 1h cache 30m ago pct want 45-55%, got ${cache_ttl_pct}%"; FAIL=$(( FAIL + 1 ))
fi
if [ "$cache_ttl_str" != "expired" ] && [ -n "$cache_ttl_str" ]; then
    echo "PASS: 1h cache 30m ago not expired (got $cache_ttl_str)"; PASS=$(( PASS + 1 ))
else
    echo "FAIL: 1h cache 30m ago should not be expired, got '$cache_ttl_str'"; FAIL=$(( FAIL + 1 ))
fi

# 5m cache: wrote 6 minutes ago → expired
WROTE_6M_AGO=$(date -d "@$(( NOW - 360 ))" -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
    || date -u -r $(( NOW - 360 )) +"%Y-%m-%dT%H:%M:%SZ")
compute_cache_ttl "$WROTE_6M_AGO" 300
assert_eq "5m cache expired str" "$cache_ttl_str" "expired"
assert_eq "5m cache expired pct" "$cache_ttl_pct" "0"

# Empty ISO → silent skip (str stays empty)
compute_cache_ttl "" 3600
assert_eq "empty iso: ttl_str empty" "$cache_ttl_str" ""

# "null" ISO → silent skip
compute_cache_ttl "null" 3600
assert_eq "null iso: ttl_str empty" "$cache_ttl_str" ""

# Fresh write (2s ago) → pct >= 99
WROTE_2S_AGO=$(date -d "@$(( NOW - 2 ))" -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
    || date -u -r $(( NOW - 2 )) +"%Y-%m-%dT%H:%M:%SZ")
compute_cache_ttl "$WROTE_2S_AGO" 3600
if [ "$cache_ttl_pct" -ge 99 ]; then
    echo "PASS: fresh 1h write pct>=99 (got ${cache_ttl_pct}%)"; PASS=$(( PASS + 1 ))
else
    echo "FAIL: fresh write want pct>=99, got ${cache_ttl_pct}%"; FAIL=$(( FAIL + 1 ))
fi

echo ""; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
