#!/usr/bin/env bash
#
# test-install.sh — smoke-test the aider-saia-gwdg installer.
#
# Runs src/add-saia-aider.sh against a throwaway HOME / AIDER_CONFIG_FILE so it
# never touches ~/.aider.conf.yml and never installs aider (aider is assumed
# present). Verifies the generated config points at the GWDG SAIA base URL with
# the right key and default model, and that the fake SAIA endpoint answers.
#
#   bash test/test-install.sh
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

WORK="$(mktemp -d)"
export HOME="$WORK/home"
export AIDER_CONFIG_FILE="$WORK/aider.conf.yml"
mkdir -p "$HOME"

cleanup() {
  [[ -n "${FAKE_PID:-}" ]] && kill "$FAKE_PID" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# ── Start the fake SAIA ──────────────────────────────────────────────
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
