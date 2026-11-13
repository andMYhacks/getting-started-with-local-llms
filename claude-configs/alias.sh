#!/bin/bash

# Claude Code -> local LLMs over Tailscale
# Add to ~/.bashrc or ~/.zshrc, then: source ~/.*shrc
# Assumes settings.ollama.json and settings.vllm.json are saved in ~/.claude/

alias claude-ollama='claude --settings ~/.claude/settings.ollama.json'
alias claude-vllm='claude --settings ~/.claude/settings.vllm.json'
alias claude-litellm='claude --settings ~/.claude/settings.model-router.json'

# --- Server side (run on the GPU box) ---------------------------------------
#
# Ollama:
#   export OLLAMA_HOST=100.x.y.z:11434     # Tailscale IP of the GPU box
#   export OLLAMA_CONTEXT_LENGTH=65536
#   ollama serve
#   ollama pull qwen3-coder
#
# vLLM:
#   vllm serve Qwen/Qwen3-Coder-30B-A3B-Instruct \
#     --host 127.0.0.1 --port 8000 \
#     --served-model-name qwen3-coder \
#     --enable-auto-tool-choice --tool-call-parser qwen3_coder \
#     --api-key "$VLLM_API_KEY" \
#     --max-model-len 131072
#
#   # HTTPS on the tailnet via a real cert:
#   tailscale serve --bg --https=8443 http://localhost:8000
#
# --- Smoke test --------------------------------------------------------------
#   curl -s http://gpu-box.tailnet-name.ts.net:11434/v1/messages \
#     -H 'content-type: application/json' -H 'x-api-key: ollama' \
#     -d '{"model":"qwen3-coder","max_tokens":32,"messages":[{"role":"user","content":"ping"}]}'
#
#   claude-ollama -p "say hi"