include Util/BuildTools/Vars.mk
ifeq ($(OS),Windows_NT)
include Util/BuildTools/Windows.mk
else
include Util/BuildTools/Linux.mk
endif

docker:
	Util/Docker/build.sh --monolith \
		--branch main \
		--repo https://github.com/taiya/carla.git \
		--epic-user=$(EPIC_USER) \
		--epic-token=$(EPIC_TOKEN)
