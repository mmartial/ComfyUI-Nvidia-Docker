FROM nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive

ARG BUILD_APT_PROXY
# Make use of apt-cacher-ng if available
RUN if [ "A${BUILD_APT_PROXY:-}" != "A" ]; then \
        echo "Using APT proxy: ${BUILD_APT_PROXY}"; \
        printf 'Acquire::http::Proxy "%s";\n' "$BUILD_APT_PROXY" > /etc/apt/apt.conf.d/01proxy; \
    fi \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates wget gnupg \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

ARG BUILD_ARCH=x86_64 
# Install NVIDIA CUDA repo keyring (adds /usr/share/keyrings/cuda-archive-keyring.gpg) and remove duplicate CUDA repo definitions to avoid Signed-By conflicts, then add a single canonical CUDA repo entry using the keyring
RUN wget -qO /tmp/cuda-keyring.deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/${BUILD_ARCH}/cuda-keyring_1.1-1_all.deb \
    && dpkg -i /tmp/cuda-keyring.deb \
    && rm -f /tmp/cuda-keyring.deb \
    && rm -f /etc/apt/sources.list.d/cuda*.list /etc/apt/sources.list.d/cuda*.sources \
    && rm -f /etc/apt/sources.list.d/nvidia*.list /etc/apt/sources.list.d/nvidia*.sources \
    && echo "deb [signed-by=/usr/share/keyrings/cuda-archive-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/${BUILD_ARCH}/ /" > /etc/apt/sources.list.d/cuda-ubuntu2404.list \
    && apt-get update \
    && apt-get clean

ARG BASE_DOCKER_FROM=nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04
