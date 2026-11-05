#!/usr/bin/env bash
# Print the usage limits of AI coding assistants as JSON.
#
# Reads the credentials the official tools already keep on disk.
# Nothing is written and no tokens are refreshed. Needs curl and jq.
#
# Usage: ai-limits.sh [claude] [codex] [antigravity]

set -euo pipefail

PROVIDERS=(claude codex antigravity)
declare -A NAMES=([claude]="Claude Code" [codex]="Codex" [antigravity]="Antigravity")
USER_AGENT="ai-limits-plasmoid/1.0"

# Shared jq helpers: every provider is reduced to [{label, used, resets_at, group}].
# Limits with the same group share one quota (one section of the panel ring).
# shellcheck disable=SC2016 # jq code, not shell expansions
JQ_LIB='
  def epoch: if . then sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601 else null end;
  def window_name:
    if (. // 0) == 0 then "Limit"
    else (. / 3600 | round) as $h | if $h >= 24 and $h % 24 == 0 then "\($h / 24)d" else "\($h)h" end
    end;
  def limit($label; $used; $resets_at; $group):
    {label: $label, used: ([[$used, 0] | max, 100] | min | round), resets_at: $resets_at, group: $group};
'

die() {
  echo "$*" >&2
  exit 1
}

# GET/POST a URL and print the JSON body; extra arguments go to curl.
# Secrets are passed as `-H @<(...)` so they never appear in the process list.
http_json() {
  local response status
  response=$(curl -s --max-time 10 -A "$USER_AGENT" -w '\n%{http_code}' "$@" 2>/dev/null) || die "Service unreachable"
  status=${response##*$'\n'}
  case $status in
    2??) printf '%s\n' "${response%$'\n'*}" ;;
    401 | 403) die "Not authorized, sign in again" ;;
    *) die "HTTP error $status" ;;
  esac
}

# --- Claude Code -------------------------------------------------------------

fetch_claude() {
  local credentials=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json token expires_ms
  [[ -r $credentials ]] || die "Not signed in"
  token=$(jq -r '.claudeAiOauth.accessToken // empty' "$credentials")
  expires_ms=$(jq -r '.claudeAiOauth.expiresAt // 0' "$credentials")
  [[ -n $token ]] || die "Not signed in"
  ((expires_ms == 0 || expires_ms / 1000 > $(date +%s))) || die "Token expired, run claude to renew it"

  http_json https://api.anthropic.com/api/oauth/usage \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H @<(printf 'Authorization: Bearer %s\n' "$token") |
    parse_claude
}

parse_claude() {
  jq -c "$JQ_LIB"'
    . as $usage
    | [ {five_hour: "5h", seven_day: "7d", seven_day_opus: "7d · Opus", seven_day_sonnet: "7d · Sonnet"}
        | to_entries[] | .value as $label
        | $usage[.key] | select(.utilization != null)
        | limit($label; .utilization; .resets_at | epoch; $label) ]
  '
}

# --- Codex -------------------------------------------------------------------

fetch_codex() {
  local auth=${CODEX_HOME:-$HOME/.codex}/auth.json token account_id
  [[ -r $auth ]] || die "Not signed in"
  token=$(jq -r '.tokens.access_token // empty' "$auth")
  account_id=$(jq -r '.tokens.account_id // empty' "$auth")
  [[ -n $token ]] || die "Not signed in with ChatGPT"

  http_json https://chatgpt.com/backend-api/wham/usage \
    -H @<(printf 'Authorization: Bearer %s\n' "$token"; [[ -z $account_id ]] || printf 'ChatGPT-Account-Id: %s\n' "$account_id") |
    parse_codex
}

parse_codex() {
  jq -c "$JQ_LIB"'
    [ .rate_limit // {} | .primary_window, .secondary_window | select(.)
      | (.limit_window_seconds | window_name) as $label
      | limit($label; .used_percent // 0; .reset_at; $label) ]
  '
}

# --- Antigravity -------------------------------------------------------------

fetch_antigravity() {
  local pid token port response
  read -r pid token < <(find_language_server) || die "Antigravity is not running"

  for port in $(listening_ports "$pid"); do
    # The local language server uses a self-signed certificate, hence --insecure (loopback only).
    if response=$(http_json "https://127.0.0.1:$port/exa.language_server_pb.LanguageServerService/GetUserStatus" \
      --insecure --noproxy '*' --max-time 3 \
      -H "Content-Type: application/json" -H "Connect-Protocol-Version: 1" \
      -H @<(printf 'X-Codeium-Csrf-Token: %s\n' "$token") \
      -d '{"metadata": {"ideName": "antigravity", "extensionName": "antigravity", "locale": "en"}}' 2>/dev/null); then
      parse_antigravity <<< "$response"
      return
    fi
  done
  die "Language server is not responding"
}

parse_antigravity() {
  # protobuf JSON omits zero values, so a missing remainingFraction means nothing is left.
  # The API has no quota-group field: Gemini models share one quota, third-party models another.
  jq -c "$JQ_LIB"'
    def group:
      if (.modelId // "" | startswith("gemini")) or (.modelId == null and (.label // "" | startswith("Gemini")))
      then "Gemini" else "Claude / GPT-OSS" end;
    [ .userStatus.cascadeModelConfigData.clientModelConfigs[]? | select(.quotaInfo)
      | limit(.label // "Unknown"; (1 - (.quotaInfo.remainingFraction // 0)) * 100; .quotaInfo.resetTime | epoch; group) ]
    | sort_by(.group != "Gemini", .label)
  '
}

# Print "PID CSRF_TOKEN" of the running Antigravity language server.
find_language_server() {
  local cmdline args token
  for cmdline in /proc/[0-9]*/cmdline; do
    mapfile -d '' args < "$cmdline" 2>/dev/null || continue
    [[ ${args[0]-} == *language_server* ]] || continue
    [[ $(flag --app_data_dir "${args[@]}") == antigravity || ${args[0],,} == */antigravity/* ]] || continue
    token=$(flag --csrf_token "${args[@]}") || continue
    cmdline=${cmdline#/proc/}
    echo "${cmdline%/cmdline} $token"
    return
  done
  return 1
}

# Value of `--name value` or `--name=value` in a list of arguments.
flag() {
  local name=$1
  shift
  while (($#)); do
    case $1 in
      "$name") [[ $# -ge 2 ]] && echo "$2" && return ;;
      "$name"=*) echo "${1#*=}" && return ;;
    esac
    shift
  done
  return 1
}

# TCP ports a process listens on, read from /proc (no ss/lsof needed).
listening_ports() {
  local fd sockets=()
  for fd in /proc/"$1"/fd/*; do
    [[ $(readlink "$fd") =~ ^socket:\[([0-9]+)\]$ ]] && sockets+=("${BASH_REMATCH[1]}")
  done
  cat /proc/"$1"/net/tcp /proc/"$1"/net/tcp6 2>/dev/null | ports_in_table "${sockets[@]}"
}

# Read a /proc/net/tcp table on stdin, print LISTEN ports owned by the given socket inodes.
ports_in_table() {
  local _ address state inode
  while read -r _ address _ state _ _ _ _ _ inode _; do
    if [[ $state == 0A && " $* " == *" $inode "* ]]; then # 0A = TCP_LISTEN
      echo $((16#${address##*:}))
    fi
  done | sort -nu
}

# --- entry point -------------------------------------------------------------

collect() {
  local id=$1 output
  if output=$("fetch_$id" 2>&1); then
    jq -cn --arg id "$id" --arg name "${NAMES[$id]}" --argjson limits "${output:-[]}" '{$id, $name, $limits, error: null}'
  else
    [[ $output == jq:* || -z $output ]] && output="Unexpected response"
    jq -cn --arg id "$id" --arg name "${NAMES[$id]}" --arg error "$output" '{$id, $name, limits: [], $error}'
  fi
}

main() {
  local dependency id
  for dependency in curl jq; do
    command -v "$dependency" > /dev/null || die "ai-limits needs $dependency installed"
  done

  (($#)) || set -- "${PROVIDERS[@]}"
  for id; do
    [[ -v NAMES[$id] ]] || die "Unknown provider: $id. Choose from: ${PROVIDERS[*]}"
  done

  for id; do collect "$id"; done | jq -cs '{updated: (now | floor), providers: .}'
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
