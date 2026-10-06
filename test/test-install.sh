#!/usr/bin/env bash
#
# test-install.sh — smoke-test the aider-saia-gwdg installer.
#
# Runs src/add-saia-aider.sh against a throwaway HOME / AIDER_CONFIG_FILE so it
# never touches ~/.aider.conf.yml and never installs aider (aider is assumed
# present). Verifies the generated config points at the GWDG SAIA base URL with
# the right key and default model, and that the fake SAIA endpoint answers.
# Then checks the automatic key swap: with two keys, the first one revoked,
# aider is pointed at the local saia-keyring proxy and a request through it
# fails over to the second key. The proxy is started with
# SAIA_KEYRING_SERVICE=none, so no systemd unit or real shell rc is touched.
#
#   bash test/test-install.sh
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

WORK="$(mktemp -d)"
export HOME="$WORK/home"
export AIDER_CONFIG_FILE="$WORK/aider.conf.yml"
export SAIA_KEYRING_SERVICE=none
mkdir -p "$HOME"

cleanup() {
  [[ -n "${FAKE_PID:-}" ]] && kill "$FAKE_PID" 2>/dev/null || true
  if [[ -n "${KR_PORT:-}" ]]; then
    curl -s "http://127.0.0.1:$KR_PORT/_keyring/health" \
      | python3 -c 'import json,os,sys; os.kill(json.load(sys.stdin)["pid"], 15)' 2>/dev/null || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

# ── Start the fake SAIA ──────────────────────────────────────────────
FAKE_DEAD_KEYS=dead-key SEEN_FILE="$WORK/seen" COUNT_FILE="$WORK/count" \
  python3 ./fake-saia.py >"$WORK/port" 2>"$WORK/fake.log" &
FAKE_PID=$!
for _ in $(seq 40); do [[ -s "$WORK/port" ]] && break; sleep 0.1; done
PORT="$(cat "$WORK/port")"
[[ -n "$PORT" ]] || { echo "FAIL: fake-saia did not start" >&2; cat "$WORK/fake.log" >&2; exit 1; }
echo "fake-saia on port $PORT"

# ── Run the installer source against the fake ────────────────────────
# Point the base URL at the fake by overriding via a wrapper is not supported,
# so we run the real script with a dummy key and check the config it writes.
SAIA_API_KEY=dummy bash ../src/add-saia-aider.sh >"$WORK/install.log" 2>&1 || {
  echo "FAIL: add-saia-aider.sh exited non-zero" >&2
  cat "$WORK/install.log" >&2
  exit 1
}

fail() { echo "FAIL: $1" >&2; echo "--- config ---" >&2; cat "$AIDER_CONFIG_FILE" >&2; exit 1; }

[[ -f "$AIDER_CONFIG_FILE" ]] || fail "config file not written"
grep -q "openai-api-base: https://chat-ai.academiccloud.de/v1" "$AIDER_CONFIG_FILE" \
  || fail "base URL missing"
grep -q "openai-api-key: dummy" "$AIDER_CONFIG_FILE" \
  || fail "API key missing"
grep -q "model: openai/deepseek-v4-flash-0731" "$AIDER_CONFIG_FILE" \
  || fail "default model missing"
grep -q "openai/qwen3-coder-next" "$AIDER_CONFIG_FILE" \
  || fail "model list not written"

# ── Verify the fake endpoint answers (models list) ───────────────────
MODELS_JSON="$(curl -s -H "Authorization: Bearer dummy" "http://127.0.0.1:$PORT/v1/models")"
echo "$MODELS_JSON" | grep -q "fake-model" || fail "fake endpoint did not list models"

echo "PASS: config written with base URL, key, default model, and model list"
echo "      fake SAIA endpoint answered /v1/models"

# ── SAIA_BASE_URL override (used by the benchmark's local gateway) ─────
OV="$WORK/override"; mkdir -p "$OV/home"
HOME="$OV/home" AIDER_CONFIG_FILE="$OV/aider.conf.yml" SAIA_BASE_URL="http://127.0.0.1:$PORT/v1" \
  SAIA_API_KEY=dummy bash ../src/add-saia-aider.sh >"$WORK/override.log" 2>&1 \
  || fail "installer failed with SAIA_BASE_URL set"
grep -qx "openai-api-base: http://127.0.0.1:$PORT/v1" "$OV/aider.conf.yml" \
  || fail "SAIA_BASE_URL not written to the aider config"
echo "PASS: SAIA_BASE_URL override"

# ── Extra keys without --keyring: SAIA directly, no proxy (opt-in only) ─
NK="$WORK/nokeyring"; mkdir -p "$NK/home"
HOME="$NK/home" AIDER_CONFIG_FILE="$NK/aider.conf.yml" SAIA_API_KEYS_EXTRA=extra-key \
  SAIA_API_KEY=dummy bash ../src/add-saia-aider.sh >"$WORK/nokeyring.log" 2>&1 \
  || { cat "$WORK/nokeyring.log" >&2; fail "installer failed with extra keys but no --keyring"; }
grep -qx "openai-api-base: https://chat-ai.academiccloud.de/v1" "$NK/aider.conf.yml" \
  || fail "extra keys alone pointed aider away from SAIA"
[[ ! -e "$NK/home/.config/saia-keyring" ]] || fail "keyring set up without --keyring"
grep -q "opt-in (add --keyring)" "$WORK/nokeyring.log" || fail "no note about the unused extra keys"
echo "PASS: extra keys without --keyring: direct to SAIA, no proxy"

# ── Automatic key swap: two keys, the first one revoked ───────────────
KR="$WORK/keyring"; mkdir -p "$KR/home"
KR_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
HOME="$KR/home" AIDER_CONFIG_FILE="$KR/aider.conf.yml" SAIA_KEYRING_PORT="$KR_PORT" \
  SAIA_BASE_URL="http://127.0.0.1:$PORT/v1" SAIA_API_KEY=dead-key \
  bash ../src/add-saia-aider.sh --keyring --extra-keys good-key >"$WORK/keyring.log" 2>&1 \
  || { cat "$WORK/keyring.log" >&2; fail "installer failed with --keyring"; }
grep -qx "openai-api-base: http://127.0.0.1:$KR_PORT/v1" "$KR/aider.conf.yml" \
  || { cat "$WORK/keyring.log" >&2; fail "aider config not pointed at the keyring proxy"; }
grep -qx "openai-api-key: dead-key" "$KR/aider.conf.yml" \
  || fail "aider config must keep the primary key"
KR_CFG="$KR/home/.config/saia-keyring/keyring.json"
[[ "$(python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$KR_CFG")" == 0o600 ]] \
  || fail "keyring.json is not chmod 600"
: >"$WORK/seen"
CODE="$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer dead-key" \
  "http://127.0.0.1:$KR_PORT/v1/models")"
[[ "$CODE" == 200 ]] || fail "request through the keyring proxy returned $CODE"
[[ "$(paste -sd, "$WORK/seen")" == "dead-key,good-key" ]] \
  || fail "proxy did not fail over from the revoked key (saw: $(paste -sd, "$WORK/seen"))"
echo "PASS: automatic key swap (revoked key -> next key through the local proxy)"
