# Decisions

- 2026-11-11: Setup created. The orchestrator files live in MoonMod, because the workspace root is not a
  repository and MoonMod holds the character tools and the mod package the work lands in.
- 2026-11-11: The proof of concept replaces the Dasher (`e06a`, native model id 3, the Divine Beast Cave's
  first floor) with one of Bloodborne's ordinary smaller beast enemies (the user's choice). Which beast is
  still open.
- 2026-11-11: The Bloodborne model is read with DSAnimStudio's SoulsFormats (`tools/bb/BbModel`, C#), not a reader
  of our own. Bloodborne's models use Edge-compressed vertex and index data and its textures the PS4's tiling; the
  library already reads both, and `tools/anim/reference` already builds against it on the user's machine.
- 2026-11-11: `BbModel` writes the model as the file holds it (`model.json`, the game's own space, nothing turned),
  and every choice after that (mirroring, scale, which bones map where) is made in Python or Blender, where it can
  be seen and changed without the dump.
- 2026-11-11: The first pass keeps the Dasher's own motions and AI: only its body and textures become the beast's.
  Bloodborne's animations and sounds come after the body is seen in game.
