# tools/bb

A Bloodborne character model read from your own dump, as the first step of putting one into Dark Cloud in a
monster's place (the plan and where it stands: [docs/progress.md](../../docs/progress.md)).

Everything these tools read comes from your own copy of the game, and everything they write goes to a folder you
name, outside the repository. None of it is committed or shipped: these are FromSoftware's models and textures.

| Step | Tool | Gives |
|---|---|---|
| 1 | `BbModel list` | Every character archive in the dump's `chr` folder with its size, to choose from |
| 2 | `BbModel export` | `model.json` (skeleton, materials, meshes, weights) and `textures/*.dds` |
| 3 | `model_gltf.py` | `model.gltf` + `model.bin`, to open in Blender |
| - | `template_facts.py` | What the Dark Cloud monster's pack and its export hold, as text (below) |

## What you need

- Your Bloodborne dump, unpacked (the folder with `dvdroot_ps4/chr/c????.chrbnd.dcx`).
- DSAnimStudio unpacked somewhere, as for [`tools/anim/reference`](../anim/reference/README.md): this builds against
  its `SoulsFormats.dll`. Nothing of it is copied here.
- The .NET 9 SDK, and Python 3.11 or newer.

## Build, list, export

```bash
dotnet build tools/bb -c Release -p:DsasDir="C:/path/to/DSAnimStudio"
```

```bash
tools/bb/bin/Release/net9.0/BbModel.exe list "C:/path/to/dump/dvdroot_ps4/chr"
tools/bb/bin/Release/net9.0/BbModel.exe export "C:/path/to/dump/dvdroot_ps4/chr/c????.chrbnd.dcx" "$LOCALAPPDATA/Moonmod/bb/c????"
python tools/bb/model_gltf.py "$LOCALAPPDATA/Moonmod/bb/c????"
```

`list` prints one line per archive: meshes, vertices, triangles, bones, textures. `export` takes more archives after
the out folder and reads them for textures only, for a character whose textures sit in an archive of their own.
`model_gltf.py` writes `model.gltf` beside `model.json`; open it with Blender's File > Import > glTF 2.0.

## model.json

The model as the file holds it, in the game's own space (nothing turned or mirrored):

- `nodes`: the skeleton. Each has `name`, `parent` (-1 for a root), `translation`, `rotation` (radians), `scale`
  and `world`, its bind matrix in model space: 16 numbers, row by row, for row vectors (a point times the matrix),
  so the move is the last four.
- `materials`: `name`, `mtd` and `textures` (`param`, `path`, and `file`, the texture's name in `textures/`).
- `meshes`: `material`, `node`, `dynamic`, `has_bone_indices`, the counts, and flat lists: `positions` and `normals`
  (3 a vertex), `uvs` (2), `joints` and `weights` (4 each; `joints` are numbers in `nodes`) and `triangles` (3 a
  triangle). Only the full-detail triangles are kept.
- `textures`: what was written, with the game's format number and size; `texture_errors`: what could not be.

## From model.json to glTF

`model_gltf.py` writes one skinned mesh per model mesh on one skeleton, with each material's texture names in its
`extras`. The game's space is left-handed and glTF's is not, so the model is mirrored on the way (`--mirror x`, the
default; `z` or `none` to choose). No pictures are attached: load the `.dds` files in Blender by the names in the
material.

## The monster the model replaces

```bash
python tools/chr/chrtool.py export "C:/path/to/data/dun/monstor/e06a.chr" "C:/path/to/work/e06a"
python tools/bb/template_facts.py "C:/path/to/data/dun/monstor/e06a.chr" "C:/path/to/work/e06a"
```

`template_facts.py` prints the pack's members, its `.cfg` text, the skeleton as a tree, and each mesh's size, material
and whether it is skinned, then the textures' sizes and the motions' lengths: what a new body has to fit. It reads
only. If the pack's cfg skins a mesh and the export has no skin weights, it says so: the toolkit build that wrote
the export does not keep them ([docs/known-issues.md](../../docs/known-issues.md)).

## Checked, and not

- `model_gltf.py` is tested on a model made up in the test (`tools/tests/test_bb_model.py`), with no game data,
  and its output was imported with Blender 5.3: bones, vertex groups, and the skin following a posed bone.
- `template_facts.py` is tested on a made-up pack (`tools/tests/test_bb_template_facts.py`) and was run on one real
  export, Opar's `c07d.chr` from `mods/moonmod.opar`. It has not been run on a monster's pack.
- `BbModel` has been written against the source of DSAnimStudio's SoulsFormats (v5-rc6.1) but **not built or run**:
  the machine it was written on has neither that library nor a dump. If your DSAnimStudio is older, the names it
  reads by either spelling (`Nodes`/`Bones`, `NodeIndex`/`DefaultBoneIndex`, `ParamName`/`Type`) should still fit.
- Not yet seen: which way the model faces and which hand holds the weapon after the mirror, whether a mesh that is
  not `dynamic` sits in place, and whether every texture format gets its header.
