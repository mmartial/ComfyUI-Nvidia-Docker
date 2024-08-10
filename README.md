# ComfyUI in CTPO

[ComfyUI](https://github.com/comfyanonymous/ComfyUI/tree/master) is an impressive diffusion WebUI. With the recent addition of a [Flux example](https://comfyanonymous.github.io/ComfyUI_examples/flux/) I wanted to test it.

[CTPO](https://github.com/Infotrend-Inc/CTPO) is a building block container providing CUDA, TensorFlow, PyTorch and OpenCV. Having its Jupyter lab version already installed on a system allows us to have a reproducible development environment.

This container is built `FROM` that base image (which is also the base image for the Jupyter lab version).

This build is set to use ComfyUI v0.0.5 (released Today -- 20240810) and to run as a `comfy` user whose UID and GID are copied from the user's own `uid` and `gid`.
This will allow a local directory structure for side data (input, output, temp, user), Hugging Face `HF_HOME` if used, and the entire `models` being separate from the running container.

## Building the container

Running `make` will show us the `build` option to "builds comfyui-ctpo:0.0.5 (to be run as uid: UID / gid: GID) and tags it as comfyui-ctpo:latest"

Run:
```bash
make build
```

Feel free to modify the `Dockerfile` as needed.

## Running the container

In the directory where we intend to run the container, prefer a subset of directories to place data (if they are not already present):

```bash
mkdir HF
mkdir -p data/{input,output,temp}
mkdir user
mkdir -p models/{checkpoints,clip,clip_vision,configs,controlnet,diffusers,embeddings,gligen,hypernetworks,loras,photomaker,style_models,unet,upscale_models,vae,vae_approx}
```

Running the container on an NVIDIA GPU, mounting the different directories to the locally created ones and exposing the port 8188 (change this by altering the `-p local:container` port mapping):

```bash
docker run --rm -it --runtime nvidia --gpus all -v `pwd`/HF:/HF -v `pwd`/models:/ComfyUI/models -v `pwd`/data:/data -v `pwd`/user:/ComfyUI/user -p 8188:8188 comfyui-ctpo:latest
```

At first run, going to the IP of our host on port 8188 (likely http://127.0.0.1:8188), we will see the bottle generating example.

See the file name displayed in the "Load Checkpoint" node, and find it on [HuggingFace](https://huggingface.co/) or [CivitAI](https://civitai.com/).
After obtaining it, we place it in the `models/checkpoints` directory, matching the file name.
If placing more than one checkpoint in the directory, using the "Refresh" button will update the "Load Checkpoint" list of options.

We can now `Queue Prompt` :)

