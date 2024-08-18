SHELL := /bin/bash
.PHONY: all

DOCKER_CMD=docker

# Following ComfyUI release number
# To manually set the release
COMFYUI_VERSION_FILE=.comfyui_version
COMFYUI_VERSION=$(file < ${COMFYUI_VERSION_FILE})
# Note that due to rate limiting, we use a cached version

# To bypass all this check, uncomment both lines and set the version
#COMFYUI_VERSION_OVERRIDE=True
#COMFYUI_VERSION=0.0.8

# BASE container build
COMFYUI_BASE=comfyui-nvidia-base
BASE_BUILD=${COMFYUI_BASE}:${BASE_DATE}
BASE_BUILD_LATEST=${COMFYUI_BASE}:latest

BASE_DOCKER_FROM=nvidia/cuda:12.3.2-runtime-ubuntu22.04
BASE_DOCKERFILE=Dockerfile-base
BASE_DATE=$(shell printf '%(%Y%m%d)T' -1)

# ComfyUI container build "FROM" the BASE container
COMFYUI_CONTAINER_NAME=comfyui-nvidia-docker
NAMED_BUILD=${COMFYUI_CONTAINER_NAME}:${COMFYUI_VERSION}
NAMED_BUILD_LATEST=${COMFYUI_CONTAINER_NAME}:latest

DOCKERFILE=Dockerfile
DOCKER_FROM=${BASE_BUILD_LATEST}

# UID and GID are obtained from the user building the image
COMFYUI_UID=`id -u`
COMFYUI_GID=`id -g`
# or can be set manually
#COMFYUI_UID=1000
#COMFYUI_GID=1000

DOCKER_PRE="NVIDIA_VISIBLE_DEVICES=all"

CHECK_EXISTING_BUILD=True
# Uncomment to attempt to build even if the build already exist (usually uncommented for dev)
#CHECK_EXISTING_BUILD=False

DOCKER_BUILD_ARGS=
#DOCKER_BUILD_ARGS="--no-cache"

VERBOSE_PRINT=False
# Uncomment to see the process
#VERBOSE_PRINT=True

#####

all:
	@make check_comfy_version
	@echo ""
	@echo "** Available Docker images to be built (make targets):"
	@echo "base:           builds ${BASE_BUILD} and tags it as ${BASE_BUILD_LATEST}"
	@echo "local:          builds ${NAMED_BUILD} (to be run as uid: ${COMFYUI_UID} / gid: ${COMFYUI_GID}) and tags it as ${NAMED_BUILD_LATEST} (requires base)"
	@echo ""
	@echo "build:          builds local"

##### Verbose print

verbose_print:
ifeq (${VERBOSE_PRINT}, True)
	@echo "VERBOSE: ${VERB}"
endif

##### Check ComfyUI version

check_comfy_version:
ifeq (${COMFYUI_VERSION_OVERRIDE}, True) # if override is requested, let's just check that there is a version set
	@VERB="override requested, checking for version" make verbose_print
ifeq (${COMFYUI_VERSION},) # can not continue
	@echo "COMFY_VERSION override requested but no version set, can not continue" && false
endif
else # no override, normal checks
	@VERB="no override -> check2" make verbose_print
	@make check_comfy_version_part2
endif

check_comfy_version_part2:
ifeq (${COMFYUI_VERSION},) # if we have no value, we have no choice but to check
	@VERB="no value -> check3" make verbose_print
	@make check_comfy_version_part3
else # Otherwise, that will depend on how old the file is
ifneq ("$(wildcard $(COMFYUI_VERSION_FILE))","") # if the file exists and is over 60 minutes, we can check if a new version is out
	@if test `find "${COMFYUI_VERSION_FILE}" -mmin +60`; then make check_comfy_version_part3; fi
endif
endif

check_comfy_version_part3:
	@VERB="check3: obtain GH latest release" make verbose_print
	@$(eval TMP_V=$(shell curl  -L -sS  -H "Accept: application/json" https://api.github.com/repos/comfyanonymous/comfyui/releases/latest | grep tag_name | perl -ne 'print $$1 if m%\"v([\d\.]+)\"%')) # attempt to grab the latest version info
	@VERB="Found: ${TMP_V}" make verbose_print
	@if [ "A${TMP_V}" == "A" ]; then make check_comfy_version_part4_empty; else make TMP_V=${TMP_V} check_comfy_version_part4_value; fi 

check_comfy_version_part4_empty:
	@VERB="check4: no found value, checking against existing one" make verbose_print
ifeq (${COMFYUI_VERSION},) # if it is empty, do nothing ... as long as we already have a value
	@echo "!! We have no cached value for the latest version of ComfyUI, we can not continue" && false
endif
	@echo "ComfyUI version: ${COMFYUI_VERSION}"

check_comfy_version_part4_value: # if the new value differ, make it the default (write it to disk and fail)
	@VERB="check5: checking if cached value (${COMFYUI_VERSION}) differs from the latest retrieved value (${TMP_V})" make verbose_print
	@if [ "A${COMFYUI_VERSION}" != "A${TMP_V}" ]; then echo "!! The cached value (${COMFYUI_VERSION}) differs from the latest retrieved value (${TMP_V}), storing the latest value and stopping"; echo -n ${TMP_V} > ${COMFYUI_VERSION_FILE}; echo -n "Written to ${COMFYUI_VERSION_FILE}: "; cat ${COMFYUI_VERSION_FILE}; echo ""; false; fi
# else: value match, do nothing
	@echo "ComfyUI version: ${COMFYUI_VERSION}"


##### base

base:
	@VAR_NT=${COMFYUI_BASE}-${BASE_DATE} make build_base_check

build_base_check:
	@echo "== [${BASE_BUILD}] =="
ifeq (${CHECK_EXISTING_BUILD}, True)
	@VERB="base: check existing ${NAMED_BUILD} build" make verbose_print
ifeq ($(shell docker images -q ${NAMED_BUILD} 2> /dev/null),)
	@make build_base_check_part2
else
	@echo "Image ${NAMED_BUILD} already exists, skipping base step" 
endif
else
	@make build_base_check_part2
endif

build_base_check_part2:
ifeq (${CHECK_EXISTING_BUILD}, True)
	@VERB="base: check existing ${BASE_BUILD} build" make verbose_print
ifeq ($(shell docker images -q ${BASE_BUILD} 2> /dev/null),)
	@make build_base_actual
else
	@echo "Image ${BASE_BUILD} exists, skipping step"
endif
else
	@make build_base_actual
endif

build_base_actual:
	@VERB="base: actual build" make verbose_print
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

build:
	@make local

local:
	@make base
	@make check_comfy_version
	@VAR_NT=${COMFYUI_CONTAINER_NAME}-${COMFYUI_VERSION} USED_UID=${COMFYUI_UID} USED_GID=${COMFYUI_GID} USED_BUILD=${NAMED_BUILD} USED_BUILD_LATEST=${NAMED_BUILD_LATEST} make build_main_check


build_main_check:
	@make check_comfy_version
	@echo "== [${USED_BUILD}] =="
ifeq (${CHECK_EXISTING_BUILD}, True)
	@VERB="local: check existing ${USED_BUILD} build" make verbose_print
ifeq ($(shell docker images -q ${USED_BUILD} 2> /dev/null),)
	@make build_main_actual
else
	@echo "Image ${USED_BUILD} exists, skipping step"
endif
else
	@make build_main_actual
endif

build_main_actual:
	@VERB="local: actual build" make verbose_print
	@make check_comfy_version
	@echo "-- Docker command to be run:"
	@echo "BUILDX_EXPERIMENTAL=1 ${DOCKER_PRE} docker buildx debug --on=error build --progress plain --platform linux/amd64 ${DOCKER_BUILD_ARGS} \\" > ${VAR_NT}.cmd
	@echo "  --build-arg DOCKER_FROM=\"${DOCKER_FROM}\" \\" >> ${VAR_NT}.cmd
	@echo "  --build-arg COMFYUI_VERSION=\"${COMFYUI_VERSION}\" \\" >> ${VAR_NT}.cmd
	@echo "  --build-arg COMFYUI_UID=\"${USED_UID}\" \\" >> ${VAR_NT}.cmd
	@echo "  --build-arg COMFYUI_GID=\"${USED_GID}\" \\" >> ${VAR_NT}.cmd
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

clean_base:
	docker rmi ${BASE_BUILD}

clean_local:
	docker rmi ${NAMED_BUILD}


##### push 
DOCKERHUB_REPO="mmartial"

docker_tag:
	@make check_comfy_version
	@echo "Creating docker hub tags -- Press Ctl+c within 5 seconds to cancel -- will only work for maintainers"
	@for i in 5 4 3 2 1; do echo -n "$$i "; sleep 1; done; echo ""
	@make base
	@${DOCKER_CMD} tag ${BASE_BUILD} ${DOCKERHUB_REPO}/${BASE_BUILD}
	@${DOCKER_CMD} tag ${BASE_BUILD_LATEST} ${DOCKERHUB_REPO}/${BASE_BUILD_LATEST}
	@make local
	@${DOCKER_CMD} tag ${NAMED_BUILD} ${DOCKERHUB_REPO}/${NAMED_BUILD}
	@${DOCKER_CMD} tag ${NAMED_BUILD_LATEST} ${DOCKERHUB_REPO}/${NAMED_BUILD_LATEST}

docker_push:
	@make docker_tag
	@echo "hub.docker.com upload -- Press Ctl+c within 5 seconds to cancel -- will only work for maintainers"
	@for i in 5 4 3 2 1; do echo -n "$$i "; sleep 1; done; echo ""
	@${DOCKER_CMD} push ${DOCKERHUB_REPO}/${BASE_BUILD}
	@${DOCKER_CMD} push ${DOCKERHUB_REPO}/${BASE_BUILD_LATEST}
	@${DOCKER_CMD} push ${DOCKERHUB_REPO}/${NAMED_BUILD}
	@${DOCKER_CMD} push ${DOCKERHUB_REPO}/${NAMED_BUILD_LATEST}
