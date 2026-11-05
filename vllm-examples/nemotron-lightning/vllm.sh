#!/bin/bash

# ---- Add Weightle.ss abliteration to enable Cyber capabilities ----

# WEIGHTLESS_STEER_PATH="/data/huggingface/hub/\
# models--msuiche--Nemotron-3.5-Lightning-30B-A3B-abliterated-cyber-GLP-51-L1-51-a1.0/\
# snapshots/1bdaa9c4b494af1ef63275e7391b8087cce17918/\
# Nemotron-3.5-Lightning-30B-A3B-abliterated-GLP-51-L1-51-a1.0.gguf"

# then prepend the exec command below with this line to enable weightless abliteration:

# python3 /home/path/to/loadouts/weightless/weightless/patches/hotfix-nemotron35-steering-projective.py &&

# ---- Remove this line and the comments below if enableing Weightle.ss ----

# Note: if you run this in a container you'll need to change the host stanza
# to 0.0.0.0 in order for the model to be accessible from outside the container.
exec /home/username/.venv/bin/vllm serve --model $MODEL_CKPT \
    --served-model-name Nemotron-3.5-Lightning \
    --host 127.0.0.1 \
    --moe-backend marlin \
    --port 8000 \
    --kv-cache-dtype fp8 \
    --enable-prefix-caching \
    --gpu-memory-utilization 0.85 \
    --speculative_config.num_speculative_tokens 3 \
    --mamba-backend flashinfer \
    --mamba-cache-mode align \
    --reasoning-parser nemotron_v3 \
    --speculative_config.model $DSPARK_CKPT \
    --tool-call-parser qwen3_coder \
    --enable-auto-tool-choice
