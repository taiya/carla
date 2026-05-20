include Util/BuildTools/Vars.mk
ifeq ($(OS),Windows_NT)
include Util/BuildTools/Windows.mk
else
include Util/BuildTools/Linux.mk
endif

# --- token should have read access over private repositories (sigh...)
check-auth:
	git ls-remote https://$(EPIC_USER):$(EPIC_TOKEN)@github.com/CarlaUnreal/UnrealEngine.git HEAD

# --- build the full monolith image (~233 GB, ~2+ hours).
# Compiles Unreal Engine 4 + CARLA from source inside Docker.
# Requires EPIC_USER and EPIC_TOKEN env vars (GitHub credentials for CarlaUnreal/UnrealEngine).
docker.monolith:
	Util/Docker/build.sh --monolith \
		--branch main \
		--repo https://github.com/taiya/carla.git \
		--epic-user=$(EPIC_USER) \
		--epic-token=$(EPIC_TOKEN)

# Image name for the lightweight runtime image.
# If WAYVE_REGISTRY is set (see ~/.bashrc), the image is tagged directly with
# the full registry path so `make docker` + `make docker.push` need no retag step.
# Falls back to a plain local name when WAYVE_REGISTRY is unset.
CARLA_RUNTIME_IMAGE := $(if $(WAYVE_REGISTRY),$(WAYVE_REGISTRY)/library/carlasim/carla:0.9.16novignette,carla-runtime:main)

# --- build the lightweight runtime image (~20 GB) from the pre-built monolith.
# Requires: make docker.monolith  (must run first; ~233 GB image, ~2+ hours to build)
docker:
	docker build \
		--build-arg DIST_DIR=$$(docker run --rm carla-monolith:main bash -c \
			"ls /workspaces/carla/Dist/ | grep -v .tar.gz | head -1") \
		-f Util/Docker/Runtime.Dockerfile \
		-t $(CARLA_RUNTIME_IMAGE) \
		Util/Docker

# Push the runtime image to the registry specified by WAYVE_REGISTRY env var.
# Requires: export WAYVE_REGISTRY=<registry-host>  (set in ~/.bashrc)
docker.push:
	@test -n "$(WAYVE_REGISTRY)" || (echo "ERROR: WAYVE_REGISTRY is not set"; exit 1)
	az acr login --name $(WAYVE_REGISTRY)
	docker push $(CARLA_RUNTIME_IMAGE)
	@echo "Pushed: $(CARLA_RUNTIME_IMAGE)"

# ---------------------------------------------------------------------------
# Video capture targets
#
# Each target runs a self-contained Docker container that:
#   1. Starts CarlaUE4 in headless/offscreen mode
#   2. Runs hello_video.py (mounted from the host) to save PNG frames
#   3. Exits; ffmpeg then encodes the frames on the host
#
# Requirements on the host:
#   - NVIDIA Container Toolkit  (for --gpus all)
#   - ffmpeg                    (apt install ffmpeg)
#   - runtime image built via: make docker  (needs docker.monolith first)
#
# Output layout:
#   $(OUTPUT_DIR)/<run>/frames/*.png  -- captured frames
#   $(OUTPUT_DIR)/<run>.mp4           -- encoded video
# ---------------------------------------------------------------------------

DOCKER_IMAGE ?= $(CARLA_RUNTIME_IMAGE)
VIDEO_FRAMES ?= 200
VIDEO_FPS    ?= 20
OUTPUT_DIR   ?= /workspace/output/carla

# Inside the runtime image the packaged CARLA lives directly under /workspace/.
# The carla Python wheel is pre-installed at image build time (no pip needed at run time).
CARLA_LAUNCHER = /workspace/CarlaUE4.sh

# $(1) = run name   $(2) = --postprocess arg   $(3) = --vignette arg
define CAPTURE
	mkdir -p $(OUTPUT_DIR)/$(1)/frames
	docker run --rm --gpus all --net=host \
		--user $$(id -u):$$(id -g) \
		-e HOME=/tmp \
		-v $(OUTPUT_DIR):/output \
		-v $(CURDIR)/PythonAPI/examples/hello_video.py:/hello_video.py:ro \
		$(DOCKER_IMAGE) bash -lc '\
			$(CARLA_LAUNCHER) -RenderOffScreen -nosound -quality-level=Epic & \
			SERVER_PID=$$!; \
			sleep 15; \
			python3.8 /hello_video.py \
				--postprocess $(2) --vignette $(3) \
				--frames $(VIDEO_FRAMES) --outdir /output/$(1)/frames; \
			EXIT_CODE=$$?; \
			kill $$SERVER_PID; wait $$SERVER_PID 2>/dev/null || true; \
			exit $$EXIT_CODE'
endef

# $(1) = run name -> $(OUTPUT_DIR)/$(1)/frames/*.png -> $(OUTPUT_DIR)/$(1).mp4
define ENCODE
	ffmpeg -y -framerate $(VIDEO_FPS) \
		-i $(OUTPUT_DIR)/$(1)/frames/%06d.png \
		-c:v libx264 -pix_fmt yuv420p \
		$(OUTPUT_DIR)/$(1).mp4
endef

# (1) Default: all post-processing on
video.default:
	$(call CAPTURE,default,on,on)
	$(call ENCODE,default)

# (2) Post-processing disabled
video.no-postprocess:
	$(call CAPTURE,no_postprocess,off,on)
	$(call ENCODE,no_postprocess)

# (4) Vignette disabled — requires the patched taiya/carla build
video.no-vignette:
	$(call CAPTURE,no_vignette,on,off)
	$(call ENCODE,no_vignette)

videos: video.default video.no-postprocess video.no-vignette
