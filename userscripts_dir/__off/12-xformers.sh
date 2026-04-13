#!/bin/bash

# Pre-requisites (run first):
# - 00-nvidiaDev.sh

# Install xformers
# 
# https://github.com/facebookresearch/xformers

# --- CONFIGURATION ---
FORCE_REINSTALL="${FORCE_REINSTALL:-false}"
# ---------------------

# --- COLOR CODES (for console)---
LOG_ERR=$(printf '\033[0;41m') # White on RED BG
# LOG_ERR=$(printf '\033[0;91m') # Red on Black BG
# LOG_ERR=$(printf '\033[0m') # No Color

LOG_WARN=$(printf '\033[0;33m') # Yellow
# LOG_WARN=$(printf '\033[0m') # No Color 

LOG_OK=$(printf '\033[0;32m') # GREEN
# LOG_OK=$(printf '\033[0m') # No Color 

# LOG_INFO=$(printf '\033[0;32m') # Green 
LOG_INFO=$(printf '\033[0m') # No Color

NC=$(printf '\033[0m') # No Color
# --------------------------------

set -e

error_exit() {
 echo -n -e "${LOG_ERR}!! ERROR: ${NC}"
  echo $*
  echo "!! Exiting xformers script (ID: $$)"
  exit 1
}

source /comfy/mnt/venv/bin/activate || error_exit "Failed to activate virtualenv"

# --- CHECK EXISTING INSTALLATION ---
if [ "$FORCE_REINSTALL" = "false" ]; then
    if pip show xformers > /dev/null 2>&1; then
        echo "${LOG_INFO}INFO:${NC} Xformers is already installed."
        echo "     (Set FORCE_REINSTALL=true in script to force rebuild/reinstall)"
        exit 0
    fi
else
    echo "${LOG_INFO}INFO:${NC} FORCE_REINSTALL is true. Proceeding..."
fi
# -----------------------------------

echo "** Installing xformers**"

# We need both uv and the cache directory to enable build with uv
use_uv=true
uv="/comfy/mnt/venv/bin/uv"
uv_cache="/comfy/mnt/uv_cache"
if [ ! -x "$uv" ] || [ ! -d "$uv_cache" ]; then use_uv=false; fi

echo "Checking if nvcc is available"
if ! command -v nvcc &> /dev/null; then
    error_exit " !! nvcc not found, canceling run"
fi

if pip3 show setuptools &>/dev/null; then
  echo " ++ setuptools installed"
else
  error_exit " !! setuptools not installed, canceling run"
fi
if pip3 show ninja &>/dev/null; then
  echo " ++ ninja installed"
else
  error_exit " !! ninja not installed, canceling run"
fi

cd /comfy/mnt
bb="venv/.build_base.txt"
if [ ! -f $bb ]; then error_exit "${bb} not found"; fi
BUILD_BASE=$(cat $bb)
# extract CUDA version from build base
CUDA_VERSION=$(echo $BUILD_BASE | grep -oP 'cuda\d+\.\d+')
if [ -z "$CUDA_VERSION" ]; then error_exit "CUDA version not found in build base"; fi

echo "CUDA version: $CUDA_VERSION"

must_build=false
if pip3 show torch &>/dev/null; then
  torch_version=$(pip3 show torch | grep Version | awk '{print $2}' | cut -d'.' -f1-2)
else
  error_exit "torch not installed, canceling run"
fi

# If aarch64, we must build (no whl available)
if [ "$(uname -m)" == "aarch64" ]; then must_build=true; fi

echo "PyTorch version: $torch_version"
echo "must_build: \"${must_build}\""

if [ "A$must_build" == "Atrue" ]; then
  echo "PIP3_CMD: \"${PIP3_CMD}\""
  if [ ! -d src ]; then mkdir src; fi
  cd src

  mkdir -p ${BUILD_BASE}
  if [ ! -d ${BUILD_BASE} ]; then error_exit "${BUILD_BASE} not found"; fi
  cd ${BUILD_BASE}

  if [ -z "$torch_version" ]; then error_exit "error getting torch version, canceling run"; fi
  td="Torch_${torch_version}"
  if [ ! -d $td ]; then mkdir $td; fi
  cd $td

  dd="/comfy/mnt/src/${BUILD_BASE}/$td/xformers-git"
  if [ -d $dd ]; then
    echo "${LOG_WARN}WARNING:${NC} xformers source already present, you must delete $dd to force reinstallation"
    exit 0
  fi
  tdd="$dd-`date +%Y%m%d%H%M%S`"
  mkdir -p $tdd

  # we are not downloading the source code, we are building from git, as described in the xformers documentation
  # Set build parallelism based on available CPU cores (matching SageAttention/nunchaku pattern)
  numproc=$(nproc --all)
  echo " - numproc: $numproc"
  ext_parallel=$(( numproc / 2 ))
  if [ "$ext_parallel" -lt 1 ]; then ext_parallel=1; fi
  echo " - ext_parallel: $ext_parallel"
  num_threads=$(( numproc / 2 ))
  if [ "$num_threads" -lt 1 ]; then num_threads=1; fi
  echo " - num_threads: $num_threads"

  if [ "A$use_uv" == "Atrue" ]; then
    echo "== Using uv"
    echo " - uv: $uv"
    echo " - uv_cache: $uv_cache"
  else
    echo "== Using pip"
    echo " - TORCH_INDEX_URL: $TORCH_INDEX_URL"
  fi

  CMD="EXT_PARALLEL=$ext_parallel NVCC_APPEND_FLAGS=\"--threads $num_threads\" MAX_JOBS=$numproc ${PIP3_CMD} xformers --no-build-isolation git+https://github.com/facebookresearch/xformers.git@main#egg=xformers"
  echo "CMD: \"${CMD}\""
  echo $CMD > $tdd/build.cmd; chmod +x $tdd/build.cmd
  script -a -e -c $tdd/build.cmd $tdd/build.log || error_exit "Failed to build xformers"
  cd ..
  mv $tdd $dd
  echo "${LOG_OK}SUCCESS:${NC} xformers built successfully"
  exit 0
fi

whl_cuda13_torch29="https://download.pytorch.org/whl/cu130/xformers-0.0.33.post2-cp39-abi3-manylinux_2_28_x86_64.whl"
whl_cuda13_torch210="https://download.pytorch.org/whl/cu130/xformers-0.0.34-cp39-abi3-manylinux_2_28_x86_64.whl"
if [ "$CUDA_VERSION" == "cuda13.0" ] || [ "$CUDA_VERSION" == "cuda13.1" ] || [ "$CUDA_VERSION" == "cuda13.2" ]; then
  CMD=""
  if [ "$torch_version" == "2.9" ]; then
    CMD="${PIP3_CMD} $whl_cuda13_torch29"
  elif [ "$torch_version" == "2.10" ]; then
    CMD="${PIP3_CMD} $whl_cuda13_torch210"
  fi

  if [ ! -z "$CMD" ]; then
    echo "CMD: \"${CMD}\""
    ${CMD} || error_exit "Failed to install xformers"
    exit 0
  fi
fi

if [ "A$use_uv" == "Atrue" ]; then
  if [ -z "${UV_TORCH_BACKEND+x}" ]; then error_exit "UV_TORCH_BACKEND is not set"; fi
  echo "== Using uv"
  echo " - uv: $uv"
  echo " - uv_cache: $uv_cache"
  echo " - UV_TORCH_BACKEND: $UV_TORCH_BACKEND"
else
  echo "== Using pip"
  echo " - TORCH_INDEX_URL: $TORCH_INDEX_URL"
fi

CMD="${PIP3_CMD} xformers ${PIP3_XTRA}"
echo "CMD: \"${CMD}\""
${CMD} || error_exit "Failed to install xformers"
echo "${LOG_OK}SUCCESS:${NC} xformers installed successfully"
exit 0