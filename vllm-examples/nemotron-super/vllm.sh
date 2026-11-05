#!/bin/bash

# Export your HF_TOKEN first and then run this script.

docker run -it --gpus all \
  -e VLLM_NVFP4_GEMM_BACKEND=marlin \
  -e VLLM_ALLOW_LONG_MAX_MODEL_LEN=1 \
  -e VLLM_FLASHINFER_ALLREDUCE_BACKEND=trtllm \
  -e VLLM_USE_FLASHINFER_MOE_FP4=0 \
  -e HF_TOKEN=$HF_TOKEN \
  -v /data:/data \
  -v $(pwd)/super_v3_reasoning_parser.py:/app/super_v3_reasoning_parser.py \
  -p 8000:8000 \
  vllm/vllm-openai:v0.27.1 \
  --model nvidia/NVIDIA-Nemotron-3-Super-120B-A12B-NVFP4 \
  --served-model-name nemotron-3-super \
  --host 0.0.0.0 \
  --port 8000 \
  --async-scheduling \
  --dtype auto \
  --kv-cache-dtype fp8 \
  --trust-remote-code \
  --tensor-parallel-size 1 \
  --gpu-memory-utilization 0.90 \
  --enable-chunked-prefill \
  --max-num-seqs 4 \
  --max-model-len 262144 \
  --moe-backend marlin \
  --mamba_ssm_cache_dtype float16 \
  --quantization fp4 \
  --speculative_config '{"method":"mtp","num_speculative_tokens":3,"model":"nvidia/Nemotron-3-Super-120B-A12B-BF16-MTPv2","moe_backend":"triton"}' \
  --reasoning-parser-plugin /app/super_v3_reasoning_parser.py \
  --reasoning-parser super_v3 \
  --tool-call-parser qwen3_coder \
  --enable-auto-tool-choice
