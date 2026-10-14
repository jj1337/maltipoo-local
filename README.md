# Maltipoo Local 🐶

> **This is the local-models version** of [Maltipoo](https://github.com/jj1337/maltipoo-dog). It runs fully offline against Ollama / LM Studio instead of Claude Code.

Fork of the Maltipoo desktop pet that talks to **local models** (Ollama, LM Studio, anything OpenAI-compatible) instead of Claude Code. No cloud, no API keys.

Double-tap **⌘ Command** to open the chat.

## Build
    ./build_app.sh   # build/MaltipooLocal.app

Allow Accessibility (double-⌘) and, for screenshots, Screen Recording.

## Setup
1. `ollama serve` and `ollama pull <model>` (LM Studio: start its local server on :1234).
2. Pick the server, chat model and screenshot model in the dog's menu. Default endpoint: `http://localhost:11434`.
3. Screenshots and images need a vision model (qwen2.5vl, gemma3, llava…).

## Differences from the Claude version
- Dialogs are stored in `~/.maltipoo-local/chats/*.json` (no Claude app sync).
- No file tools: attached text files are inlined (first 16 KB), folders are sent as a listing, images go as vision input. The dog can't edit files.
- One model per answer ("all models" mode removed).
