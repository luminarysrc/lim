#!/usr/bin/env bash
# Unit tests for the response parsers. Run: bash tests/test.sh

# shellcheck source=SCRIPTDIR/../package/contents/code/ai-limits.sh
source "$(dirname "$0")/../package/contents/code/ai-limits.sh"

failures=0

expect() {
  local name=$1 expected=$2 actual=$3
  if [[ $actual == "$expected" ]]; then
    echo "ok    $name"
  else
    printf 'FAIL  %s\n      expected: %s\n      actual:   %s\n' "$name" "$expected" "$actual"
    failures=$((failures + 1))
  fi
}

expect "claude: known windows, empty ones skipped" \
  '[{"label":"5h","used":42,"resets_at":1761141600,"group":"5h"},{"label":"7d","used":7,"resets_at":1761555600,"group":"7d"}]' \
  "$(parse_claude <<< '{
    "five_hour": {"utilization": 42.0, "resets_at": "2025-10-22T14:00:00.123456+00:00"},
    "seven_day": {"utilization": 7.4, "resets_at": "2025-10-27T09:00:00Z"},
    "seven_day_opus": null,
    "seven_day_sonnet": {"utilization": null, "resets_at": null}}')"

expect "codex: primary and secondary windows, usage capped at 100" \
  '[{"label":"5h","used":27,"resets_at":2000000000,"group":"5h"},{"label":"7d","used":100,"resets_at":2000500000,"group":"7d"}]' \
  "$(parse_codex <<< '{"plan_type": "plus", "rate_limit": {
    "primary_window": {"used_percent": 27, "limit_window_seconds": 18000, "reset_at": 2000000000},
    "secondary_window": {"used_percent": 105, "limit_window_seconds": 604800, "reset_at": 2000500000}}}')"

expect "codex: no rate limit" '[]' "$(parse_codex <<< '{"rate_limit": null}')"

expect "antigravity: grouped by model id, Gemini first, missing fraction means exhausted" \
  '[{"label":"Gemini 3 Pro","used":20,"resets_at":1763632800,"group":"Gemini"},{"label":"Gemini Flash","used":0,"resets_at":1763632800,"group":"Gemini"},{"label":"Claude Sonnet","used":100,"resets_at":1763632800,"group":"Claude / GPT-OSS"},{"label":"GPT-OSS 120B (Medium)","used":0,"resets_at":1763632800,"group":"Claude / GPT-OSS"}]' \
  "$(parse_antigravity <<< '{"userStatus": {"cascadeModelConfigData": {"clientModelConfigs": [
    {"label": "Gemini 3 Pro", "modelId": "gemini-3-pro", "quotaInfo": {"remainingFraction": 0.8, "resetTime": "2025-11-20T10:00:00Z"}},
    {"label": "Claude Sonnet", "modelId": "claude-sonnet-4-6", "quotaInfo": {"resetTime": "2025-11-20T10:00:00Z"}},
    {"label": "GPT-OSS 120B (Medium)", "modelId": "gpt-oss-120b-medium", "quotaInfo": {"remainingFraction": 1, "resetTime": "2025-11-20T10:00:00Z"}},
    {"label": "Gemini Flash", "quotaInfo": {"remainingFraction": 1, "resetTime": "2025-11-20T10:00:00Z"}},
    {"label": "No quota model"}]}}}')"

args=(/opt/antigravity/language_server_linux_x64 --csrf_token abc --app_data_dir=antigravity)
expect "flag: --name value" abc "$(flag --csrf_token "${args[@]}")"
expect "flag: --name=value" antigravity "$(flag --app_data_dir "${args[@]}")"
expect "flag: missing" "" "$(flag --missing "${args[@]}")"

expect "ports: only LISTEN sockets of the process" 41394 "$(ports_in_table 111 222 << 'EOF'
  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 0100007F:A1B2 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 111
   1: 0100007F:1F90 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 999
   2: 0100007F:C350 0100007F:A1B2 01 00000000:00000000 00:00000000 00000000  1000        0 222
EOF
)"

# shellcheck disable=SC2317 # called indirectly by collect
fetch_fails() { die "Not signed in"; }
NAMES[fails]="Failing"
expect "collect: provider errors are reported, not raised" \
  '{"id":"fails","name":"Failing","limits":[],"error":"Not signed in"}' "$(collect fails)"

# Panel ring logic (QML/JS), needs Qt 6's qmltestrunner.
qmltestrunner=/usr/lib/qt6/bin/qmltestrunner
[[ -x $qmltestrunner ]] || qmltestrunner=qmltestrunner6
if QT_QPA_PLATFORM=offscreen "$qmltestrunner" -input "$(dirname "$0")/tst_rings.qml" > /dev/null 2>&1; then
  echo "ok    rings: tst_rings.qml"
else
  echo "FAIL  rings: tst_rings.qml (run: $qmltestrunner -input tests/tst_rings.qml)"
  failures=$((failures + 1))
fi

exit $((failures > 0))
