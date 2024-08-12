SHELL := /bin/bash
.PHONY: all

DOCKER_CMD=docker

# Following ComfyUI release number
COMFY_VERSION="0.0.6"
NAMED_CONTAINER_NAME="comfyui-ctpo"
NAMED_BUILD="${NAMED_CONTAINER_NAME}:${COMFY_VERSION}"
NAMED_BUILD_LATEST="${NAMED_CONTAINER_NAME}:latest"

VAR_NT="${NAMED_CONTAINER_NAME}-${COMFY_VERSION}"
DOCKER_PRE="NVIDIA_VISIBLE_DEVICES=all"

DOCKER_BUILD_ARGS=
#DOCKER_BUILD_ARGS="--no-cache"

C_UID=`id -u`
C_GID=`id -g`
#C_UID=1000
#C_GID=1000

all:
	@echo "** Available Docker images to be built (make targets):"
	@echo "build:          builds ${NAMED_BUILD} (to be run as uid: ${C_UID} / gid: ${C_GID}) and tags it as ${NAMED_BUILD_LATEST}"

build:
	@make build_main

build_main:
	@echo "-- Docker command to be run:"
	@echo "BUILDX_EXPERIMENTAL=1 ${DOCKER_PRE} docker buildx debug --on=error build --progress plain --platform linux/amd64 ${DOCKER_BUILD_ARGS} \\" > ${VAR_NT}.cmd
	@echo "  --build-arg COMFY_VERSION=\"${COMFY_VERSION}\" \\" >> ${VAR_NT}.cmd
	@echo "  --build-arg C_UID=\"${C_UID}\" \\" >> ${VAR_NT}.cmd
	@echo "  --build-arg C_JID=\"${C_GID}\" \\" >> ${VAR_NT}.cmd
	@echo "  --tag=\"${NAMED_BUILD}\" \\" >> ${VAR_NT}.cmd
	@echo "  -f Dockerfile \\" >> ${VAR_NT}.cmd
	@echo "  ." >> ${VAR_NT}.cmd

	@cat ${VAR_NT}.cmd | tee ${VAR_NT}.log.temp
	@chmod +x ./${VAR_NT}.cmd
	@script -a -e -c ./${VAR_NT}.cmd ${VAR_NT}.log.temp; exit "$${PIPESTATUS[0]}"

	@mv ${VAR_NT}.log.temp ${VAR_NT}.log
	@rm -f ./${VAR_NT}.cmd

	@${DOCKER_CMD} tag ${NAMED_BUILD} ${NAMED_BUILD_LATEST}

