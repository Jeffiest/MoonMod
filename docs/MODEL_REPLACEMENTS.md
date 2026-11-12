# Chronicle 3D model and texture replacements

MoonFactory packages can replace Chronicle meshes and their native textures. The in-game Mod Manager controls whether a package is enabled and its load order; there is no separate in-game visual menu.

## Use the model replacer

Run:

```powershell
python tools/model_replacer.py --save "C:\path\to\save" --exe "C:\path\to\darkcloud.exe" --data "C:\path\to\chronicle\data"
```

`--save` must be the same save root passed to the game. The tool's **Dump models** button launches the selected executable with `DC_DUMP_MODELS=1`; open the models or weapons in game, then refresh the list. Select a dumped mesh, choose a `.obj`, `.glb`, or supported `.dae` model, adjust its fit, and install it. The tool creates a valid Chronicle package under `<save>\mods\<name>` with the mesh and, when available, a PNG texture override.

After installing, enable the package in **Options > Game+ > Mod Manager**, then restart Chronicle so its package assets load. New packages created by the tool use an id under `moonmod.models.*` and contain no custom UI code.

The legacy Windows workflow specifically supports 3D weapon models shown by the Equip screen: dump the model while it is visible there, then replace its texture-keyed mesh. Chronicle routes model construction through the package replacement hook, so these 3D previews use the same replacement assets as other matching models. The authoring tool flattens the active GLB scene, applies node transforms, expands sparse accessors, and triangulates triangle-strip and triangle-fan primitives before installing the result as OBJ. Point and line primitives are skipped because Chronicle's replacement renderer consumes triangles.

Chronicle's 2D item and weapon icons are atlas draws: native item metadata selects a rectangle from the `itemicon` or `wepicon` texture. Package PNG overrides at `textures/itemicon.png` and `textures/wepicon.png` can repaint those atlases, at the PNG's own size (see [Larger textures](#larger-textures)). This changes atlas pixels while retaining native per-item icon rectangles; it does not add icon entries or change their UV mapping. The Windows branch currently contains no PNG, OBJ, GLB, or DAE icon/model assets to merge. Any fork-specific art stored outside that branch still needs to be supplied before it can be integrated.

## Package layout

- `models/<texture>.obj` or `.glb` replaces each matching source mesh.
- `models/<texture>__<vertex-count>v.obj` limits replacement to that source vertex count.
- `models/<texture>.json` can set `scale`, `rotate_deg`, `offset`, and `flip_v`.
- `textures/<texture>.png` replaces the decoded native texture and keeps the PNG's own size (see
  [Larger textures](#larger-textures)).

Later packages in resolved Mod Manager load order win when they replace the same texture or mesh. Mesh replacement keeps the original material strips and follows Chronicle's native animation hooks. Direct `.glb` package loading flattens mesh instances in the selected scene, applies node hierarchy transforms, expands sparse accessors, and converts triangle, strip, and fan primitives into the renderer's triangle list. Point and line primitives are skipped. Custom skeleton data is not imported: animated replacements inherit skin weights from the source mesh.

The runtime skips model and texture files larger than 64 MiB. Texture overrides use the package's root `textures` directory and match the native texture name, case-insensitively.

## Larger textures

A texture PNG may be larger than the texture it replaces, and the game draws it at that size: a 1024x1024 picture for
a 256x256 texture shows four times the detail each way. The game still places it by the texture's own measure, so
models, icon rectangles and menu layouts stay where they were. Animated textures (water, blinking faces, scrolling
surfaces) keep working when the frames they are copied from are larger too.

- The picture keeps its own size, halved (both sides together) while a side is over 4096 or over 8 times the
  texture's. In the browser build the limits are 2048 and 2 times. A picture smaller than the texture is enlarged to
  it; one of another shape is stretched to fit.
- `DC_TEXTURE_SCALE_MAX=<1..64>` in the environment changes the 8 (the browser's 2). `1` gives every picture the
  texture's own size, as before.
- A file over 64 MiB or over 16 million pixels is skipped.
- `stayframe`, a menu sheet, is loaded another way and cannot be replaced.
- A file goes on every texture of its name, and a few names hold a different picture from place to place (each
  dungeon has its own `frame`). `textures/<texture>.<key>.png` goes on one of those pictures alone: the key is eight
  hex digits, the CRC-32 of the game's own picture as straight RGBA rows (what the dump writes). A file with a key is
  taken before one without, whatever the load order; `textures/<texture>.png` goes on the pictures of the name that
  have no file of their own. Text pictures differ by language, so a key for one is for the language it was dumped in.
- The log names each picture taken: `mods: replaced texture e01t03 from <file> (1024x1024 for 256x256)`. Where a name
  has files with keys and the picture met has none, it says so once, with the key:
  `mods: texture frame is picture e014ed16 here, which no frame.<key>.png is for`.

Start the game with `DC_TEXTURE_DUMP=<folder>` and it writes every texture it loads to `<folder>/<texture name>.png`,
the game's own picture even where a package replaces it, with text in the game's chosen language. A second, different
picture of a name is written as `<texture name>.<key>.png`: the name a package file for that picture has. Those files
give you the names and sizes, and something to paint over or upscale.

[`tools/textures/texture_pack.py`](../tools/textures/README.md) does the whole job: `dump` runs the game for the
pictures, `upscale` enlarges them with an upscaling model (ONNX; none is included) into a package's `textures` folder,
and `check` lists a package's pictures with the size the game keeps each at. Pictures made this way come from the game
disc: share the tool and your settings, not the pictures.
