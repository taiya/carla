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
