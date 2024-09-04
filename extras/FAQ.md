<h1>Extra FAQ</h1>

**It is recommended to have a docker log viewer when performing operations that perform python packages installation. Those will take a long time, and the log will help confirm progress until ComfyUI Manager provides a status update**

- [1. Installating components](#1-installating-components)
  - [1.1. Updating ComfyUI](#11-updating-comfyui)
  - [1.2. Updating ComfyUI Manager](#12-updating-comfyui-manager)
  - [1.3. Installing a custom node from git](#13-installing-a-custom-node-from-git)
  - [1.4. Intalling a know custom node](#14-intalling-a-know-custom-node)
- [2. Short list of custom nodes](#2-short-list-of-custom-nodes)
  - [2.1. rgthree-comfy](#21-rgthree-comfy)
  - [2.2. Crystools](#22-crystools)
  - [2.3. ComfyUI\_bitsandbytes\_NF4](#23-comfyui_bitsandbytes_nf4)
  - [2.4. FLUX.1-dev-gguf](#24-flux1-dev-gguf)

# 1. Installating components

## 1.1. Updating ComfyUI

- From the ComfyUI canvas, in the "Queue Prompt" menu (usually on the bottom right), select `Manager` (ComfyUI Manager)
- From this new menu, in the center row, select `Update ComfyUI`
- Wait for a completion popup
- Click `Restart` and validate if prompted
- Wait for the `Reconnected` (green message in the top right)
- Reload the webpage using your browser
- Display the Manager again. In the news box (within manager, box on the right side), scroll down to see the git commit information from ComfyUI (and the date of that commit)

## 1.2. Updating ComfyUI Manager

- On the ComfyUI canvas, select "Manager"
- Select `Custom Nodes Manager`
- Filter by `Installed`
- Use `Try Update` next to the `ComfyUI-Manager` line
- If watching the logs, you will see a `Update custom node 'ComfyUI-Manager'` entry
- When completed, at the bottom of the WebUI (in red) as message similar to `To apply the installed/updated/disabled/enabled custom node, please restart ComfyUI. And refresh browser` will appear
- Click `Restart` and validate if prompted
- Wait for the `Reconnected` (green message in the top right)
- Reload the webpage using your browser
- Display the Manager again. In the news box (within manager, box on the right side), scroll down to see the version of ComfyUI-Manager that was installed.

## 1.3. Installing a custom node from git

- On the ComfyUI canvas, select "Manager"
- Select `Custom Nodes Manager`
- Use the `Install via Git URL` button
- Enter the git repo location of your custom node
- Click `Install` and wait for the process to complete
- If watching the logs, you will see the python packages requirements installation process
- When completed, you will see a message similar to `To apply the installed custom node, please RESTART ComfyUI.`
- Click the `RESTART` button in that message and validate if prompted
- Wait for the `Reconnected` (green message in the top right)
- Reload the webpage using your browser
- After double clicking on the canvas, your custom node should now be searchable

## 1.4. Intalling a know custom node

Many nodes are already added to the search functionality of ComfyUI Manager.
To see what is available:
- On the ComfyUI canvas, select "Manager"
- Select `Custom Nodes Manager`
- Search for an item of interest
- Click `Install` and wait for the process to complete
- Follow similar steps as the steps following "Click Install" from "Installing a custom node from git"


# 2. Short list of custom nodes

## 2.1. rgthree-comfy

URL: https://github.com/rgthree/rgthree-comfy

A quality of life node as "a collection of nodes and improvements": Progress Bar (runs alongs the top of the app window), Reroute, Power Lora Loader, Power Prompt(s), 

can be installed directly from ComfyUI Manager using the "known custom node" method:
- Select `Custom Nodes Manager`
- Type `rgthree` from the search bar
- `rgthree` is the "Author"
- `Select` and `Install`
- Follow the steps after "Click Install" from "Installing a custom node from git"

## 2.2. Crystools

URL: https://github.com/crystian/ComfyUI-Crystools.git

Quality of life node providing "resources monitor, progress bar & time elapsed, ..."

Can be installed as a "known custom node" from the search menu.
- Select `Custom Nodes Manager`
- Type `crys` from the search bar
- `crystian` is the "Author", decide if you want to install the available custom nodes.
- `Select` and `Install`
- Follow the steps after "Click Install" from "Installing a custom node from git"

## 2.3. ComfyUI_bitsandbytes_NF4

URL: https://github.com/comfyanonymous/ComfyUI_bitsandbytes_NF4.git
(deprecated in favor of GGUF)

Follow the "Installing a custom node from git"

If possible, find a test workflow, obtain the required weights and after placing them in the expected location (see the "Running the container" section of the main [README.md](../README.md) for further details), `Queue Prompt`

## 2.4. FLUX.1-dev-gguf

URL: https://github.com/city96/ComfyUI-GGUF.git

GGUF Quantization support for native ComfyUI model

GGUF can be installed directly from ComfyUI Manager using the "known custom node" method:
- Select `Custom Nodes Manager`
- Type `GGUF` from the search bar
- `city96` is the "Author"
- `Select` and `Install`
- Follow the steps after "Click Install" from "Installing a custom node from git"

