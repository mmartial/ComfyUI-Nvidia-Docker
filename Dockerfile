ARG DOCKER_FROM=nvidia/cuda:12.3.2-runtime-ubuntu22.04
FROM ${DOCKER_FROM}

# Adapted from https://gitlab.com/nvidia/container-images/cuda/-/blob/master/dist/12.2.2/ubuntu2204/devel/cudnn8/Dockerfile
ENV NV_CUDNN_VERSION=8.9.7.29
ENV NV_CUDNN_PACKAGE_NAME="libcudnn8"
ENV NV_CUDA_ADD=cuda12.2
ENV NV_CUDNN_PACKAGE="$NV_CUDNN_PACKAGE_NAME=$NV_CUDNN_VERSION-1+$NV_CUDA_ADD"
ENV NV_CUDNN_PACKAGE_DEV="$NV_CUDNN_PACKAGE_NAME-dev=$NV_CUDNN_VERSION-1+$NV_CUDA_ADD"
LABEL com.nvidia.cudnn.version="${NV_CUDNN_VERSION}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    ${NV_CUDNN_PACKAGE} \
    ${NV_CUDNN_PACKAGE_DEV} \
    && apt-mark hold ${NV_CUDNN_PACKAGE_NAME} \
    && rm -rf /var/lib/apt/lists/*

##### Base

# Install system packages
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -y --fix-missing\
  && apt-get install -y \
    apt-utils \
    locales \
    ca-certificates \
    && apt-get upgrade -y \
    && apt-get clean

# UTF-8
RUN localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG=en_US.utf8
ENV LC_ALL=C

# Install needed packages
RUN apt-get update -y --fix-missing \
  && apt-get upgrade -y \
  && apt-get install -y \
    build-essential \
    python3-dev \
    unzip \
    wget \
    zip \
    zlib1g \
    zlib1g-dev \
    gnupg \
    rsync \
    python3-pip \
    python3-venv \
    git \
    sudo \
  && apt-get clean

ENV BUILD_FILE="/etc/image_base.txt"
ARG BASE_DOCKER_FROM
RUN echo "DOCKER_FROM: ${BASE_DOCKER_FROM}" | tee ${BUILD_FILE}
RUN echo "CUDNN: ${NV_CUDNN_PACKAGE_NAME} (${NV_CUDNN_VERSION})" | tee -a ${BUILD_FILE}

##### ComfyUI preparation
# The comfy user will have UID 1024 and GID 1024
ENV COMFYUSER_DIR="/comfy"
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers \
    && useradd -u 1024 -U -d ${COMFYUSER_DIR} -s /bin/bash -m comfy \
    && usermod -G users comfy \
    && adduser comfy sudo \
    && test -d ${COMFYUSER_DIR}
RUN it="/etc/comfyuser_dir"; echo ${COMFYUSER_DIR} > $it && chmod 555 $it

ENV NVIDIA_VISIBLE_DEVICES=all

EXPOSE 8188

USER comfy
WORKDIR ${COMFYUSER_DIR}
COPY --chown=comfy:comfy --chmod=555 init.bash comfyui-nvidia_init.bash

ARG BUILD_DATE="unknown"
LABEL comfyui-nvidia-docker-build=${BUILD_DATE}

CMD [ "./comfyui-nvidia_init.bash" ]
