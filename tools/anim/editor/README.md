# Animation editor

A page in your browser for posing and timing Dark Cloud motions by hand, on the real model: the six party members,
Opar, and every monster.

```bash
python tools/anim/editor/server.py
```

Then open <http://127.0.0.1:8765>. `Animation Editor.bat` beside this file does both. Options: `--data <extracted
game data>` (default `E:/Gauntlet-build/run/data`, or `DC_DATA`), `--play <save folder>` (where saves are copied for
playing, default `E:/Gauntlet-build/play/save`), `--port`, and `--lan` to open it to the other devices on your local
network (a tablet, another PC): it prints the address to use, such as `http://192.168.1.3:8765`. Anyone on that network
can then open and save motions, so leave it off on a network you don't trust. Windows may ask once to let Python
through its firewall; allow it on private networks.

Needs Python 3.11 or newer and an internet connection the first time the page loads (three.js comes from jsDelivr).

## Using it

1. **Pick a character or monster** at the top left.
2. **Open a motion**: one of the game's own (a key on every frame; *Thin out keys* keeps only the ones that matter),
   a mod's motion file, or *New from this pose*.
3. **Pose.** Click a dot on the model or a bone in the list on the right.
   - **Rotate** (`R`): turn the bone with the rings, or type degrees.
   - **Move** (`T`): move a bone the motion moves (the body's centre: `ctr` on the party, often `hip` on monsters).
   - **Limb** (`I`): pick a hand, foot or any bone and drag the handle; the two animated bones above it bend so it
     follows, the knee or elbow staying in the plane it bends in.

   Posing on a frame without a key makes one there.
4. **Time it** on the timeline: drag keys to retime them, set the ease into the selected key, change the length and
   the speed. *Play* runs at the game's speed (60 ticks a second, `speed` motion frames a tick).
5. **Travel preview**: the engine carries a move by its `lunge` (losing `decay` every tick). Tick *show travel* and
   enter the move's numbers to see the motion with the distance it covers.
6. **Save** (`Ctrl+S`) to a path under `mods/` or `examples/`. The server bakes the keys with `moonanim.bake` and
   writes the file with `moonanim.motion_document`, the same as the authoring scripts. If the play save has that mod,
   the file is copied there too, so the next launch uses it.

Monster motions save and reopen; a mod gives them to the monster in the game with `animations.monster_register`
(`animations.player_register` is for playable characters).

Keys: `Space` play, `←` `→` a frame, `K` key the pose, `Del` delete a key, `Ctrl+C`/`Ctrl+V` copy and paste a pose,
`Ctrl+Z`/`Ctrl+Y` undo and redo. *Copy a native pose…* takes any frame of any of the rig's native motions.

## Reference: Elden Ring animations beside the character

If you own Elden Ring, the *Reference* panel draws one of its animations as a stick figure beside the character (green
its left side, red its right), to watch how a similar action moves while you pose your own keys. It is scaled to the
character's height, turned to face +Z like him, and either fitted over this motion's length (*fit to this motion*, from
and to any of its frames) or played at its own speed (*real time*). It stays beside him on screen from any angle;
*its own travel* moves it along its root motion. Nothing of it is saved, and it is never copied into a motion.

The panel appears once there is a reference cache: `tools/anim/reference` reads the player's skeleton and the game's
own animations from your install, and lists any downloaded animation repositories beside them (see its README). The
server looks for the cache in `%LOCALAPPDATA%/Moonmod/reference` (or `--reference`, or `MOONANIM_REFERENCE`) and
decodes each animation the first time you show it.

## Driving it from an assistant (MCP)

`mcp_server.py` is an MCP server (stdio, no packages) for the page you have open, so an assistant can do what you do
there while you watch. The repository's `.mcp.json` registers it for Claude Code as `moonmod-animation-editor`; for
another client, run `python tools/anim/editor/mcp_server.py` from the repository (`--editor <url>` if the editor isn't
on port 8765). If the editor isn't running, the first command starts it in a window of its own and opens the page.

| Tool | What it does |
|---|---|
| `list_rigs` | The characters, Opar and the monsters (filter by group or name). |
| `list_motions` | A rig's native motions, its mod motion files and its animated bones. |
| `editor_status` | The page's rig and motion: path, length, speed, keys and eases, travel preview. |
| `open_motion` | Opens a rig and a native motion, a motion file, or a new motion from the current pose. |
| `get_pose` | Each bone's rotation (the bone panel's degrees), translation and position at a frame. |
| `set_pose` | Keys a frame: start from a native frame, set or turn bones, move the centre, reach a hand or foot to a point. |
| `edit_motion` | Undo and redo, delete or move keys, eases, length, speed, thin out keys, the travel preview. |
| `save_motion` | Saves as the Save button does (under `mods/` or `examples/`, copied into the play save). |
| `screenshot` | A PNG of a frame, or of several tiled, from a fitted camera (front, side, top, three-quarter) or yours. |
| `reference` | The Reference panel: list its groups and animations, show one, and set how it's placed and timed. |

Every change it makes is one undo step on the page, so `Ctrl+Z` takes it back. Commands travel through the server
(`/api/bridge`): the page asks for the next one and posts the answer. Unsaved work lives only in the page: if it
reloads or closes, the command it was on fails with that message and nothing runs on the fresh page, and
`editor_status`'s `page` id changes, so save before you reload. With two pages open, whichever asks first takes the
command.

## How it draws the model

The page loads the converted glTF (`<data>/dun/mainchara`, `<data>/dun/monstor`; Opar's from `art/opar/build/rig`)
without its animations, and poses its nodes from the pack's own motion channels (served by `moonanim`, so what you
see is what the game plays).

The converter writes each joint's inverse bind matrix as the inverse of that joint's own bind-pose (`.bbp`) matrix,
local to its parent. glTF expects the whole chain's. So, as Dark Cloud skins (`MotionProc2` in Chronicle's
`port/src/game/gameutil.cpp`), the page rebuilds every joint's bind matrix as the product down from the skin's parent,
joints by their `.bbp` matrix and other nodes by their own transform. This is also why Blender's import pulls the
skins apart.

## Checks

- Saving a motion file unchanged gives it back (Vigil's `toan_dive_roll.json`: largest difference 1e-6).
- Every MCP tool answered against the open page, including a reload in the middle of a call; reaching Toan's right
  hand and left foot to points lands on them exactly.
- The reference: the game's forward roll (`a000_027100`) faces and moves the way Toan does, upright on the floor, in step
  with his timeline in both timings, and beside him in every screenshot view.
- All 178 packs open, and the 32 skinned ones (the party, Opar, Dran, the parts of Master Utan and more) skin around their bones.
