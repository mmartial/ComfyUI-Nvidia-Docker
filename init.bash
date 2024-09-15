#!/bin/bash

set -e

error_exit() {
  echo $*
  exit 1
}

whoami=`whoami`
script_dir=$(dirname $0)
script_name=$(basename $0)
echo "======================================"
echo "==================="
echo "== Running ${script_name} in ${script_dir} as ${whoami}"
script_fullname=$0
cmd_wuid=$1
cmd_wgid=$2
cmd_cmdline_base=$3
cmd_cmdline_xtra=$4

# everyone can read our files by default
umask 0022

# Write a world-writeable file (preferably inside /tmp within the container)
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

it=$itdir/comfy_cmdline_base
if [ ! -z "$cmd_cmdline_base" ]; then COMFY_CMDLINE_BASE=`cat $cmd_cmdline_base`; else cmd_cmdline_base=$it;  fi
if [ -z ${COMFY_CMDLINE_BASE+x} ]; then COMFY_CMDLINE_BASE="python3 ./main.py --listen 0.0.0.0 --disable-auto-launch"; fi
if [ !  -z ${COMFY_CMDLINE_BASE+x} ]; then write_worldtmpfile $it "$COMFY_CMDLINE_BASE"; fi
if [ ! -f $it ]; then error_exit "$it missing, exiting"; fi
COMFY_CMDLINE_BASE=`cat $it`
echo "-- COMFY_CMDLINE_BASE: \"${COMFY_CMDLINE_BASE}\""

it=$itdir/comfy_cmdline_xtra
if [ ! -z "$cmd_cmdline_xtra" ]; then COMFY_CMDLINE_XTRA=`cat $cmd_cmdline_xtra`; else cmd_cmdline_xtra=$it; fi
if [ -z ${COMFY_CMDLINE_XTRA+x} ]; then COMFY_CMDLINE_XTRA=""; fi
if [ ! -z ${COMFY_CMDLINE_XTRA+x} ]; then write_worldtmpfile $it "$COMFY_CMDLINE_XTRA"; fi
if [ ! -f $it ]; then error_exit "$it missing, exiting"; fi
COMFY_CMDLINE_XTRA=`cat $it`
echo "-- COMFY_CMDLINE_XTRA: \"${COMFY_CMDLINE_XTRA}\""


if [ -z "$WANTED_UID" ]; then WANTED_UID=$cmd_wuid; fi
if [ -z "$WANTED_UID" ]; then echo "-- No WANTED_UID provided, using comfy user default of 1024"; WANTED_UID=1024; fi
if [ -z "$WANTED_GID" ]; then WANTED_GID=$cmd_wgid; fi
if [ -z "$WANTED_GID" ]; then echo "-- No WANTED_GID provided, using comfy user default of 1024"; WANTED_GID=1024; fi

# The script is started as comfy
# if the UID/GID are not correct, we create a new comfytoo user with the correct UID/GID which will restart the script
# after the script restart we restart again as comfy
if [ "A${whoami}" == "Acomfytoo" ]; then
  echo "-- Not running as comfy, will try to switch to comfy (Docker USER)"
  # Make the comfy user (the Docker USER) have the proper UID/GID as well
  sudo usermod -u ${WANTED_UID} -o -g ${WANTED_GID} comfy
  # restart the script as comfy (Docker USER) with the correct UID/GID this time
  sudo su comfy $script_fullname ${WANTED_UID} ${WANTED_GID} ${cmd_cmdline_base} ${cmd_cmdline_xtra} && exit
fi

it=/etc/image_base.txt
if [ ! -f $it ]; then error_exit "$it missing, exiting"; fi
echo "-- Base image details (from $it):"; cat $it

it=/etc/comfyuser_dir
if [ ! -f $it ]; then error_exit "$it missing, exiting"; fi
COMFYUSER_DIR=`cat $it`
echo "-- COMFYUIUSER_DIR: \"${COMFYUSER_DIR}\""
if test -z ${COMFYUSER_DIR}; then error_exit "Empty COMFYUSER_DIR variable"; fi

# we are running with some given UID/GID, do we need to modify UID/GID
current_uid=`id -u`
current_gid=`id -g`

do_change="False"

if [ ! -z "$WANTED_GID" -a "$WANTED_GID" != "$current_gid" ]; then
  echo "-- Will attempt to create a new user with GID ${WANTED_GID}"
  do_change="True"
fi
if [ ! -z "$WANTED_UID" -a "$WANTED_UID" != "$current_uid" ]; then
  echo "-- Will attempt to create a new user with UID ${WANTED_UID}"
  do_change="True"
fi

if [ $do_change == "True" ]; then
  # Make a "comfytoo" user
  sudo chown -R ${WANTED_UID}:${WANTED_GID} ${COMFYUSER_DIR}
  (getent group ${WANTED_GID} || (sudo addgroup --group --gid ${WANTED_GID} comfytoo || true))
  sudo useradd -u ${WANTED_UID} -o -g ${WANTED_GID} -s /bin/bash -d ${COMFYUSER_DIR} -M comfytoo
  sudo adduser comfytoo sudo
  # Reload the script to bypass limitation (and exit)
  sudo su comfytoo $script_fullname ${WANTED_UID} ${WANTED_GID} ${cmd_cmdline_base} ${cmd_cmdline_xtra} && exit
fi

new_gid=`id -g`
new_uid=`id -u`
echo "== user -- uid: $new_uid / gid: $new_gid"
if [ ! -z "$WANTED_GID" -a "$WANTED_GID" != "$new_gid" ]; then echo "Wrong GID ($new_gid), exiting"; exit 0; fi
if [ ! -z "$WANTED_UID" -a "$WANTED_UID" != "$new_uid" ]; then echo "Wrong UID ($new_uid), exiting"; exit 0; fi

# We are now running as comfy
echo "== Running as comfy"

# Obtain the latest version of ComfyUI if not already present
cd ${COMFYUSER_DIR}/mnt
if [ ! -d "ComfyUI" ]; then
  echo "== Cloning ComfyUI"
  git clone https://github.com/comfyanonymous/ComfyUI.git ComfyUI || error_exit "ComfyUI clone failed"
fi

if [ ! -d HF ]; then
  echo "== Creating HF directory"
  mkdir -p HF
fi
export HF_HOME=${COMFYUSER_DIR}/mnt/HF

# virtualenv for installation
if [ ! -d "venv" ]; then
  echo "== Creating virtualenv"
  python3 -m venv venv || error_exit "Virtualenv creation failed"
fi

# Activate the virtualenv and upgrade pip
if [ ! -f ${COMFYUSER_DIR}/mnt/venv/bin/activate ]; then error_exit "virtualenv not created, please erase any venv directory"; fi
echo "== Activating virtualenv"
source ${COMFYUSER_DIR}/mnt/venv/bin/activate || error_exit "Virtualenv activation failed"
echo "== Upgrading pip"
pip3 install --upgrade pip || error_exit "Pip upgrade failed"

# extent the PATH to include the user local bin directory
export PATH=${COMFYUSER_DIR}/.local/bin:${PATH}

# Verify the variables
echo "==================="
echo "== Environment details:"
echo -n "  PATH: "; echo $PATH
echo -n "  Python version: "; python3 --version
echo -n "  Pip version: "; pip3 --version
echo -n "  python bin: "; which python3
echo -n "  pip bin: "; which pip3
echo -n "  git bin: "; which git

# Install ComfyUI's requirements
cd ComfyUI
echo "== Installing/Updating from ComfyUI's requirements"
pip3 install --trusted-host pypi.org --trusted-host files.pythonhosted.org -r requirements.txt || error_exit "ComfyUI requirements install/upgrade failed"
echo "== Installing Huggingface Hub"
pip3 install --trusted-host pypi.org --trusted-host files.pythonhosted.org -U "huggingface_hub[cli]" || error_exit "HuggingFace Hub CLI install/upgrade failed"

export COMFYUI_PATH=`pwd`
echo "-- COMFYUI_PATH: ${COMFYUI_PATH}"

# Install ComfyUI Manager if not already present
cd custom_nodes
if [ ! -d ComfyUI-Manager ]; then
  echo "== Cloning ComfyUI-Manager"
  git clone https://github.com/ltdrdata/ComfyUI-Manager.git || error_exit "ComfyUI-Manager clone failed"
fi
if [ ! -d ComfyUI-Manager ]; then error_exit "ComfyUI-Manager not found"; fi
cd ComfyUI-Manager
if [ ! -f config.ini ]; then
  echo "== You will need to run ComfyUI-Manager a first time for the configuration file to be generated, we can not attempt to update its security level yet"
else
  echo "== Attempting to update ComfyUI-Manager security level (running in a container, we need to expose the WebUI to 0.0.0.0)"
  perl -p -i -e "s%security_level = normal%security_level = weak%g" config.ini
  perl -p -i -e "s%security_level = strict%security_level = weak%g" config.ini
fi

cd ${COMFYUI_PATH}
echo -n "== Container directory: "; pwd

# Check for a user custom script
it=${COMFYUSER_DIR}/mnt/user_script.bash
echo "== Checking for user script: ${it}"
if [ -f $it ]; then
  if [ ! -x $it ]; then
    echo "== Attempting to make user script executable"
    chmod +x $it || error_exit "Failed to make user script executable"
  fi
  echo "  Running user script: ${it}"
  $it || error_exit "User script failed or exited with an error (possibly on purpose to avoid running the default ComfyUI command)"
fi

echo "==================="
echo "== Running ComfyUI"
# Full list of CLI options at https://github.com/comfyanonymous/ComfyUI/blob/master/comfy/cli_args.py
echo "-- Running: ${COMFY_CMDLINE_BASE} ${COMFY_CMDLINE_XTRA}"
${COMFY_CMDLINE_BASE} ${COMFY_CMDLINE_XTRA} || error_exit "ComfyUI failed or exited with an error"
