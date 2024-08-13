# ComfyUI in CTPO

[ComfyUI](https://github.com/comfyanonymous/ComfyUI/tree/master) is an impressive diffusion WebUI. With the recent addition of a [Flux example](https://comfyanonymous.github.io/ComfyUI_examples/flux/), I created this container builder to test it.

[CTPO](https://github.com/Infotrend-Inc/CTPO) is a building block container providing CUDA, TensorFlow, PyTorch and OpenCV. Having its Jupyter lab version already installed on a system allows us to have a reproducible development environment.

This container is built `FROM` that base image (which is also the base image for the Jupyter lab version).

The `Makefile` will attempt to find the latest published release on GitHub and automatically propose to build this version.
It is also possible to manually set the version, by modifying the `Makefile` and adapting the `COMFY_VERSION` variable. 
This build is also set to run as a `comfy` user whose UID and GID are copied from the container building user' own `uid` and `gid`.
This will allow a local directory structure for side data (input, output, temp, user), Hugging Face `HF_HOME` if used, and the entire `models` being separate from the running container.

## Building the container

Running `make` will show us the different build options; `local` is the one most people will want.

Run:
```bash
make local
```

Feel free to modify the `Dockerfile` as needed.

## Running the container

In the directory where we intend to run the container, create one `run` directory that will be populated with a few sub-directories created with the UID/GID of the user that built the container (more on that shortly)

The directories that will be created within that directory will be `HF, data/{input,output,temp}, user, models/{checkpoints,clip,clip_vision,configs,controlnet,diffusers,embeddings,gligen,hypernetworks,loras,photomaker,style_models,unet,upscale_models,vae,vae_approx}`

Running the container on an NVIDIA GPU, mounting the specified directory and exposing the port 8188 (change this by altering the `-p local:container` port mapping):

```bash
docker run --rm -it --runtime nvidia --gpus all -v `pwd`/run:/home/comfy/mnt -e WANTED_UID=`id -u` -e WANTED_GID=`id -g` -p 8188:8188 comfyui-ctpo:latest
```

At first run, going to the IP of our host on port 8188 (likely http://127.0.0.1:8188), we will see the bottle generating example.

See the file name displayed in the "Load Checkpoint" node, and find it on [HuggingFace](https://huggingface.co/) or [CivitAI](https://civitai.com/).
After obtaining it, we place it in the `models/checkpoints` directory, matching the file name.
If placing more than one checkpoint in the directory, using the "Refresh" button will update the "Load Checkpoint" list of options.

We can now `Queue Prompt` :)

### Note

Note that the `docker run` command passes the running user UID and GID to the container.
To support this, a new user with the proper UID/GID is created within the newly created container.
