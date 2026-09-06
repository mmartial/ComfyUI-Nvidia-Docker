#!/bin/bash

# Pre-requisites (run first):
# - 00-nvidiaDev.sh (optional)

# Workaround for https://github.com/Comfy-Org/ComfyUI-Manager/issues/2843:
# In ComfyUI-Manager 4.2.1 and 4.2.2, a CSRF protection gate
# (`reject_simple_form_post`) was added to POST handlers. When running
# with `--enable-manager-legacy-ui`, clicking "Update ComfyUI" or "Update All"
# triggers `queue_batch` which calls `await update_comfyui(None)`.
#
# Because `request` is None, evaluating `request.content_type` crashes with:
# `AttributeError: 'NoneType' object has no attribute 'content_type'`
#
# We patch `reject_simple_form_post` in `manager_security.py` so that it
# checks `if request is not None and request.content_type in ...`, allowing
# the internal subroutine call to proceed while keeping CSRF protection intact
# for incoming HTTP requests.
#
# Idempotent: re-runs are no-ops once the patch marker is present, and the
# patch is skipped if upstream fixes or refactors the code in future releases.

# --- COLOR CODES (for console)---
LOG_ERR=$(printf '\033[0;41m')
LOG_WARN=$(printf '\033[0;33m')
LOG_OK=$(printf '\033[0;32m')
LOG_INFO=$(printf '\033[0m')
NC=$(printf '\033[0m')
# --------------------------------

set -e

error_exit() {
  echo -n -e "${LOG_ERR}!! ERROR: ${NC}"
  echo $*
  echo "!! Exiting manager_csrf_patch script (ID: $$)"
  exit 1
}

# Find all potential manager_security.py files in the venv and custom_nodes
targets=()

# Virtualenv site-packages (standard for new manager)
for f in /comfy/mnt/venv/lib/python*/site-packages/comfyui_manager/common/manager_security.py; do
  if [ -f "$f" ]; then targets+=("$f"); fi
done

# Custom nodes directory (legacy manager clone if applicable)
CUSTOM_NODES_DIR="${BASE_DIRECTORY:-/basedir}/custom_nodes"
for f in "$CUSTOM_NODES_DIR"/ComfyUI-Manager*/common/manager_security.py \
         "/comfy/mnt/ComfyUI/custom_nodes"/ComfyUI-Manager*/common/manager_security.py; do
  if [ -f "$f" ]; then targets+=("$f"); fi
done

if [ ${#targets[@]} -eq 0 ]; then
  echo "${LOG_INFO}INFO:${NC} ComfyUI-Manager manager_security.py not found, skipping patch"
  exit 0
fi

marker="# COMFYUI_MANAGER_CSRF_PATCH"
old_line="if request.content_type in _SIMPLE_FORM_CONTENT_TYPES:"

for target in "${targets[@]}"; do
  if grep -q "$marker" "$target" || grep -qF "if request is not None and request.content_type in _SIMPLE_FORM_CONTENT_TYPES:" "$target"; then
    echo "${LOG_INFO}INFO:${NC} ComfyUI-Manager already patched at $target, skipping"
    continue
  fi

  if ! grep -qF "$old_line" "$target"; then
    echo "${LOG_INFO}INFO:${NC} expected target line not found in $target; upstream may already have fixed or refactored it, skipping"
    continue
  fi

  # If the patch cannot be applied (e.g. upstream already fixed/refactored the
  # code, file not writable, ...), report it and move on instead of failing.
  if ! python3 - "$target" "$marker" <<'PY'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
marker = sys.argv[2]
src = path.read_text()
old = "if request.content_type in _SIMPLE_FORM_CONTENT_TYPES:"
new = f"if request is not None and request.content_type in _SIMPLE_FORM_CONTENT_TYPES:  {marker}"
if new in src:
    raise SystemExit("patch already applied")
if old not in src:
    raise SystemExit("expected line not found")
# copy the original file to a backup before patching
date = __import__('datetime').datetime.now().strftime("%Y%m%d%H%M%S")
backup_path = path.with_suffix(path.suffix + ".bak.${date}")
backup_path.write_text(src)
print(f"backup created at {backup_path}")
path.write_text(src.replace(old, new, 1))
print(f"patched {path} with marker {marker}")
PY
  then
    echo "${LOG_WARN}WARN:${NC} could not apply ComfyUI-Manager CSRF patch to $target, skipping"
    continue
  fi

  echo "${LOG_OK}SUCCESS:${NC} patched ComfyUI-Manager CSRF check in $target"
done

exit 0

