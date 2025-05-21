ARG BASE_DOCKER_FROM=nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04

#-----------------------------------------------------------------------------------------------------------------------
# Builder Stage
#-----------------------------------------------------------------------------------------------------------------------
FROM ${BASE_DOCKER_FROM} AS builder
ARG BASE_DOCKER_FROM

# Install build-time system packages
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -y --fix-missing \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
    apt-utils \
    build-essential \
    python3-dev \
    unzip \
    wget \
    zip \
    zlib1g-dev \
    gnupg \
    rsync \
    git \
    ca-certificates \
    locales \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# UTF-8 (Needed in builder for some tools)
RUN localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG=en_US.utf8
ENV LC_ALL=C

#-----------------------------------------------------------------------------------------------------------------------
# Final Stage
#-----------------------------------------------------------------------------------------------------------------------
FROM ${BASE_DOCKER_FROM}
ARG BASE_DOCKER_FROM

##### Base

# Install runtime system packages
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -y --fix-missing \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    locales \
    python3-pip \
    python3-venv \
    sudo \
    libglib2.0-0 \
    libglvnd0 \
    libvulkan1 \
    # libegl1-mesa should be installed if libegl1-mesa-dev was providing libegl1
    # The base CUDA image or other dependencies like libglvnd0 might pull in libegl1.
    # For now, we are only removing the -dev packages as instructed.
    # If EGL issues arise, consider adding libegl1 or libegl1-mesa explicitly.
    ffmpeg \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# UTF-8
RUN localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG=en_US.utf8
ENV LC_ALL=C

# Add libEGL ICD loaders and libraries + Vulkan ICD loaders and libraries
# Per https://github.com/mmartial/ComfyUI-Nvidia-Docker/issues/26
# This needs to be in the final stage as it modifies the runtime environment
RUN mkdir -p /usr/share/glvnd/egl_vendor.d \
  && echo '{"file_format_version":"1.0.0","ICD":{"library_path":"libEGL_nvidia.so.0"}}' > /usr/share/glvnd/egl_vendor.d/10_nvidia.json \
  && mkdir -p /usr/share/vulkan/icd.d \
  && echo '{"file_format_version":"1.0.0","ICD":{"library_path":"libGLX_nvidia.so.0","api_version":"1.3"}}' > /usr/share/vulkan/icd.d/nvidia_icd.json
ENV MESA_D3D12_DEFAULT_ADAPTER_NAME="NVIDIA"

ENV BUILD_FILE="/etc/image_base.txt"
# ARG BASE_DOCKER_FROM # Already defined in this stage
RUN echo "DOCKER_FROM: ${BASE_DOCKER_FROM}" | tee ${BUILD_FILE}
# NV_CUDNN_PACKAGE_NAME and NV_CUDNN_VERSION are available from the base image
RUN echo "CUDNN: ${NV_CUDNN_PACKAGE_NAME} (${NV_CUDNN_VERSION})" | tee -a ${BUILD_FILE}

ARG BUILD_BASE="unknown"
LABEL comfyui-nvidia-docker-build-from=${BUILD_BASE}
RUN it="/etc/build_base.txt"; echo ${BUILD_BASE} > $it && chmod 555 $it

# Place the init script and its config in / so it can be found by the entrypoint
COPY --chmod=555 init.bash /comfyui-nvidia_init.bash
COPY --chmod=555 config.sh /comfyui-nvidia_config.sh

##### ComfyUI preparation
# Create a new group for the comfy and comfytoo users
RUN groupadd -g 1024 comfy \
    && groupadd -g 1025 comfytoo

# The comfy (resp. comfytoo) user will have UID 1024 (resp. 1025),
# be part of the comfy (resp. comfytoo) and users groups and be sudo capable
RUN useradd -u 1024 -d /home/comfy -g comfy -s /bin/bash -m comfy \
    && usermod -G users comfy \
    && adduser comfy sudo
RUN useradd -u 1025 -d /home/comfytoo -g comfytoo -s /bin/bash -m comfytoo \
    && usermod -G users comfytoo \
    && adduser comfytoo sudo

ENV COMFYUSER_DIR="/comfy"
RUN mkdir -p ${COMFYUSER_DIR}
RUN it="/etc/comfyuser_dir"; echo ${COMFYUSER_DIR} > $it && chmod 555 $it

USER comfytoo

ENV NVIDIA_DRIVER_CAPABILITIES="all"
ENV NVIDIA_VISIBLE_DEVICES=all

EXPOSE 8188

ARG COMFYUI_NVIDIA_DOCKER_VERSION="unknown"
LABEL comfyui-nvidia-docker-build=${COMFYUI_NVIDIA_DOCKER_VERSION}
RUN echo "COMFYUI_NVIDIA_DOCKER_VERSION: ${COMFYUI_NVIDIA_DOCKER_VERSION}" | tee -a ${BUILD_FILE}

# We use ENTRYPOINT to run the init script (from CMD)
ENTRYPOINT [ "/comfyui-nvidia_init.bash" ]
