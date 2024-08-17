SHELL := /bin/bash
.PHONY: all

DOCKER_CMD=docker

# Following ComfyUI release number
# Automatically find the latest release number
COMFY_VERSION=$(shell curl  -L -sS  -H "Accept: application/json" https://api.github.com/repos/comfyanonymous/comfyui/releases/latest | grep tag_name | perl -ne 'print $$1 if m%\"v([\d\.]+)\"%')
# To manually set the release, uncomment and modify the line below
#COMFY_VERSION="0.0.6"

# BASE container build
COMFY_BASE=comfyui-nvidia-base
BASE_BUILD=${COMFY_BASE}:${BASE_DATE}
BASE_BUILD_PRESENT=$(shell test $(docker images -q ${BASE_BUILD}) && echo 1 || echo 0)
BASE_BUILD_LATEST=${COMFY_BASE}:latest

BASE_DOCKER_FROM=nvidia/cuda:12.3.2-runtime-ubuntu22.04
BASE_DOCKERFILE=Dockerfile-base
BASE_DATE=$(shell printf '%(%Y%m%d)T' -1)

# ComfyUI container build "FROM" the BASE container
COMFY_CONTAINER_NAME=comfyui-nvidia-docker

DOCKERFILE=Dockerfile
DOCKER_FROM=${BASE_BUILD_LATEST}

NAMED_BUILD=${COMFY_CONTAINER_NAME}:${COMFY_VERSION}
NAMED_BUILD_LATEST=${COMFY_CONTAINER_NAME}:latest
# UID and GID are obtained from the user building the image
COMFY_UID=`id -u`
COMFY_GID=`id -g`
# or can be set manually
#COMFY_UID=1000
#COMFY_GID=1000

DOCKER_PRE="NVIDIA_VISIBLE_DEVICES=all"

DOCKER_BUILD_ARGS=
#DOCKER_BUILD_ARGS="--no-cache"

all:
	@echo "== Latest ComfyUI version: ${COMFY_VERSION}"
	@echo "** Available Docker images to be built (make targets):"
	@echo "base:           builds ${BASE_BUILD} and tags it as ${BASE_BUILD_LATEST}"
	@echo "local:          builds ${NAMED_BUILD} (to be run as uid: ${COMFY_UID} / gid: ${COMFY_GID}) and tags it as ${NAMED_BUILD_LATEST} (requires base)"
	@echo "build:          builds local"

##### base

base:
	@echo "ComfyUI version: ${COMFY_VERSION}"
	@VAR_NT=${COMFY_BASE}-${BASE_DATE} make build_base_check

build_base_check:
	@echo "== [${BASE_BUILD}] =="
ifeq ($(shell docker images -q ${NAMED_BUILD} 2> /dev/null),)
	@make build_base_check_part2
else
	@echo "Image ${NAMED_BUILD} already exists, skipping base step" 
endif

build_base_check_part2:
ifeq ($(shell docker images -q ${BASE_BUILD} 2> /dev/null),)
	@make build_base_actual
else
	@echo "Image ${BASE_BUILD} exists, skipping step"
endif

build_base_actual:
	@echo "-- Docker command to be run:"
	@echo "BUILDX_EXPERIMENTAL=1 ${DOCKER_PRE} docker buildx debug --on=error build --progress plain --platform linux/amd64 ${DOCKER_BUILD_ARGS} \\" > ${VAR_NT}.cmd
	@echo "  --build-arg DOCKER_FROM=\"${BASE_DOCKER_FROM}\" \\" >> ${VAR_NT}.cmd
	@echo "  --tag=\"${BASE_BUILD}\" \\" >> ${VAR_NT}.cmd
	@echo "  -f ${BASE_DOCKERFILE} \\" >> ${VAR_NT}.cmd
	@echo "  ." >> ${VAR_NT}.cmd

	@cat ${VAR_NT}.cmd | tee ${VAR_NT}.log.temp
	@chmod +x ./${VAR_NT}.cmd
	@script -a -e -c ./${VAR_NT}.cmd ${VAR_NT}.log.temp; exit "$${PIPESTATUS[0]}"

	@mv ${VAR_NT}.log.temp ${VAR_NT}.log
	@rm -f ./${VAR_NT}.cmd

	@${DOCKER_CMD} tag ${BASE_BUILD} ${BASE_BUILD_LATEST}


##### main

local: base
	@VAR_NT=${COMFY_CONTAINER_NAME}-${COMFY_VERSION} USED_UID=${COMFY_UID} USED_GID=${COMFY_GID} USED_BUILD=${NAMED_BUILD} USED_BUILD_LATEST=${NAMED_BUILD_LATEST} make build_main_check

build: local

build_main_check:
	@echo "== [${USED_BUILD}] =="
ifeq ($(shell docker images -q ${USED_BUILD} 2> /dev/null),)
	@make build_main_actual
else
	@echo "Image ${USED_BUILD} exists, skipping step"
endif

build_main_actual:
	@echo "-- Docker command to be run:"
	@echo "BUILDX_EXPERIMENTAL=1 ${DOCKER_PRE} docker buildx debug --on=error build --progress plain --platform linux/amd64 ${DOCKER_BUILD_ARGS} \\" > ${VAR_NT}.cmd
	@echo "  --build-arg DOCKER_FROM=\"${DOCKER_FROM}\" \\" >> ${VAR_NT}.cmd
	@echo "  --build-arg COMFY_VERSION=\"${COMFY_VERSION}\" \\" >> ${VAR_NT}.cmd
	@echo "  --build-arg COMFY_UID=\"${USED_UID}\" \\" >> ${VAR_NT}.cmd
	@echo "  --build-arg COMFY_GID=\"${USED_GID}\" \\" >> ${VAR_NT}.cmd
	@echo "  --tag=\"${USED_BUILD}\" \\" >> ${VAR_NT}.cmd
	@echo "  -f ${DOCKERFILE} \\" >> ${VAR_NT}.cmd
	@echo "  ." >> ${VAR_NT}.cmd

	@cat ${VAR_NT}.cmd | tee ${VAR_NT}.log.temp
	@chmod +x ./${VAR_NT}.cmd
	@script -a -e -c ./${VAR_NT}.cmd ${VAR_NT}.log.temp; exit "$${PIPESTATUS[0]}"

	@mv ${VAR_NT}.log.temp ${VAR_NT}.log
	@rm -f ./${VAR_NT}.cmd

	@${DOCKER_CMD} tag ${USED_BUILD} ${USED_BUILD_LATEST}

##### push 
DOCKERHUB_REPO="mmartial"

docker_push: local
	@echo "Creating docker hub tags -- Press Ctl+c within 5 seconds to cancel -- will only work for maintainers"
	@for i in 5 4 3 2 1; do echo -n "$$i "; sleep 1; done; echo ""
	@make base
	@${DOCKER_CMD} tag ${BASE_BUILD} ${DOCKERHUB_REPO}/${BASE_BUILD}
	@${DOCKER_CMD} tag ${BASE_BUILD_LATEST} ${DOCKERHUB_REPO}/${BASE_BUILD_LATEST}
	@make local
	@${DOCKER_CMD} tag ${NAMED_BUILD} ${DOCKERHUB_REPO}/${NAMED_BUILD}
	@${DOCKER_CMD} tag ${NAMED_BUILD_LATEST} ${DOCKERHUB_REPO}/${NAMED_BUILD_LATEST}
	@echo "hub.docker.com upload -- Press Ctl+c within 5 seconds to cancel -- will only work for maintainers"
	@for i in 5 4 3 2 1; do echo -n "$$i "; sleep 1; done; echo ""
	@${DOCKER_CMD} push ${DOCKERHUB_REPO}/${BASE_BUILD}
	@${DOCKER_CMD} push ${DOCKERHUB_REPO}/${BASE_BUILD_LATEST}
	@${DOCKER_CMD} push ${DOCKERHUB_REPO}/${NAMED_BUILD}
	@${DOCKER_CMD} push ${DOCKERHUB_REPO}/${NAMED_BUILD_LATEST}
