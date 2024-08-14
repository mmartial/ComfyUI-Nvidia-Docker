#!/bin/bash

set -e

if [ ! -f /etc/comfy_dir ]; then
  echo "/etc/comfy_dir missing, exiting"
  exit 1
fi


COMFY_DIR=`cat /etc/comfy_dir`
echo "-- COMFY_DIR: \"${COMFY_DIR}\""

# we are running as comfy, see if we need to modify UID/GID
comfy_uid=`id -u`
comfy_gid=`id -g`

do_change="False"
# Not checking the passed WANTED_ value (if any)

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
  (sudo addgroup --group --gid ${WANTED_GID} comfytoo || true)
  sudo adduser --force-badname --disabled-password --gecos '' --uid ${WANTED_UID} --gid ${WANTED_GID} --shell /bin/bash comfytoo
  sudo adduser comfytoo sudo
  sudo chmod 755 /home/comfy
  sudo chown -R comfytoo:comfytoo /home/comfy/mnt

  # Reload the script to bypass limitation (and exit)
  sudo su comfytoo /home/init.bash && exit
fi

new_gid=`id -g`
new_uid=`id -u`
echo "== user -- uid: $new_uid / gid: $new_gid"
if [ ! -z "$WANTED_GID" -a "$WANTED_GID" != "$new_gid" ]; then echo "Wrong GID ($new_gid), exiting"; exit 0; fi
if [ ! -z "$WANTED_UID" -a "$WANTED_UID" != "$new_uid" ]; then echo "Wrong UID ($new_uid), exiting"; exit 0; fi

# This should be the only directory mounted 
cd /home/comfy/mnt
for dir in HF data/input data/output data/temp user models/checkpoints models/clip models/clip_vision models/configs models/controlnet models/diffusers models/embeddings models/gligen models/hypernetworks models/loras models/photomaker models/style_models models/unet models/upscale_models models/vae models/vae_approx; do
  if [ ! -d $dir ]; then echo "-- Attempting to create directory $dir"; mkdir -p $dir; fi
  if [ ! -d $dir ]; then echo "** Unable to create directory $dir -- exiting"; exit 1; fi 
done

# Full list of CLI options at https://github.com/comfyanonymous/ComfyUI/blob/master/comfy/cli_args.py
cd ${COMFY_DIR}
python3 main.py --listen 0.0.0.0 --disable-auto-launch --output-directory /home/comfy/mnt/data/output --temp-directory /home/comfy/mnt/data/temp --input-directory /home/comfy/mnt/data/input
