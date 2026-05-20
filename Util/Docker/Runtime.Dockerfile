# Multi-stage build: extract the pre-compiled LinuxNoEditor package from the
# monolith image and wrap it in a minimal runtime-only layer (~20 GB vs ~233 GB).
#
# Prerequisites: carla-monolith:main must already be built (make docker.monolith).
#
# Usage (via Makefile):
#   make docker        <- builds carla-runtime:main
#   make docker.monolith  <- builds carla-monolith:main (233 GB, ~2+ hours)

ARG MONOLITH_TAG=main

# ---------------------------------------------------------------------------
# Stage 1: extraction layer — pull the packaged runtime out of the monolith.
# ---------------------------------------------------------------------------
FROM carla-monolith:${MONOLITH_TAG} AS monolith

# ---------------------------------------------------------------------------
# Stage 2: lean runtime image (~20 GB).
# ---------------------------------------------------------------------------
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN useradd -m carla

RUN apt-get update && apt-get install -y --no-install-recommends \
        libsdl2-2.0-0 \
        xserver-xorg \
        libvulkan1 \
        libomp5 \
        xdg-user-dirs \
        python3.8 \
        python3-pip \
        libjpeg8 \
        libtiff5 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# DIST_DIR is the build-artifact name inside the monolith (e.g. CARLA_Shipping_c0150db-dirty).
# The Makefile resolves this dynamically with `docker run --rm carla-monolith:main ls Dist/`.
ARG DIST_DIR
COPY --from=monolith --chown=carla:carla \
    /workspaces/carla/Dist/${DIST_DIR}/LinuxNoEditor/ .

# Pre-install the CARLA Python 3.8 client wheel so consumers don't need pip.
RUN python3.8 -m pip install --no-index \
    /workspace/PythonAPI/carla/dist/carla-0.9.16-cp38-cp38-linux_x86_64.whl

ENV OMP_PROC_BIND="FALSE"
ENV OMP_NUM_THREADS="48"
ENV NVIDIA_DRIVER_CAPABILITIES="all"
ENV NVIDIA_VISIBLE_DEVICES="all"

USER carla

CMD ["/bin/bash", "CarlaUE4.sh"]
