#!/bin/bash

script_name=$(basename $0)

# This script will check for installed NVIDIA development tools
#
# At the end of the run, we are saving the environment variables to /tmp/comfy_${script_name}_env.txt
# so they can be used by the init.bash script

set -e

error_exit() {
  echo -n "!! ERROR: "
  echo $*
  echo "!! Exiting script (ID: $$)"
  exit 1
}

check_nvcc() {
  if ! command -v nvcc &> /dev/null; then
    return 1
  fi
  return 0
}

save_env() {
  tosave=$1
  echo "-- Saving environment variables to $tosave"
  env | sort > "$tosave"
}


echo "Obtaining build base"
cd /comfy/mnt
bb="venv/.build_base.txt"
if [ ! -f $bb ]; then error_exit "${bb} not found"; fi
BUILD_BASE=$(cat $bb)
if [ "A$BUILD_BASE" = "A" ]; then error_exit "BUILD_BASE is empty"; fi

echo " ++ Build base: ${BUILD_BASE}"

# Attempt to fix the dpkg lock potential issue
# the dpkg step might fail so always exiting with "true" 
if [ -f /var/lib/dpkg/lock ]; then
  echo "++ Attempting to fix dpkg lock"
  sudo rm /var/lib/dpkg/lock
  sudo dpkg --configure -a || true
fi

echo "Checking if nvcc is available"
if ! check_nvcc; then
  error_exit " !! nvcc not found, stopping further execution"
fi

save_env /tmp/comfy_${script_name}_env.txt
exit 0
