#!/usr/bin/env bash
#
# build.sh — pack the live SAIA config into install-aider-saia-gwdg.sh
#
# Reads the current src/add-saia-aider.sh and src/models.txt and
# emits a single self-contained installer that can be copied to other devices.
# Rerun this after ANY change to those files, and commit both.
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

OUT="install-aider-saia-gwdg.sh"
MANIFEST=(
  src/add-saia-aider.sh
  src/models.txt
)

# ── Sanity checks ────────────────────────────────────────────────────
for f in "${MANIFEST[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: missing source file: $f" >&2
    exit 1
  fi
  if grep -qF "__ASA_EOF__" "$f"; then
    echo "ERROR: delimiter '__ASA_EOF__' occurs in $f — pick a different delimiter" >&2
    exit 1
  fi
  if [[ -n "$(tail -c 1 "$f")" ]]; then
    echo "ERROR: $f lacks a trailing newline (heredoc packing would add one)" >&2
    exit 1
  fi
done

COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
DIRTY=""
git diff --quiet HEAD -- "${MANIFEST[@]}" 2>/dev/null || DIRTY="-dirty"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

TMP_OUT="$(mktemp "$OUT.XXXXXX")"
trap 'rm -f "$TMP_OUT"' EXIT

# ── Header (interpolates the stamp) ──────────────────────────────────
cat >"$TMP_OUT" <<ASA_GEN_HEADER
#!/usr/bin/env bash
#
# install-aider-saia-gwdg.sh — GENERATED FILE, DO NOT EDIT.
# Regenerate with: ./build.sh  (in the aider-saia-gwdg repo)
# Source: aider-saia-gwdg commit $COMMIT$DIRTY, packed $STAMP
#
# Installs the GWDG SAIA setup for aider: provider + ${#MANIFEST[@]} source files.

ASA_GEN_HEADER

# ── Static installer body ────────────────────────────────────────────
cat >>"$TMP_OUT" <<'ASA_GEN_BODY'
set -euo pipefail

CONFIG_FILE="${AIDER_CONFIG_FILE:-$HOME/.aider.conf.yml}"

usage() {
  cat <<'USAGE'
Usage: SAIA_API_KEY="your-key" bash install-aider-saia-gwdg.sh [OPTIONS]

Installs the GWDG SAIA setup for aider:
  - Installs aider (if missing) via the official installer
  - Writes ~/.aider.conf.yml pointing aider at the GWDG SAIA API

Options:
  -y, --yes           answer yes to prompts (e.g. installing aider)
      --key <value>   SAIA API key (overrides SAIA_API_KEY env)
      --key-file <p>  file containing the SAIA API key
  -h, --help          show this help

The API key is taken from --key, --key-file or the SAIA_API_KEY environment
variable; if none of them is set, you are prompted for it.
An existing ~/.aider.conf.yml is backed up to ~/.aider.conf.yml.bak-<timestamp>/ first.
USAGE
}

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
    echo "Set it: SAIA_API_KEY=\"your-key\" bash install-aider-saia-gwdg.sh" >&2
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

ASSUME_YES=0
KEY=""
KEY_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) ASSUME_YES=1; shift ;;
    --key|--key-file)
      [[ $# -ge 2 ]] || { echo "ERROR: $1 requires a value" >&2; exit 2; }
      if [[ $1 == --key ]]; then KEY="$2"; else KEY_FILE="$2"; fi
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# ── Obtain the API key ───────────────────────────────────────────────
# Reuse a key from a previous install; only ask when there is none to reuse,
# and ask before anything is installed, so an empty-handed user loses nothing.
if [[ -z "$KEY" && -z "$KEY_FILE" && -z "${SAIA_API_KEY:-}" ]]; then
  SAIA_API_KEY="$(key_from_config)"
  if [[ -n "$SAIA_API_KEY" ]]; then
    export SAIA_API_KEY
    echo "Reusing the SAIA key already in $CONFIG_FILE (pass --key to replace it)."
  else
    prompt_for_key
  fi
fi

# ── Unpack the bundled source files ──────────────────────────────────
# Into a temp dir, not next to the installer: this file is meant to be copied
# to a fresh machine on its own, and it must not litter (or overwrite) a repo
# checkout it happens to be run from.
EXTRACT_DIR="$(mktemp -d)"
trap 'rm -rf "$EXTRACT_DIR"' EXIT
mkdir -p "$EXTRACT_DIR/src"
ASA_GEN_BODY

# ── Append the packed source files ───────────────────────────────────
echo "" >>"$TMP_OUT"
echo "# ── Packed source files ────────────────────────────────────────────" >>"$TMP_OUT"

for f in "${MANIFEST[@]}"; do
  echo "cat >\"\$EXTRACT_DIR/$f\" <<'__ASA_EOF__'" >>"$TMP_OUT"
  cat "$f" >>"$TMP_OUT"
  echo "__ASA_EOF__" >>"$TMP_OUT"
  echo "" >>"$TMP_OUT"
done

# ── Static installer tail: run what we just unpacked ──────────────────
cat >>"$TMP_OUT" <<'ASA_GEN_TAIL'
chmod +x "$EXTRACT_DIR/src/add-saia-aider.sh"
CHILD_ARGS=()
if [[ -n "$KEY" ]]; then CHILD_ARGS+=(--key "$KEY"); fi
if [[ -n "$KEY_FILE" ]]; then CHILD_ARGS+=(--key-file "$KEY_FILE"); fi
# ${a[@]+"${a[@]}"}: bash 3.2 (stock macOS) calls an empty array unbound under set -u
"$EXTRACT_DIR/src/add-saia-aider.sh" ${CHILD_ARGS[@]+"${CHILD_ARGS[@]}"}
ASA_GEN_TAIL

# ── Finalize ─────────────────────────────────────────────────────────
mv "$TMP_OUT" "$OUT"
chmod +x "$OUT"

echo "Generated: $OUT"
echo "Commit: $COMMIT$DIRTY"
echo "Timestamp: $STAMP"
