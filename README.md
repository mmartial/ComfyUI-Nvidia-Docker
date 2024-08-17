# ComfyUI (NVIDIA) Docker

[ComfyUI](https://github.com/comfyanonymous/ComfyUI/tree/master) is an impressive diffusion WebUI. 
With the recent addition of a [Flux example](https://comfyanonymous.github.io/ComfyUI_examples/flux/), I created this container builder to test it.

The `Makefile` will attempt to find the latest published release on GitHub and automatically propose to build this version.
It is also possible to manually set the version, by modifying the `Makefile` and adapting the `COMFY_VERSION` variable. 

This build is also set to run as a user whose UID and GID are copied from the container building user' own `uid` and `gid`.
This is done to a allow end users to have local directory structures for all the side data (input, output, temp, user), Hugging Face `HF_HOME` if used, and the entire `models` being separate from the running container and able to be altered by the user.

It is also possible to request a different UID/GID at run time using the `WANTED_UID` and `WANTED_GID` environment variables when calling the container.

Note: 
- for details on how to set up a Docker to support an NVIDIA GPU on an Ubuntu 24.04 system, please see [Setting up NVIDIA docker & podman (Ubuntu 24.04)](https://blg.gkr.one/20240404-u24_nvidia_docker_podman/)
- recommended read: [ComfyUI FLUX examples](https://comfyanonymous.github.io/ComfyUI_examples/flux/)
- also available: [FLUX.1dev with ComfyUI and Stability Matrix](https://blg.gkr.one/20240810-flux1dev/)

## Building the container

Running `make` will show us the different build options; `local` is the one most people will want.

Run:
```bash
make local
```

The "base" image uses `Dockerfile-base` while the final image `Dockerfile`.
Feel free to modify either as needed.

## Running the container

In the directory where we intend to run the container, create one `run` folder (or give it another name, just be adapt the `-v` mapping in the `docker run` below). That `run` folder will be populated with a few sub-directories created with the UID/GID passed on the command line (see the command line below).
The folders to be created within `run` are `HF, data/{input,output,temp}, user, models/{checkpoints,clip,clip_vision,configs,controlnet,diffusers,embeddings,gligen,hypernetworks,loras,photomaker,style_models,unet,upscale_models,vae,vae_approx}`

To run the container on an NVIDIA GPU, mounting the specified directory, exposing the port 8188 (change this by altering the `-p local:container` port mapping) and passing the calling user's UID and GID to the container:

```bash
docker run --rm -it --runtime nvidia --gpus all -v `pwd`/run:/home/comfy/mnt -e WANTED_UID=`id -u` -e WANTED_GID=`id -g` -p 8188:8188 comfyui-docker:latest
```

At first run, going to the IP of our host on port 8188 (likely http://127.0.0.1:8188), we will see the latest run or the bottle generating example. Depending on the workflow, and the needed files by the different nodes, some , and find it on [HuggingFace](https://huggingface.co/) or [CivitAI](https://civitai.com/).
For example, for checkpoints, those would go in the `run/models/checkpoints` directory (the UI might need a click on the "Refresh" button to find those before a "Queue Prompt")

## Availability on DockerHub

