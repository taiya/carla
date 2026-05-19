CARLA Simulator
===============

See [README_original.md](README_original.md) for the original upstream README.

## Modifications from upstream (0.9.16)

- **`Util/Docker/build.sh`** — added `--repo` option to specify the CARLA git repository URL;
  defaults to `https://github.com/taiya/carla.git` on branch `main`
- **`Util/Docker/Development.Dockerfile`** — added `REPO` build arg (clone from configurable repo);
  kept `Dist/` after `make package` so the image can be launched headlessly
- **`Makefile`** — added `make docker` and `make video.*` targets (see below)
- **`sensor.camera.rgb`** — new `enable_vignette` blueprint attribute (bool, default `true`);
  independent of `enable_postprocess_effects`; requires the patched build
- **`PythonAPI/examples/hello_video.py`** — new demo script for frame capture

### Epic credentials

The Docker build requires a GitHub username and personal access token linked to an Epic Games
account (needed to clone the Unreal Engine fork). Export them in your shell before running:

```bash
export EPIC_USER=your_github_username
export EPIC_TOKEN=your_github_token
make docker
```

### Video capture

Requires `ffmpeg` on the host and the NVIDIA Container Toolkit (`--gpus all`).
Output goes to `/workspace/output/carla/` by default (override with `OUTPUT_DIR=...`).

| Target | Effect |
|---|---|
| `make video.default` | All post-processing on |
| `make video.no-postprocess` | Post-processing disabled |
| `make video.no-vignette` | Post-processing on, vignette off (requires patched build) |
| `make videos` | All three above in sequence |

All targets use `carla-monolith:main` by default. Override with `DOCKER_IMAGE=...`.

Number of frames and FPS are configurable:

```bash
make videos VIDEO_FRAMES=400 VIDEO_FPS=30
```

### `enable_vignette` camera attribute

The patched build adds a `enable_vignette` attribute to `sensor.camera.rgb` (and DVS):

```python
camera_bp = world.get_blueprint_library().find('sensor.camera.rgb')
camera_bp.set_attribute('enable_vignette', 'false')  # disable vignette independently
```

This is independent of `enable_postprocess_effects`. The attribute is absent on stock 0.9.16;
use `camera_bp.has_attribute('enable_vignette')` to detect the patched build at runtime.
