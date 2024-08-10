FROM infotrend/ctpo-cuda_tensorflow_pytorch_opencv:12.3.2_2.16.1_2.2.2_4.9.0-20240421

RUN apt update -y && apt upgrade -y

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

# Prepare directories
RUN mkdir /HF
ENV HF_HOME=/HF

RUN mkdir -p /data/input /data/output /data/temp

# Create a local comfy user (can make it the same uid and gid as the user building the container)
ARG C_UID=1000
ARG C_GID=1000
USER root
RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y --no-install-recommends sudo
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers && \
    (addgroup --group --gid ${C_GID} comfy || true) && \
    adduser --force-badname --disabled-password --gecos '' --uid ${C_UID} --gid ${C_GID} --shell /bin/bash comfy && \
    adduser comfy sudo
USER comfy
RUN sudo chown -R comfy /home/comfy /HF /data

ENV NVIDIA_VISIBLE_DEVICES=all

EXPOSE 8188

# Full list of CLI options at https://github.com/comfyanonymous/ComfyUI/blob/master/comfy/cli_args.py
CMD python3 main.py --listen 0.0.0.0 --disable-auto-launch --output-directory /data/output --temp-directory /data/temp --input-directory /data/input
