# GWDG SAIA Provider Setup for aider

## Summary

This installer configures aider to use the GWDG SAIA provider with all 14 ready models.

## Prerequisites

- **SAIA API key** (from GWDG SAIA) — the installer reuses the key from a previous
  install, and prompts for it only when there is none
- **aider** will be installed automatically if missing (via the official installer)

## Quick start

```bash
SAIA_API_KEY="your-key" bash install-aider-saia-gwdg.sh --yes
```

This one-shot installer:
- Installs aider (if missing) via the official installer
- Writes `~/.aider.conf.yml` pointing aider at the GWDG SAIA API with 14 ready models
- Works on macOS, Linux, and WSL

## Detailed installation

### 1. Obtain your SAIA API key

Your key is stored in `~/.local/share/opencode/auth.json` (if you use opencode with SAIA), or you can generate a new one at the GWDG SAIA portal.

### 2. Run the installer

```bash
# Option A: via environment variable (recommended)
SAIA_API_KEY="your-key" bash install-aider-saia-gwdg.sh --yes

# Option B: via --key argument
bash install-aider-saia-gwdg.sh --key "your-key" --yes

# Option C: via --key-file (reads from a file)
bash install-aider-saia-gwdg.sh --key-file ~/.local/share/opencode/auth.json --yes

# Option D: pass nothing — reuses the key from a previous install,
# or asks for it (input hidden) if this is the first one
bash install-aider-saia-gwdg.sh --yes
```

The `--yes` flag enables non-interactive mode and auto-installs aider if missing. Without it, the installer will prompt before installing aider.

The installer will:
- Verify aider is installed (installing it via `curl -LsSf https://aider.chat/install.sh | sh` if missing)
- Back up your existing `~/.aider.conf.yml` to `~/.aider.conf.yml.bak-<timestamp>/`
- Write `~/.aider.conf.yml` with the GWDG SAIA base URL, your API key, and the default model

### 3. Verify installation

```bash
cat ~/.aider.conf.yml
```

You should see `openai-api-base: https://chat-ai.academiccloud.de/v1` and your key.

### 4. Test the provider

```bash
aider --message "Reply with exactly: OK"
```

Expected output: `OK`.

## Usage

### Start a session with a SAIA model

```bash
# Use the default SAIA model
aider

# Or start with a specific model
aider --model openai/qwen3-coder-next
```

### Available models

All 14 ready SAIA models:

- apertus-70b-instruct-2509
- devstral-2-123b-instruct-2512
- qwen3.8-27b
- deepseek-v4-flash-0731
- glm-5.3-flash
- qwen3-coder-next
- qwen3-omni-30b-a3b-instruct
- mistral-medium-3.5-128b
- qwen3.5-397b-a17b
- gemma-4-31b-it
- qwen3.6-35b-a3b
- meta-llama-3.1-8b-instruct
- openai-gpt-oss-120b
- qwen3-30b-a3b-instruct-2507

## Config schema

The provider is stored in `~/.aider.conf.yml`:

```yaml
# OpenAI-compatible endpoint: GWDG SAIA
model: openai/deepseek-v4-flash-0731
openai-api-base: https://chat-ai.academiccloud.de/v1
openai-api-key: <your-key>
```

**Note**: the API key is written in plaintext to `~/.aider.conf.yml` with 600 permissions (owner read/write only).

## Troubleshooting

### Config not taking effect

Aider looks for `.aider.conf.yml` in your home directory, the git root, and the current directory (in that order). If you have a project-level config, it overrides the home one. Use `--config ~/.aider.conf.yml` to force it.

### Model warnings

Aider warns about unknown context window sizes and costs for models it does not recognize. This is expected for SAIA models — the warnings are harmless. You can silence them with `--no-show-model-warnings`.

### API key errors

- Ensure `SAIA_API_KEY` is set correctly (no quotes in the env var value); with no
  key set at all, the installer asks for one, and fails only if there is no terminal
  to ask on (CI, cron) — set the env var there
- Verify the key is valid at the GWDG SAIA portal
- Check rate limits: 30 req/min, 200/hour, 1000/day, 3000/month per key

### aider not found

The installer automatically installs aider via the official installer if missing:

```bash
curl -LsSf https://aider.chat/install.sh | sh
```

This installs to `~/.local/bin/aider`. If it is not on your PATH, add `~/.local/bin` to it.

## Advanced: Regenerate the installer

If you modify `src/add-saia-aider.sh` or `src/models.txt`, regenerate the installer:

```bash
./build.sh
```

This creates a new `install-aider-saia-gwdg.sh` with the changes embedded.

## License

MIT
