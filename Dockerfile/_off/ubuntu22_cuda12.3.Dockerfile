FROM nvidia/cuda:12.3.2-cudnn9-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive

ARG BUILD_APT_PROXY
# Make use of apt-cacher-ng if available
RUN if [ "A${BUILD_APT_PROXY:-}" != "A" ]; then \
        echo "Using APT proxy: ${BUILD_APT_PROXY}"; \
        printf 'Acquire::http::Proxy "%s";\n' "$BUILD_APT_PROXY" > /etc/apt/apt.conf.d/01proxy; \
    fi \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates wget gnupg \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

ARG BUILD_ARCH=x86_64 
# Install NVIDIA CUDA repo keyring (adds /usr/share/keyrings/cuda-archive-keyring.gpg) and remove duplicate CUDA repo definitions to avoid Signed-By conflicts, then add a single canonical CUDA repo entry using the keyring
RUN wget -qO /tmp/cuda-keyring.deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/${BUILD_ARCH}/cuda-keyring_1.1-1_all.deb \
    && dpkg -i /tmp/cuda-keyring.deb \
    && rm -f /tmp/cuda-keyring.deb \
    && rm -f /etc/apt/sources.list.d/cuda*.list /etc/apt/sources.list.d/cuda*.sources \
    && rm -f /etc/apt/sources.list.d/nvidia*.list /etc/apt/sources.list.d/nvidia*.sources \
    && echo "deb [signed-by=/usr/share/keyrings/cuda-archive-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/${BUILD_ARCH}/ /" > /etc/apt/sources.list.d/cuda-ubuntu2404.list \
    && apt-get update \
    && apt-get clean

ARG BASE_DOCKER_FROM=nvidia/cuda:12.3.2-cudnn9-devel-ubuntu22.04
##### Base

# Install system packages
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -y --fix-missing \
  && apt-get install -y \
    apt-utils \
    locales \
    ca-certificates \
    && apt-get upgrade -y \
    && apt-get clean

# UTF-8
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=C

RUN apt-get update && apt-get install -y --no-install-recommends locales \
  && locale-gen en_US.UTF-8 \
  && update-locale LANG=en_US.UTF-8 \
  && apt-get clean
  
# Install needed packages
RUN apt-get update -y --fix-missing \
  && apt-get upgrade -y \
  && apt-get install -y --no-install-recommends \
    build-essential \
    python3-dev \
    unzip \
    wget \
    curl \
    zip \
    zlib1g \
    zlib1g-dev \
    gnupg \
    rsync \
    python3-pip \
    python3-venv \
    git \
    sudo \
    libglib2.0-0 \
    socat \
    pkg-config \
    libcairo2-dev \
    libpango1.0-dev \
    libjpeg-dev \
    libpng-dev \
    libffi-dev \
    libsm6 \
    libxext6 \
    libxrender1 \
    xdg-utils \
    libcurl4-openssl-dev \
    ffmpeg \
    sqlite3 \
    libsqlite3-dev \
  && apt-get clean

# Add libEGL ICD loaders and libraries + Vulkan ICD loaders and libraries
# Per https://github.com/mmartial/ComfyUI-Nvidia-Docker/issues/26
RUN apt-get install -y --no-install-recommends libglvnd0 libglvnd-dev libegl1-mesa-dev libvulkan1 libvulkan-dev \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && mkdir -p /usr/share/glvnd/egl_vendor.d \
  && echo '{"file_format_version":"1.0.0","ICD":{"library_path":"libEGL_nvidia.so.0"}}' > /usr/share/glvnd/egl_vendor.d/10_nvidia.json \
  && mkdir -p /usr/share/vulkan/icd.d \
  && echo '{"file_format_version":"1.0.0","ICD":{"library_path":"libGLX_nvidia.so.0","api_version":"1.3"}}' > /usr/share/vulkan/icd.d/nvidia_icd.json
ENV MESA_D3D12_DEFAULT_ADAPTER_NAME="NVIDIA"

ENV BUILD_FILE="/etc/image_base.txt"
ARG BASE_DOCKER_FROM
RUN echo "DOCKER_FROM: ${BASE_DOCKER_FROM}" | tee ${BUILD_FILE}
RUN echo "CUDNN: ${NV_CUDNN_PACKAGE_NAME} (${NV_CUDNN_VERSION})" | tee -a ${BUILD_FILE}

ARG BUILD_BASE="unknown"
LABEL comfyui-nvidia-docker-build-from=${BUILD_BASE}
RUN it="/etc/build_base.txt"; echo ${BUILD_BASE} > $it && chmod 555 $it

# Place the init script and its config in / so it can be found by the entrypoint
COPY --chmod=555 init.bash /comfyui-nvidia_init.bash
COPY --chmod=555 config.sh /comfyui-nvidia_config.sh

##### ComfyUI preparation
# Every sudo group user does not need a password
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Create a new group for the comfy and comfytoo users
RUN groupadd -g 1024 comfy \ 
    && groupadd -g 1025 comfytoo

# The comfy (resp. comfytoo) user will have UID 1024 (resp. 1025), 
# be part of the comfy (resp. comfytoo) and users groups and be sudo capable (passwordless) 
RUN useradd -u 1024 -d /home/comfy -g comfy -s /bin/bash -m comfy \
    && usermod -G users comfy \
    && adduser comfy sudo
RUN useradd -u 1025 -d /home/comfytoo -g comfytoo -s /bin/bash -m comfytoo \
    && usermod -G users comfytoo \
    && adduser comfytoo sudo

ENV COMFYUSER_DIR="/comfy"
RUN mkdir -p ${COMFYUSER_DIR}
RUN it="/etc/comfyuser_dir"; echo ${COMFYUSER_DIR} > $it && chmod 555 $it

ENV NVIDIA_DRIVER_CAPABILITIES="all"
ENV NVIDIA_VISIBLE_DEVICES=all

EXPOSE 8188

# Remove APT proxy configuration and clean up APT downloaded files
RUN rm -rf /var/lib/apt/lists/* /etc/apt/apt.conf.d/01proxy \
    && apt-get clean

ARG COMFYUI_NVIDIA_DOCKER_VERSION="unknown"
LABEL comfyui-nvidia-docker-build=${COMFYUI_NVIDIA_DOCKER_VERSION}
RUN echo "COMFYUI_NVIDIA_DOCKER_VERSION: ${COMFYUI_NVIDIA_DOCKER_VERSION}" | tee -a ${BUILD_FILE}

# We start as comfytoo and will switch to the comfy user AFTER the container is up
# and after having altered the comfy details to match the requested UID/GID
USER comfytoo

# We use ENTRYPOINT to run the init script (from CMD)
ENTRYPOINT [ "/comfyui-nvidia_init.bash" ]
