CARLA Simulator
===============

See [README_original.md](README_original.md) for the original upstream README.

## Modifications from upstream (0.9.16)

- **`Util/Docker/build.sh`** — added `--repo` option to specify the CARLA git repository URL;
  defaults to `https://github.com/taiya/carla.git` on branch `main`
- **`Util/Docker/Development.Dockerfile`** — added `REPO` build arg so the monolith Docker build
  clones from a configurable repository instead of the hardcoded upstream URL
- **`Makefile`** — added `make docker` target as a shorthand for the monolith Docker build

### Epic credentials

The Docker build requires a GitHub username and personal access token linked to an Epic Games
account (needed to clone the Unreal Engine fork). Export them in your shell before running:

```bash
export EPIC_USER=your_github_username
export EPIC_TOKEN=your_github_token
make docker
```
