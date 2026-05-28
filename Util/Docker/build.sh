#!/bin/bash

set -e

DOC_STRING="Build docker images.

This script builds the base, development, and CI/CD docker images."

USAGE_STRING=$(cat <<- END
Usage: $0 [options]

Build configurations (choose one or more):

    --base               Build base docker image (required by dev, ue4, monolith and ci)
    --dev                Build development docker image
    --ue4                Build UE4 image (carla-ue4:<branch>). Requires EPIC credentials.
    --monolith           Build monolith image (carla-monolith:<branch>). Uses the UE4 image
                         as its base, so it does NOT need EPIC credentials.
    --ci                 Build CI/CD docker image

User and group options:

    --user UID:GID       Set host UID and GID for the container (default: current user)
    --docker-gid GID     Set GID of the Docker group (default: $(getent group docker | cut -d: -f3))

Ubuntu distribution:

    --ubuntu-distro DISTRO   Specify ubuntu distro (default: 20.04).

Build options:

    --force-rebuild      Force rebuild images with no cache
    --branch             CARLA branch or tag (default: main; used by --ue4 to tag the
                         image and by --monolith to clone CARLA)
    --repo               CARLA git repository URL (only for --monolith)
    --ue4-image          Pre-built UE4 image to use as base for --monolith
                         (default: carla-ue4:<branch>)

Epic credentials (only needed for --ue4)
    --epic-user          Github user name
    --epic-token         Github access token

Other commands:

    -h, --help           Show this help message and exit
END
)

UBUNTU_DISTRO=20.04

BUILD_BASE=false
BUILD_DEV=false
BUILD_UE4=false
BUILD_MONOLITH=false
BUILD_CI=false

# CARLA target branch and repo for monolith build
BRANCH="main"
REPO="https://github.com/taiya/carla.git"
EPIC_USER=
EPIC_TOKEN=
UE4_IMAGE=

HOST_UID=$(id -u)
HOST_GID=$(id -g)
DOCKER_GID=$(getent group docker | cut -d: -f3)

FORCE_REBUILD=

OPTS=`getopt -o h --long help,ubuntu-distro:,base,dev,ue4,monolith,ci,user:,docker-gid:,branch:,repo:,ue4-image:,epic-user:,epic-token:,force-rebuild -n 'parse-options' -- "$@"`

eval set -- "$OPTS"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ubuntu-distro )
      UBUNTU_DISTRO="$2";
      shift 2 ;;
    --base )
      BUILD_BASE=true
      shift ;;
    --dev )
      BUILD_DEV=true
      shift ;;
    --ue4 )
      BUILD_UE4=true
      shift ;;
    --monolith )
      BUILD_MONOLITH=true
      shift ;;
    --ci )
      BUILD_CI=true
      shift ;;
    --ue4-image)
      UE4_IMAGE="$2"
      shift 2 ;;
    --user )
      IFS=':' read -r HOST_UID HOST_GID <<< "$2"
      shift 2 ;;
    --docker-gid)
      DOCKER_GID="$2"
      shift 2 ;;
    --branch)
      BRANCH="$2"
      shift 2 ;;
    --repo)
      REPO="$2"
      shift 2 ;;
    --epic-user)
      EPIC_USER="$2"
      shift 2 ;;
    --epic-token)
      EPIC_TOKEN="$2"
      shift 2 ;;
    --force-rebuild )
      FORCE_REBUILD=true
      shift ;;
    -h | --help )
      echo "$DOC_STRING"
      echo "$USAGE_STRING"
      exit 1
      ;;
    * )
      shift ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CARLA_ROOT=${SCRIPT_DIR}/../..

# Copy python runtime requirements for later installation in the docker image
rm -rf ${SCRIPT_DIR}/.tmp && mkdir ${SCRIPT_DIR}/.tmp
cp ${CARLA_ROOT}/PythonAPI/examples/requirements.txt ${SCRIPT_DIR}/.tmp/examples_requirements.txt
cp ${CARLA_ROOT}/PythonAPI/util/requirements.txt ${SCRIPT_DIR}/.tmp/util_requirements.txt

if ${BUILD_BASE} || ${BUILD_DEV} || ${BUILD_UE4} || ${BUILD_MONOLITH} || ${BUILD_CI}; then
  echo "Building base image carla-base:ue4-${UBUNTU_DISTRO}"
  docker build \
    --build-arg UBUNTU_DISTRO=${UBUNTU_DISTRO} \
    -t carla-base:ue4-${UBUNTU_DISTRO} \
    -f ${SCRIPT_DIR}/Base.Dockerfile ${SCRIPT_DIR}
fi

# UE4 (and monolith) also need the development image as a starting point.
if ${BUILD_UE4} || ${BUILD_MONOLITH}; then
  BUILD_DEV=true
fi

if ${BUILD_DEV}; then
  if [ "$FORCE_REBUILD" = true ]; then
    echo "Removing existing volume carla-development-ue4-${UBUNTU_DISTRO}"
    docker volume rm -f carla-development-ue4-${UBUNTU_DISTRO} 2>/dev/null || true
  fi
  echo "Ensuring volume carla-development-ue4-${UBUNTU_DISTRO} exists"
  docker volume create carla-development-ue4-${UBUNTU_DISTRO}

  echo "Building development image carla-development:ue4-${UBUNTU_DISTRO} with user ${HOST_UID}:${HOST_GID}"
  docker build ${FORCE_REBUILD:+--no-cache} \
    --build-arg UBUNTU_DISTRO=${UBUNTU_DISTRO} \
    --build-arg UID=${HOST_UID} \
    --build-arg GID=${HOST_GID} \
    --build-arg DOCKER_GID=${DOCKER_GID} \
    --target development \
    -t carla-development:ue4-${UBUNTU_DISTRO} \
    -f ${SCRIPT_DIR}/Development.Dockerfile ${SCRIPT_DIR}
fi

if ${BUILD_UE4}; then
  # Load .env file for EPIC_USER, EPIC_PASS, etc.
  if [ -f "${CARLA_ROOT}/.env" ]; then
    # shellcheck disable=SC2046
    export $(grep -v '^#' "${CARLA_ROOT}/.env" | xargs)
  fi

  if [ -z "${EPIC_USER}" ] || [ -z "${EPIC_TOKEN}" ]; then
    echo "[ERROR] Missing EPIC credentials!"
    echo "Please make sure both EPIC_USER and EPIC_TOKEN are defined."
    echo "You can set them in a .env file at the project root or export them as environment variables."
    exit 1
  fi

  echo "Building UE4 image carla-ue4:${BRANCH} with user ${HOST_UID}:${HOST_GID}"
  BUILDKIT_STEP_LOG_MAX_SIZE=104857600 docker build --progress=plain ${FORCE_REBUILD:+--no-cache} \
    --build-arg UBUNTU_DISTRO=${UBUNTU_DISTRO} \
    --build-arg UID=${HOST_UID} \
    --build-arg GID=${HOST_GID} \
    --build-arg DOCKER_GID=${DOCKER_GID} \
    --secret id=epic_user,env=EPIC_USER \
    --secret id=epic_token,env=EPIC_TOKEN \
    --target ue4 \
    -t carla-ue4:${BRANCH} \
    -f ${SCRIPT_DIR}/Development.Dockerfile ${SCRIPT_DIR}
fi

if ${BUILD_MONOLITH}; then
  # If no UE4 base image was specified, fall back to the conventional tag.
  : "${UE4_IMAGE:=carla-ue4:${BRANCH}}"

  if ! docker image inspect "${UE4_IMAGE}" >/dev/null 2>&1; then
    echo "[ERROR] UE4 base image '${UE4_IMAGE}' not found locally."
    echo "Build it first with: $0 --ue4 --branch ${BRANCH} --epic-user ... --epic-token ..."
    exit 1
  fi

  echo "Building monolith image carla-monolith:${BRANCH} on top of ${UE4_IMAGE}"
  BUILDKIT_STEP_LOG_MAX_SIZE=104857600 docker build --progress=plain ${FORCE_REBUILD:+--no-cache} \
    --build-arg UE4_IMAGE="${UE4_IMAGE}" \
    --build-arg BRANCH=${BRANCH} \
    --build-arg REPO=${REPO} \
    -t carla-monolith:${BRANCH} \
    -f ${SCRIPT_DIR}/Monolith.Dockerfile ${SCRIPT_DIR}
fi

if  ${BUILD_CI} ; then
  echo "Building CI/CD image carla-builder:ue4-${UBUNTU_DISTRO} with user ${HOST_UID}:${HOST_GID}"
  docker build ${FORCE_REBUILD:+--no-cache} \
    --build-arg UBUNTU_DISTRO=${UBUNTU_DISTRO} \
    --build-arg UID=${HOST_UID} \
    --build-arg GID=${HOST_GID} \
    --build-arg DOCKER_GID=${DOCKER_GID} \
    -t carla-builder:ue4-${UBUNTU_DISTRO} \
    -f ${SCRIPT_DIR}/CI.Dockerfile ${SCRIPT_DIR}
fi

