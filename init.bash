#!/bin/bash

set -e

error_exit() {
  echo -n "!! ERROR: "
  echo $*
  echo "!! Exiting script (ID: $$)"
  exit 1
}

ok_exit() {
  echo $*
  echo "++ Exiting script (ID: $$)"
  exit 0
}

# Load config (must have at least ENV_IGNORELIST and ENV_OBFUSCATE_PART set)
it=/comfyui-nvidia_config.sh
if [ -f $it ]; then
  source $it || error_exit "Failed to load config: $it"
else
  error_exit "Failed to load config: $it not found"
fi
# Check for ENV_IGNORELIST and ENV_OBFUSCATE_PART
if [ -z "${ENV_IGNORELIST+x}" ]; then error_exit "ENV_IGNORELIST not set"; fi
if [ -z "${ENV_OBFUSCATE_PART+x}" ]; then error_exit "ENV_OBFUSCATE_PART not set"; fi

whoami=`whoami`
script_dir=$(dirname $0)
script_name=$(basename $0)
echo ""; echo ""
echo "======================================"
echo "=================== Starting script (ID: $$)"
echo "== Running ${script_name} in ${script_dir} as ${whoami}"
script_fullname=$0
echo "  - script_fullname: ${script_fullname}"
## 20250418: Removed previous command line arguments to support command line override
ignore_value="VALUE_TO_IGNORE"
echo " - started with umask: $(umask)"

# default umask: 0022 (files readable by others); allow override using the UMASK environment variable
umask "${UMASK:-0022}"
echo "=> umask: $(umask)"

# Write a world-writeable file (preferably inside /tmp -- ie within the container)
write_worldtmpfile() {
  tmpfile=$1
  if [ -z "${tmpfile}" ]; then error_exit "write_worldfile: missing argument"; fi
  if [ -f $tmpfile ]; then rm -f $tmpfile; fi
  echo -n $2 > ${tmpfile}
  chmod 777 ${tmpfile}
}

itdir=/tmp/comfy_init
if [ ! -d $itdir ]; then mkdir $itdir; chmod 777 $itdir; fi
if [ ! -d $itdir ]; then error_exit "Failed to create $itdir"; fi

# Set user and group id
# logic: if not set and file exists, use file value, else use default. Create file for persistence when the container is re-run
# reasoning: needed when using docker compose as the file will exist in the stopped container, and changing the value from environment variables or configuration file must be propagated from comfytoo to comfytoo transition (those values are the only ones loaded before the environment variables dump file are loaded)
it=$itdir/comfy_user_uid
if [ -z "${WANTED_UID+x}" ]; then
  if [ -f $it ]; then WANTED_UID=$(cat $it); fi
fi
WANTED_UID=${WANTED_UID:-1024}
write_worldtmpfile $it "$WANTED_UID"
echo "-- WANTED_UID: \"${WANTED_UID}\""

it=$itdir/comfy_user_gid
if [ -z "${WANTED_GID+x}" ]; then
  if [ -f $it ]; then WANTED_GID=$(cat $it); fi
fi
WANTED_GID=${WANTED_GID:-1024}
write_worldtmpfile $it "$WANTED_GID"
echo "-- WANTED_GID: \"${WANTED_GID}\""

# Set security level
it=$itdir/comfy_security_level
if [ -z "${SECURITY_LEVEL+x}" ]; then
  if [ -f $it ]; then SECURITY_LEVEL=$(cat $it); fi
fi
SECURITY_LEVEL=${SECURITY_LEVEL:-"normal"}
write_worldtmpfile $it "$SECURITY_LEVEL"
echo "-- SECURITY_LEVEL: \"${SECURITY_LEVEL}\""

# allow_git_url_install
it=$itdir/comfy_allow_git_url_install
if [ -z "${ALLOW_GIT_URL_INSTALL+x}" ]; then
  if [ -f $it ]; then ALLOW_GIT_URL_INSTALL=$(cat $it); fi
fi
ALLOW_GIT_URL_INSTALL=${ALLOW_GIT_URL_INSTALL:-false}
write_worldtmpfile $it "$ALLOW_GIT_URL_INSTALL"
echo "-- ALLOW_GIT_URL_INSTALL: \"${ALLOW_GIT_URL_INSTALL}\""

# allow_pip_install
it=$itdir/comfy_allow_pip_install
if [ -z "${ALLOW_PIP_INSTALL+x}" ]; then
  if [ -f $it ]; then ALLOW_PIP_INSTALL=$(cat $it); fi
fi
ALLOW_PIP_INSTALL=${ALLOW_PIP_INSTALL:-false}
write_worldtmpfile $it "$ALLOW_PIP_INSTALL"
echo "-- ALLOW_PIP_INSTALL: \"${ALLOW_PIP_INSTALL}\""

# Set network mode
it=$itdir/comfy_network_mode
if [ -z "${NETWORK_MODE+x}" ]; then
  if [ -f $it ]; then NETWORK_MODE=$(cat $it); fi
fi
NETWORK_MODE=${NETWORK_MODE:-"personal_cloud"}
write_worldtmpfile $it "$NETWORK_MODE"
echo "-- NETWORK_MODE: \"${NETWORK_MODE}\""

# Set base directory (if not used, set to $ignore_value)
it=$itdir/comfy_base_directory
if [ -z "${BASE_DIRECTORY+x}" ]; then
  if [ -f $it ]; then BASE_DIRECTORY=$(cat $it); fi
fi
BASE_DIRECTORY=${BASE_DIRECTORY:-"$ignore_value"}
write_worldtmpfile $it "$BASE_DIRECTORY"
echo "-- BASE_DIRECTORY: \"${BASE_DIRECTORY}\""

# Validate base directory
if [ ! -z "$BASE_DIRECTORY" ]; then if [ $BASE_DIRECTORY != $ignore_value ] && [ ! -d "$BASE_DIRECTORY" ]; then error_exit "BASE_DIRECTORY requested but not found or not a directory ($BASE_DIRECTORY)"; fi; fi

echo "== Most Environment variables set"

# if command line arguments are provided, write them to a file, for example /bin/bash would give us a shell as comfy
cmd_override_file=$itdir/comfy_run.sh
if [ ! -z "$*" ]; then 
  echo "!! Seeing command line override, placing it in $cmd_override_file: $*"
  write_worldtmpfile $cmd_override_file "$*"
fi

echo "== Extracting base image information"
# extract base image information
it=/etc/image_base.txt
if [ ! -f $it ]; then error_exit "$it missing, exiting"; fi
echo "-- Base image details (from $it):"; cat $it

# extract comfy user directory
it=/etc/comfyuser_dir
if [ ! -f $it ]; then error_exit "$it missing, exiting"; fi
COMFYUSER_DIR=`cat $it`
echo "-- COMFYUIUSER_DIR: \"${COMFYUSER_DIR}\""
if test -z ${COMFYUSER_DIR}; then error_exit "Empty COMFYUSER_DIR variable"; fi

# extract build base information
it=/etc/build_base.txt
if [ ! -f $it ]; then error_exit "$it missing, exiting"; fi
BUILD_BASE=`cat $it`
BUILD_BASE_FILE=$it
BUILD_BASE_SPECIAL="ubuntu22_cuda12.3.2" # this is a special value: when this feature was introduced, will be used to mark exisitng venv if the marker is not present
echo "-- BUILD_BASE: \"${BUILD_BASE}\""
if test -z ${BUILD_BASE}; then error_exit "Empty BUILD_BASE variable"; fi
if [ "A${BUILD_BASE}" == "Aunknown" ]; then error_exit "Invalid BUILD_BASE value"; fi
DGX_BUILD=$(echo "${BUILD_BASE}" | grep -q "dgx" && echo "true" || echo "false")
BUILD_BASE=$(echo "${BUILD_BASE}" | sed 's/-dgx//g')
if [ "A${DGX_BUILD}" == "Atrue" ]; then echo "-- DGX_BUILD: \"${DGX_BUILD}\""; fi

# Check user id and group id
new_gid=`id -g`
new_uid=`id -u`
echo "== user ($whoami)"
echo "  uid: $new_uid / WANTED_UID: $WANTED_UID"
echo "  gid: $new_gid / WANTED_GID: $WANTED_GID"

save_env() {
  tosave=$1
  echo "-- Saving environment variables to $tosave"
  env | sort > "$tosave"
  # environment variables are saved with the original `umask 0022` permissions to allow the smartgallerytoo user to read them and pass them to the smartgallery user
  chmod 755 "$tosave"
}

load_env() {
  tocheck=$1
  overwrite_if_different=$2
  ignore_list="${ENV_IGNORELIST}"
  obfuscate_part="${ENV_OBFUSCATE_PART}"
  if [ -f "$tocheck" ]; then
    echo "-- Loading environment variables from $tocheck (overwrite existing: $overwrite_if_different) (ignorelist: $ignore_list) (obfuscate: $obfuscate_part)"
    while IFS='=' read -r key value; do
      doit=false
      # checking if the key is in the ignorelist
      for i in $ignore_list; do
        if [[ "A$key" ==  "A$i" ]]; then doit=ignore; break; fi
      done
      if [[ "A$doit" == "Aignore" ]]; then continue; fi
      rvalue=$value
      # checking if part of the key is in the obfuscate list
      doobs=false
      for i in $obfuscate_part; do
        if [[ "A$key" == *"$i"* ]]; then doobs=obfuscate; break; fi
      done
      if [[ "A$doobs" == "Aobfuscate" ]]; then rvalue="**OBFUSCATED**"; fi

      if [ -z "${!key}" ]; then
        echo "  ++ Setting environment variable $key [$rvalue]"
        doit=true
      elif [ "A$overwrite_if_different" == "Atrue" ]; then
        cvalue="${!key}"
        if [[ "A${doobs}" == "Aobfuscate" ]]; then cvalue="**OBFUSCATED**"; fi
        if [[ "A${!key}" != "A${value}" ]]; then
          echo "  @@ Overwriting environment variable $key [$cvalue] -> [$rvalue]"
          doit=true
        else
          echo "  == Environment variable $key [$rvalue] already set and value is unchanged"
        fi
      fi
      if [[ "A$doit" == "Atrue" ]]; then
        export "$key=$value"
      fi
    done < "$tocheck"
  fi
}

lc() { echo "$1" | tr '[:upper:]' '[:lower:]'; }
FORCE_CHOWN=${FORCE_CHOWN:-"false"} # any value works, empty value or false means disabled
FORCE_CHOWN=`lc "${FORCE_CHOWN}"`

# comfytoo is a specfiic user not existing by default on ubuntu, we can check its whomai
if [ "A${whoami}" == "Acomfytoo" ]; then 
  echo "-- Running as comfytoo, will switch comfy to the desired UID/GID"
  # The script is started as comfytoo -- UID/GID 1025/1025
  
  if [ "A${FORCE_CHOWN}" != "Afalse" ]; then
    echo "-- Force chown mode enabled, will force change directory ownership as comfy user during script rerun (might be slow)"
    sudo touch /etc/comfy_force_chown
  fi

  # We are altering the UID/GID of the comfy user to the desired ones and restarting as comfy
  # using usermod for the already create comfy user, knowing it is not already in use
  # per usermod manual: "You must make certain that the named user is not executing any processes when this command is being executed"
  sudo groupmod -o -g ${WANTED_GID} comfy || error_exit "Failed to set GID of comfy user"
  sudo usermod -o -u ${WANTED_UID} comfy || error_exit "Failed to set UID of comfy user"
  sudo chown -R ${WANTED_UID}:${WANTED_GID} /home/comfy || error_exit "Failed to set owner of /home/comfy"
  sudo chown ${WANTED_UID}:${WANTED_GID} ${COMFYUSER_DIR} || error_exit "Failed to set owner of ${COMFYUSER_DIR}"
  save_env /tmp/comfytoo_env.txt  
  # restart the script as comfy set with the correct UID/GID this time
  echo "-- Restarting as comfy user with UID ${WANTED_UID} GID ${WANTED_GID}"
  sudo su comfy $script_fullname || error_exit "subscript failed"
  ok_exit "Clean exit"
fi

# If we are here, the script is started as another user than comfytoo
# because the whoami value for the comfy user can be any existing user, we can not check against it
# instead we check if the UID/GID are the expected ones
if [ "$WANTED_GID" != "$new_gid" ]; then error_exit "comfy MUST be running as UID ${WANTED_UID} GID ${WANTED_GID}, current UID ${new_uid} GID ${new_gid}"; fi
if [ "$WANTED_UID" != "$new_uid" ]; then error_exit "comfy MUST be running as UID ${WANTED_UID} GID ${WANTED_GID}, current UID ${new_uid} GID ${new_gid}"; fi

########## 'comfy' specific section below

# We are therefore running as comfy
echo ""; echo "== Running as comfy"

# Load environment variables one by one if they do not exist from /tmp/comfytoo_env.txt
it=/tmp/comfytoo_env.txt
if [ -f $it ]; then
  echo "-- Loading not already set environment variables from $it"
  load_env $it true
fi

# default umask: 0022 (files readable by others); allow override using the UMASK environment variable
umask "${UMASK:-0022}"
echo "== umask: $(umask)"

# If a command line override was provided, run it
if [ -f $cmd_override_file ]; then
  echo ""; echo "== Running provided command line override from $cmd_override_file"
  sudo chmod +x $cmd_override_file || error_exit "Failed to make $cmd_override_file executable"
  $cmd_override_file
  # This is a complete override of the script, exit right after
  exit 0
fi

######## Environment variables (consume AFTER the load_env)

# if SECURITY_LEVEL is set to weak OR ALLOW_GIT_URL_INSTALL is set to true OR ALLOW_PIP_INSTALL is set to true, enable USE_SOCAT
if [ "${SECURITY_LEVEL:-normal}" = "weak" ] || [ "${ALLOW_GIT_URL_INSTALL:-false}" = "true" ] || [ "${ALLOW_PIP_INSTALL:-false}" = "true" ]; then
  echo "== Security level is weak or ALLOW_GIT_URL_INSTALL or ALLOW_PIP_INSTALL is true, enabling USE_SOCAT and forcing SECURITY_LEVEL to weak"
  USE_SOCAT="true"
  SECURITY_LEVEL="weak"
fi

# Default behavior: listen on 0.0.0.0
USE_SOCAT=${USE_SOCAT:-"false"}
USE_SOCAT=`lc "${USE_SOCAT}"`
if [ "A${USE_SOCAT}" == "Atrue" ]; then
  LISTEN_ADDRESS="127.0.0.1"
  LISTEN_PORT="8181"
  echo "== Using alternate behavior: socat listens on 0.0.0.0:8188 -> forward to ComfyUI on ${LISTEN_ADDRESS}:${LISTEN_PORT}"
else
  LISTEN_ADDRESS="0.0.0.0"
  LISTEN_PORT="8188"
  echo "== Using default behavior: ComfyUI listens on ${LISTEN_ADDRESS}:${LISTEN_PORT}"
fi

# Set ComfyUI base command line
it=$itdir/comfy_cmdline_base
if [ -f $it ]; then COMFY_CMDLINE_BASE=$(cat $it); fi
COMFY_CMDLINE_BASE=${COMFY_CMDLINE_BASE:-"python3 ./main.py --listen ${LISTEN_ADDRESS} --port ${LISTEN_PORT} --disable-auto-launch"}
if [ ! -f $it ]; then write_worldtmpfile $it "$COMFY_CMDLINE_BASE"; fi
echo "-- COMFY_CMDLINE_BASE: \"${COMFY_CMDLINE_BASE}\""

# Set ComfyUI command line extra
if [ ! -z ${COMFY_CMDLINE_XTRA+x} ]; then COMFY_CMDLINE_EXTRA="${COMFY_CMDLINE_XTRA}"; fi # support previous variable
it=$itdir/comfy_cmdline_extra
if [ -f $it ]; then COMFY_CMDLINE_EXTRA=$(cat $it); fi
COMFY_CMDLINE_EXTRA=${COMFY_CMDLINE_EXTRA:-""}
if [ ! -f $it ]; then write_worldtmpfile $it "$COMFY_CMDLINE_EXTRA"; fi
echo "-- COMFY_CMDLINE_EXTRA: \"${COMFY_CMDLINE_EXTRA}\""

########## ComfyUI specific section below

echo ""; echo "== Confirming we have the NVIDIA driver loaded and showing details for the seen GPUs"
if ! command -v nvidia-smi &> /dev/null; then
  error_exit "nvidia-smi not found"
fi
nvidia-smi || error_exit "Failed to run nvidia-smi"

driver_cuda_version=$(nvidia-smi | grep "CUDA Version" | awk -F': ' '{print $3}' | cut -d' ' -f1)
driver_cuda_major=$(echo "$driver_cuda_version" | awk -F'.' '{print $1}')
driver_cuda_minor=$(echo "$driver_cuda_version" | awk -F'.' '{print $2}')
echo ""; echo "-- Found Max driver CUDA version: $driver_cuda_version (major: $driver_cuda_major, minor: $driver_cuda_minor)"
if [ "$driver_cuda_major" -lt 12 ]; then error_exit "Driver CUDA version $driver_cuda_version is below minimum version 12, please upgrade your driver"; fi


# Checking the version of CUDA supported by the container itself to decide which PyTorch wheel to install (from BUILD_BASE)
# per https://pytorch.org/ the default installation is 12.6, but 12.8 is available
cuda_version=$(echo "${BUILD_BASE}" | awk -F'cuda' '{print $2}')
cuda_major=$(echo "$cuda_version" | awk -F'.' '{print $1}')
cuda_minor=$(echo "$cuda_version" | awk -F'.' '{print $2}')
echo "-- Found Max container CUDA version: $cuda_version (major: $cuda_major, minor: $cuda_minor)"
if [ $driver_cuda_minor -gt $cuda_minor ]; then echo "FYSA: The Driver CUDA supports a more recent version than the used container does. Consider using a more recent container version (if available)."; fi


dir_validate() { # arg1 = directory to validate / arg2 = "mount" or ""; a "mount" can not be chmod'ed
  testdir=$1

  if [ ! -d "$testdir" ]; then error_exit "Directory $testdir not found (or not a directory)"; fi

  if [ "A$2" == "A" ] && [ -f /etc/comfy_force_chown ]; then
    echo "  ++ Attempting to recursively set ownership of $testdir to ${WANTED_UID}:${WANTED_GID} (might take a long time)"
    sudo chown -R ${WANTED_UID}:${WANTED_GID} "$testdir" || error_exit "Failed to set owner of $testdir"
  fi

  # check if the directory is owned by WANTED_UID/WANTED_GID
  if [ "$(stat -c %u:%g "$testdir")" != "${WANTED_UID}:${WANTED_GID}" ]; then
    xtra_txt=" -- recommended to start with the FORCE_CHOWN=yes environment varable enabled"
    if [ "A$2" == "Amount" ]; then
      xtra_txt=" -- FORCE_CHOWN will not work for this folder, it is a PATH mounted at container startup and requires a manual fix: chown -R ${WANTED_UID}:${WANTED_GID} foldername"
    fi
    error_exit "Directory $testdir owned by unexpected user/group, expected ${WANTED_UID}:${WANTED_GID}, actual $(stat -c %u:%g "$testdir")$xtra_txt"
  fi

  if [ ! -w "$testdir" ]; then error_exit "Directory $testdir not writeable"; fi
  if [ ! -x "$testdir" ]; then error_exit "Directory $testdir not executable"; fi
  if [ ! -r "$testdir" ]; then error_exit "Directory $testdir not readable"; fi
}

## Path: ${COMFYUSER_DIR}/mnt
echo ""; echo "== Testing write access as the comfy user to the run directory"
it_dir="${COMFYUSER_DIR}/mnt"
dir_validate "${it_dir}" "mount"
it="${it_dir}/.testfile"; touch $it && rm -f $it || error_exit "Failed to write to $it_dir"

##
it_dir="${COMFYUSER_DIR}/mnt/pip_cache"
if [ -d "${it_dir}" ]; then
  echo ""; echo "== ${it_dir} present: Setting the PIP_CACHE_DIR variable to use it"
  dir_validate "${it_dir}"
  it="${it_dir}/.testfile"; touch $it && rm -f $it || error_exit "Failed to write to pip cache directory as the comfy user"
  export PIP_CACHE_DIR=${COMFYUSER_DIR}/mnt/pip_cache
fi

##
it_dir="${COMFYUSER_DIR}/mnt/tmp"
if [ -d "${it_dir}" ]; then
  echo ""; echo "== ${it_dir} present: Setting the TMPDIR variable to use it"
  dir_validate "${it_dir}"
  it="${it_dir}/.testfile"; touch $it && rm -f $it || error_exit "Failed to write to tmp directory as the comfy user"
  export TMPDIR=${COMFYUSER_DIR}/mnt/tmp
fi

##
DISABLE_UPGRADES=${DISABLE_UPGRADES:-"false"}
DISABLE_UPGRADES=`lc "${DISABLE_UPGRADES}"`
if [ "A${DISABLE_UPGRADES}" == "Atrue" ]; then
  echo "== Using alternate behavior: Disabling upgrade (including disabling USE_PIPUPGRADE)"
  USE_PIPUPGRADE="false"
else
  echo "== Using default behavior: Enabling upgrades (behavior depends on USE_PIPUPGRADE)"
fi

PIP3_BASE="pip3"
## uv setup
USE_UV=${USE_UV:-"false"}
USE_UV=`lc "${USE_UV}"`
UPDATE_UV=${UPDATE_UV:-"true"}
if [ "A${USE_UV}" == "Atrue" ]; then
  if [ "A${UPDATE_UV}" == "Atrue" ]; then
    echo "== Updating uv"
    curl -LsSf https://astral.sh/uv/install.sh | sh
  else
    echo "== Using existing uv installation"
  fi
  export PATH="/home/comfy/.local/bin/:$PATH"

  # Check that uv is properly installed and available, and that python3 is available as well
  if ! command -v uv &> /dev/null; then
    error_exit "uv not found after installation"
  fi
  if ! command -v python3 &> /dev/null; then
    error_exit "python3 not found"
  fi

  echo "  == Verify that python3 and uv are installed";
  echo -n "  - python3: "; which python3
  echo -n "    version: "; python3 --version
  echo -n "  -      uv: "; which uv
  echo -n "    version: "; uv --version
  PIP3_BASE="uv pip"

  it_dir="${COMFYUSER_DIR}/mnt/uv_cache"
  if [ ! -d "${it_dir}" ]; then
    mkdir -p "${it_dir}"
    dir_validate "${it_dir}"
    it="${it_dir}/.testfile" && rm -f $it || error_exit "Failed to write to uv cache directory as the comfy user"
  fi
  echo ""; echo "== Setting the UV_CACHE_DIR variable to ${it_dir}"
  export UV_CACHE_DIR="$it_dir"
fi

USE_PIPUPGRADE=${USE_PIPUPGRADE:-"true"}
USE_PIPUPGRADE=`lc "${USE_PIPUPGRADE}"`
DEFAULT_PIP3_CMD="${PIP3_BASE} install --trusted-host pypi.org --trusted-host files.pythonhosted.org"
if [ "A${USE_PIPUPGRADE}" == "Atrue" ]; then
  PIP3_CMD="${DEFAULT_PIP3_CMD} --upgrade"
else
  PIP3_CMD="${DEFAULT_PIP3_CMD}"
fi
echo "== PIP3_CMD: \"${PIP3_CMD}\""

TORCH_LOCK=${TORCH_LOCK:-""}
if [ ! -z "${TORCH_LOCK}" ]; then
  echo "== TORCH_LOCK set: creating constraint file with values: \"${TORCH_LOCK}\""
  # Replace spaces with newlines to ensure valid constraints file format (though pip usually handles spaces, newlines are safer for constraints files)
  echo "${TORCH_LOCK}" | tr ' ' '\n' > ${COMFYUSER_DIR}/mnt/torch_lock.txt
  PIP3_CMD="${PIP3_CMD} --constraint ${COMFYUSER_DIR}/mnt/torch_lock.txt"
  echo "== Updated PIP3_CMD with constraints: \"${PIP3_CMD}\""
fi

##
USE_NEW_REPO_URL=${USE_NEW_REPO_URL:-"true"}
USE_NEW_REPO_URL=`lc "${USE_NEW_REPO_URL}"`
COMFY_REPO_NEW_URL="https://github.com/Comfy-Org/ComfyUI.git"
COMFY_REPO_URL="https://github.com/comfyanonymous/ComfyUI.git"
if [ "A${USE_NEW_REPO_URL}" == "Atrue" ]; then
  COMFY_REPO_URL=${COMFY_REPO_NEW_URL}
fi
it_dir="${COMFYUSER_DIR}/mnt"
echo ""; echo "== Obtaining the latest version of ComfyUI (if folder not present)"
cd $it_dir # ${COMFYUSER_DIR}/mnt -- stay here for the following checks/setups
if [ ! -d "ComfyUI" ]; then
  echo ""; echo "== Cloning ComfyUI"
  git clone ${COMFY_REPO_URL} ComfyUI || error_exit "ComfyUI clone failed"
  if [ "$A{DISABLE_UPGRADES}" == "Atrue" ]; then
    echo ""; echo "== This is a new installation, setting DISABLE_UPGRADES to false"
    DISABLE_UPGRADES=false
  fi
fi

##
echo ""; echo "== Confirm the ComfyUI directory is present and we can write to it"
it_dir="${COMFYUSER_DIR}/mnt/ComfyUI"
dir_validate "${it_dir}" 
it="${it_dir}/.testfile"; touch $it && rm -f $it || error_exit "Failed to write to ComfyUI directory as the comfy user"

# Check that ComfyUI's remote is set to the correct one
cdir="$(pwd)"
cd "${it_dir}"
git_remote=$(git remote get-url origin 2>/dev/null)
if [ "A${git_remote}" != "A${COMFY_REPO_URL}" ]; then
  echo ""; echo "== ComfyUI's remote ($git_remote) is not set to the expected value, updating to ${COMFY_REPO_URL}"
  git remote set-url origin "${COMFY_REPO_URL}"
fi
echo -n "== ComfyUI origin set to: "; git remote get-url origin
echo "   Expected: ${COMFY_REPO_URL}"
cd "${cdir}"

##
echo ""; echo "== Check on BASE_DIRECTORY (if used / if using \"$ignore_value\" then disable it)"
if [ "$BASE_DIRECTORY" == "$ignore_value" ]; then BASE_DIRECTORY=""; fi
if [ ! -z "$BASE_DIRECTORY" ]; then 
  it_dir=$BASE_DIRECTORY
  dir_validate "${it_dir}" "mount"
  it="${it_dir}/.testfile"; touch $it && rm -f $it || error_exit "Failed to write to BASE_DIRECTORY"
fi

##
echo ""; echo "== Validate/Create HuggingFace directory"
it_dir="${COMFYUSER_DIR}/mnt/HF"
if [ ! -d "${it_dir}" ]; then
  echo "";echo "== Creating HF directory"
  mkdir -p ${it_dir}
fi
dir_validate "${it_dir}"
it=${it_dir}/.testfile; touch $it && rm -f $it || error_exit "Failed to write to HF directory as the comfy user"
export HF_HOME=${COMFYUSER_DIR}/mnt/HF

# Attempting to support multiple build bases
# the venv directory is specific to the build base
# we are placing a marker file in the venv directory to match it to a build base
# if the marker is not for container's build base, we rename the venv directory to avoid conflicts

## Current path: ${COMFYUSER_DIR}/mnt
echo ""; echo "== if a venv is present, confirm we can write to it"
it_dir="${COMFYUSER_DIR}/mnt/venv"
if [ -d "${it_dir}" ]; then
  dir_validate "${it_dir}"
  it=${it_dir}/.testfile; touch $it && rm -f $it || error_exit "Failed to write to venv directory as the comfy user"
  # use the special value to mark existing venv if the marker is not present
  it=${it_dir}/.build_base.txt; if [ ! -f $it ]; then echo $BUILD_BASE_SPECIAL > $it; fi
fi

##
echo ""; echo "== Matching any existing venv to container's BUILD_BASE (${BUILD_BASE})"
SWITCHED_VENV=true # this is a marker to indicate that we have switched to a different venv, which is set unless we re-use the same venv as before (see below)
# Check for an existing venv; if present, is it the proper one -- ie does its .build_base.txt match the container's BUILD_BASE_FILE?
if [ -d venv ]; then
  it=venv/.build_base.txt
  venv_bb=`cat $it`

  echo ""
  if cmp --silent $it $BUILD_BASE_FILE; then
    echo "== venv is for this BUILD_BASE (${BUILD_BASE})"
    SWITCHED_VENV=false
  else
    echo "== venv ($venv_bb) is not for this BUILD_BASE (${BUILD_BASE}), renaming it and seeing if a valid one is present"
    mv venv venv-${venv_bb} || error_exit "Failed to rename venv to venv-${venv_bb}"

    if [ -d venv-${BUILD_BASE} ]; then
      echo "== Existing venv (${BUILD_BASE}) found, attempting to use it"
      mv venv-${BUILD_BASE} venv || error_exit "Failed to rename ven-${BUILD_BASE} to venv"
    fi
  fi
fi

##
echo ""; echo "== Create virtualenv for installation (if not present)"
if [ ! -d "venv" ]; then
  echo ""; echo "== Creating virtualenv"
  python3 -m venv venv || error_exit "Virtualenv creation failed"
  echo $BUILD_BASE > venv/.build_base.txt
fi

##
echo ""; echo "== Confirming venv is writeable"
it_dir="${COMFYUSER_DIR}/mnt/venv"
dir_validate "${it_dir}"
it="${it_dir}/.testfile"; touch $it && rm -f $it || error_exit "Failed to write to venv directory as the comfy user"

##
echo ""; echo "== Activate the virtualenv"
it="${it_dir}/bin/activate"
if [ ! -f "$it" ]; then error_exit "virtualenv not created, please erase any venv directory"; fi
echo ""; echo "  == Activating virtualenv"
source "$it" || error_exit "Virtualenv activation failed"
if [ "A${DISABLE_UPGRADES}" != "Atrue" ]; then
  echo ""; echo "  == Upgrading pip"
  ${PIP3_CMD} pip || error_exit "Pip upgrade failed"
fi

# extent the PATH to include the user local bin directory
export PATH=${COMFYUSER_DIR}/.local/bin:${PATH}

# Verify the variables
echo ""; echo ""; echo "==================="
echo "== Environment details:"
echo -n "  PATH: "; echo $PATH
echo -n "  Python version: "; python3 --version
echo -n "  Pip version: "; pip3 --version
echo -n "  python bin: "; which python3
echo -n "  pip bin: "; which pip3
echo -n "  git bin: "; which git
echo "  PIP3_CMD: ${PIP3_CMD}"
echo -n "  DISABLE_UPGRADES: "; echo ${DISABLE_UPGRADES}
echo -n "  USE_PIPUPGRADE: "; echo ${USE_PIPUPGRADE}
echo ""

echo "Installing comfy-cli"
${PIP3_CMD} comfy-cli || error_exit "Failed to install comfy-cli"

export PIP3_CMD=${PIP3_CMD}
run_userscript() {
  userscript=$1
  if [ ! -f $userscript ]; then
    echo "!! ${userscript} not found, skipping it"
    return
  fi

  exec_method=$2
  if [ "A$exec_method" == "Askip" ]; then
    if [ ! -x $userscript ]; then
      echo "!! ${userscript} not executable, skipping it"
      return
    fi
  elif [ "A$exec_method" == "Achmod" ]; then
    if [ ! -x $userscript ]; then
      echo "== Attempting to make user script executable"
      chmod +x $userscript || error_exit "Failed to make user script executable"
    fi
  else
    echo "!! Invalid exec_method: ${exec_method}, skipping it"
    return
  fi
  userscript_name=$(basename $userscript)
  userscript_env="/tmp/comfy_${userscript_name}_env.txt"
  if [ -f $userscript_env ]; then
    rm -f $userscript_env || error_exit "Failed to remove ${userscript_env}"
  fi

  echo "++ Running user script: ${userscript}"
  $userscript || error_exit "User script ($userscript) failed or exited with an error, stopping further processing"

  if [ -f $userscript_env ]; then
    load_env $userscript_env true
  fi
  echo "-- User script completed: ${userscript}"
  echo ""
}

# Check that `pynvml` is not installed, uninstall it if it is
if ${PIP3_BASE} show pynvml &>/dev/null; then
  echo "== Uninstalling pynvml"
  if [ $USE_UV == "true" ]; then
    uv pip uninstall pynvml || error_exit "Failed to uninstall pynvml"
  else
    pip3 uninstall -y pynvml || error_exit "Failed to uninstall pynvml"
  fi
fi

# Pre-install dev packages (used to be 10-pip3Dev.sh)
${PIP3_CMD} setuptools || error_exit "Failed to install setuptools"
${PIP3_CMD} ninja || error_exit "Failed to install ninja"
${PIP3_CMD} cmake || error_exit "Failed to install cmake"
${PIP3_CMD} wheel || error_exit "Failed to install wheel"
${PIP3_CMD} pybind11 || error_exit "Failed to install pybind11"
${PIP3_CMD} packaging || error_exit "Failed to install packaging"
${PIP3_CMD} Cython || error_exit "Failed to install Cython"
# Addressing: FutureWarning: The pynvml package is deprecated. Please install nvidia-ml-py instead.
${PIP3_CMD} nvidia-ml-py || error_exit "Failed to install nvidia-ml-py"
# Manually remove `pynvml` after a `dockr exec`
# % sudo su comfy
# % source /comfy/mnt/venv/bin/activate
# % uv pip uninstall pynvml

# Check for the post-venv script
it=${COMFYUSER_DIR}/mnt/postvenv_script.bash
echo ""; echo "== Checking for post-venv script: ${it}"
run_userscript $it "chmod"

# Prep UV_TORCH_BACKEND and TORCH_INDEX_URL
torch_version="torch torchvision torchaudio"
# Determine CUDA backend based on version
if [ "$cuda_major" -lt 13 ]; then
  if [ "$cuda_minor" -lt 6 ]; then # CUDA 12.4
    echo "== Will be installing torch for CUDA 12.4, disabling upgrade for pip3 if enabled to avoid overwriting torch"
    PIP3_CMD="${DEFAULT_PIP3_CMD}"
    echo "== updated PIP3_CMD: \"${PIP3_CMD}\""
    cuda_backend="cu124"
    torch_version="torch==2.6.0 torchvision==0.21.0 torchaudio==2.6.0"
  elif [ "$cuda_minor" -lt 8 ]; then # CUDA 12.6
    cuda_backend="cu126"
  elif [ "$cuda_minor" -lt 9 ]; then # CUDA 12.8
    cuda_backend="cu128"
  else # CUDA 12.9
    cuda_backend="cu129"
  fi
else # CUDA 13.2 -- https://download.pytorch.org/whl/cu132 is now there, and uv supports it -- but Comfy requires cu130 for now, so we will use that
#  if [ "$cuda_minor" -gt 1 ]; then
#    cuda_backend="cu132"
#  else # CUDA 13.0 and 13.1 use the same wheel
    cuda_backend="cu130"
#  fi
fi

# check that cuda_backend is set
if [ -z "${cuda_backend}" ]; then error_exit "cuda_backend is not set"; fi

if [ ! -z "${TORCH_LOCK}" ]; then
  echo "== TORCH_LOCK set: locking torch version to ${TORCH_LOCK}"
  torch_version="${TORCH_LOCK}"
fi

# Apply backend to either UV or pip
if [ "A${USE_UV}" == "Atrue" ]; then
  export UV_TORCH_BACKEND="${cuda_backend}"
else
  export TORCH_INDEX_URL="https://download.pytorch.org/whl/${cuda_backend}"
fi
# We are exporting UV_TORCH_BACKEND and TORCH_INDEX_URL to make it available to the userscripts

# Pre-install/upgrade Torch (default is true, unless DISABLE_UPGRADES is set to true)
if [ "A${DISABLE_UPGRADES}" == "Atrue" ]; then
  echo "== Torch upgrade disabled by DISABLE_UPGRADES"
else
  PREINSTALL_TORCH=${PREINSTALL_TORCH:-"true"}
  if [ "A${PREINSTALL_TORCH}" == "Atrue" ]; then
    echo ""; echo "== Pre-installing/Upgrading torch"
    # Allow the override of the torch installation command
    if [ ! -z "${PREINSTALL_TORCH_CMD+x}" ]; then
      it="${PREINSTALL_TORCH_CMD}"
      # fix: recommendation was to use "pip3 install ..." must remove "pip3 install" from the command
      it=${it//pip3 install/}
    else
      if [ "A${USE_UV}" == "Atrue" ]; then
        if [ ! ${UV_TORCH_BACKEND+x} ]; then error_exit "UV_TORCH_BACKEND is not set"; fi
        echo "== Installing torch using uv with backend: ${UV_TORCH_BACKEND}"
        it="${torch_version}"
      else
        if [ ! ${TORCH_INDEX_URL+x} ]; then error_exit "TORCH_INDEX_URL is not set"; fi
        echo "== Installing torch using pip with index url: ${TORCH_INDEX_URL}"
        it="${torch_version} --index-url ${TORCH_INDEX_URL}"
      fi
    fi

    echo "Installing: ${it}"
    ${PIP3_CMD} ${it} || error_exit "Torch installation failed"
  fi
fi

# Install ComfyUI's requirements
cd ComfyUI
it=requirements.txt
if [ "A${DISABLE_UPGRADES}" == "Atrue" ]; then
  echo "== ComfyUI requirements upgrade disabled by DISABLE_UPGRADES"
else
  echo ""; echo "== Installing/Updating from ComfyUI's requirements"
  ${PIP3_CMD} -r $it || error_exit "ComfyUI requirements install/upgrade failed"
fi

# Install Huggingface Hub
if [ "A${DISABLE_UPGRADES}" == "Atrue" ]; then
  echo "== Huggingface Hub upgrade disabled by DISABLE_UPGRADES"
else
  echo ""; echo "== Installing Huggingface Hub"
  ${PIP3_CMD} "huggingface_hub" || error_exit "HuggingFace Hub install/upgrade failed"
fi

export COMFYUI_PATH=`pwd`
echo ""; echo "-- COMFYUI_PATH: ${COMFYUI_PATH}"

USE_NEW_MANAGER=${USE_NEW_MANAGER:-"false"}

# if the legacy manager is not installed, we will install the new manager instead
customnodes_dir=${COMFYUI_PATH}/custom_nodes
if [ ! -z "$BASE_DIRECTORY" ]; then it=${BASE_DIRECTORY}/custom_nodes; if [ -d $it ]; then customnodes_dir=$it; fi; fi
it="$it/ComfyUI-Manager"
if [ ! -d "$it" ]; then
  echo "!! Legacy ComfyUI Manager not found, using new ComfyUI Manager"
  USE_NEW_MANAGER="true"
fi

# if the new manager is requested, install it
# Per https://blog.comfy.org/p/meet-the-new-comfyui-manager the new one and old one can exist together
if [ "A${USE_NEW_MANAGER}" == "Atrue" ]; then
  echo "== Using new ComfyUI Manager"
  it_dir="${COMFYUI_PATH}"
  new_manager_requirements="$it_dir/manager_requirements.txt"
  if [ ! -f $new_manager_requirements ]; then
    echo "== ComfyUI Manager requirements not found, using legacy ComfyUI Manager"
    USE_NEW_MANAGER="false"
  else
    echo "== Installing/Updating from ComfyUI Manager's requirements"
    ${PIP3_CMD} -r $new_manager_requirements || error_exit "ComfyUI Manager requirements install/upgrade failed"
  fi
fi

if [ "A${USE_NEW_MANAGER}" == "Afalse" ]; then
  echo "== Using legacy ComfyUI Manager"

  # Install ComfyUI Manager if not already present
  echo ""
  customnodes_dir=${COMFYUI_PATH}/custom_nodes
  if [ ! -z "$BASE_DIRECTORY" ]; then it=${BASE_DIRECTORY}/custom_nodes; if [ -d $it ]; then customnodes_dir=$it; fi; fi
  cd ${customnodes_dir}
  if [ ! -d ComfyUI-Manager ]; then
    echo "== Cloning ComfyUI-Manager (within ${customnodes_dir})"
    git clone https://github.com/ltdrdata/ComfyUI-Manager.git || error_exit "ComfyUI-Manager clone failed"
    echo "== Installing ComfyUI-Manager's requirements (from ${customnodes_dir}/ComfyUI-Manager/requirements.txt)"
    ${PIP3_CMD} -r ${customnodes_dir}/ComfyUI-Manager/requirements.txt || error_exit "ComfyUI-Manager CLI requirements installation failed" 
  fi
  if [ ! -d ComfyUI-Manager ]; then error_exit "ComfyUI-Manager not found"; fi
  if [ "A${DISABLE_UPGRADES}" == "Atrue" ]; then
    echo "== ComfyUI-Manager packages upgrade disabled by DISABLE_UPGRADES"
  else
    echo "== Installing/Updating ComfyUI-Manager's requirements (from ${customnodes_dir}/ComfyUI-Manager/requirements.txt)"
    ${PIP3_CMD} -r ${customnodes_dir}/ComfyUI-Manager/requirements.txt || error_exit "ComfyUI-Manager CLI requirements install/upgrade failed" 
  fi
fi

# Please see https://github.com/ltdrdata/ComfyUI-Manager?tab=readme-ov-file#security-policy for details on authorized values
# recent releases of ComfyUI-Manager have a config.ini file in the user folder, if this is not present, we expect it in the default folder
# 3.38 new path: /basedir/user/__manager/config.ini
cm_conf_candidates="user/__manager/config.ini user/default/ComfyUI-Manager/config.ini custom_nodes/ComfyUI-Manager/config.ini"
cm_conf="NOT_FOUND"
if [ ! -z "$BASE_DIRECTORY" ]; then
  for it in $cm_conf_candidates; do
    if [ -f $BASE_DIRECTORY/$it ]; then cm_conf=$BASE_DIRECTORY/$it; break; fi
  done
else
  for it in $cm_conf_candidates; do
    if [ -f ${COMFYUI_PATH}/$it ]; then cm_conf=${COMFYUI_PATH}/$it; break; fi
  done
fi
echo ""
echo "== ComfyUI-Manager config file: $cm_conf"
echo ""
if [ ! -f $cm_conf ]; then
  echo "== ComfyUI-Manager $cm_conf not found-- script potentially never run before. You will need to run ComfyUI-Manager a first time for the configuration file to be generated, we can not attempt to update its security level yet -- if this keeps occurring, please let the developer know so he can investigate. Thank you"
else
  echo "  -- Using ComfyUI-Manager config file: $cm_conf"
  # SECURITY_LEVEL
  perl -p -i -e 's%^security_level\s*=.+$%security_level = '${SECURITY_LEVEL}'%g' $cm_conf
  echo -n "  -- ComfyUI-Manager (should show: ${SECURITY_LEVEL}): "
  grep security_level $cm_conf
  # USE_UV
  W_UV="False"; if [ "A${USE_UV}" == "Atrue" ]; then W_UV="True"; fi
  perl -p -i -e 's%^use_uv\s*=.+$%use_uv = '${W_UV}'%g' $cm_conf
  echo -n "  -- ComfyUI-Manager (should show: ${W_UV}): "
  grep use_uv $cm_conf
  # NETWORK_MODE=personal_cloud
  perl -p -i -e 's%^network_mode\s*=.+$%network_mode = '${NETWORK_MODE}'%g' $cm_conf
  echo -n "  -- ComfyUI-Manager (should show: ${NETWORK_MODE}): "
  grep network_mode $cm_conf
  # ALLOW_GIT_URL_INSTALL
  perl -p -i -e 's%^allow_git_url_install\s*=.+$%allow_git_url_install = '${ALLOW_GIT_URL_INSTALL}'%g' $cm_conf
  echo -n "  -- ComfyUI-Manager (should show: ${ALLOW_GIT_URL_INSTALL}): "
  grep allow_git_url_install $cm_conf
  # ALLOW_PIP_INSTALL
  perl -p -i -e 's%^allow_pip_install\s*=.+$%allow_pip_install = '${ALLOW_PIP_INSTALL}'%g' $cm_conf
  echo -n "  -- ComfyUI-Manager (should show: ${ALLOW_PIP_INSTALL}): "
  grep allow_pip_install $cm_conf
fi

# Attempt to use ComfyUI Manager CLI to fix all installed nodes -- This must be done within the activated virtualenv
echo ""
echo "== SWITCHED_VENV: ${SWITCHED_VENV}"
if [ "A${SWITCHED_VENV}" == "Afalse" ]; then
  echo "== Skipping ComfyUI-Manager CLI fix as we are re-using the same venv as the last execution"
  echo "  -- If you are experiencing issues with custom nodes, use 'Manager -> Custom Nodes Manager -> Filter: Import Failed -> Try Fix' from the WebUI"
else 
  cm_cli=${COMFYUI_PATH}/custom_nodes/ComfyUI-Manager/cm-cli.py
  if [ ! -z "$BASE_DIRECTORY" ]; then it=${BASE_DIRECTORY}/custom_nodes/ComfyUI-Manager/cm-cli.py ; if [ -f $it ]; then cm_cli=$it; fi; fi
  it="/comfy/mnt/venv/bin/cm-cli"; if [ -f $it ]; then cm_cli="/not_at_file"; fi
  if [ "A${cm_cli}" == "A/not_at_file" ]; then
    echo "== ComfyUI-Manager CLI is part of the virtual environment (new manager) and is to be used with the comfy cli which currently does NOT support the base-directory option, skipping. Prefer: userscripts_dir/05-customnodes_fixer.sh"
  elif [ -f $cm_cli ]; then
    echo "== Running ComfyUI-Manager CLI to fix installed custom nodes"
    python3 $cm_cli fix all || echo "ComfyUI-Manager CLI failed -- in case of issue with custom nodes: use 'Manager -> Custom Nodes Manager -> Filter: Import Failed -> Try Fix' from the WebUI"
  else
    echo "== ComfyUI-Manager CLI not found, skipping"
  fi
fi

# If we are using a base directory... 
if [ ! -z "$BASE_DIRECTORY" ]; then
  if [ ! -d "$BASE_DIRECTORY" ]; then error_exit "BASE_DIRECTORY ($BASE_DIRECTORY) not found or not a directory"; fi
  dir_validate "${BASE_DIRECTORY}" "mount"
  it=${BASE_DIRECTORY}/.testfile; touch $it && rm -f $it || error_exit "Failed to write to BASE_DIRECTORY"

  echo ""; echo "== Setting base_directory: $BASE_DIRECTORY"

  # List of content to process obtained from https://github.com/comfyanonymous/ComfyUI/pull/6600/files

  # we want to MOVE content from the expected directories into the new base_directory (if those directories do not exist yet)
  # any git pull on the ComfyUI directory will create new folder structure under the source directories but since we have moved existing
  # ones to the new base_directory, the new structure will be ignored
  echo "++ Logic to move content from ComfyUI directories to the new base_directory"
  for i in models input output temp user custom_nodes; do
    in=${COMFYUI_PATH}/$i
    out=${BASE_DIRECTORY}/$i
    if [ -d $in ]; then
      if [ ! -d $out ]; then
        echo "  ++ Moving $in to $out"
        mv $in $out || error_exit "Failed to move $in to $out"
      else
        echo "  -- Both $in (in) and $out (out) exist, skipping move."
        echo "FYI attempting to list files in 'in' that are not in 'out' (empty means no differences):"
        comm -23 <(find $in -type f -printf "%P\n" | sort) <(find $out -type f -printf "%P\n" | sort)
      fi
    else
        if [ ! -d $out ]; then
          echo "  ++ $in not found, $out does not exist: creating destination directory"
          mkdir -p $out || error_exit "Failed to create $out"
        else
          echo "  -- $in not found, $out exists, skipping"
        fi
    fi

    dir_validate "$out"
    it=${out}/.testfile; touch $it && rm -f $it || error_exit "Failed to write to $out"
  done

  # Next check that all expected directories in models are present. Create them otherwise
  echo "  == Checking models directory"
  present_directories=""
  if [ -d ${BASE_DIRECTORY}/models ]; then
    for i in ${BASE_DIRECTORY}/models/*; do
      if [ -d $i ]; then  
        present_directories+="${i##*/} "
      fi
    done
  fi

  present_directories_unique=$(echo "$present_directories" checkpoints loras vae configs clip_vision style_models diffusers vae_approx gligen upscale_models embeddings hypernetworks photomaker classifiers| tr ' ' '\n' | sort -u | tr '\n' ' ')

  for i in ${present_directories_unique}; do
    it=${BASE_DIRECTORY}/models/$i
    if [ ! -d $it ]; then
      echo "    ++ Creating $it"
      mkdir -p $it || error_exit "Failed to create $it"
    else
      echo "    -- $it already exists, skipping"
    fi

    dir_validate "$it"
    it=${it}/.testfile; touch $it && rm -f $it || error_exit "Failed to write to $it"
  done

  # Re-Create the ComfyUI/user folder if it does not exist, so the comfyui.db can be placeed there (needed until BASEDIR is supported)
  # per https://github.com/mmartial/ComfyUI-Nvidia-Docker/issues/81
  it=${COMFYUI_PATH}/user
  if [ ! -d $it ]; then
    echo "  ++ Creating $it"
    mkdir -p $it || error_exit "Failed to create $it"
  fi

  # and extend the command line using COMFY_CMDLINE_EXTRA (export to be accessible to child processes such as the user script)
  export COMFY_CMDLINE_EXTRA="${COMFY_CMDLINE_EXTRA} --base-directory $BASE_DIRECTORY"
  echo "!! COMFY_CMDLINE_EXTRA extended, make sure to use it in user script (if any): ${COMFY_CMDLINE_EXTRA}"
fi

# Using comfy CLI to set some default values -- does not set basedir, unable to update nodes?
echo ""; echo "== Using comfy CLI to set some default values"
comfy set-default /comfy/mnt/ComfyUI
comfy setup --where local --project-dir /basedir -y
comfy tracking disable
comfy --install-completion

if [ "A${USE_NEW_MANAGER}" == "Atrue" ]; then
  echo "== Using new ComfyUI Manager's required command line addition: --enable-manager"
  export COMFY_CMDLINE_EXTRA="${COMFY_CMDLINE_EXTRA} --enable-manager"
  USE_LEGACY_UI=${USE_LEGACY_UI:-"false"}
  # it is possible to keep the legacy UI while using the new manager
  # per https://github.com/comfyanonymous/ComfyUI?tab=readme-ov-file#command-line-options
  if [ "A${ENABLE_MANAGER_LEGACY_UI}" == "Atrue" ]; then
    echo "== Enabling Manager's legacy UI"
    export COMFY_CMDLINE_EXTRA="${COMFY_CMDLINE_EXTRA} --enable-manager-legacy-ui"
  fi
  echo "!! COMFY_CMDLINE_EXTRA extended, make sure to use it in user script (if any): ${COMFY_CMDLINE_EXTRA}"
fi

# Final steps before running ComfyUI
cd ${COMFYUI_PATH}
echo "";echo -n "== Container directory: "; pwd

# Saving environment variables
it=/tmp/comfy_env.txt
save_env $it


# Run independent user scripts if a /userscript_dir is mounted
it_dir=/userscripts_dir
if [ -d $it_dir ]; then
  echo "== Running user scripts from directory: ${it_dir}"
  torun=$(ls $it_dir/*.sh | sort)
  # Order the scripts by name to run them in order
  for it in $torun; do
    run_userscript $it "skip"
  done
fi


# Check for the main custom user script (usually with command line override)
it=${COMFYUSER_DIR}/mnt/user_script.bash
echo ""; echo "== Checking for primary user script: ${it}"
run_userscript $it "chmod"


# Saving environment variables
it=/tmp/comfy_env_final.txt
save_env $it

# Run socat if requested
if [ "A${USE_SOCAT}" == "Atrue" ]; then
  echo ""; echo "==================="
  echo "== Running socat"
  socat TCP4-LISTEN:8188,fork,reuseaddr TCP4:127.0.0.1:8181,retry=30,interval=1,forever &
fi

echo ""; echo "==================="
echo "== Running ComfyUI"
# Full list of CLI options at https://github.com/comfyanonymous/ComfyUI/blob/master/comfy/cli_args.py
echo "-- Command line run: ${COMFY_CMDLINE_BASE} ${COMFY_CMDLINE_EXTRA}"
${COMFY_CMDLINE_BASE} ${COMFY_CMDLINE_EXTRA} || error_exit "ComfyUI failed or exited with an error"

ok_exit "Clean exit"
