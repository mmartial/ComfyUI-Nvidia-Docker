ARG DOCKER_FROM=comfyui-base:latest
FROM ${DOCKER_FROM}

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -y --fix-missing \
  && apt-get upgrade -y \
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

RUN wget -q https://github.com/comfyanonymous/ComfyUI/archive/refs/tags/v${COMFYUI_VERSION}.tar.gz -O - | tar --strip-components=1 -xz -C ${COMFYUI_DIR} \
    && cd ${COMFYUI_DIR} \
    && pip3 install --trusted-host pypi.org --trusted-host files.pythonhosted.org -r requirements.txt \
    && pip3 install --trusted-host pypi.org --trusted-host files.pythonhosted.org -U "huggingface_hub[cli]" \
    && rm -rf /root/.cache/pip

# Create a local comfy user and prepare a directory with ComfyUI's own directories ready to copy to the end user
ENV COMFYUI_USERDIR="/ComfyUI-user"
RUN mkdir -p ${COMFYUI_USERDIR}/data/temp ${COMFYUI_USERDIR}/HF ${COMFYUI_USERDIR}/user
ARG COMFYUI_UID=1000
ARG COMFYUI_GID=1000

USER root
RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y --no-install-recommends sudo rsync
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers \
    && (getent group ${COMFYUI_GID} || (sudo addgroup --group --gid ${COMFYUI_GID} comfytoo || true)) \
    && adduser --force-badname --disabled-password --gecos '' --uid ${COMFYUI_UID} --gid ${COMFYUI_GID} --shell /bin/bash comfy \
    && adduser comfy sudo
RUN cd ${COMFYUI_DIR} \
  && ln -s /home/comfy/mnt/user \
  && mv models ${COMFYUI_USERDIR}/. && ln -s /home/comfy/mnt/models \
  && mv custom_nodes ${COMFYUI_USERDIR}/. && ln -s /home/comfy/mnt/custom_nodes \
  && mv input ${COMFYUI_USERDIR}/data/. && ln -s /home/comfy/mnt/data/input \
  && mv output ${COMFYUI_USERDIR}/data/. && ln -s /home/comfy/mnt/data/output \
  && mv comfy_extras ${COMFYUI_USERDIR}/. && ln -s /home/comfy/mnt/comfy_extras

RUN echo ${COMFYUI_DIR} > /etc/comfy_dir && chmod 555 /etc/comfy_dir
RUN echo ${COMFYUI_USERDIR} > /etc/comfy_userdir && chmod 555 /etc/comfy_userdir
RUN echo ${COMFYUI_VERSION} > /etc/comfy_version && chmod 555 /etc/comfy_version
RUN echo -n "BUILD_DATE: UTC " | tee /etc/comfy_main.txt; date +'%Y%m%d_%H%M%S' | tee -a /etc/comfy_main.txt

USER comfy
RUN cd /home/comfy && mkdir -p mnt/HF
ENV HF_HOME=/home/comfy/mnt/HF

ENV NVIDIA_VISIBLE_DEVICES=all

EXPOSE 8188

COPY --chown=${COMFYUI_UID}:${COMFYUI_GID} --chmod=555 init.bash /home/init.bash

CMD [ "/home/init.bash" ]
