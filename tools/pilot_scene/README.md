# pilot_scene (v12.91)

The sample pictures and clips for the PilotScene test (HL_PILOTSCENE) are in assets/pilot_scene/_sample/ (left out of the export). These are NOT game art.
The owner's real files go in `assets/pilot_scene/<male|female>/` (see `scripts/pilot_scene.gd` for the names). His MP4s go
through `import_clips.py`, which makes the .ogv files Godot plays and checks the first and last frames.
