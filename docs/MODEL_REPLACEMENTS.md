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

Chronicle's 2D item and weapon icons are atlas draws: native item metadata selects a rectangle from the `itemicon` or `wepicon` texture. Package PNG overrides at `textures/itemicon.png` and `textures/wepicon.png` can repaint those atlases, resampled to their native dimensions and mip levels. This changes atlas pixels while retaining native per-item icon rectangles; it does not add icon entries or change their UV mapping. The Windows branch currently contains no PNG, OBJ, GLB, or DAE icon/model assets to merge. Any fork-specific art stored outside that branch still needs to be supplied before it can be integrated.

## Package layout

- `models/<texture>.obj` or `.glb` replaces each matching source mesh.
- `models/<texture>__<vertex-count>v.obj` limits replacement to that source vertex count.
- `models/<texture>.json` can set `scale`, `rotate_deg`, `offset`, and `flip_v`.
- `textures/<texture>.png` replaces the decoded native texture, resampled to its original dimensions and mip levels.

Later packages in resolved Mod Manager load order win when they replace the same texture or mesh. Mesh replacement keeps the original material strips and follows Chronicle's native animation hooks. Direct `.glb` package loading flattens mesh instances in the selected scene, applies node hierarchy transforms, expands sparse accessors, and converts triangle, strip, and fan primitives into the renderer's triangle list. Point and line primitives are skipped. Custom skeleton data is not imported: animated replacements inherit skin weights from the source mesh.

The runtime skips model and texture files larger than 64 MiB. Texture overrides use the package's root `textures` directory and match the native texture name, case-insensitively. Texture dump/export tooling and user asset compatibility still need to be checked in a game session.
