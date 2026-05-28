# Clones and compiles CARLA on top of a pre-built UE4 image. Does NOT need
# EPIC credentials — UE4 is already baked into the base image.
#
# Inputs:
#   UE4_IMAGE — UE4 image tag to start from (default: carla-ue4:novehicle).
#               Produced by Development.Dockerfile target `ue4`.
#   BRANCH    — CARLA branch / tag to clone.
#   REPO      — CARLA git repository URL.
#
# Output: an image with CARLA built and packaged at /workspaces/carla/Dist.

ARG UE4_IMAGE=carla-ue4:novehicle
FROM ${UE4_IMAGE}

ARG USERNAME="carla"
USER ${USERNAME}

ENV CARLA_UE4_ROOT="/workspaces/carla"
ARG BRANCH=main
ARG REPO=https://github.com/taiya/carla.git
RUN git clone --depth 1 --branch ${BRANCH} ${REPO} ${CARLA_UE4_ROOT}

WORKDIR ${CARLA_UE4_ROOT}

# Fix libpng download URL: SourceForge moved 1.6.37 to older-releases/.
# This patch is idempotent and safe on newer clones where Setup.sh is already fixed.
RUN sed -i 's|sourceforge.net/projects/libpng/files/libpng16/|downloads.sourceforge.net/project/libpng/libpng16/older-releases/|g' \
    Util/BuildTools/Setup.sh

# NOTE: Don't run these commands together as Update.sh truncates the output
RUN ./Update.sh
RUN make PythonAPI
RUN make CarlaUE4Editor
RUN make package
