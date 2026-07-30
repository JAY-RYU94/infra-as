#!/usr/bin/env bash
set -euo pipefail

umask 077

: "${AZP_URL:?AZP_URL is required}"
: "${AZP_POOL:?AZP_POOL is required}"
: "${AZP_AGENT_NAME:?AZP_AGENT_NAME is required}"
: "${AZP_TOKEN_FILE:?AZP_TOKEN_FILE is required}"

if [[ ! -r "${AZP_TOKEN_FILE}" ]]; then
  echo "Azure Pipelines PAT file is not readable: ${AZP_TOKEN_FILE}" >&2
  exit 1
fi

AZP_TOKEN="$(<"${AZP_TOKEN_FILE}")"
export VSO_AGENT_IGNORE="AZP_TOKEN,AZP_TOKEN_FILE"

agent_pid=""

remove_agent() {
  local exit_code=$?
  trap - EXIT INT TERM

  if [[ -n "${agent_pid}" ]] && kill -0 "${agent_pid}" 2>/dev/null; then
    kill -TERM "${agent_pid}" 2>/dev/null || true
    wait "${agent_pid}" 2>/dev/null || true
  fi

  if [[ -f .agent ]]; then
    for attempt in 1 2 3; do
      if ./config.sh remove \
        --unattended \
        --auth PAT \
        --token "${AZP_TOKEN}"; then
        break
      fi
      sleep "${attempt}"
    done
  fi

  exit "${exit_code}"
}

trap remove_agent EXIT INT TERM

./config.sh \
  --unattended \
  --acceptTeeEula \
  --url "${AZP_URL}" \
  --auth PAT \
  --token "${AZP_TOKEN}" \
  --pool "${AZP_POOL}" \
  --agent "${AZP_AGENT_NAME}" \
  --work "${AZP_WORK:-/azp/_work}" \
  --replace

./run.sh &
agent_pid=$!
wait "${agent_pid}"
