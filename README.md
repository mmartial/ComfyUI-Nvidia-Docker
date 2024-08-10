# Comfy in CTPO

## Building the container

```bash
make build
```

## Running the container

```bash
mkdir HF
mkdir -p data/{input,output,temp}
mkdir user
mkdir -p models/{checkpoints,clip,clip_vision,configs,controlnet,diffusers,embeddings,gligen,hypernetworks,loras,photomaker,style_models,unet,upscale_models,vae,vae_approx}
```

```bash
docker run --rm -it --gpus all -v `pwd`/HF:/HF -v `pwd`/models:/ComfyUI/models -v `pwd`/data:/data -v `pwd`/user:/ComfyUI/user -p 8188:8188 comfyui-ctpo:latest
````

The test model is located at https://civitai.com/models/18798?modelVersionId=112809
Obtain it and place it in models/