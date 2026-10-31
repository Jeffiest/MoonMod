# Opar showcase video

`opar_showcase.mp4` (1280x720, 60 fps, 33 s): real game footage, captured headless and cut with cards and captions.

- `vshot.ps1`: one headless capture from a copy of the video save (the Gauntlet, plus a director mod), screenshots every
  frame (60 a second). The video save is a test save with the Gauntlet's Opar setting on, Move tips off, the map
  overlay and fps gauge off, and a run started as Opar.
- `director_main.lua`: the director mod (`moonmod.video`): Opar takes over, stays unhurt, and the camera follows the
  shot's `video_shot.txt` (distance and height, set every frame: set now and then, the follow camera eases back between and the view
  pulses; `free` leaves the follow camera alone).
- `capture.py`: the shots (idle, run, spit, gob, bubble, croak, slam, and others), each its own run and input script.
- `edit.py`: the cut: graded frames, title and end cards, captions, a few of his croaks on the sound track, ffmpeg.

Shots where he travels (the Belly Slide, the Frog Hop, the Back Hop) are left out: the headless camera doesn't follow
him, so he shrinks into the distance. The Tongue Lash and Staff Swat need a locked-on enemy.
