#!/bin/bash
#!/usr/bin/env bash
#
# run.sh — load environment, then start vLLM.
#
# Order matters: settings.sh must be *sourced* (not executed in a subshell)
# so its exported vars land in this shell and are inherited by vllm.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Resolve the directory this script lives in, so it works from any cwd.

SETTINGS="${SCRIPT_DIR}/settings.sh"
VLLM="${SCRIPT_DIR}/vllm.sh"

# Sanity-check both scripts are present before doing anything.
for f in "$SETTINGS" "$VLLM"; do
  if [[ ! -f "$f" ]]; then
    echo "run.sh: required script not found: $f" >&2
    exit 1
  fi
done

# 1) Load env vars into THIS shell (source, don't execute).
echo "run.sh: loading environment from settings.sh"
# shellcheck source=/dev/null
source "$SETTINGS"

# Fail fast if the vars we expect didn't get set.
: "${MODEL_CKPT:?run.sh: MODEL_CKPT not set — check settings.sh}"
: "${DSPARK_CKPT:?run.sh: DSPARK_CKPT not set — check settings.sh}"

# 2) Launch vLLM. exec replaces this process so signals (Ctrl-C) reach vLLM directly.
echo "run.sh: starting vLLM with MODEL_CKPT=${MODEL_CKPT}"
exec bash "$VLLM"
