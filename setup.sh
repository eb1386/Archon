#!/bin/bash
set -e

# archon setup script
# automated setup for fully local voice control

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ARCHON_DIR="$HOME/.archon"
MODELS_DIR="$ARCHON_DIR/models"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WHISPER_LIB_DIR="$SCRIPT_DIR/Libraries/whisper"

info() { echo -e "${GREEN}▸${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }

# check macos
if [[ "$(uname)" != "Darwin" ]]; then
    fail "Archon requires macOS. Detected: $(uname)"
fi

# check apple silicon
ARCH="$(uname -m)"
if [[ "$ARCH" != "arm64" ]]; then
    fail "Archon requires Apple Silicon (arm64). Detected: $ARCH"
fi

info "macOS on Apple Silicon detected"

# check xcode cli tools
if ! xcode-select -p &>/dev/null; then
    warn "Xcode Command Line Tools not found. Installing..."
    xcode-select --install
    echo "Press Enter after Xcode Command Line Tools installation completes."
    read -r
    if ! xcode-select -p &>/dev/null; then
        fail "Xcode Command Line Tools still not found. Please install manually."
    fi
fi
info "Xcode Command Line Tools found"

# check homebrew
if ! command -v brew &>/dev/null; then
    warn "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
    if ! command -v brew &>/dev/null; then
        fail "Homebrew installation failed."
    fi
fi
info "Homebrew found"

# install deps
info "Installing system dependencies..."
brew install cmake git-lfs 2>/dev/null || true
info "cmake and git-lfs installed"

# create dirs
mkdir -p "$ARCHON_DIR"
mkdir -p "$MODELS_DIR"
mkdir -p "$WHISPER_LIB_DIR/include"
mkdir -p "$WHISPER_LIB_DIR/lib"
info "Created ~/.archon/ directories"

# build whisper.cpp
if [[ ! -f "$WHISPER_LIB_DIR/lib/libwhisper.a" ]]; then
    info "Building whisper.cpp..."
    WHISPER_TMP="/tmp/whisper.cpp"
    rm -rf "$WHISPER_TMP"
    cd /tmp
    git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git
    cd whisper.cpp
    cmake -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DWHISPER_BUILD_EXAMPLES=OFF \
        -DWHISPER_BUILD_TESTS=OFF
    cmake --build build --config Release -j$(sysctl -n hw.ncpu)

    # the lib can end up in different places depending on version
    FOUND_LIB=$(find build -name "libwhisper.a" -print -quit)
    if [[ -z "$FOUND_LIB" ]]; then
        fail "whisper.cpp build succeeded but can't find libwhisper.a"
    fi
    cp "$FOUND_LIB" "$WHISPER_LIB_DIR/lib/"

    # headers — try common locations
    for hdir in include ggml/include; do
        if [[ -f "$hdir/whisper.h" ]]; then
            cp "$hdir/whisper.h" "$WHISPER_LIB_DIR/include/"
            break
        fi
    done
    # grab ggml headers too if they exist
    find . -maxdepth 3 -name "ggml*.h" -path "*/include/*" -exec cp {} "$WHISPER_LIB_DIR/include/" \; 2>/dev/null || true

    cd "$SCRIPT_DIR"
    rm -rf "$WHISPER_TMP"
    info "whisper.cpp built and installed"
else
    info "whisper.cpp already built"
fi

# download whisper model
if [[ ! -f "$MODELS_DIR/ggml-base.en.bin" ]]; then
    info "Downloading Whisper base.en model (~150MB)..."
    curl -L --progress-bar \
        -o "$MODELS_DIR/ggml-base.en.bin" \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"
    info "Whisper model downloaded"
else
    info "Whisper model already exists"
fi

# download silero vad
if [[ ! -f "$MODELS_DIR/silero_vad.onnx" ]]; then
    info "Downloading Silero VAD model..."
    curl -L --progress-bar \
        -o "$MODELS_DIR/silero_vad.onnx" \
        "https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx"
    info "VAD model downloaded"
else
    info "VAD model already exists"
fi

# download qwen llm
if [[ ! -d "$MODELS_DIR/qwen2.5-3b-instruct-4bit" ]]; then
    info "Downloading Qwen2.5-3B-Instruct-4bit (~2.5GB)..."
    git lfs install
    git clone "https://huggingface.co/mlx-community/Qwen2.5-3B-Instruct-4bit" \
        "$MODELS_DIR/qwen2.5-3b-instruct-4bit"
    info "LLM model downloaded"
else
    info "LLM model already exists"
fi

# generate config
CONFIG_FILE="$ARCHON_DIR/config.json"
if [[ ! -f "$CONFIG_FILE" ]]; then
    cat > "$CONFIG_FILE" << 'CONFIGEOF'
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
CONFIGEOF
    info "Default config created at $CONFIG_FILE"
else
    info "Config already exists"
fi

# build archon
info "Building Archon..."
cd "$SCRIPT_DIR"
swift build -c release

echo ""
echo -e "${GREEN}✓ Archon installed successfully.${NC}"
echo ""
echo "Before running:"
echo "  1. Open System Settings → Privacy & Security → Accessibility"
echo "     Add: .build/release/Archon"
echo "  2. Open System Settings → Privacy & Security → Microphone"
echo "     Allow: Archon"
echo ""
echo "Run with:"
echo "  .build/release/Archon"
echo ""
echo "Archon is always listening. Speak naturally. Say \"open Safari\" to start."
