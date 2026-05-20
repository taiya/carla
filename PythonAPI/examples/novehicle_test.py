#!/usr/bin/env python3
"""novehicle_test.py – demonstrate set_render_hidden() with a follow camera.

Two modes are captured side-by-side:
  original   – camera follows behind the vehicle; vehicle is visible.
  novehicle  – same pose, same tick; vehicle is hidden via set_render_hidden(True).

Usage:
    python novehicle_test.py [--host HOST] [--port PORT] [--frames N]
                             [--output-dir DIR] [--no-video]

Requirements:
    - A running CARLA server built from the patched source on this branch.
    - Python packages: carla (patched wheel), opencv-python, numpy.
"""

import argparse
import os
import sys
import time

try:
    import carla
except ImportError:
    sys.exit("carla package not found – install the patched wheel first.")

try:
    import cv2
    import numpy as np
except ImportError:
    sys.exit("opencv-python and numpy are required: pip install opencv-python numpy")


# ---------------------------------------------------------------------------
# Camera geometry
# ---------------------------------------------------------------------------
# Offset from the vehicle origin: behind by 8 m, above by 3 m.
CAMERA_OFFSET = carla.Transform(
    carla.Location(x=-8.0, y=0.0, z=3.0),
    carla.Rotation(pitch=-10.0, yaw=0.0, roll=0.0),
)

CAMERA_WIDTH  = 1280
CAMERA_HEIGHT = 720
CAMERA_FOV    = 90


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def build_camera_bp(world: carla.World) -> carla.ActorBlueprint:
    bp = world.get_blueprint_library().find("sensor.camera.rgb")
    bp.set_attribute("image_size_x", str(CAMERA_WIDTH))
    bp.set_attribute("image_size_y", str(CAMERA_HEIGHT))
    bp.set_attribute("fov", str(CAMERA_FOV))
    return bp


def image_to_array(image: carla.Image) -> np.ndarray:
    arr = np.frombuffer(image.raw_data, dtype=np.uint8)
    arr = arr.reshape((image.height, image.width, 4))
    return arr[:, :, :3]  # drop alpha, keep BGR


def label_frame(frame: np.ndarray, text: str, colour=(255, 255, 255)) -> np.ndarray:
    out = frame.copy()
    cv2.putText(out, text, (20, 40), cv2.FONT_HERSHEY_SIMPLEX, 1.2, colour, 2)
    return out


def save_png(path: str, arr: np.ndarray) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    cv2.imwrite(path, arr)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def run(args: argparse.Namespace) -> None:
    client = carla.Client(args.host, args.port)
    client.set_timeout(10.0)

    world  = client.get_world()
    bp_lib = world.get_blueprint_library()

    # Use synchronous mode for deterministic frame capture.
    original_settings = world.get_settings()
    settings = world.get_settings()
    settings.synchronous_mode = True
    settings.fixed_delta_seconds = 0.05
    world.apply_settings(settings)

    vehicle = None
    camera  = None
    frames_original: list[np.ndarray] = []
    frames_novehicle: list[np.ndarray] = []
    latest_image: list[np.ndarray] = [None]

    def on_image(image: carla.Image) -> None:
        latest_image[0] = image_to_array(image)

    try:
        # -- Spawn vehicle ---------------------------------------------------
        vehicle_bp = bp_lib.filter("vehicle.lincoln.mkz_2020")[0]
        spawn_point = world.get_map().get_spawn_points()[0]
        vehicle = world.spawn_actor(vehicle_bp, spawn_point)
        vehicle.set_autopilot(True)

        # -- Attach camera behind vehicle ------------------------------------
        camera_bp = build_camera_bp(world)
        camera = world.spawn_actor(camera_bp, CAMERA_OFFSET, attach_to=vehicle)
        camera.listen(on_image)

        # Let autopilot stabilise for a second.
        for _ in range(20):
            world.tick()
            time.sleep(0.01)

        print(f"Capturing {args.frames} frames (original + novehicle) …")

        # -- Capture ORIGINAL (vehicle visible) ------------------------------
        latest_image[0] = None
        for i in range(args.frames):
            world.tick()
            time.sleep(0.02)
            if latest_image[0] is not None:
                frames_original.append(latest_image[0].copy())
                latest_image[0] = None

        # -- Hide vehicle ----------------------------------------------------
        assert hasattr(vehicle, "set_render_hidden"), (
            "set_render_hidden not found – is this the patched build?"
        )
        vehicle.set_render_hidden(True)
        print("vehicle.set_render_hidden(True) called – vehicle hidden.")

        # -- Capture NO-VEHICLE (vehicle invisible) --------------------------
        latest_image[0] = None
        for i in range(args.frames):
            world.tick()
            time.sleep(0.02)
            if latest_image[0] is not None:
                frames_novehicle.append(latest_image[0].copy())
                latest_image[0] = None

        # -- Restore ---------------------------------------------------------
        vehicle.set_render_hidden(False)
        print("vehicle.set_render_hidden(False) called – vehicle restored.")

    finally:
        # Restore async mode before cleanup.
        world.apply_settings(original_settings)
        if camera is not None:
            camera.stop()
            camera.destroy()
        if vehicle is not None:
            vehicle.destroy()

    # -- Save frames ---------------------------------------------------------
    n = min(len(frames_original), len(frames_novehicle))
    if n == 0:
        print("No frames captured – did the camera callback fire?")
        return

    os.makedirs(args.output_dir, exist_ok=True)

    for i in range(n):
        orig_labelled = label_frame(frames_original[i],  "original",   colour=(200, 255, 200))
        novo_labelled = label_frame(frames_novehicle[i], "novehicle",  colour=(200, 200, 255))

        side_by_side = np.concatenate([orig_labelled, novo_labelled], axis=1)

        save_png(os.path.join(args.output_dir, "original",  f"{i:06d}.png"), frames_original[i])
        save_png(os.path.join(args.output_dir, "novehicle", f"{i:06d}.png"), frames_novehicle[i])
        save_png(os.path.join(args.output_dir, "sbs",       f"{i:06d}.png"), side_by_side)

    print(f"Saved {n} frame(s) per mode to '{args.output_dir}/'")

    # -- Optional video ------------------------------------------------------
    if not args.no_video and n > 1:
        _write_video(
            os.path.join(args.output_dir, "sbs"),
            os.path.join(args.output_dir, "comparison.mp4"),
            fps=20,
            width=CAMERA_WIDTH * 2,
            height=CAMERA_HEIGHT,
        )


def _write_video(frame_dir: str, out_path: str, fps: int, width: int, height: int) -> None:
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    writer = cv2.VideoWriter(out_path, fourcc, fps, (width, height))
    try:
        files = sorted(f for f in os.listdir(frame_dir) if f.endswith(".png"))
        for fname in files:
            frame = cv2.imread(os.path.join(frame_dir, fname))
            if frame is not None:
                writer.write(frame)
    finally:
        writer.release()
    print(f"Video written to '{out_path}'")


# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--host",       default="127.0.0.1")
    p.add_argument("--port",       default=2000, type=int)
    p.add_argument("--frames",     default=30,   type=int,
                   help="Number of frames to capture per mode (default 30)")
    p.add_argument("--output-dir", default="output/novehicle_test",
                   help="Directory for saved frames and video")
    p.add_argument("--no-video",   action="store_true",
                   help="Skip video assembly (only save PNGs)")
    return p.parse_args()


if __name__ == "__main__":
    run(parse_args())
