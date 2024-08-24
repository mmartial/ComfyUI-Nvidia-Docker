<h1>ComfyUI (NVIDIA) Docker</h1>

[ComfyUI](https://github.com/comfyanonymous/ComfyUI/tree/master) is an impressive diffusion WebUI. 
With the recent addition of a [Flux example](https://comfyanonymous.github.io/ComfyUI_examples/flux/), I created this container builder to test it.

The container size (over 5GB) is mostly because of the Nvidia components. It is a Ubuntu 22.04 image with Nvidia CUDA and CuDNN.

At first boot, it will download all the python packages needed by ComfyUI and place them in the `run/venv` (run directory's virtual environment)'s folder. This adds an expected 5GB of content to the installation.

**About 10GB of space is needed between the container and the virtual environment additional installation.**
This does not take into account the models and other additional packages installation that the end user might perform.

- [1. Preamble](#1-preamble)
- [2. Running the container](#2-running-the-container)
  - [2.1. docker run](#21-docker-run)
  - [2.2. Docker compose](#22-docker-compose)
  - [2.3. First time use](#23-first-time-use)
- [3. Docker image](#3-docker-image)
  - [3.1. Building the image](#31-building-the-image)
  - [3.2. Availability on DockerHub](#32-availability-on-dockerhub)
  - [3.3. Unraid availability](#33-unraid-availability)
  - [3.4. Nvidia base container](#34-nvidia-base-container)
- [4. Screenshots](#4-screenshots)
  - [4.1. First run: Bottle image](#41-first-run-bottle-image)
  - [4.2. FLUX.1\[dev\] example](#42-flux1dev-example)
- [5. FAQ](#5-faq)
  - [5.1. Virtualenv](#51-virtualenv)
  - [5.2. user\_script.bash](#52-user_scriptbash)
  - [5.3. ComfyUI Manager](#53-comfyui-manager)

## 1. Preamble

The `Makefile` will attempt to find the latest published release on GitHub and automatically propose to prepare this version to be installed during the container start. It will create a Python virtual environment, activate it and install all requirements from the requested version.

If desired, it is also possible to manually set the version, by modifying the `Makefile` and adapting the `COMFY_VERSION` variable and enabling the `COMFYUI_VERSION_OVERRIDE` flag.

This build is also set to not run as the `root` user, but run the requested UID/GID at `docker run` time (if none are provided, the container will use 1024/1024).
This is done to a allow end users to have local directory structures for all the side data (input, output, temp, user), Hugging Face `HF_HOME` if used, and the entire `models` being separate from the running container and able to be altered by the user.

The tag for the ComfyUI container image is obtained from the latest official release from GitHub.

Note that a `docker buildx prune -f` might be needed to force a clean build after removing already existing containers.

To request a different UID/GID at run time use the `WANTED_UID` and `WANTED_GID` environment variables when calling the container.

Note: 
- for details on how to set up a Docker to support an NVIDIA GPU on an Ubuntu 24.04 system, please see [Setting up NVIDIA docker & podman (Ubuntu 24.04)](https://blg.gkr.one/20240404-u24_nvidia_docker_podman/)
- If you are new to ComfyUI, a recommended read: [ComfyUI_examples](https://comfyanonymous.github.io/ComfyUI_examples/)
- [ComfyUI FLUX examples](https://comfyanonymous.github.io/ComfyUI_examples/flux/)
- [FLUX.1[dev] with ComfyUI and Stability Matrix](https://blg.gkr.one/20240810-flux1dev/)
- [FLUX.1 LoRA training](https://blg.gkr.one/20240818-flux_lora_training/)

## 2. Running the container

In the directory where we intend to run the container, create the `run` folder as the user that we want to share the UID/GID with **before running the container (the container is started as root, as such the folder if it does not exist will be created as root)** (or give it another name, just be adapt the `-v` mapping in the `docker run` below). 

That `run` folder will be populated with a few sub-directories created with the UID/GID passed on the command line (see the command line below). 
Among the folders that will be created within `run` are `HF, data/{input,output,temp}, user, models, custom_nodes, comfy_extras`
The `venv` is also added to this `run` folder; this virtual environment is where all the required pyton packages for ComfyUI will be placed. A default installation requires about 5GB of additional install in addition to the container itself.

**The initialization script (run at each restart of the container) will do its best to not overwrite existing files (keeping the most recent -- if you are modifying an existing file, it might be safer to rename it; if a new version appears on Comfy's GitHub, your version might get erased) or remove files that are already in the destination.**

The image starts the `init.bash` script that performs a few operations:
- Ensure we are able to use the `WANTED_UID` and `WANTED_GID` as the `comfy` user (the user set to run the container)
- Copy all the ComfyUI specific content that will be placed inside the "run" directory. This is to ensure the models and other content is available outside of a container that is expected to be update, while giving the end user access to those directories to place content to use.
- Create and activate a python virtual environment that exists in the "run" directory. This also separate package management from the container, and allow the end user to install additional ComfyUI package (such as ComfyUI Manager and others)
- Check for a user custom script in the "run" directory. It must be named `user_script.bash`. If one exists, run it.
- Run the ComfyUI WebUI. For the exact command run, please see the last line of `init.bash`


### 2.1. docker run

To run the container on an NVIDIA GPU, mounting the specified directory, exposing the port 8188 (change this by altering the `-p local:container` port mapping) and passing the calling user's UID and GID to the container:

```bash
docker run --rm -it --runtime nvidia --gpus all -v `pwd`/run:/comfy/mnt -e WANTED_UID=`id -u` -e WANTED_GID=`id -g` -p 8188:8188 --name comfyui-nvidia mmartial/comfyui-nvidia-docker:latest
```

### 2.2. Docker compose

In the directory where you want to run the compose stack, create the `compose.yaml` file with the following content:

```yaml
services:
  comfyui-nvidia-docker:
    image: mmartial/comfyui-nvidia-docker:latest
    container_name: comfyui-nvidia
    ports:
      - 8188:8188
    volumes:
      - ./run:/comfy/mnt
    restart: unless-stopped
    environment:
      - WANTED_UID=1000
      - WANTED_GID=1000
      - NVIDIA_VISIBLE_DEVICES=all
      - NVIDIA_DRIVER_CAPABILITIES=all
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities:
                - gpu
                - compute
                - utility
```

This will expose on port 8188 (host:container), use a `run` directory local to the directory where this `compose.yml`  is, and specify the `WANTED_UID` and `WANTED_GID` to 1000 (adapt as needed).

Start it with `docker compose up` (with `-detached` to run the container in the background)

Please see [docker compose up](https://docs.docker.com/reference/cli/docker/compose/up/) reference manual for additional details.

### 2.3. First time use

The first time you run the container, going to the IP of our host on port 8188 (likely http://127.0.0.1:8188), we will see the latest run or the bottle generating example.

This example requires the `v1-5-pruned-emaonly.ckpt` file.

It is available for example at https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.ckpt

The way to get the WebUI to see if is to first put it in the `models/checkpoints` folder:

```bash
cd <YOUR_RUN_DIRECTORY>/models/checkpoints
wget https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.ckpt
```

After the download is complete, click "Refresh" on the WebUI and "Queue Prompt"

Depending on the workflow, and the needed files by the different nodes, some can be found on [HuggingFace](https://huggingface.co/) or [CivitAI](https://civitai.com/).

For example, for checkpoints, those would go in the `run/models/checkpoints` directory (the UI might need a click on the "Refresh" button to find those) before a "Queue Prompt". 
Clicking on the model's filename in the "Checkpoint Loader" will show the list of available files in that folder.

## 3. Docker image

### 3.1. Building the image

The `comfyui-nvidia-base` (`base`) image contains the prerequisites to enable a ComfyUI installation from its latest release from GitHub.
The tag for the base image is based on Today's date.


The `comfyui-nvidia-docker` (`local`) image contains the installation of the core components of ComfyUI from its latest release from GitHub. 
The tag for the final image is based on the version of ComfyUI.

Running `make` will show us the different build options; `local` is the one most people will want.

Run:
```bash
make local
```

The "base" image uses `Dockerfile-base` while the final image `Dockerfile`.
Feel free to modify either as needed.

### 3.2. Availability on DockerHub

Builds are available on DockerHub:
- [mmartial/comfyui-nvidia-docker](https://hub.docker.com/r/mmartial/comfyui-nvidia-docker), the ComfyUI pre-built image generated from the file in this repository's `Dockerfile`.
- [mmartial/comfyui-nvidia-base](https://hub.docker.com/r/mmartial/comfyui-nvidia-base), the base container that is used by the ComfyUI image. This image is published as it can be useful being a Ubuntu 22.04 with Nvidia components installed. For details on what is incorporated, please see the `Dockerfile-base` file.

### 3.3. Unraid availability

The container has been tested on Unraid.
I will update this when it has been added to the Community Apps.
For the time being, if interested, you can see the template from https://raw.githubusercontent.com/mmartial/unraid-templates/main/templates/ComfyUI-Nvidia-Docker.xml


### 3.4. Nvidia base container

Note that the original `Dockerfile` `FROM` is from Nvidia, as such:

```
This container image and its contents are governed by the NVIDIA Deep Learning Container License.
By pulling and using the container, you accept the terms and conditions of this license:
https://developer.nvidia.com/ngc/nvidia-deep-learning-container-license
```

## 4. Screenshots

### 4.1. First run: Bottle image

![First Run](assets/FirstRun.png)

### 4.2. FLUX.1[dev] example

Template at [Flux example](https://comfyanonymous.github.io/ComfyUI_examples/flux/)

![Flux Dev example](assets/Flux1Dev-run.png)

## 5. FAQ

### 5.1. Virtualenv

The container pip installs all required packages to the container, then creates a virtualenv (in `/comfy/mnt/venv` with `comfy/mnt` being mounted with the `docker run [...] -v`). 
This allows for installations of python packages using `pip3 install` after running `docker exec -t comfy-nvidia /bin/bash` and from the provided `bash` prompt activating the `venv` with `source /comfy/mnt/venv/bin/activate`.
From the `bash` prompt you can run `pip3 freeze` or other `pip3` commands such as `pip3 install civitai`

### 5.2. user_script.bash

The user script can perform many operations. Because this is a Docker container, updating the container will wipe any additional installations that are not in the "run" directory, so it is possible to force some reinstall without modifying the `Makefile`.
It is also possible bypass the ComfyUI command started (for people interested in trying the `--fast` for example).

The container image is a Ubuntu 22.04 with CUDA and CuDNN.
The `comfy` user is `sudo` capable.

A simple example of one could be:

```bash
#!/bin/bash

echo "== Adding system package"
sudo apt update
sudo apt install -y nvtop

echo "== Adding python  package"
source /comfy/mnt/venv/bin/activate
pip3 install nvitop

echo "== Override ComfyUI launch command"
cd /ComfyUI
python3 ./main.py --listen 0.0.0.0 --disable-auto-launch --temp-directory /comfy/mnt/data --fast

echo "== To preventing the regular Comfy command from starting, we 'exit 1'"
echo "   If we had not overrode it, we could simply end with an ok exit: 'exit 0'" 
exit 1
```

The script will be placed in the base of the "run" directory, and must be named `user_script.bash` to be found.

### 5.3. ComfyUI Manager

[ComfyUI Manager](https://github.com/ltdrdata/ComfyUI-Manager/) can be installed to be available in the container.
The `/comfy/mnt` directory is mounted using the `docker run [...] -v`.
As such, going to the "run directory" and going into the `custom_nodes` folder:
```bash
git clone https://github.com/ltdrdata/ComfyUI-Manager.git
```
You will need to restart ComfyUI for it to be recognized.

The container to be accessible runs on `0.0.0.0` internally (ie all network interfaces).
Docker takes care of exposing the port and control the access.
Unfortunately when using ComfyUI Manager, this means that the security scan settings has to be lowered to be able to be able to `Install PIP packages` for example.
To do so, in your run directory, edit `custom_nodes/ComfyUI-Manager/config.ini` and use the following `security_level = weak` (then reload ComfyUI)

To use `cm-cli`, from the virtualenv, use: `python3 /comfy/mnt/custom_nodes/ComfyUI-Manager/cm-cli.py`.
For example: `python3 /comfy/mnt/custom_nodes/ComfyUI-Manager/cm-cli.py show installed` (`COMFYUI_PATH=/ComfyUI` should be set)
