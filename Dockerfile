ARG DOCKER_FROM=comfyui-base:latest
FROM ${DOCKER_FROM}

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -y --fix-missing \
  && apt-get upgrade -y \
  && apt-get install -y rsync python3-venv git \
  && apt-get clean

RUN localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG=en_US.utf8
ENV LC_ALL=C

ARG COMFYUI_VERSION="fail"
ENV COMFYUI_DIR="/ComfyUI"
RUN mkdir -p ${COMFYUI_DIR} 
WORKDIR ${COMFYUI_DIR}

ENV PIP_ROOT_USER_ACTION=ignore

RUN wget -q -O /tmp/get-pip.py --no-check-certificate https://bootstrap.pypa.io/get-pip.py \
  && python3 /tmp/get-pip.py \
  && pip3 install --trusted-host pypi.org --trusted-host files.pythonhosted.org -U pip \
  && rm /tmp/get-pip.py

# Need git for ComfyUI Manager
#RUN wget -q https://github.com/comfyanonymous/ComfyUI/archive/refs/tags/v${COMFYUI_VERSION}.tar.gz -O - | tar --strip-components=1 -xz -C ${COMFYUI_DIR} \
RUN git clone --depth 1 --branch v${COMFYUI_VERSION} https://github.com/comfyanonymous/ComfyUI.git ${COMFYUI_DIR} \
    && cd ${COMFYUI_DIR} \
    && pip3 install --trusted-host pypi.org --trusted-host files.pythonhosted.org -r requirements.txt \
    && pip3 install --trusted-host pypi.org --trusted-host files.pythonhosted.org -U "huggingface_hub[cli]" \
    && rm -rf /root/.cache/pip

# Create a local comfy user and prepare a directory with ComfyUI's own directories ready to copy to the end user
ENV COMFYUI_USERDIR="/ComfyUI-user"
RUN mkdir -p ${COMFYUI_USERDIR}/data/temp ${COMFYUI_USERDIR}/HF ${COMFYUI_USERDIR}/user

ENV COMFYUSER_DIR="/comfy"
ENV COMFYMNT_DIR="${COMFYUSER_DIR}/mnt"
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends sudo
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers \
    && useradd -u 1024 -U -d ${COMFYUSER_DIR} -s /bin/bash -m comfy \
    && usermod -G users comfy \
    && adduser comfy sudo \
    && test -d ${COMFYUSER_DIR}
RUN cd ${COMFYUI_DIR} \
  && ln -s ${COMFYMNT_DIR}/user \
  && mv models ${COMFYUI_USERDIR}/. && ln -s ${COMFYMNT_DIR}/models \
  && mv custom_nodes ${COMFYUI_USERDIR}/. && ln -s ${COMFYMNT_DIR}/custom_nodes \
  && mv input ${COMFYUI_USERDIR}/data/. && ln -s ${COMFYMNT_DIR}/data/input \
  && mv output ${COMFYUI_USERDIR}/data/. && ln -s ${COMFYMNT_DIR}/data/output \
  && mv comfy_extras ${COMFYUI_USERDIR}/. && ln -s ${COMFYMNT_DIR}/comfy_extras

RUN it="/etc/comfyuser_dir"; echo ${COMFYUSER_DIR} > $it && chmod 555 $it

USER comfy
RUN it="${COMFYUSER_DIR}/comfymnt_dir"; echo ${COMFYMNT_DIR} > $it && chmod 555 $it
RUN it="${COMFYUSER_DIR}/comfy_dir"; echo ${COMFYUI_DIR} > $it && chmod 555 $it
RUN it="${COMFYUSER_DIR}/comfy_userdir"; echo ${COMFYUI_USERDIR} > $it && chmod 555 $it
RUN it="${COMFYUSER_DIR}/comfy_version"; echo ${COMFYUI_VERSION} > $it && chmod 555 $it
RUN echo -n "BUILD_DATE: UTC " | tee ${COMFYUSER_DIR}/comfy_main.txt; date +'%Y%m%d_%H%M%S' | tee -a ${COMFYUSER_DIR}/comfy_main.txt

RUN sudo chown -R comfy:comfy ${COMFYUI_USERDIR}
RUN cd ${COMFYUI_USERDIR} && mkdir -p HF
ENV HF_HOME=${COMFYUI_USERDIR}/HF

ENV NVIDIA_VISIBLE_DEVICES=all

EXPOSE 8188

COPY --chown=comfy:comfy --chmod=555 init.bash comfyui-nvidia-docker_init.bash

CMD [ "./comfyui-nvidia-docker_init.bash" ]
