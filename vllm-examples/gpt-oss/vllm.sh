#!/bin/bash

vllm serve openai/gpt-oss-120b \
  --served-model-name GPT-OSS \
  --host: 127.0.0.1 \
  --moe-backend marlin \
  --kv-cache-dtype fp8 \
  --enable-prefix-caching \
  --max-model-len 131072 \
  --max-num-batched-tokens 8192 \
  --gpu-memory-utilization 0.85 \
  --tool-call-parser openai \
  --enable-auto-tool-choice \
  --reasoning-parser openai_gptoss