# ChronicleTwo-Script compatibility

MoonFactory complements [ChronicleTwo-Script](https://github.com/fakegenie/ChronicleTwo-Script), whose upstream repository now presents as DC2-Toolkit. The current toolchain targets the PAL disc: creators edit C script patches and assets, then use `dc2tk` to compile and write a patched ISO. It also supports authored maps and models. These outputs have different runtime assumptions from a MoonFactory Lua package for the playable PC port.

The current upstream toolchain decompiles PAL scripts to readable C, lets creators patch named functions and author assets/maps/models, and builds a patched disc image. Its mod manifests, SDK, stable symbol allocation, and build-time conflict checks are useful prior art. The runtime framework starts from local Lua packages for the playable PC port and does not require an ISO or image rebuild for ordinary mod changes. A legacy Python CLI checkout is also present locally, but its commands and extracted-tree layout differ from current `dc2tk`.

## Compatibility boundary

- An API major 1 runtime Lua package is a folder with `mod.json`, `main.lua`, supported storage permissions, and settings. Bundled resources are a later compatibility step.
- A ChronicleTwo-Script package remains a build-time C/asset package and continues to be built by its repository tool into an image (`dc2tk` in current upstream releases).
- There is no direct importer for compiled `.stb` scripts or a built ISO. The compatibility report tool inventories a source mod's script patches, whole-file overrides, dependencies, added/changed assets, and allocated script symbols. It labels these as build-only until the PC adapter can load and test them; it does not copy decompiled scripts or disc assets into a runtime package.
- Save flags, item ids, script ids, and map ids are game-owned namespaces. An importer must preserve the originating content id and must detect collisions before the PC runtime loads the content.
- Any compatibility command should identify the `c2` version, game revision, source mod id, output resource hashes, and unsupported features.

## Follow-up spike

The repository's published usage and modding guides document function fingerprints, dependency ordering, stable allocated flag/counter/program numbers, `add`/`replace` asset declarations, and script and asset tests. Its examples include a new map with an entrance and return path and a new rigged, animated character. The map remains a bridge fixture; authored-rig and fighting-style fixtures are deferred until model-rigging work is in scope. Existing embedded-motion playback stays at its verified baseline, as described in [`CHRONICLETWO_SCRIPT_BRIDGE.md`](CHRONICLETWO_SCRIPT_BRIDGE.md).

Use the local scanner to inspect a mod and optionally ask `dc2tk` to compile-check its patches:

```powershell
python .\MoonFactory\tools\chronicle_two_script_bridge.py C:\path\to\ChronicleTwo-Script --mod my-mod --output .\my-mod-bridge-report.json
python .\MoonFactory\tools\chronicle_two_script_bridge.py C:\path\to\DC2-Toolkit --mod my-mod --run-mod-check --dc2tk C:\path\to\dc2tk.exe --disc C:\path\to\your-own-pal.iso
```

The report fingerprints the local definitions and optional disc, retains asset source paths and hashes, and reports unsupported PC-runtime components. `--run-mod-check` delegates to the user's local `dc2tk`; the ISO stays in place and is only read. The report tool's synthetic fixtures run as part of `verify-headless.ps1`.

The remaining spike is to run the current bridge against an actual authored mod and turn one supported asset declaration into a real PC-runtime conversion. Do not equate `dc2tk build` success or an ISO round-trip with PC runtime support. New locations, whole dungeons, authored model assets, and native script hooks still need their PC adapters and headless proofs. Runtime Georama registration and native placement have retail proofs for data-only variants in both games; authored geometry, visual persistence after process reload, and player-save compatibility remain open. Standalone animation authoring and fighting-style definitions are deferred until model-rigging work is in scope; embedded motion playback remains supported for registered models that already contain native motion data.
