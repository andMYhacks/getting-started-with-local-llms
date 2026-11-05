#!/bin/bash

export VLLM_USE_FLASHINFER_SAMPLER=0

vllm serve Qwen/Qwen2.5-Coder-7B-Instruct-AWQ \
  --served-model-name Qwen2.5-Coder-7B \
  --quantization awq_marlin \
  --dtype float16 \
  --gpu-memory-utilization 0.90 \
  --max-model-len 32768 \
  --max-num-seqs 16 \
  --port 8000 \
  --enable-auto-tool-choice \
  --tool-call-parser hermes
