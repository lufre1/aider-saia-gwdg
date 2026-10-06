#!/usr/bin/env bash
set -euo pipefail

# Base URL override for tests and local gateways (default: production SAIA).
SAIA_BASE_URL="${SAIA_BASE_URL:-https://chat-ai.academiccloud.de/v1}"

# add-saia-aider.sh — Add GWDG SAIA provider to aider
#
# Reads SAIA API key from environment variable SAIA_API_KEY or --key/--key-file.
# Installs aider if missing (via the official installer), then writes
# ~/.aider.conf.yml pointing aider at the GWDG SAIA OpenAI-compatible API.
#
# Usage:
#   SAIA_API_KEY="your-key" ./add-saia-aider.sh
#   ./add-saia-aider.sh --key "your-key"
#   ./add-saia-aider.sh --key-file ~/.local/share/opencode/auth.json
#   SAIA_API_KEYS_EXTRA="key2,key3" ./add-saia-aider.sh --key "your-key" --keyring
#
# The API key is written to ~/.aider.conf.yml (chmod 600). aider's YAML config
# accepts the OpenAI-style key directly, which is what the SAIA endpoint uses.
#
# With --keyring (opt-in) and extra keys (SAIA_API_KEYS_EXTRA / --extra-keys /
# --extra-keys-file) aider is pointed at the local saia-keyring proxy instead,
# which swaps to the next key when the active one is revoked, drained or rate
# limited (saia-keyring.sh).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_FILE="${SCRIPT_DIR}/models.txt"
# shellcheck source=saia-keyring.sh
source "${SCRIPT_DIR}/saia-keyring.sh"

# ── Parse arguments ──────────────────────────────────────────────────
ASSUME_YES=0
KEY=""
KEY_FILE=""
SAIA_KEY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --key)
      KEY="$2"
      shift 2
      ;;
    -y|--yes)
      ASSUME_YES=1
      shift
      ;;
    --key-file)
      KEY_FILE="$2"
      shift 2
      ;;
    --extra-keys|--extra-keys-file|--keyring|--no-keyring)
      keyring_arg "$@"
      shift "$KEYRING_SHIFT"
      ;;
    -h|--help)
      echo "Usage: SAIA_API_KEY=... ./add-saia-aider.sh [--key <key> | --key-file <path>]"
      echo ""
      echo "Options:"
      echo "  --key <value>       SAIA API key (overrides SAIA_API_KEY env)"
      echo "  --key-file <path>   File containing the SAIA API key"
      echo "  -y, --yes           Install the agent without asking (for non-TTY runs)"
      keyring_usage
      echo "  -h, --help          Show this help"
      echo ""
      echo "The API key is taken from:"
      echo "  1. --key <value> argument (if provided)"
      echo "  2. SAIA_API_KEY environment variable (if set)"
      echo "  3. --key-file <path> (reads first line)"
      echo "  4. the key stored by a previous install, if any"
      echo "  5. an interactive prompt, if none of the above is set"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# Pull the key out of a previous install so a reinstall does not ask again.
key_from_config() {
  local cfg="${AIDER_CONFIG_FILE:-$HOME/.aider.conf.yml}"
  [[ -f "$cfg" ]] || return 0
  awk '/^openai-api-key:/{print $2;exit}' "$cfg"
  return 0
}

prompt_for_key() {
  if ! { : </dev/tty; } 2>/dev/null; then   # -r only stats; this actually opens it
    echo "ERROR: No SAIA API key given and no terminal to ask on." >&2
    echo "Set it: SAIA_API_KEY=\"your-key\" ./add-saia-aider.sh" >&2
    echo "Get one at https://chat-ai.academiccloud.de/" >&2
    exit 1
  fi
  local key=""
  for _ in 1 2 3; do
    read -rsp "GWDG SAIA API key (input hidden): " key </dev/tty
    echo >&2
    key="${key//[[:space:]]/}"   # paste hygiene; SAIA keys carry no whitespace
    if [[ -n "$key" ]]; then
      export SAIA_API_KEY="$key"
      return
    fi
    echo "Key cannot be empty." >&2
  done
  echo "ERROR: no key entered." >&2
  exit 1
}

# ── Obtain API key ───────────────────────────────────────────────────
if [[ -n "$KEY" ]]; then
  SAIA_KEY="$KEY"
elif [[ -n "${SAIA_API_KEY:-}" ]]; then
  SAIA_KEY="$SAIA_API_KEY"
elif [[ -n "$KEY_FILE" ]]; then
  if [[ ! -f "$KEY_FILE" ]]; then
    echo "ERROR: Key file not found: $KEY_FILE" >&2
    exit 1
  fi
  # Try to read as JSON (opencode auth.json format)
  if command -v python3 &>/dev/null; then
    SAIA_KEY=$(python3 -c "import json; d=json.load(open('$KEY_FILE')); print(d.get('saia-gwdg',{}).get('key',''))" 2>/dev/null || echo "")
  fi
  # Fallback: read first line
  if [[ -z "$SAIA_KEY" ]]; then
    SAIA_KEY=$(head -n 1 "$KEY_FILE" 2>/dev/null || echo "")
  fi
else
  SAIA_KEY="$(key_from_config)"
  if [[ -n "$SAIA_KEY" ]]; then
    echo "Reusing the SAIA key already in your aider config (pass --key to replace it)."
  else
    prompt_for_key
    SAIA_KEY="$SAIA_API_KEY"
  fi
fi

if [[ -z "$SAIA_KEY" ]]; then
  echo "ERROR: SAIA_API_KEY is empty." >&2
  exit 1
fi

# ── Load models ──────────────────────────────────────────────────────
if [[ ! -f "$MODELS_FILE" ]]; then
  echo "ERROR: Models file not found: $MODELS_FILE" >&2
  exit 1
fi

MODELS=()
while IFS= read -r model || [[ -n "$model" ]]; do
  [[ -z "$model" || "$model" =~ ^# ]] && continue
  MODELS+=("$model")
done < "$MODELS_FILE"

if [[ ${#MODELS[@]} -eq 0 ]]; then
  echo "ERROR: No models found in $MODELS_FILE" >&2
  exit 1
fi

# ── Check/install aider ──────────────────────────────────────────────
AIDER_BIN="$HOME/.local/bin/aider"
if ! command -v aider &>/dev/null; then
  if [[ -x "$AIDER_BIN" ]]; then
    export PATH="$HOME/.local/bin:$PATH"
  elif [[ $ASSUME_YES -eq 1 ]]; then
    :  # --yes: install without asking
  elif [[ -t 0 ]]; then
    read -r -p "aider not found — install it via the official installer? [y/N] " reply
    if [[ $reply != [yY]* ]]; then
      echo "Aborted." >&2
      exit 1
    fi
  else
    echo "ERROR: aider not found and not in TTY mode — use --yes to auto-install" >&2
    exit 1
  fi

  if ! command -v aider &>/dev/null; then
    if ! command -v curl &>/dev/null; then
      echo "ERROR: curl is required to install aider" >&2
      exit 1
    fi

    echo "Downloading and installing aider..."
    if ! curl -LsSf https://aider.chat/install.sh | sh; then
      echo "ERROR: aider installation failed" >&2
      exit 1
    fi

    export PATH="$HOME/.local/bin:$PATH"

    if ! command -v aider &>/dev/null; then
      echo "ERROR: aider installation completed but not found in PATH" >&2
      exit 1
    fi

    echo "aider installed successfully"
  fi
fi

# ── Automatic key swap (--keyring) ───────────────────────────────────
# Sets SAIA_EFFECTIVE_BASE_URL: the local proxy when it is up, else SAIA itself.
keyring_setup "$SAIA_KEY"

# ── Write ~/.aider.conf.yml ──────────────────────────────────────────
CONFIG_FILE="${AIDER_CONFIG_FILE:-$HOME/.aider.conf.yml}"
DEFAULT_MODEL="${SAIA_DEFAULT_MODEL:-deepseek-v4-flash-0731}"

if [[ -f "$CONFIG_FILE" ]]; then
  BACKUP_DIR="$HOME/.aider.conf.yml.bak-$(date +%Y%m%d%H%M%S)"
  cp "$CONFIG_FILE" "$BACKUP_DIR"
  echo "Backed up existing $CONFIG_FILE to $BACKUP_DIR"
fi

mkdir -p "$(dirname "$CONFIG_FILE")"

{
  echo "# GWDG SAIA provider for aider (generated by aider-saia-gwdg)"
  echo "# Regenerate with: bash install-aider-saia-gwdg.sh"
  echo ""
  echo "# OpenAI-compatible endpoint: GWDG SAIA"
  echo "model: openai/$DEFAULT_MODEL"
  echo "openai-api-base: $SAIA_EFFECTIVE_BASE_URL"
  echo "openai-api-key: $SAIA_KEY"
  echo ""
  echo "# Available SAIA models (use with: aider --model openai/<model>):"
  for m in "${MODELS[@]}"; do
    echo "#   openai/$m"
  done
} > "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

echo ""
echo "✓ GWDG SAIA provider configured for aider!"
echo "  Config: $CONFIG_FILE"
echo "  Base URL: $SAIA_EFFECTIVE_BASE_URL"
echo "  Default model: openai/$DEFAULT_MODEL"
echo "  Models: ${#MODELS[@]} ready SAIA models"
echo ""
echo "Usage: aider                          # SAIA is the default model"
echo "       aider --model openai/<model>   # pick another SAIA model"
