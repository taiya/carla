include Util/BuildTools/Vars.mk
ifeq ($(OS),Windows_NT)
include Util/BuildTools/Windows.mk
else
include Util/BuildTools/Linux.mk
endif

# --- token should have read access over private repositories (sigh...)
check-auth:
	git ls-remote https://$(EPIC_USER):$(EPIC_TOKEN)@github.com/CarlaUnreal/UnrealEngine.git HEAD

# --- build the docker image
docker:
	Util/Docker/build.sh --monolith \
		--branch main \
		--repo https://github.com/taiya/carla.git \
		--epic-user=$(EPIC_USER) \
		--epic-token=$(EPIC_TOKEN)

# ---------------------------------------------------------------------------
# Video capture targets
#
# Each target runs a self-contained Docker container (carla-monolith:main) that:
#   1. Starts CarlaUE4 in headless/offscreen mode from the packaged Dist/
#   2. Runs hello_video.py (mounted from the host) to save PNG frames
#   3. Exits; ffmpeg then encodes the frames on the host
#
# Requirements on the host:
#   - NVIDIA Container Toolkit  (for --gpus all)
#   - ffmpeg                    (apt install ffmpeg)
#   - carla-monolith:main image built via: make docker EPIC_USER=... EPIC_TOKEN=...
#
# Output layout:
#   $(OUTPUT_DIR)/<run>/frames/*.png  -- captured frames
#   $(OUTPUT_DIR)/<run>.mp4           -- encoded video
# ---------------------------------------------------------------------------

DOCKER_IMAGE ?= carla-monolith:main
VIDEO_FRAMES ?= 200
VIDEO_FPS    ?= 20
OUTPUT_DIR   ?= /workspace/output/carla

# Inside the monolith image:
#   CarlaUE4.sh is at /workspaces/carla/Dist/CARLA_0.9.16/LinuxNoEditor/CarlaUE4.sh
#   Python 3.10 is at /usr/local/bin/python3.10
#   carla wheel is at /workspaces/carla/PythonAPI/carla/dist/carla-*-cp310-*.whl
CARLA_LAUNCHER = /workspaces/carla/Dist/CARLA_0.9.16/LinuxNoEditor/CarlaUE4.sh
CARLA_WHEEL    = /workspaces/carla/PythonAPI/carla/dist/carla-0.9.16-cp310-cp310-manylinux_2_31_x86_64.whl

# $(1) = run name   $(2) = --postprocess arg   $(3) = --vignette arg
define CAPTURE
	mkdir -p $(OUTPUT_DIR)/$(1)/frames
	docker run --rm --gpus all --net=host \
		-v $(OUTPUT_DIR):/output \
		-v $(CURDIR)/PythonAPI/examples/hello_video.py:/hello_video.py:ro \
		$(DOCKER_IMAGE) bash -lc '\
			python3.10 -m pip install --quiet $(CARLA_WHEEL) && \
			$(CARLA_LAUNCHER) -RenderOffScreen -nosound -quality-level=Epic & \
			SERVER_PID=$$!; \
			sleep 15; \
			python3.10 /hello_video.py \
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
