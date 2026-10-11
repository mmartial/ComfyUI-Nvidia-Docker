FROM nvidia/cuda:13.3.1-cudnn-devel-ubuntu26.04

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

ARG BASE_DOCKER_FROM=nvidia/cuda:13.3.1-cudnn-devel-ubuntu26.04

ENV TORCH_CUDA_ARCH_LIST=12.1a
