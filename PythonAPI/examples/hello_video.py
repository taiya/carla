#!/usr/bin/env python

# Copyright (c) 2019 Computer Vision Center (CVC) at the Universitat Autonoma de
# Barcelona (UAB).
#
# This work is licensed under the terms of the MIT license.
# For a copy, see <https://opensource.org/licenses/MIT>.

"""
hello_video.py - Minimal CARLA demo that records PNG frames for video encoding.

Spawns a vehicle on autopilot in the current map, attaches an RGB camera, and
saves N frames to disk. Designed to be encoded into an MP4 with ffmpeg afterwards.

Usage:
    python3 hello_video.py [--host H] [--port P] [--postprocess {on,off}]
                           [--vignette {on,off}] [--frames N] [--outdir PATH]

Portability:
    --postprocess on/off   Works on stock CARLA 0.9.16 and the patched fork.
    --vignette on/off      Requires the patched taiya/carla build. If run against
                           a stock image with --vignette off the script will exit
                           with a descriptive error.
"""

import argparse
import os
import queue
import sys

import carla


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', default='127.0.0.1', help='CARLA server host (default: 127.0.0.1)')
    parser.add_argument('--port', type=int, default=2000, help='CARLA server port (default: 2000)')
    parser.add_argument('--postprocess', choices=['on', 'off'], default='on',
                        help='Enable/disable all post-processing effects (default: on)')
    parser.add_argument('--vignette', choices=['on', 'off'], default='on',
                        help='Enable/disable vignette effect (default: on, requires patched build)')
    parser.add_argument('--frames', type=int, default=200,
                        help='Number of frames to capture (default: 200)')
    parser.add_argument('--outdir', default='_out',
                        help='Output directory for PNG frames (default: _out)')
    return parser.parse_args()


def main():
    args = parse_args()
    os.makedirs(args.outdir, exist_ok=True)

    actor_list = []
    frame_queue = queue.Queue()

    try:
        client = carla.Client(args.host, args.port)
        client.set_timeout(10.0)
        world = client.get_world()

        blueprint_library = world.get_blueprint_library()

        # Use a deterministic vehicle spawn point
        spawn_points = world.get_map().get_spawn_points()
        if not spawn_points:
            print('ERROR: No spawn points available in this map.', file=sys.stderr)
            return 1
        transform = spawn_points[0]

        # Spawn vehicle
        vehicle_bp = blueprint_library.find('vehicle.tesla.model3')
        vehicle = world.spawn_actor(vehicle_bp, transform)
        actor_list.append(vehicle)
        print('Spawned vehicle: %s' % vehicle.type_id)
        vehicle.set_autopilot(True)

        # Configure RGB camera blueprint
        camera_bp = blueprint_library.find('sensor.camera.rgb')
        camera_bp.set_attribute('image_size_x', '1280')
        camera_bp.set_attribute('image_size_y', '720')

        # enable_postprocess_effects is present in stock 0.9.16 — always safe to set
        if args.postprocess == 'off':
            camera_bp.set_attribute('enable_postprocess_effects', 'false')

        # enable_vignette is patched-build-only — only set when disabling, guard carefully
        if args.vignette == 'off':
            if camera_bp.has_attribute('enable_vignette'):
                camera_bp.set_attribute('enable_vignette', 'false')
            else:
                print(
                    'ERROR: Camera blueprint has no "enable_vignette" attribute.\n'
                    'This requires the patched CARLA build (taiya/carla fork).\n'
                    'Run with --vignette on, or rebuild the Docker image with patched sources.',
                    file=sys.stderr)
                return 1

        camera_transform = carla.Transform(carla.Location(x=1.5, z=2.4))
        camera = world.spawn_actor(camera_bp, camera_transform, attach_to=vehicle)
        actor_list.append(camera)
        print('Spawned camera: %s (postprocess=%s, vignette=%s)' % (
            camera.type_id, args.postprocess, args.vignette))

        # Use synchronous mode for deterministic frame capture
        settings = world.get_settings()
        original_settings = world.get_settings()
        settings.synchronous_mode = True
        settings.fixed_delta_seconds = 1.0 / 20.0
        world.apply_settings(settings)

        camera.listen(frame_queue.put)

        print('Capturing %d frames into %s ...' % (args.frames, args.outdir))
        frame_index = 0
        while frame_index < args.frames:
            world.tick()
            image = frame_queue.get(timeout=5.0)
            image.save_to_disk(os.path.join(args.outdir, '%06d.png' % frame_index))
            frame_index += 1
            if frame_index % 20 == 0:
                print('  %d / %d frames' % (frame_index, args.frames))

        print('Done. Frames saved to: %s' % args.outdir)

    finally:
        # Restore async mode before destroying actors
        try:
            world.apply_settings(original_settings)
        except Exception:
            pass
        print('Destroying actors ...')
        for actor in reversed(actor_list):
            actor.destroy()
        print('Done.')


if __name__ == '__main__':
    sys.exit(main())
