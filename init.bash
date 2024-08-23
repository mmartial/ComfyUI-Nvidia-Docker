#!/bin/bash

set -e

error_exit() {
  echo $*
  exit 1
}

whoami=`whoami`
script_dir=$(dirname $0)
script_name=$(basename $0)
echo "== Running ${script_name} in ${script_dir} as ${whoami}"
script_fullname=$0
cmd_wuid=$1
cmd_wgid=$2

if [ -z "$WANTED_UID" ]; then
  WANTED_UID=$cmd_wuid
fi
if [ -z "$WANTED_GID" ]; then
  WANTED_GID=$cmd_wgid
fi
if [ -z "$WANTED_UID" ]; then
  error_exit "Missing WANTED_UID"
fi
if [ -z "$WANTED_GID" ]; then
  error_exit "Missing WANTED_GID"
fi

# The script is started as comfy
# if the UID/GID are not correct, we create a new comfytoo user with the correct UID/GID which will restart the script
# after the script restart we restart again as comfy
if [ "A${whoami}" == "Acomfytoo" ]; then 
  echo "-- Not running as comfy, will try to switch to comfy (Docker USER)"
  # Make the comfy user (the Docker USER) have the proper UID/GID as well
  sudo usermod -u ${WANTED_UID} -o -g ${WANTED_GID} comfy
  # restart the script as comfy (Docker USER) with the correct UID/GID this time
  sudo su comfy $script_fullname $WANTED_UID $WANTED_GID && exit
fi

it=/etc/comfy_base.txt
if [ ! -f $it ]; then error_exit "$it missing, exiting"; fi
echo "-- Base image details (from $it):"; cat $it

it=/etc/comfyuser_dir
if [ ! -f $it ]; then error_exit "$it missing, exiting"; fi
COMFYUSER_DIR=`cat $it`
echo "-- COMFYUIUSER_DIR: \"${COMFYUSER_DIR}\""
if test -z ${COMFYUSER_DIR}; then error_exit "Empty COMFYUSER_DIR variable"; fi

it=${COMFYUSER_DIR}/comfy_main.txt
if [ ! -f $it ]; then error_exit "$it missing, exiting"; fi
echo "-- Main image details (from $it):"; cat $it

it=${COMFYUSER_DIR}/comfy_dir
if [ ! -f $it ]; then error_exit "$it missing, exiting"; fi
COMFY_DIR=`cat $it`
echo "-- COMFY_DIR: \"${COMFY_DIR}\""
if test -z ${COMFY_DIR}; then error_exit "Empty COMFY_DIR variable"; fi

it=${COMFYUSER_DIR}/comfymnt_dir
if [ ! -f $it ]; then error_exit "$it missing, exiting"; fi
COMFYMNT_DIR=`cat $it`
echo "-- COMFYMNT_DIR: \"${COMFYMNT_DIR}\""
if test -z ${COMFYMNT_DIR}; then error_exit "Empty COMFYMNT_DIR variable"; fi

it=${COMFYUSER_DIR}/comfy_userdir
if [ ! -f $it ]; then error_exit "$it missing, exiting"; fi
COMFY_USERDIR=`cat $it`
if test -z ${COMFY_USERDIR}; then error_exit "Empty COMFY_USERDIR variable"; fi
echo "-- Content directory: \"${COMFY_USERDIR}\""
#find ${COMFY_USERDIR} -type f -exec ls -l {} \;

it=${COMFYUSER_DIR}/comfy_version
if [ ! -f $it ]; then error_exit "$it missing, exiting"; fi
COMFY_VERSION=`cat $it`
if test -z ${COMFY_VERSION}; then error_exit "Empty COMFY_VERSION variable"; fi
echo "-- ComfyUI version: \"${COMFY_VERSION}\""

# we are running with some given UID/GID, do we need to modify UID/GID
comfy_uid=`id -u`
comfy_gid=`id -g`

do_change="False"

if [ ! -z "$WANTED_GID" -a "$WANTED_GID" != "$comfy_gid" ]; then
  echo "-- Will attempt to create a new user with GID ${WANTED_GID}"
  do_change="True"
fi
if [ ! -z "$WANTED_UID" -a "$WANTED_UID" != "$comfy_uid" ]; then
  echo "-- Will attempt to create a new user with UID ${WANTED_UID}"
  do_change="True"
fi

if [ $do_change == "True" ]; then
  # Make a "comfytoo" user
  sudo chown -R ${WANTED_UID}:${WANTED_GID} ${COMFYUSER_DIR}
  (getent group ${WANTED_GID} || (sudo addgroup --group --gid ${WANTED_GID} comfytoo || true))
  sudo useradd -u ${WANTED_UID} -o -g ${WANTED_GID} -s /bin/bash -d ${COMFYUSER_DIR} -M comfytoo
  sudo adduser comfytoo sudo
  # change the source directory owned by the expected UID/GID
  sudo chown -R ${WANTED_UID}:${WANTED_GID} ${COMFYMNT_DIR}
  sudo chown -R ${WANTED_UID}:${WANTED_GID} ${COMFY_USERDIR}
  sudo chown -R ${WANTED_UID}:${WANTED_GID} ${COMFY_DIR}
  # Reload the script to bypass limitation (and exit)
  sudo su comfytoo $script_fullname ${WANTED_UID} ${WANTED_GID} && exit
fi

new_gid=`id -g`
new_uid=`id -u`
echo "== user -- uid: $new_uid / gid: $new_gid"
if [ ! -z "$WANTED_GID" -a "$WANTED_GID" != "$new_gid" ]; then echo "Wrong GID ($new_gid), exiting"; exit 0; fi
if [ ! -z "$WANTED_UID" -a "$WANTED_UID" != "$new_uid" ]; then echo "Wrong UID ($new_uid), exiting"; exit 0; fi


# ${COMFYMNT_DIR} is mounted to the `docker run [...] -v` and is the only directory we should write to 
# rsync the prepared directory, doing its best to not overwrite existing files (using "update" keep the most recent) or remove files that are already in the destination
rsync -avRuh  ${COMFY_USERDIR}/./* ${COMFYMNT_DIR}/. || error_exit "rsync failed"

# virtualenv for custom installs
cd ${COMFYMNT_DIR}
if [ ! -d "venv" ]; then
  python3 -m venv --system-site-packages venv 
fi

# Activate the virtualenv and upgrade pip
if [ ! -f ${COMFYMNT_DIR}/venv/bin/activate ]; then error_exit "Virtualenv not created, please erase any venv directory"; fi
source ${COMFYMNT_DIR}/venv/bin/activate
pip3 install --upgrade pip
echo -n "PATH: "; echo $PATH
echo -n "Python version: "; python3 --version
echo -n "Pip version: "; pip3 --version
echo -n "python bin: "; which python3
echo -n "pip bin: "; which pip3
echo -n "git bin: "; which git

# Full list of CLI options at https://github.com/comfyanonymous/ComfyUI/blob/master/comfy/cli_args.py
cd ${COMFY_DIR}
export COMFYUI_PATH=${COMFY_DIR}
echo "-- COMFYUI_PATH: ${COMFYUI_PATH}"
echo "-- ComfyUI version: \"${COMFY_VERSION}\""
python3 ./main.py --listen 0.0.0.0 --disable-auto-launch --temp-directory /comfy/mnt/data
