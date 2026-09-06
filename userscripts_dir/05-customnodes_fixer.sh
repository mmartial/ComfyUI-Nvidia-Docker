#!/bin/bash

# Pre-requisites (run first):
# - 00-nvidiaDev.sh

set -e

error_exit() {
  echo -n -e "${LOG_ERR}!! ERROR: ${NC}"
  echo $*
  echo -e "!! Exiting onnxruntime-gpu Script (ID: $$)"
  exit 1
}

source /comfy/mnt/venv/bin/activate || error_exit "Failed to activate virtualenv"

# We need both uv and the cache directory to enable build with uv
use_uv=true
uv="/comfy/mnt/venv/bin/uv"
uv_cache="/comfy/mnt/uv_cache"
if [ ! -x "$uv" ] || [ ! -d "$uv_cache" ]; then use_uv=false; fi

# Remove --upgrade from PIP3_CMD
PIP3_CMD=$(echo "$PIP3_CMD" | sed 's/--upgrade//g')

echo "== PIP3_CMD: \"${PIP3_CMD}\""
if [ "A$use_uv" == "Atrue" ]; then
  echo "== Using uv"
  echo " - uv: $uv"
  echo " - uv_cache: $uv_cache"
else
  echo "== Using pip"
fi

# Find custom nodes with requirements.txt in /basedir/custom_nodes
# list all folders in /basedir/custom_nodes, ignore __pycache__

todo=$(ls -d /basedir/custom_nodes/* | grep -v __pycache__)
for cn in $todo; do
  if [ ! -d "$cn" ]; then continue; fi
  cn_name=$(basename $cn)
  echo "++ Checking custom node: $cn_name"
  cd "$cn"
  status=1
  # Discard the pyproject.toml as it contains the custom node version
  # Try to install requirements.txt
  if [ -f "requirements.txt" ]; then
    echo " ++ Found requirements.txt, installing"
    if $PIP3_CMD -r requirements.txt; then
      status=0
    else
      status=1
    fi
    echo " ++ Status: $status"
  fi
done

echo "++ Done checking custom nodes"
exit 0
