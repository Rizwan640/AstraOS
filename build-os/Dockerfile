# ==============================================================================
#  AstraOS ISO Builder Container
#  Usage:
#    docker build -f build-os/Dockerfile -t astraos-builder .
#    docker run --privileged --rm -v "${PWD}/output:/output" astraos-builder
# ==============================================================================

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    debootstrap \
    squashfs-tools \
    xorriso \
    grub-pc-bin \
    grub-efi-amd64-bin \
    mtools \
    dosfstools \
    curl \
    ca-certificates \
    rsync \
    bash \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
COPY . /workspace

RUN chmod +x /workspace/build-os/build-iso.sh

CMD ["/workspace/build-os/build-iso.sh"]
