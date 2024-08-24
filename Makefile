SHELL := /bin/bash
.PHONY: all

DOCKER_CMD=docker

DOCKER_FROM=nvidia/cuda:12.3.2-runtime-ubuntu22.04

BUILD_DATE=$(shell printf '%(%Y%m%d_%H%M)T' -1)

COMFYUI_CONTAINER_NAME=comfyui-nvidia-docker
NAMED_BUILD=${COMFYUI_CONTAINER_NAME}:${BUILD_DATE}
NAMED_BUILD_LATEST=${COMFYUI_CONTAINER_NAME}:latest

DOCKERFILE=Dockerfile
DOCKER_PRE="NVIDIA_VISIBLE_DEVICES=all"


DOCKER_BUILD_ARGS=
#DOCKER_BUILD_ARGS="--no-cache"

# Set to False to make it less verbose
VERBOSE_PRINT=True

#####

all:
	@echo "** Available Docker images to be built (make targets):"
	@echo "latest:          builds ${NAMED_BUILD} and tags it as ${NAMED_BUILD_LATEST}"
	@echo ""
	@echo "build:          builds latest"

##### latest

build:
	@make latest


latest:
	@VAR_NT=${COMFYUI_CONTAINER_NAME}-${COMFYUI_VERSION} USED_BUILD=${NAMED_BUILD} USED_BUILD_LATEST=${NAMED_BUILD_LATEST} make build_main_actual


build_main_actual:
	@echo "== [${USED_BUILD}] =="
	@echo "-- Docker command to be run:"
	@echo "BUILDX_EXPERIMENTAL=1 ${DOCKER_PRE} docker buildx debug --on=error build --progress plain --platform linux/amd64 ${DOCKER_BUILD_ARGS} \\" > ${VAR_NT}.cmd
	@echo "  --build-arg DOCKER_FROM=\"${DOCKER_FROM}\" \\" >> ${VAR_NT}.cmd
	@echo "  --build-arg BASE_DOCKER_FROM=\"${DOCKER_FROM}\" \\" >> ${VAR_NT}.cmd
	@echo "  --build-arg BUILD_DATE=\"${BUILD_DATE}\" \\" >> ${VAR_NT}.cmd
	@echo "  --tag=\"${USED_BUILD}\" \\" >> ${VAR_NT}.cmd
	@echo "  -f ${DOCKERFILE} \\" >> ${VAR_NT}.cmd
	@echo "  ." >> ${VAR_NT}.cmd

	@cat ${VAR_NT}.cmd | tee ${VAR_NT}.log.temp
	@chmod +x ./${VAR_NT}.cmd
	@script -a -e -c ./${VAR_NT}.cmd ${VAR_NT}.log.temp; exit "$${PIPESTATUS[0]}"

	@mv ${VAR_NT}.log.temp ${VAR_NT}.log
	@rm -f ./${VAR_NT}.cmd

	@${DOCKER_CMD} tag ${USED_BUILD} ${USED_BUILD_LATEST}


##### clean

docker_rmi:
	docker rmi --force ${NAMED_BUILD} ${DOCKERHUB_REPO}/${NAMED_BUILD} ${NAMED_BUILD_LATEST} ${DOCKERHUB_REPO}/${NAMED_BUILD_LATEST}


##### push 
DOCKERHUB_REPO="mmartial"

docker_tag:
	@make latest
	@${DOCKER_CMD} tag ${NAMED_BUILD} ${DOCKERHUB_REPO}/${NAMED_BUILD}
	@${DOCKER_CMD} tag ${NAMED_BUILD_LATEST} ${DOCKERHUB_REPO}/${NAMED_BUILD_LATEST}
	@make docker_tag_list

docker_tag_list:
	@echo "Docker images tagged:"
	@${DOCKER_CMD} images --filter "label=comfyui-nvidia-docker-build=${BUILD_DATE}"

docker_push:
	@make docker_tag
	@echo "hub.docker.com upload -- Press Ctl+c within 5 seconds to cancel -- will only work for maintainers"
	@for i in 5 4 3 2 1; do echo -n "$$i "; sleep 1; done; echo ""
	@${DOCKER_CMD} push ${DOCKERHUB_REPO}/${NAMED_BUILD}
	@${DOCKER_CMD} push ${DOCKERHUB_REPO}/${NAMED_BUILD_LATEST}
