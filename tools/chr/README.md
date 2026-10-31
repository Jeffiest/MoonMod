# tools/chr

Character packs (`.chr`) rebuilt from an edited glTF: the way a new playable character (Opar) gets into the game. The
format work is done by the DC1 toolkit (`E:/dc1tk-blender`, `dc2tk model-export` / `model-build`); these scripts
drive it and check what comes out.

- `chrtool.py`: export a pack to `<stem>.gltf` + `.bin` + `textures/`, build one back on a template pack, and read,
  edit and compare the glTF meshes (unweld, subdivide, `surfaces`/`unmatched`, `cloth_meshes`).
- `roundtrip_test.py`: the proof, on any of the six characters (Toan, `c01d`, by default).

Python 3.11, no packages needed. `DC2TK=<path to dc2tk.exe>` points at another toolkit build.

## The round trip

```bash
python tools/chr/roundtrip_test.py E:/Gauntlet-build/run/data/dun/mainchara c01d <work folder>
```

1. The export built back unchanged is the game's pack byte for byte.
2. Every mesh but the cloth split three ways (each triangle around its centre), built, exported again: every triangle,
   normal, UV and skin weight is what was given (within float precision), every other member (motions, shadow model,
   cloth, textures, `base.cfg`) is untouched, and the weight lists name the same bones in the same order as the game's.

It writes `<work>/c01d_rebuilt.chr`. In game, a test mod overrides `dun/mainchara/c01d.chr` with it
(`game.resources.override`); checked 2026-10-29 with the headless capture (`animshot.ps1`): Toan idles, runs and
attacks with the rebuilt mesh, skin and cloth as he does with the game's pack, only the shading of the split
triangles differing.

## What the pipeline needed (fixed 2026-10-29)

| Where | Problem | Fix |
|---|---|---|
| Toolkit `info_cfg.rs` | DC1 turns skinning on with `VERTEX_ANIME 1` and names the skinned meshes with `ALLOC_DBUFF` (DC2 names them in `VERTEX_ANIME`), so the export had no skin and the weights were lost | `ALLOC_DBUFF` names are the skinned meshes when `VERTEX_ANIME` is a number |
| Toolkit `from_gltf.rs` | DC1 skins by walking a mesh's weight lists in order: the list aimed at the mesh's parent starts it and each bone's matrix builds on its parent's. The toolkit wrote only the bones with weights, so the skin stayed in the bind pose (Toan's arms straight out) | a rebuilt skinned mesh keeps a list for every bone from its parent down (`chained_weights`), keys or none |
| Engine (`dataread.cpp`, Chronicle patch) | an override read left the port's record of what was read at that address before, so pack members were found by luck and the textures were looked up as another file's (`baked asset resolution failed` and an abort), even for an unchanged pack | `DataReadTrackUnindexedFile`: the mod's bytes are recorded as a pack with no retail identity; its textures decode from its own bytes |

## A new character (Opar, `c07d`)

```bash
python tools/chr/build_character.py start E:/Gauntlet-build/run/data/dun/mainchara    # once: art/opar/opar.blend
python tools/chr/build_character.py build E:/Gauntlet-build/run/data/dun/mainchara    # art/opar/build/c07d.chr
```

- **Template** (`chrtool.derive`): Toan's pack with `c01d`/`c01s` renamed `c07d`/`c07s` in its members, `base.cfg`,
  the `.img`'s texture names and the meshes' material names, every file the same size. Frame (bone) names stay.
- **Blender rest** (`chrtool.bind_rest`): DC1's `.bbp` holds a *local* bind matrix per chain frame, multiplied down
  the hierarchy; the toolkit exports it as world matrices, so Blender's bones would heap at the origin and a plain
  import stretches the skin. The starting file's skeleton is the real bind pose (hips at 8.6, head 14.7, arms out at
  13); `restore_rest` gives the toolkit its own matrices back at build. Checked: Toan through Blender this way builds
  back byte for byte.
- **The starting file** (`blender/start_character.py`): collection **Character** (exported: the armature and the
  body `skin`) and **Template reference** (Toan's meshes as wireframe and the concept picture; not exported), with a
  blockout weighted to the 20 chain joints (`DEFORM`). Opar's own model replaces it: `art/opar/make_opar.py`
  (see `art/opar/README.md`).
- **The build** (`blender/export_character.py`, then `build_character.py`): Character exported, the template's skeleton
  restored, every Toan mesh it does not give removed (the toolkit's `extras.dc2tk_remove`), built on the template,
  and with the cloth gone `CLOTH`/`ALLOC_MDT` commented out. Textures: the template's, with each `art/opar/textures/*.png`
  in place of the one of its name.
- Checked 2026-10-29: the blockout's every triangle, UV and weight is in the pack (the toolkit drops the degenerate
  triangles at the spheres' poles); loaded in Toan's place (test mod overriding `dun/mainchara/c01d.chr`), it idles,
  walks and swings Toan's sword with the skin following the bones.

Modelling rules for the body:

- One skinned mesh named `skin` (the frame `ALLOC_DBUFF` names). Weight it only to the chain joints: `jnt1_1` hips,
  `jnt2_1` chest, `jnt11_1` neck, `jnt12_1` head, `jnt8_1`/`jnt16_1` collarbones, `jnt9_1`/`jnt9_2`/`jnt10_1` and
  `jnt17_1`/`jnt17_2`/`jnt18_1` arms and hands, `jnt22_1`/`jnt22_2`/`jnt23_1`/`jnt24_1` and
  `jnt5_1`/`jnt5_2`/`jnt6_1`/`jnt7_1` legs, feet and toes. The frames Toan's rigid meshes hang on (`kao`, `l_hand`,
  `r_f`...) sit at the origin (their meshes are in model space), and the rest are links and attachment points
  (`weapon`, `dcol`, `item`). Up to 4 weights a vertex.
- Materials take the pack's texture names: `c07d02`-`c07d05` are 256 x 256 (custom property `texture`, or the
  material's name). Leave `c07d01` (128 x 128) out: the eye blink (`TEX_ANIME`) copies into it.
- **Proportions** (`art/<name>/proportions.json`, `"move": {frame: [dx, dy, dz]}` in Blender's axes): a frame and
  everything below it moved from the template's place. The model script moves the bones in the .blend; the build
  moves the frame's translation in the glTF and its inverse bind matrix (the toolkit's inverse bind matrix of a chain
  frame is the inverse of the frame's local matrix, and it writes the `.bbp` from them: `chrtool.move_joints` checks
  that first), then writes the translation into the frame's record in the `.mds` (one 112-byte record a frame, the
  translation first, records from byte 112; `chrtool.set_frame_translations`), which the toolkit keeps from the
  template. Only frames whose translation no motion keys can move this way (Toan's motions key translations on
  `ctr`, `dcol`, `weapon`, `l_hand` and the root only). Opar's hips (`chn5`, `chn22`) are 0.7 wider, checked in game.
  The shadow model keeps the template's frames.
- Under the dungeon's light the blockout's blue-black reads nearly black: paint lighter than the concept.
- Still Toan's: the shadow model (`c07s.mds`, his silhouette on the ground), the eye-blink lines, the hand-up pack.

## Rules for a new model

- **Build on a character's pack as the template**: its frames (bones) keep their names and numbers, so motions,
  weapons, `moonanim` and the move runner find them. Meshes replace the template's by frame name.
- **Cloth meshes** (`ALLOC_MDT` in `base.cfg`: Toan's `cloth1`-`cloth3`) are driven by the `.clo` files by vertex
  number. Keep their vertices as they are, or drop the cloth (its `CLOTH` and `ALLOC_MDT` lines), or rebuild the
  `.clo`; a re-meshed poncho comes out as a stretched bar.
- **Limits** the toolkit checks: 32 bones per skinned mesh, 4 weights per vertex. The character model buffer
  (`CharaModelBuffer`, 210,000 quadwords) held Toan with every mesh split three ways at 121,007.
- The toolkit's size warning ("MoonMod will refuse it") is for kinds held to their retail size; a `.chr` may grow to
  16 MiB on Chronicle (API: *Chronicle: overrides larger than retail*).
- The shadow model (`c01s.mds`) is a separate mesh; a new character needs one of its own.
