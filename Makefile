SHELL := /bin/bash
.PHONY: all

DOCKER_CMD=docker
DOCKER_FROM="infotrend/ctpo-cuda_tensorflow_pytorch_opencv:12.3.2_2.16.1_2.2.2_4.9.0-20240421"

# Following ComfyUI release number
# Automatically find the latest release number
COMFY_VERSION=$(shell curl  -L -sS  -H "Accept: application/json" https://api.github.com/repos/comfyanonymous/comfyui/releases/latest | grep tag_name | perl -ne 'print $$1 if m%\"v([\d\.]+)\"%')
# To manually set the release, uncomment and modify the line below
#COMFY_VERSION="0.0.6"

COMFY_CONTAINER_NAME=comfyui-ctpo

NAMED_BUILD=${COMFY_CONTAINER_NAME}:${COMFY_VERSION}
NAMED_BUILD_LATEST=${COMFY_CONTAINER_NAME}:latest
# UID and GID are obtained from the user building the image
COMFY_UID=`id -u`
COMFY_GID=`id -g`
# or can be set manually
#COMFY_UID=1000
#COMFY_GID=1000

UNRAID_BUILD=${COMFY_CONTAINER_NAME}-unraid:${COMFY_VERSION}
UNRAID_BUILD_LATEST=${COMFY_CONTAINER_NAME}-unraid:latest
UNRAID_UID=99
UNRAID_GID=100

DOCKER_PRE="NVIDIA_VISIBLE_DEVICES=all"

DOCKER_BUILD_ARGS=
#DOCKER_BUILD_ARGS="--no-cache"

all:
	@echo "** Available Docker images to be built (make targets):"
	@echo "local:          builds ${NAMED_BUILD} (to be run as uid: ${COMFY_UID} / gid: ${COMFY_GID}) and tags it as ${NAMED_BUILD_LATEST}"
	@echo "unraid:         builds ${UNRAID_BUILD} (to be run as uid: ${UNRAID_UID} / gid: ${UNRAID_GID}) and tags it as ${UNRAID_BUILD_LATEST}"
	@echo "build:          builds both local and unraid"

local:
	@VAR_NT=${COMFY_CONTAINER_NAME}-${COMFY_VERSION} USED_UID=${COMFY_UID} USED_GID=${COMFY_GID} USED_BUILD=${NAMED_BUILD} USED_BUILD_LATEST=${NAMED_BUILD_LATEST} make build_main

unraid:
	@VAR_NT=${COMFY_CONTAINER_NAME}-unraid-${COMFY_VERSION} USED_UID=${UNRAID_UID} USED_GID=${UNRAID_GID} USED_BUILD=${UNRAID_BUILD} USED_BUILD_LATEST=${UNRAID_BUILD_LATEST} make build_main

build_main:
	@echo "-- Docker command to be run:"
	@echo "BUILDX_EXPERIMENTAL=1 ${DOCKER_PRE} docker buildx debug --on=error build --progress plain --platform linux/amd64 ${DOCKER_BUILD_ARGS} \\" > ${VAR_NT}.cmd
	@echo "  --build-arg DOCKER_FROM=\"${DOCKER_FROM}\" \\" >> ${VAR_NT}.cmd
	@echo "  --build-arg COMFY_VERSION=\"${COMFY_VERSION}\" \\" >> ${VAR_NT}.cmd
	@echo "  --build-arg COMFY_UID=\"${USED_UID}\" \\" >> ${VAR_NT}.cmd
	@echo "  --build-arg COMFY_GID=\"${USED_GID}\" \\" >> ${VAR_NT}.cmd
	@echo "  --tag=\"${USED_BUILD}\" \\" >> ${VAR_NT}.cmd
	@echo "  -f Dockerfile \\" >> ${VAR_NT}.cmd
	@echo "  ." >> ${VAR_NT}.cmd

	@cat ${VAR_NT}.cmd | tee ${VAR_NT}.log.temp
	@chmod +x ./${VAR_NT}.cmd
	@script -a -e -c ./${VAR_NT}.cmd ${VAR_NT}.log.temp; exit "$${PIPESTATUS[0]}"

	@mv ${VAR_NT}.log.temp ${VAR_NT}.log
	@rm -f ./${VAR_NT}.cmd

	@${DOCKER_CMD} tag ${USED_BUILD} ${USED_BUILD_LATEST}
