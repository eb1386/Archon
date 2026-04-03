# archon

local voice control for macOS. talk to your computer, it does things.

replaces keyboard/mouse with speech for common tasks — opening apps, clicking buttons, typing text, navigating browsers, filling forms. everything runs on-device (whisper for STT, qwen 3B for planning, accessibility APIs for execution). no cloud, no API keys.

## requirements

- macOS 13+, apple silicon
- ~6GB disk (models)
- 8GB RAM works but tight (see note below)

## quickstart

```
git clone <url> archon && cd archon
chmod +x setup.sh && ./setup.sh
.build/release/Archon
```

you'll need to grant accessibility + microphone permissions in system settings.

## how it works

mic (always on) → silero VAD → whisper.cpp STT → qwen 2.5 3B (local, via MLX) → accessibility API actions

all local. latency is roughly 1-3 seconds end to end on M1.

## 8GB RAM note

it works but you're running at ~3.5-4GB for models alone. if you hit memory pressure, edit `~/.archon/config.json` and swap the llm path to a 1.5B model instead:

```
git clone https://huggingface.co/mlx-community/Qwen2.5-1.5B-Instruct-4bit ~/.archon/models/qwen2.5-1.5b-instruct-4bit
```

then set `"llm_model_path": "~/.archon/models/qwen2.5-1.5b-instruct-4bit"` in config.

## config

`~/.archon/config.json` — wake word, delays, thresholds, etc. see `setup.txt` for full reference.

## examples

- "open safari and search for pizza near me"
- "scroll down"
- "close this window"
- "switch to vs code"
- "turn up the volume"
- "open terminal and run npm start"
