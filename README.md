# aider-saia-gwdg

GWDG SAIA provider for **aider**

This repo provides an installer that configures [aider](https://aider.chat/) to use the [GWDG SAIA](https://chat-ai.academiccloud.de/) OpenAI-compatible API, giving you access to 14 ready models including Qwen, DeepSeek, GLM, and more.

## Quick start

```bash
SAIA_API_KEY="your-key" bash install-aider-saia-gwdg.sh --yes
```

No key in the environment? Run `bash install-aider-saia-gwdg.sh --yes` and it asks for one
(or pass `--key <value>` / `--key-file <path>`). Reinstalls reuse the key already in
your aider config, so you only ever type it once.

This one-shot installer:
- Installs aider (if missing) via the official installer (`curl -LsSf https://aider.chat/install.sh | sh`)
- Writes `~/.aider.conf.yml` pointing aider at the GWDG SAIA API with 14 ready models
- Sets the default model to a SAIA model, so aider runs with **no OpenAI account**
- Optional, with `--keyring`: routes aider through a local
  key-rotating proxy that swaps keys automatically when one is revoked, drained or
  rate limited (see `SETUP.md` → *Multiple keys*)
- Works on macOS, Linux, and WSL

Or see `SETUP.md` for detailed instructions and troubleshooting.

## What's included

| File | Purpose |
|------|---------|
| `install-aider-saia-gwdg.sh` | Self-contained installer (generated; never edit directly) |
| `build.sh` | Regenerates the installer from source files |
| `src/add-saia-aider.sh` | Live source script (portable key sourcing) |
| `src/models.txt` | List of 14 ready SAIA models |
| `src/saia_keyring.py`, `src/saia-keyring.sh` | Key-rotating proxy and its install logic, vendored from `opencode-extras/keyring/` (never edit here) |
| `test/fake-saia.py` | Fake SAIA endpoint for the smoke test (not packed) |
| `test/test-install.sh` | Smoke test that verifies the config is written (not packed) |

## Architecture

```
SAIA_API_KEY → install-aider-saia-gwdg.sh → [aider install] → src/add-saia-aider.sh → ~/.aider.conf.yml
                                                                                          │
                                                                                          ▼
                                                              https://chat-ai.academiccloud.de/v1
```

## Maintaining

After changing `src/add-saia-aider.sh` or `src/models.txt`, regenerate the installer
(the keyring files are synced in by `opencode-extras/keyring/sync.sh`, which also rebuilds):

```bash
./build.sh
```

## License

MIT
