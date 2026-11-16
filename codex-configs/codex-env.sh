# Codex -> local LLMs over Tailscale: API keys and aliases
# Add to ~/.bashrc or ~/.zshrc, then: source ~/.zshrc

# Keys read by config.toml's env_key fields (prefer pulling these from a secret manager)
export VLLM_API_KEY="REPLACE_WITH_VLLM_API_KEY"            # matches vllm --api-key
export LITELLM_MASTER_KEY="REPLACE_WITH_LITELLM_MASTER_KEY"

alias codex-gpu1='codex --profile gpu1-vllm'
alias codex-mac='codex --profile mac-ollama'
alias codex-gpu2='codex --profile gpu2-ollama'
alias codex-gw='codex --profile gateway-coder'

# Smoke test the Responses endpoint on any backend:
#   curl -s http://gpu-box-1.tailnet-name.ts.net:8000/v1/responses \
#     -H "Authorization: Bearer $VLLM_API_KEY" -H 'content-type: application/json' \
#     -d '{"model":"qwen3-coder","input":"ping"}'
#
#   codex exec --profile gpu1-vllm "say hi"
