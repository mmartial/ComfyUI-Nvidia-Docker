#!/bin/bash

set -e

error_exit() {
  echo $*
  exit 1
}

it=/etc/comfy_base.txt
if [ ! -f $it ]; then error_exit "$it missing, exiting"; fi
echo "-- Base image details (from $it):"; cat $it

it=/etc/comfy_main.txt
if [ ! -f $it ]; then error_exit "$it missing, exiting"; fi
echo "-- Main image details (from $it):"; cat $it

it=/etc/comfy_dir
if [ ! -f $it ]; then error_exit "$it missing, exiting"; fi
COMFY_DIR=`cat $it`
echo "-- COMFY_DIR: \"${COMFY_DIR}\""
if test -z ${COMFY_DIR}; then error_exit "Empty COMFY_DIR variable"; fi

it=/etc/comfy_userdir
if [ ! -f $it ]; then error_exit "$it missing, exiting"; fi
COMFY_USERDIR=`cat $it`
if test -z ${COMFY_USERDIR}; then error_exit "Empty COMFY_USERDIR variable"; fi
echo "-- Content directory: \"${COMFY_USERDIR}\""
find ${COMFY_USERDIR} -type f -exec ls -l {} \;


it=/etc/comfy_version
if [ ! -f $it ]; then error_exit "$it missing, exiting"; fi
COMFY_VERSION=`cat $it`
if test -z ${COMFY_VERSION}; then error_exit "Empty COMFY_VERSION variable"; fi
echo "-- ComfyUI version: \"${COMFY_VERSION}\""

# we are running with some given UID/GID, do we need to modify UID/GID
comfy_uid=`id -u`
comfy_gid=`id -g`

do_change="False"
# Not checking the validity (or security) of passed WANTED_ value

do_gid="False"
if [ ! -z "$WANTED_GID" -a "$WANTED_GID" != "$comfy_gid" ]; then
  echo "-- Will attempt to create a new user with GID ${WANTED_GID}"
  do_change="True"
  do_gid="True"
fi
do_uid="False"
if [ ! -z "$WANTED_UID" -a "$WANTED_UID" != "$comfy_uid" ]; then
  echo "-- Will attempt to create a new user with UID ${WANTED_UID}"
  do_change="True"
  do_uid="True"
fi

if [ $do_change == "True" ]; then
  (getent group ${WANTED_GID} || (sudo addgroup --group --gid ${WANTED_GID} comfytoo || true))
  sudo adduser --force-badname --disabled-password --gecos '' --uid ${WANTED_UID} --gid ${WANTED_GID} --shell /bin/bash comfytoo
  sudo adduser comfytoo sudo
  sudo chmod 755 /home/comfy
  sudo chown -R ${WANTED_UID}:${WANTED_GID} /home/comfy/mnt

  # Reload the script to bypass limitation (and exit)
  sudo su comfytoo /home/init.bash && exit
fi

new_gid=`id -g`
new_uid=`id -u`
echo "== user -- uid: $new_uid / gid: $new_gid"
if [ ! -z "$WANTED_GID" -a "$WANTED_GID" != "$new_gid" ]; then echo "Wrong GID ($new_gid), exiting"; exit 0; fi
if [ ! -z "$WANTED_UID" -a "$WANTED_UID" != "$new_uid" ]; then echo "Wrong UID ($new_uid), exiting"; exit 0; fi

# Make the rsync source directory owned by the expected UID/GID
sudo chown -R ${WANTED_UID}:${WANTED_GID} ${COMFY_USERDIR}

# /home/comfy/mnt/ is mounted to the `docker run [...] -v` and is the only directory we should write to 
# rsync the prepared directory, doing its best to not overwrite existing files (using "update" keep the most recent) or remove files that are already in the destination
rsync -avRuh  ${COMFY_USERDIR}/./* /home/comfy/mnt/. || error_exit "rsync failed"

# Full list of CLI options at https://github.com/comfyanonymous/ComfyUI/blob/master/comfy/cli_args.py
cd ${COMFY_DIR}
echo "-- ComfyUI version: \"${COMFY_VERSION}\""
python3 ./main.py --listen 0.0.0.0 --disable-auto-launch --temp-directory /home/comfy/mnt/data/temp
