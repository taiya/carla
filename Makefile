include Util/BuildTools/Vars.mk
ifeq ($(OS),Windows_NT)
include Util/BuildTools/Windows.mk
else
include Util/BuildTools/Linux.mk
endif

# --- token should have read access over private repositories (sigh...)
check-auth:
	git ls-remote https://$(EPIC_USER):$(EPIC_TOKEN)@github.com/CarlaUnreal/UnrealEngine.git HEAD

# --- build the UE4 image carla-ue4:novehicle (~150 GB, ~1+ hour).
# Compiles Unreal Engine 4 from source inside Docker.
# Requires EPIC_USER and EPIC_TOKEN env vars (GitHub credentials for CarlaUnreal/UnrealEngine).
docker.ue4:
	Util/Docker/build.sh --ue4 \
		--branch novehicle \
		--epic-user=$(EPIC_USER) \
		--epic-token=$(EPIC_TOKEN)

# --- build the monolith image carla-monolith:novehicle (~233 GB, ~1+ hour).
# Compiles CARLA on top of the carla-ue4:novehicle image (which must already
# be loaded locally; see `make docker.ue4`). Does not need EPIC credentials.
docker.monolith:
	Util/Docker/build.sh --monolith \
		--branch novehicle \
		--repo https://github.com/taiya/carla.git

CARLA_RUNTIME_IMAGE := $(AZURE_CONTAINER_REGISTRY)/library/carlasim/carla:0.9.16-novehicle

# --- build the lightweight runtime image (~20 GB) from the pre-built monolith.
# Requires: make docker.monolith  (must run first; ~233 GB image, ~2+ hours to build)
# Requires: AZURE_CONTAINER_REGISTRY env var (set in ~/.bashrc)
docker:
	@test -n "$(AZURE_CONTAINER_REGISTRY)" || (echo "ERROR: AZURE_CONTAINER_REGISTRY is not set"; exit 1)
	docker build \
		--build-arg MONOLITH_TAG=novehicle \
		--build-arg DIST_DIR=$$(docker run --rm carla-monolith:novehicle bash -c \
			"ls /workspaces/carla/Dist/ | grep -v .tar.gz | head -1") \
		-f Util/Docker/Runtime.Dockerfile \
		-t $(CARLA_RUNTIME_IMAGE) \
		Util/Docker

# Push the runtime image to the registry specified by AZURE_CONTAINER_REGISTRY env var.
# Requires: export AZURE_CONTAINER_REGISTRY=<registry-host>  (set in ~/.bashrc)
docker.push:
	@test -n "$(AZURE_CONTAINER_REGISTRY)" || (echo "ERROR: AZURE_CONTAINER_REGISTRY is not set"; exit 1)
	az acr login --name $(AZURE_CONTAINER_REGISTRY)
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

# $(1) = run name   $(2) = --postprocess arg   $(3) = --vignette arg   $(4) = --camera arg   $(5) = --hide-vehicles arg
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
				--camera $(4) --hide-vehicles $(5) \
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
	$(call CAPTURE,default,on,on,front,off)
	$(call ENCODE,default)

# (2) Post-processing disabled
video.no-postprocess:
	$(call CAPTURE,no_postprocess,off,on,front,off)
	$(call ENCODE,no_postprocess)

# (4) Vignette disabled — requires the patched taiya/carla build
video.no-vignette:
	$(call CAPTURE,no_vignette,on,off,front,off)
	$(call ENCODE,no_vignette)

# (5) Follow-cam, vehicle visible — requires the patched taiya/carla build (novehicle branch)
video.with_vehicles:
	$(call CAPTURE,with_vehicles,on,on,follow,off)
	$(call ENCODE,with_vehicles)

# (6) Follow-cam, vehicle hidden — requires the patched taiya/carla build (novehicle branch)
video.without_vehicles:
	$(call CAPTURE,without_vehicles,on,on,follow,on)
	$(call ENCODE,without_vehicles)

videos: video.default video.no-postprocess video.no-vignette video.with_vehicles video.without_vehicles

# 2×2 comparison video (runs after all three captures are done)
video.comparison:
	OUTPUT_DIR=$(OUTPUT_DIR) VIDEO_FPS=$(VIDEO_FPS) \
		PythonAPI/examples/comparison_video.sh
