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

# ── read_session_cache_stats tests ────────────────────────
TMPDIR_TEST=$(mktemp -d)
TRANSCRIPT="$TMPDIR_TEST/session.jsonl"

cat > "$TRANSCRIPT" <<'EOF'
{"type":"user","message":{"role":"user","content":"hello"}}
{"type":"assistant","timestamp":"2026-05-16T10:00:00.000Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":100,"cache_creation_input_tokens":5000,"cache_read_input_tokens":0,"output_tokens":50,"cache_creation":{"ephemeral_1h_input_tokens":5000,"ephemeral_5m_input_tokens":0}}}}
{"type":"assistant","timestamp":"2026-05-16T10:05:00.000Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":18000,"output_tokens":80,"cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0}}}}
{"type":"assistant","timestamp":"2026-05-16T10:10:00.000Z","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":20,"cache_creation_input_tokens":2000,"cache_read_input_tokens":22000,"output_tokens":60,"cache_creation":{"ephemeral_1h_input_tokens":2000,"ephemeral_5m_input_tokens":0}}}}
EOF

read_session_cache_stats "$TRANSCRIPT"
assert_eq "sess_reads"   "$sess_reads"   "40000"
assert_eq "sess_writes"  "$sess_writes"  "7000"
assert_eq "sess_inputs"  "$sess_inputs"  "170"
assert_eq "last_1h_iso"  "$last_1h_iso"  "2026-05-16T10:10:00.000Z"
assert_eq "last_5m_iso"  "$last_5m_iso"  ""

read_session_cache_stats "/nonexistent/path.jsonl"
assert_eq "missing file reads"  "$sess_reads"  "0"
assert_eq "missing file writes" "$sess_writes" "0"

read_session_cache_stats ""
assert_eq "empty path reads"  "$sess_reads"  "0"

rm -rf "$TMPDIR_TEST"

# ── read_all_sessions_cache_stats tests ───────────────────
TMPDIR_ALL=$(mktemp -d)

mkdir -p "$TMPDIR_ALL/.claude/projects/proj-a" "$TMPDIR_ALL/.claude/projects/proj-b"
cat > "$TMPDIR_ALL/.claude/projects/proj-a/sess1.jsonl" <<'EOF'
{"type":"assistant","timestamp":"2026-05-16T09:00:00.000Z","message":{"usage":{"input_tokens":200,"cache_creation_input_tokens":10000,"cache_read_input_tokens":5000,"output_tokens":100}}}
EOF
cat > "$TMPDIR_ALL/.claude/projects/proj-b/sess2.jsonl" <<'EOF'
{"type":"assistant","timestamp":"2026-05-16T10:00:00.000Z","message":{"usage":{"input_tokens":50,"cache_creation_input_tokens":3000,"cache_read_input_tokens":30000,"output_tokens":40}}}
EOF

# Delete any stale /tmp/claude/cache-all-stats.json so we force a refresh
rm -f /tmp/claude/cache-all-stats.json

HOME="$TMPDIR_ALL" read_all_sessions_cache_stats
assert_eq "all_reads"  "$all_reads"  "35000"
assert_eq "all_writes" "$all_writes" "13000"
assert_eq "all_inputs" "$all_inputs" "250"

rm -rf "$TMPDIR_ALL"

# ── build_cache_lines integration test ────────────────────
TMPDIR_BL=$(mktemp -d)
BL_TRANSCRIPT="$TMPDIR_BL/sess.jsonl"
NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat > "$BL_TRANSCRIPT" <<EOF
{"type":"assistant","timestamp":"${NOW_ISO}","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":100,"cache_creation_input_tokens":5000,"cache_read_input_tokens":20000,"output_tokens":50,"cache_creation":{"ephemeral_1h_input_tokens":5000,"ephemeral_5m_input_tokens":0}}}}
EOF

mkdir -p "$TMPDIR_BL/.claude/projects/test"
cp "$BL_TRANSCRIPT" "$TMPDIR_BL/.claude/projects/test/sess.jsonl"
rm -f /tmp/claude/cache-all-stats.json

HOME="$TMPDIR_BL" build_cache_lines "$BL_TRANSCRIPT" "claude-sonnet-4-6" "0.05"

# Strip ANSI codes for assertion
plain=$(printf "%b" "$cache_lines" | sed 's/\x1b\[[0-9;]*m//g')

echo "$plain" | grep -q "session" && { echo "PASS: session line present"; PASS=$(( PASS + 1 )); } || \
    { echo "FAIL: session line missing"; FAIL=$(( FAIL + 1 )); }
echo "$plain" | grep -q "r:20k" && { echo "PASS: reads shown as 20k"; PASS=$(( PASS + 1 )); } || \
    { echo "FAIL: reads not 20k in: $plain"; FAIL=$(( FAIL + 1 )); }
echo "$plain" | grep -q "w:5k" && { echo "PASS: writes shown as 5k"; PASS=$(( PASS + 1 )); } || \
    { echo "FAIL: writes not 5k"; FAIL=$(( FAIL + 1 )); }
echo "$plain" | grep -q "hit:" && { echo "PASS: hit rate present"; PASS=$(( PASS + 1 )); } || \
    { echo "FAIL: hit rate missing"; FAIL=$(( FAIL + 1 )); }
echo "$plain" | grep -q "cache" && { echo "PASS: TTL line present"; PASS=$(( PASS + 1 )); } || \
    { echo "FAIL: TTL line missing"; FAIL=$(( FAIL + 1 )); }
echo "$plain" | grep -q "cost" && { echo "PASS: cost present"; PASS=$(( PASS + 1 )); } || \
    { echo "FAIL: cost missing"; FAIL=$(( FAIL + 1 )); }

rm -rf "$TMPDIR_BL"

echo ""; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
