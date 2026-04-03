# archon

local voice control for macOS. talk to your computer, it does things.

replaces keyboard/mouse with speech for common tasks — opening apps, clicking buttons, typing text, navigating browsers, filling forms. everything runs on-device (whisper for STT, qwen 3B for planning, accessibility APIs for execution). no cloud, no API keys.

## requirements

- macOS 13+ (Ventura or later)
- Apple Silicon (M1, M2, M3, M4)
- ~6GB free disk space
- 8GB RAM minimum (16GB recommended)

## setup

```bash
git clone https://github.com/eb1386/Archon.git
cd Archon
chmod +x setup.sh
./setup.sh
```

setup.sh handles everything automatically:
- installs homebrew, cmake, git-lfs if you don't have them
- clones and compiles whisper.cpp as a static library
- downloads the whisper base.en model (~150MB)
- downloads the silero VAD model (~2MB)
- downloads the Qwen2.5-3B-Instruct 4-bit model via MLX (~2.5GB)
- generates a default config at `~/.archon/config.json`
- builds the archon binary

after it finishes, grant permissions:
1. **System Settings → Privacy & Security → Accessibility** → add `.build/release/Archon`
2. **System Settings → Privacy & Security → Microphone** → allow Archon

then run:
```bash
.build/release/Archon
```

## how it works

```
mic (always on) → silero VAD → whisper.cpp → qwen 2.5 3B (MLX) → macOS accessibility API
```

1. microphone streams audio continuously, VAD watches for speech (~2% CPU when idle)
2. when you stop talking, the audio clip goes to whisper for transcription (~200-500ms)
3. the transcript goes to qwen 3B running locally on the GPU via MLX (~300-800ms)
4. qwen outputs a JSON action sequence, archon executes each step through the accessibility API

total latency is about 1-3 seconds from when you stop speaking to when the action completes.

## examples

```
"open safari and search for pizza near me"
→ opens Safari, focuses address bar, types query, hits enter

"scroll down"
→ scrolls the active window down

"close this window"
→ sends cmd+w

"open messages and text mom saying I'll be home at 9"
→ opens Messages, clicks the contact, types the message, sends it

"turn up the volume"
→ presses volume up key 3 times

"open terminal and run npm start"
→ opens Terminal, types the command, hits enter

"switch to vs code"
→ brings VS Code to the front

"take a screenshot"
→ captures the screen to /tmp/
```

## config

edit `~/.archon/config.json`:

```json
{
    "whisper_model_path": "~/.archon/models/ggml-base.en.bin",
    "vad_model_path": "~/.archon/models/silero_vad.onnx",
    "llm_model_path": "~/.archon/models/qwen2.5-3b-instruct-4bit",
    "wake_word": null,
    "always_listening": true,
    "action_delay_ms": 100,
    "tts_enabled": false,
    "vad_threshold": 0.5,
    "silence_duration_ms": 500,
    "max_actions_per_command": 20,
    "log_transcriptions": true,
    "log_actions": true
}
```

- **wake_word** — set to `"archon"` so it only responds when you say "archon, do X". leave as `null` to process every utterance (careful with this one).
- **action_delay_ms** — pause between each action in a sequence. increase if apps need time to respond.
- **tts_enabled** — says "Done" out loud after completing a command.
- **vad_threshold** — how confident the VAD needs to be that you're speaking (0.0-1.0). lower = more sensitive.
- **silence_duration_ms** — how long to wait after you stop talking before processing. increase if it cuts you off mid-sentence.

## 8GB machines

it runs on 8GB but you're at ~3.5-4GB for models alone. if you get memory pressure warnings or swapping, use the 1.5B model instead:

```bash
git lfs install
git clone https://huggingface.co/mlx-community/Qwen2.5-1.5B-Instruct-4bit ~/.archon/models/qwen2.5-1.5b-instruct-4bit
```

then change `llm_model_path` in `~/.archon/config.json`:
```json
"llm_model_path": "~/.archon/models/qwen2.5-1.5b-instruct-4bit"
```

the 1.5B model is less capable at complex multi-step commands but handles simple stuff fine and uses ~1GB less RAM.

## architecture

```
archon/
├── setup.sh                     # one-command setup
├── Package.swift                # swift package manifest
├── Sources/Archon/
│   ├── main.swift               # entry point, wires pipeline
│   ├── AudioListener.swift      # AVAudioEngine mic capture
│   ├── VAD.swift                # silero voice activity detection (ONNX)
│   ├── Transcriber.swift        # whisper.cpp bindings
│   ├── ActionPlanner.swift      # sends transcript to local LLM
│   ├── MLXInference.swift       # qwen model loading/generation via MLX
│   ├── Executor.swift           # translates actions to OS events
│   ├── AccessibilityTree.swift  # AX element walking + fuzzy matching
│   ├── AppleScriptBridge.swift  # fallback for complex app interactions
│   ├── TTSFeedback.swift        # optional spoken confirmations
│   ├── Config.swift             # loads ~/.archon/config.json
│   └── Models/
│       ├── Action.swift         # action types + JSON parser
│       └── TranscriptionResult.swift
└── Libraries/whisper/           # whisper.cpp static lib (built by setup.sh)
```

pure swift + C. no electron, no python, no web views.
