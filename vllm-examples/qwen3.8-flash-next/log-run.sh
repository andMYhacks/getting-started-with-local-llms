#!/usr/bin/env bash
#
# run.sh — load environment, tee all output to a log, then start vLLM.
#
# Order matters: settings.sh must be *sourced* (not executed in a subshell)
# so its exported vars land in this shell and are inherited by vllm.sh.

set -euo pipefail

# Resolve the directory this script lives in, so it works from any cwd.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SETTINGS="${SCRIPT_DIR}/settings.sh"
VLLM="${SCRIPT_DIR}/vllm.sh"

# Where to log. Override at call time: LOG=run-0.28.0.txt ./run.sh
LOG="${LOG:-${SCRIPT_DIR}/log.txt}"

# Send everything from here on (this script + the exec'd vllm.sh) to the
# terminal AND to $LOG. 2>&1 folds stderr in — most vLLM logs, including
# the loader warnings, come out on stderr. '-a' appends; drop it to overwrite.
exec > >(tee -a "$LOG") 2>&1

echo "=== run.sh started $(date -Iseconds) — logging to ${LOG} ==="

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

# 2) Launch vLLM. exec replaces this process so signals (Ctrl-C) reach vLLM
#    directly; the tee redirect above is inherited, so its output is logged too.
echo "run.sh: starting vLLM with MODEL_CKPT=${MODEL_CKPT}"
exec bash "$VLLM"
