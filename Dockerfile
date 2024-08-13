ARG DOCKER_FROM="infotrend/ctpo-cuda_tensorflow_pytorch_opencv:12.3.2_2.16.1_2.2.2_4.9.0-20240421"
FROM ${DOCKER_FROM}

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -y --fix-missing \
  && apt-get upgrade -y \
  && apt-get clean

RUN localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG=en_US.utf8
ENV LC_ALL=C

ARG COMFY_VERSION="0.0.5"
ENV COMFY_DIR="/ComfyUI"
RUN mkdir -p ${COMFY_DIR}
WORKDIR ${COMFY_DIR}

ENV PIP_ROOT_USER_ACTION=ignore

RUN wget -q -O /tmp/get-pip.py --no-check-certificate https://bootstrap.pypa.io/get-pip.py \
  && python3 /tmp/get-pip.py \
  && pip3 install -U pip \
  && rm /tmp/get-pip.py

RUN wget -q https://github.com/comfyanonymous/ComfyUI/archive/refs/tags/v${COMFY_VERSION}.tar.gz -O - | tar --strip-components=1 -xz -C ${COMFY_DIR} \
    && cd ${COMFY_DIR} \
    && pip3 install -r requirements.txt \
    && rm -rf /root/.cache/pip

# Create a local comfy user (can make it the same uid and gid as the user building the container)
ARG COMFY_UID=1000
ARG COMFY_GID=1000
USER root
RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y --no-install-recommends sudo
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers && \
    (addgroup --group --gid ${COMFY_GID} comfy || true) && \
    adduser --force-badname --disabled-password --gecos '' --uid ${COMFY_UID} --gid ${COMFY_GID} --shell /bin/bash comfy && \
    adduser comfy sudo
RUN cd ${COMFY_DIR} && rm -rf user models && ln -s /home/comfy/mnt/user && ln -s /home/comfy/mnt/models 
RUN echo ${COMFY_DIR} > /etc/comfy_dir && chmod 555 /etc/comfy_dir
USER comfy
RUN cd /home/comfy && mkdir -p mnt/HF mnt/data/input mnt/data/output mnt/data/temp mnt/user mnt/models
ENV HF_HOME=/home/comfy/mnt/HF

ENV NVIDIA_VISIBLE_DEVICES=all

EXPOSE 8188

COPY --chown=comfy:comfy --chmod=555 init.bash /home/init.bash

CMD [ "/home/init.bash" ]
